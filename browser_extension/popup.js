/**
 * CardVault Windows Extension - Popup Controller
 * Connects directly to Google Drive via OAuth 2.0 and executes the live
 * Mobile Push Approval Handshake with the user's phone.
 */

let currentVaultItems = [];
let currentTab = 'cards';
let currentGoogleAccount = null;
let currentOAuthToken = null;
let localBackupPayload = null;
let activePollingInterval = null;
let activeCountdownInterval = null;
let cachedDevices = [];
let currentActiveTabDomain = '';

async function detectActiveTabDomain() {
  try {
    if (typeof chrome !== 'undefined' && chrome.tabs && chrome.tabs.query) {
      const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
      if (tabs && tabs[0] && tabs[0].url) {
        const urlStr = tabs[0].url;
        if (urlStr.startsWith('http')) {
          const u = new URL(urlStr);
          currentActiveTabDomain = u.hostname.replace(/^www\./, '').toLowerCase();
        }
      }
    }
  } catch (_) {}
}

function extractDomain(urlOrHost) {
  if (!urlOrHost) return '';
  let str = urlOrHost.trim().toLowerCase();
  str = str.replace(/^[a-zA-Z]+:\/\//, '');
  str = str.split('/')[0].split('?')[0].split('#')[0];
  str = str.split(':')[0];
  return str.replace(/^www\./, '');
}

const MULTI_TLDS = ['co', 'com', 'org', 'net', 'edu', 'gov', 'ac', 'bank', 'mil', 'nic', 'res', 'gen'];
const STOP_WORDS = ['bank', 'banking', 'netbanking', 'login', 'portal', 'app', 'account', 'card', 'pass', 'password', 'online', 'store', 'auth', 'web', 'mobile', 'secure', 'retail'];

function extractBaseBrand(domain) {
  if (!domain) return '';
  const clean = extractDomain(domain);
  const parts = clean.split('.');
  if (parts.length <= 1) return parts[0];
  if (parts.length >= 3 && MULTI_TLDS.includes(parts[parts.length - 2])) {
    return parts[parts.length - 3];
  }
  return parts[parts.length - 2];
}

const BANK_DOMAIN_ALIASES = {
  federal: ['federalbank.co.in', 'fednetbank.com', 'federalbank.com', 'fednet', 'federal', 'federal.bank.in'],
  hdfc: ['hdfcbank.com', 'hdfcbank.net', 'hdfc.com', 'hdfc', 'hdfc.bank.in'],
  sbi: ['onlinesbi.sbi', 'onlinesbi.com', 'sbi.co.in', 'statebankofindia.com', 'sbi', 'sbi.bank.in'],
  rbl: ['rblbank.com', 'rblbank.in', 'rbl', 'rbl.bank.in'],
  icici: ['icicibank.com', 'icici.com', 'icici', 'icici.bank.in'],
  axis: ['axisbank.com', 'axisbank.co.in', 'axis', 'axis.bank.in'],
  kotak: ['kotak.com', 'kotakbank.com', 'kotak', 'kotak.bank.in'],
  pnb: ['pnbindia.in', 'netpnb.com', 'pnb', 'pnb.bank.in'],
  bob: ['bankofbaroda.in', 'bobibanking.com', 'bankofbaroda.com', 'bob', 'bob.bank.in'],
  canara: ['canarabank.com', 'canarabank.in', 'canara', 'canarabank.bank.in'],
  idbi: ['idbibank.in', 'idbibank.com', 'idbi', 'idbi.bank.in'],
  indusind: ['indusind.com', 'indusindbank.com', 'indusind', 'indusind.bank.in'],
  yes: ['yesbank.in', 'yesbank.com', 'yes', 'yesbank.bank.in'],
  union: ['unionbankofindia.co.in', 'unionbankonline.co.in', 'union', 'unionbank.bank.in'],
  dbs: ['dbs.com', 'dbs.com.sg', 'dbs'],
  iob: ['iob.in', 'iobnet.co.in', 'iob', 'iob.bank.in'],
  sib: ['southindianbank.com', 'sib.co.in', 'sib', 'southindianbank.bank.in'],
  standardchartered: ['sc.com', 'standardchartered.co.in', 'standardchartered'],
  citi: ['citibank.co.in', 'citibank.com', 'citi']
};

function doesDomainMatch(itemWebsite, pageHost, itemNickname = '') {
  if (!pageHost) return false;
  const pageDom = extractDomain(pageHost);
  const pageBrand = extractBaseBrand(pageDom);

  // 1. Direct website URL / domain match
  if (itemWebsite && itemWebsite.trim()) {
    const itemDom = extractDomain(itemWebsite);
    const itemBrand = extractBaseBrand(itemDom);

    if (itemDom && pageDom) {
      if (itemDom === pageDom) return true;
      if (pageDom.endsWith('.' + itemDom) || itemDom.endsWith('.' + pageDom)) return true;
      if (itemBrand && pageBrand && itemBrand === pageBrand && itemBrand.length >= 3 && !STOP_WORDS.includes(itemBrand)) {
        return true;
      }
    }

    const rawClean = itemWebsite.trim().toLowerCase().replace(/^[a-zA-Z]+:\/\//, '').replace(/^www\./, '');
    if (rawClean.length >= 3) {
      if (pageDom.includes(rawClean) || rawClean.includes(pageDom)) return true;
      if (pageBrand && !STOP_WORDS.includes(pageBrand) && (pageBrand === rawClean || pageBrand.includes(rawClean) || rawClean.includes(pageBrand))) {
        return true;
      }
    }
  }

  // 2. Tokenized Brand Matching (filters out generic words like 'bank', 'banking', 'mobile', etc.)
  if (itemNickname && itemNickname.trim()) {
    const nick = itemNickname.trim().toLowerCase();
    const itemTokens = nick.split(/[^a-z0-9]+/).filter(t => t.length >= 3 && !STOP_WORDS.includes(t));
    const pageTokens = pageDom.split(/[^a-z0-9]+/).filter(t => t.length >= 3 && !STOP_WORDS.includes(t));

    // Direct distinctive token intersection
    for (const t of itemTokens) {
      if (pageTokens.includes(t) || t === pageBrand) return true;
      if (pageBrand && pageBrand.length >= 3 && !STOP_WORDS.includes(pageBrand)) {
        if (pageBrand.startsWith(t) || t.startsWith(pageBrand)) return true;
      }
    }

    // 3. Known Bank Domain Aliases
    for (const [bankKey, aliases] of Object.entries(BANK_DOMAIN_ALIASES)) {
      const bankMatched = itemTokens.includes(bankKey) || nick.includes(bankKey) || (itemWebsite && itemWebsite.toLowerCase().includes(bankKey));
      if (bankMatched) {
        if (aliases.some(a => pageDom.includes(a) || pageTokens.includes(a) || (pageBrand && pageBrand === a))) {
          return true;
        }
      }
    }
  }

  return false;
}

const driveClient = new DriveClient();

// Safe Chrome Runtime messaging helper
function sendExtensionMessage(message) {
  return new Promise((resolve) => {
    try {
      if (typeof chrome !== 'undefined' && chrome.runtime && typeof chrome.runtime.sendMessage === 'function') {
        chrome.runtime.sendMessage(message, (res) => {
          if (chrome.runtime.lastError) {
            console.warn('[CardVault] Extension message notice:', chrome.runtime.lastError.message);
            resolve(null);
          } else {
            resolve(res);
          }
        });
      } else {
        resolve(null);
      }
    } catch (err) {
      console.warn('[CardVault] Runtime messaging unavailable:', err);
      resolve(null);
    }
  });
}

document.addEventListener('DOMContentLoaded', async () => {
  initUI();

  await detectActiveTabDomain();
  await initDesktopDeviceName();
  await loadSavedGoogleAccount();

  // Instant 0ms session recovery from RAM session storage (Zero disk footprint, volatile memory only)
  try {
    if (typeof chrome !== 'undefined' && chrome.storage?.session) {
      const data = await chrome.storage.session.get(['tetherpass_session']);
      const sess = data?.tetherpass_session;
      const now = Date.now();
      if (currentGoogleAccount && sess && sess.isAuthorized && sess.isUnlocked && (!sess.authExpiresAt || now < sess.authExpiresAt)) {
        applyUnlockedUI(sess);
      } else {
        applyLockedUI(true);
      }
    } else {
      applyLockedUI(true);
    }
  } catch (_) {
    applyLockedUI(true);
  }

  // Security Enforcement: Ensure no leftover session or backup records remain in disk-backed storage
  if (typeof chrome !== 'undefined' && chrome.storage?.local) {
    chrome.storage.local.remove(['tetherpass_session', 'cachedBackupPayload']).catch(() => {});
  }

  await refreshStatus();

  // Auto-refresh desktop status periodically
  setInterval(() => {
    refreshStatus();
  }, 5000);
});

function initUI() {
  // Google OAuth connect
  document.getElementById('googleOAuthBtn')?.addEventListener('click', handleGoogleSignIn);
  document.getElementById('disconnectOAuthBtn')?.addEventListener('click', handleDisconnectOAuth);
  document.getElementById('editDesktopNameBtn')?.addEventListener('click', handleEditDesktopName);

  // Push confirmation to mobile phone
  document.getElementById('requestPushApprovalBtn')?.addEventListener('click', handleRequestMobilePushApproval);
  document.getElementById('cancelApprovalRequestBtn')?.addEventListener('click', cancelApprovalPolling);

  // Instant QR vs Push Unlock Tabs
  document.getElementById('tabModeQrBtn')?.addEventListener('click', () => switchUnlockTab('qr'));
  document.getElementById('tabModePushBtn')?.addEventListener('click', () => switchUnlockTab('push'));
  document.getElementById('refreshQrBtn')?.addEventListener('click', () => startDirectQrPairing(true));

  // ── Device Manager Modal ──
  document.getElementById('openDeviceManagerBtn')?.addEventListener('click', openDeviceManagerModal);
  document.getElementById('openDeviceManagerFromHeaderBtn')?.addEventListener('click', openDeviceManagerModal);
  document.getElementById('openDeviceManagerFromUnlockedBtn')?.addEventListener('click', openDeviceManagerModal);
  document.getElementById('closeDeviceManagerBtn')?.addEventListener('click', closeDeviceManagerModal);
  document.getElementById('doneDeviceManagerBtn')?.addEventListener('click', closeDeviceManagerModal);
  document.getElementById('deviceManagerModal')?.addEventListener('click', (e) => {
    if (e.target.id === 'deviceManagerModal') closeDeviceManagerModal();
  });

  // Lock button
  document.getElementById('lockNowBtn')?.addEventListener('click', handleLock);

  // Category filter tabs
  document.querySelectorAll('.tab-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      currentTab = btn.getAttribute('data-tab');
      renderVaultList();
    });
  });

  // Search filter
  document.getElementById('searchBar')?.addEventListener('input', (e) => {
    renderVaultList(e.target.value.toLowerCase().trim());
  });

  // Check if opened outside extension popup
  if (typeof chrome === 'undefined' || !chrome.runtime || !chrome.runtime.id) {
    const notice = document.getElementById('tabContextNotice');
    if (notice) notice.style.display = 'block';
  }

  // Listen for instant lock / status notifications from background service worker
  if (typeof chrome !== 'undefined' && chrome.runtime?.onMessage) {
    chrome.runtime.onMessage.addListener(async (message) => {
      if (message && message.action === 'VAULT_STATUS_CHANGED') {
        const unlockedView = document.getElementById('unlockedView');
        if (unlockedView && unlockedView.classList.contains('active') && !message.isUnlocked) {
          const anim = showTransitionAnimation({
            mode: 'disconnect',
            title: 'Securing Vault...',
            subtitle: message.reason || 'Session was terminated remotely from phone.'
          });
          await new Promise(r => setTimeout(r, 600));
          await anim.finish({
            title: 'Session Locked',
            subtitle: 'Sensitive data cleared from memory.'
          });
        }
        refreshStatus();
      }
    });
  }

  // Smooth second-by-second countdown timer for active session (zero network spam)
  setInterval(() => {
    const unlockedView = document.getElementById('unlockedView');
    if (unlockedView && unlockedView.classList.contains('active')) {
      updateCountdownDisplay();
    }
  }, 1000);

  // When popup window regains focus, refresh status
  window.addEventListener('focus', () => {
    refreshStatus();
  });
}


let currentGooglePicture = null;

async function loadSavedGoogleAccount() {
  try {
    if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.local) {
      const data = await chrome.storage.local.get([
        'googleAccountEmail',
        'googleAccountPicture',
        'googleOAuthToken',
        'preferredAuthMethod'
      ]);
      if (data.googleOAuthToken && data.googleAccountEmail) {
        currentOAuthToken = data.googleOAuthToken;
        currentGoogleAccount = data.googleAccountEmail;
        driveClient.setToken(data.googleOAuthToken);
        if (data.googleAccountPicture) {
          currentGooglePicture = data.googleAccountPicture;
        }
        setConnectedGoogleAccount(data.googleAccountEmail, data.googleAccountPicture || null, false);
      } else {
        currentOAuthToken = null;
        currentGoogleAccount = null;
        currentGooglePicture = null;
        driveClient.setToken(null);
        const unlinked = document.getElementById('oauthUnlinkedBox');
        if (unlinked) unlinked.style.display = 'block';
        const linked = document.getElementById('oauthLinkedBox');
        if (linked) {
          linked.style.display = 'none';
          linked.classList.add('hidden');
        }
      }
      if (data.preferredAuthMethod) {
        setAuthMethod(data.preferredAuthMethod, false);
      }
    }
    if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.session) {
      const sessData = await chrome.storage.session.get('cachedBackupPayload');
      if (sessData?.cachedBackupPayload) {
        localBackupPayload = sessData.cachedBackupPayload;
      }
    }
  } catch (err) {
    console.warn('[CardVault] Storage read error:', err);
  }
}

function setConnectedGoogleAccount(email, picture = null, save = true) {
  currentGoogleAccount = email;
  if (picture) currentGooglePicture = picture;

  const unlinkedBox = document.getElementById('oauthUnlinkedBox');
  const linkedBox = document.getElementById('oauthLinkedBox');
  const emailDisplay = document.getElementById('connectedEmailDisplay');
  const avatarLetter = document.getElementById('accountAvatarLetter');
  const profileImg = document.getElementById('accountProfileImg');
  const step1Sub = document.getElementById('step1Subtitle');

  if (step1Sub) step1Sub.style.display = 'none';
  if (unlinkedBox) unlinkedBox.style.display = 'none';
  if (linkedBox) {
    linkedBox.classList.remove('hidden');
    linkedBox.style.display = 'flex';
  }
  if (emailDisplay) emailDisplay.textContent = email;

  if (currentGooglePicture && profileImg) {
    profileImg.src = currentGooglePicture;
    profileImg.style.display = 'block';
    if (avatarLetter) avatarLetter.style.display = 'none';
    profileImg.onerror = () => {
      profileImg.style.display = 'none';
      if (avatarLetter) {
        avatarLetter.style.display = 'block';
        avatarLetter.textContent = (email[0] || 'U').toUpperCase();
      }
    };
  } else {
    if (profileImg) profileImg.style.display = 'none';
    if (avatarLetter) {
      avatarLetter.style.display = 'block';
      avatarLetter.textContent = (email[0] || 'U').toUpperCase();
    }
  }

  if (save && typeof chrome !== 'undefined' && chrome.storage && chrome.storage.local) {
    chrome.storage.local.set({
      googleAccountEmail: email,
      googleAccountPicture: currentGooglePicture,
      googleOAuthToken: currentOAuthToken
    });
  }

  // If token is present but no picture yet, query Google userinfo
  if (currentOAuthToken && !currentGooglePicture) {
    fetchGoogleUserProfile(currentOAuthToken);
  }

  // Check for registered mobile devices
  loadRegisteredDevices();

  // If locked, kick off QR generation only if IDLE
  const lockedView = document.getElementById('lockedView');
  if (lockedView && lockedView.classList.contains('active')) {
    const qrBtn = document.getElementById('tabModeQrBtn');
    if ((!qrBtn || qrBtn.classList.contains('active')) && directQrState === 'IDLE') {
      startDirectQrPairing(false);
    }
  }
}

async function fetchGoogleUserProfile(token) {
  try {
    const res = await fetch('https://www.googleapis.com/oauth2/v2/userinfo', {
      headers: { Authorization: `Bearer ${token}` }
    });
    if (res.ok) {
      const info = await res.json();
      if (info.picture) {
        currentGooglePicture = info.picture;
        const profileImg = document.getElementById('accountProfileImg');
        const avatarLetter = document.getElementById('accountAvatarLetter');
        if (profileImg) {
          profileImg.src = info.picture;
          profileImg.style.display = 'block';
        }
        if (avatarLetter) avatarLetter.style.display = 'none';

        if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.local) {
          chrome.storage.local.set({ googleAccountPicture: info.picture });
        }
      }
    }
  } catch (err) {
    console.warn('[CardVault] Could not fetch Google user profile picture:', err);
  }
}

async function loadRegisteredDevices() {
  if (!currentOAuthToken) return;
  try {
    const res = await sendExtensionMessage({
      action: 'GET_REGISTERED_DEVICES',
      payload: { token: currentOAuthToken }
    });

    if (res && res.success && Array.isArray(res.devices)) {
      cachedDevices = res.devices;
      updateDeviceSelector(res.devices);
    }
  } catch (_) {}
}

function updateDeviceSelector(devices) {
  const select = document.getElementById('targetDeviceSelect');
  const badge = document.getElementById('deviceCountBadge');
  const headerCount = document.getElementById('headerDeviceCount');

  if (!select) return;
  const previousSelected = select.value;

  select.innerHTML = '<option value="ALL">📡 All Mobile Devices (Broadcast)</option>';
  const count = Array.isArray(devices) ? devices.length : 0;

  if (count > 0) {
    devices.forEach(d => {
      const opt = document.createElement('option');
      opt.value = d.deviceId;
      opt.textContent = `📱 ${d.deviceName || 'Mobile Phone'} (${d.platform || 'Android'})`;
      select.appendChild(opt);
    });

    if (badge) badge.textContent = `(${count} phone${count > 1 ? 's' : ''})`;
    if (headerCount) headerCount.textContent = `${count} Phone${count > 1 ? 's' : ''} Linked`;
    if (previousSelected && Array.from(select.options).some(o => o.value === previousSelected)) {
      select.value = previousSelected;
    }
  } else {
    if (badge) badge.textContent = '(0 registered)';
    if (headerCount) headerCount.textContent = '0 Phones Linked';
  }
}

let deviceManagerInterval = null;

// ── Device Manager Modal Handlers ──
function openDeviceManagerModal() {
  const modal = document.getElementById('deviceManagerModal');
  if (modal) modal.style.display = 'flex';
  renderDeviceManagerList();
  refreshDeviceManagerModal();

  if (deviceManagerInterval) clearInterval(deviceManagerInterval);
  deviceManagerInterval = setInterval(async () => {
    if (modal && modal.style.display === 'flex') {
      await loadRegisteredDevices();
      renderDeviceManagerList();
    }
  }, 4000);
}

function closeDeviceManagerModal() {
  const modal = document.getElementById('deviceManagerModal');
  if (modal) modal.style.display = 'none';
  if (deviceManagerInterval) {
    clearInterval(deviceManagerInterval);
    deviceManagerInterval = null;
  }
}

async function refreshDeviceManagerModal() {
  const loading = document.getElementById('deviceManagerLoading');
  if (loading) loading.style.display = 'block';
  await loadRegisteredDevices();
  if (loading) loading.style.display = 'none';
  renderDeviceManagerList();
}

function renderDeviceManagerList() {
  const container = document.getElementById('devicesListContainer');
  const empty = document.getElementById('deviceManagerEmpty');
  if (!container) return;

  container.innerHTML = '';
  if (!cachedDevices || cachedDevices.length === 0) {
    if (empty) empty.style.display = 'block';
    return;
  }
  if (empty) empty.style.display = 'none';

  cachedDevices.forEach(device => {
    const card = document.createElement('div');
    card.className = 'device-item-card';

    let lastActiveText = 'Recently';
    if (device.lastActive) {
      try {
        const d = new Date(device.lastActive);
        lastActiveText = d.toLocaleDateString(undefined, { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
      } catch (_) {}
    }

    card.innerHTML = `
      <div class="device-item-left">
        <div class="device-avatar-icon">📱</div>
        <div class="device-item-info">
          <div class="device-item-name">${escapeHtml(device.deviceName || 'Mobile Phone')}</div>
          <div class="device-item-meta">${escapeHtml(device.platform || 'Android')} • Last active ${escapeHtml(lastActiveText)}</div>
        </div>
      </div>
      <div class="device-item-actions">
        <button type="button" class="btn-action-icon btn-rename-device" title="Rename this device">✏️</button>
        <button type="button" class="btn-action-icon btn-delete btn-remove-device" title="Remove device">🗑️</button>
      </div>
    `;

    card.querySelector('.btn-rename-device')?.addEventListener('click', () => {
      handlePromptRenameDevice(device.deviceId, device.deviceName || 'Mobile Phone');
    });

    card.querySelector('.btn-remove-device')?.addEventListener('click', () => {
      handlePromptRemoveDevice(device.deviceId, device.deviceName || 'Mobile Phone');
    });

    container.appendChild(card);
  });
}

async function handlePromptRenameDevice(deviceId, currentName) {
  const newName = prompt('Enter a new name for this device:', currentName);
  if (!newName || !newName.trim() || newName.trim() === currentName) return;

  const loading = document.getElementById('deviceManagerLoading');
  if (loading) loading.style.display = 'block';

  try {
    const res = await sendExtensionMessage({
      action: 'RENAME_REGISTERED_DEVICE',
      payload: { token: currentOAuthToken, deviceId, newName: newName.trim() }
    });
    if (res && res.success) {
      cachedDevices = res.devices || [];
      updateDeviceSelector(cachedDevices);
      renderDeviceManagerList();
    } else {
      alert('Failed to rename device: ' + (res?.error || 'Unknown error'));
    }
  } catch (err) {
    alert('Error renaming device: ' + err.message);
  } finally {
    if (loading) loading.style.display = 'none';
  }
}

async function handlePromptRemoveDevice(deviceId, deviceName) {
  const confirmed = confirm(`Are you sure you want to remove "${deviceName}"?\n\n⚠️ WARNING: This phone will immediately be revoked and all TetherPass app data on that phone will be wiped clean!`);
  if (!confirmed) return;

  const loading = document.getElementById('deviceManagerLoading');
  if (loading) loading.style.display = 'block';

  try {
    const res = await sendExtensionMessage({
      action: 'REMOVE_REGISTERED_DEVICE',
      payload: { token: currentOAuthToken, deviceId }
    });
    if (res && res.success) {
      cachedDevices = res.devices || [];
      updateDeviceSelector(cachedDevices);
      renderDeviceManagerList();
    } else {
      alert('Failed to remove device: ' + (res?.error || 'Unknown error'));
    }
  } catch (err) {
    alert('Error removing device: ' + err.message);
  } finally {
    if (loading) loading.style.display = 'none';
  }
}

async function handleGoogleSignIn() {
  const btn = document.getElementById('googleOAuthBtn');
  if (btn) {
    btn.disabled = true;
    btn.innerHTML = '<span class="pulse-ring" style="width:14px;height:14px;border-width:2px;display:inline-block;margin:0 6px 0 0;vertical-align:middle;"></span> Connecting to Google...';
  }

  try {
    const token = await driveClient.signInWithGoogle();
    currentOAuthToken = token;
    driveClient.setToken(token);

    // Fetch user profile email and profile picture
    try {
      const userInfo = await driveClient.getUserInfo();
      setConnectedGoogleAccount(userInfo.email || 'Google Account Connected', userInfo.picture || null);
    } catch (_) {
      setConnectedGoogleAccount('Google Account Connected');
    }

    // Successfully connected! Show connection options and start QR code generation
    applyLockedUI(true);
  } catch (err) {
    showError(`Google Sign-In notice: ${err.message}`);
  } finally {
    if (btn) {
      btn.disabled = false;
      btn.innerHTML = '<img src="icons/google_logo.svg" alt="G" class="google-logo" /><span>Sign in with Google Account</span>';
    }
  }
}

function showTransitionAnimation({ mode = 'connect', title = 'Connecting...', subtitle = 'Please wait...' }) {
  const overlay = document.getElementById('transitionOverlay');
  const titleEl = document.getElementById('transitionTitle');
  const subEl = document.getElementById('transitionSub');
  const iconEl = document.getElementById('transitionMainIcon');
  if (!overlay) return { finish: async () => {} };

  overlay.className = `transition-overlay show ${mode === 'disconnect' ? 'mode-disconnect' : ''}`;
  if (titleEl) titleEl.textContent = title;
  if (subEl) subEl.textContent = subtitle;
  if (iconEl) iconEl.textContent = mode === 'disconnect' ? '🔒' : '⚡';

  overlay.style.display = 'flex';

  return {
    finish: async ({ title: endTitle, subtitle: endSub, isSuccess = true } = {}) => {
      if (titleEl && endTitle) titleEl.textContent = endTitle;
      if (subEl && endSub) subEl.textContent = endSub;
      if (iconEl) iconEl.textContent = isSuccess ? (mode === 'disconnect' ? '🔒' : '✓') : '⚠️';
      overlay.classList.add('state-complete');

      await new Promise(r => setTimeout(r, 650));
      overlay.classList.remove('show');
      await new Promise(r => setTimeout(r, 220));
      overlay.style.display = 'none';
      overlay.className = 'transition-overlay';
    }
  };
}

async function handleDisconnectOAuth() {
  const anim = showTransitionAnimation({
    mode: 'disconnect',
    title: 'Disconnecting Account...',
    subtitle: 'Unlinking Google Account and wiping session...'
  });
  stopDirectQrPairing();

  const tokenToRevoke = currentOAuthToken || driveClient.token;
  if (tokenToRevoke && typeof chrome !== 'undefined' && chrome.identity?.removeCachedAuthToken) {
    try {
      await new Promise(r => chrome.identity.removeCachedAuthToken({ token: tokenToRevoke }, r));
    } catch (_) {}
  }

  currentOAuthToken = null;
  currentGoogleAccount = null;
  currentGooglePicture = null;
  driveClient.setToken(null);

  const profileImg = document.getElementById('accountProfileImg');
  if (profileImg) profileImg.style.display = 'none';

  const emailDisplay = document.getElementById('connectedEmailDisplay');
  if (emailDisplay) emailDisplay.textContent = '';

  const avatarLetter = document.getElementById('accountAvatarLetter');
  if (avatarLetter) avatarLetter.textContent = '';

  if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.local) {
    await chrome.storage.local.remove([
      'googleAccountEmail',
      'googleAccountPicture',
      'googleOAuthToken',
      'tetherpass_session',
      'cachedBackupPayload'
    ]);
  }

  try {
    await sendExtensionMessage({ action: 'LOCK_VAULT', payload: { reason: 'User disconnected account.' } });
  } catch (_) {}

  await anim.finish({
    title: 'Account Disconnected',
    subtitle: 'Sign in again anytime.'
  });

  const unlinkedBox = document.getElementById('oauthUnlinkedBox');
  const linkedBox = document.getElementById('oauthLinkedBox');
  const step1Sub = document.getElementById('step1Subtitle');
  if (step1Sub) step1Sub.style.display = 'none';
  if (unlinkedBox) unlinkedBox.style.display = 'block';
  if (linkedBox) {
    linkedBox.style.display = 'none';
    linkedBox.classList.add('hidden');
  }

  applyLockedUI(false);
}

async function handleSaveCustomToken() {
  const input = document.getElementById('customTokenInput');
  const token = input?.value.trim();
  if (!token) {
    showError('Please enter a valid OAuth Access Token.');
    return;
  }
  currentOAuthToken = token;
  driveClient.setToken(token);
  setConnectedGoogleAccount('OAuth Token Active');
}

function handleFileSelected(e) {
  const file = e.target.files[0];
  if (!file) return;

  const reader = new FileReader();
  reader.onload = async (ev) => {
    localBackupPayload = ev.target.result;
    setConnectedGoogleAccount(`Local File: ${file.name}`);
    if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.session) {
      await chrome.storage.session.set({ cachedBackupPayload: localBackupPayload });
    }
  };
  reader.readAsText(file);
}

let cachedDesktopDeviceName = '';

async function initDesktopDeviceName() {
  let desktopTag = '';
  if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.local) {
    const stored = await chrome.storage.local.get(['customDesktopName', 'desktopDeviceTag']);
    desktopTag = stored.desktopDeviceTag;
    if (!desktopTag) {
      desktopTag = 'PC-' + Math.random().toString(36).substring(2, 6).toUpperCase();
      await chrome.storage.local.set({ desktopDeviceTag: desktopTag });
    }
    if (stored.customDesktopName) {
      cachedDesktopDeviceName = stored.customDesktopName;
    }
  }

  if (!cachedDesktopDeviceName) {
    let osName = 'Windows PC';
    if (navigator.userAgent.includes('Macintosh')) osName = 'Mac';
    else if (navigator.userAgent.includes('Linux')) osName = 'Linux PC';

    let browserName = 'Chrome';
    if (navigator.userAgent.includes('Edg/')) browserName = 'Edge';
    else if (navigator.userAgent.includes('Brave')) browserName = 'Brave';

    const tagSuffix = desktopTag ? ` • ${desktopTag}` : '';
    cachedDesktopDeviceName = `${osName} (${browserName}${tagSuffix})`;
  }

  const displayEl = document.getElementById('desktopDeviceNameText');
  if (displayEl) displayEl.textContent = cachedDesktopDeviceName;
}

async function handleEditDesktopName() {
  const current = cachedDesktopDeviceName || 'Windows PC (Chrome)';
  const newName = prompt('Enter a recognizable name for this computer (e.g., Work Laptop, Prasanna Desktop):', current);
  if (newName && newName.trim().length > 0 && newName.trim() !== current) {
    cachedDesktopDeviceName = newName.trim();
    if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.local) {
      await chrome.storage.local.set({ customDesktopName: cachedDesktopDeviceName });
    }
    const displayEl = document.getElementById('desktopDeviceNameText');
    if (displayEl) displayEl.textContent = cachedDesktopDeviceName;
  }
}

/**
 * 📲 Primary Action: Sends a live access request to Google Drive
 * and triggers the confirmation pop-up on the phone!
 */
async function handleRequestMobilePushApproval() {
  const passwordInput = document.getElementById('passwordInput');
  const password = passwordInput?.value.trim() || '';

  hideMessages();

  if (!password || password.length < 4) {
    showError('Please enter your Vault Master Password.');
    return;
  }

  if (!currentOAuthToken && !localBackupPayload) {
    showError('Please sign in with your Google Account first in Step 1.');
    return;
  }

  const normalActionBox = document.getElementById('normalActionBox');
  const waitingCard = document.getElementById('waitingForMobileCard');
  const waitingTimer = document.getElementById('waitingTimer');
  const select = document.getElementById('targetDeviceSelect');
  const targetDeviceId = select?.value || 'ALL';
  const targetDeviceName = select?.options[select?.selectedIndex]?.text || 'your phone';

  const myDevice = cachedDesktopDeviceName || 'Windows PC';

  const waitingDesc = document.querySelector('.waiting-desc');
  if (waitingDesc) {
    waitingDesc.innerHTML = `Confirmation sent to <strong>${escapeHtml(targetDeviceName)}</strong> from <strong>${escapeHtml(myDevice)}</strong>.<br/>Check your phone and tap <strong>"Approve with Biometrics"</strong>.`;
  }

  if (normalActionBox) normalActionBox.style.display = 'none';
  if (waitingCard) waitingCard.style.display = 'block';

  try {
    // 1. Send request to Google Drive via background script targeting device
    const startRes = await sendExtensionMessage({
      action: 'START_MOBILE_APPROVAL_REQUEST',
      payload: {
        token: currentOAuthToken,
        deviceName: myDevice,
        targetDeviceId
      }
    });

    if (!startRes || !startRes.success) {
      cancelApprovalPolling();
      showError(startRes?.error || 'Could not send request to Google Drive. Check connection.');
      return;
    }

    const requestId = startRes.requestId;
    let secondsLeft = 30;

    // Render Pairing QR Code for Instant Phone Scan
    try {
      const qrCanvas = document.getElementById('pairingQrCanvas');
      if (qrCanvas && window.renderQRCode) {
        const pairUri = `tetherpass://pair?req=${encodeURIComponent(requestId)}&dev=${encodeURIComponent(myDevice)}`;
        window.renderQRCode(qrCanvas, pairUri, { size: 130 });
      }
    } catch (err) {
      console.warn('QR code render warning:', err);
    }

    // 2. Start Countdown Timer UI
    activeCountdownInterval = setInterval(() => {
      secondsLeft--;
      if (waitingTimer) waitingTimer.textContent = `Waiting for mobile approval (${secondsLeft}s)...`;
      if (secondsLeft <= 0) {
        cancelApprovalPolling();
        showError('Request timed out. Please tap Authorize in TetherPass on your phone.');
      }
    }, 1000);

    // 3. Start Polling for Approval (fast 800ms interval)
    activePollingInterval = setInterval(async () => {
      const pollRes = await sendExtensionMessage({
        action: 'POLL_MOBILE_APPROVAL',
        payload: {
          token: currentOAuthToken,
          requestId,
          masterPassword: password
        }
      });

      if (!pollRes) return;

      if (pollRes.status === 'APPROVED' && pollRes.success) {
        cancelApprovalPolling();
        const anim = showTransitionAnimation({
          mode: 'connect',
          title: 'Connecting to Phone...',
          subtitle: 'Push approved with Biometrics! Decrypting vault...'
        });
        await new Promise(r => setTimeout(r, 600));
        applyUnlockedUI(pollRes);
        if (passwordInput) passwordInput.value = '';
        await anim.finish({
          title: 'Connected & Unlocked!',
          subtitle: 'Welcome to your secure vault.'
        });
      } else if (pollRes.status === 'DENIED') {
        cancelApprovalPolling();
        showError('Access request was denied on your mobile phone.');
      } else if (pollRes.status === 'EXPIRED') {
        cancelApprovalPolling();
        showError('Access request expired on your mobile phone.');
      }
    }, 800);

  } catch (err) {
    cancelApprovalPolling();
    showError(`Error: ${err.message}`);
  }
}

function cancelApprovalPolling() {
  if (activePollingInterval) clearInterval(activePollingInterval);
  if (activeCountdownInterval) clearInterval(activeCountdownInterval);
  activePollingInterval = null;
  activeCountdownInterval = null;

  const normalActionBox = document.getElementById('normalActionBox');
  const waitingCard = document.getElementById('waitingForMobileCard');
  if (normalActionBox) normalActionBox.style.display = 'block';
  if (waitingCard) waitingCard.style.display = 'none';
}

let activeDirectQrInterval = null;
let activeDirectQrCountdown = null;
let currentDirectQrRequestId = null;
let qrSessionExpiresAt = 0;
let isQrExpired = false;
let directQrState = 'IDLE'; // 'IDLE' | 'GENERATING' | 'ACTIVE' | 'EXPIRED'

function switchUnlockTab(tab) {
  const qrBtn = document.getElementById('tabModeQrBtn');
  const pushBtn = document.getElementById('tabModePushBtn');
  const qrContainer = document.getElementById('qrUnlockModeContainer');
  const pushContainer = document.getElementById('pushModeContainer');

  if (tab === 'qr') {
    qrBtn?.classList.add('active');
    pushBtn?.classList.remove('active');
    if (qrContainer) qrContainer.style.display = 'block';
    if (pushContainer) pushContainer.style.display = 'none';

    // Start direct QR pairing (only if not already running a valid session)
    if (directQrState === 'IDLE') {
      startDirectQrPairing(false);
    }
  } else {
    pushBtn?.classList.add('active');
    qrBtn?.classList.remove('active');
    if (qrContainer) qrContainer.style.display = 'none';
    if (pushContainer) pushContainer.style.display = 'block';

    stopDirectQrPairing(true);
  }
}

function stopDirectQrPairing(clearSession = true) {
  if (activeDirectQrInterval) clearInterval(activeDirectQrInterval);
  if (activeDirectQrCountdown) clearInterval(activeDirectQrCountdown);
  activeDirectQrInterval = null;
  activeDirectQrCountdown = null;
  if (clearSession) {
    currentDirectQrRequestId = null;
    qrSessionExpiresAt = 0;
    isQrExpired = false;
    directQrState = 'IDLE';
  }
}

async function markQrCodeExpired() {
  if (activeDirectQrInterval) clearInterval(activeDirectQrInterval);
  if (activeDirectQrCountdown) clearInterval(activeDirectQrCountdown);
  activeDirectQrInterval = null;
  activeDirectQrCountdown = null;

  // Before giving up, do a quick final check if mobile approved right at the finish line
  if (currentDirectQrRequestId && currentOAuthToken) {
    try {
      const pollRes = await sendExtensionMessage({
        action: 'POLL_MOBILE_APPROVAL',
        payload: {
          token: currentOAuthToken,
          requestId: currentDirectQrRequestId,
          masterPassword: ''
        }
      });
      if (pollRes && pollRes.status === 'APPROVED' && pollRes.success) {
        stopDirectQrPairing(true);
        hideMessages();
        const anim = showTransitionAnimation({
          mode: 'connect',
          title: 'Connecting to Phone...',
          subtitle: 'Mobile QR Verified! Decrypting vault...'
        });
        await new Promise(r => setTimeout(r, 650));
        applyUnlockedUI(pollRes);
        await anim.finish({
          title: 'Connected & Unlocked!',
          subtitle: 'Vault is active for 30 minutes.'
        });
        return;
      }
    } catch (_) {}

    // Explicitly notify Google Drive that this pairing request is now expired
    try {
      sendExtensionMessage({
        action: 'CANCEL_MOBILE_APPROVAL_REQUEST',
        payload: {
          token: currentOAuthToken,
          requestId: currentDirectQrRequestId,
          reason: 'EXPIRED'
        }
      });
    } catch (_) {}
  }

  isQrExpired = true;
  directQrState = 'EXPIRED';

  const timerEl = document.getElementById('qrWaitingTimer');
  const canvas = document.getElementById('directPairingQrCanvas');
  const pulseDot = document.querySelector('.pulse-dot-amber');
  const refreshBtn = document.getElementById('refreshQrBtn');

  if (timerEl) timerEl.textContent = '⌛ Code expired. Tap Refresh to reload';
  if (canvas) canvas.style.opacity = '0.3';
  if (pulseDot) pulseDot.style.background = '#475569';
  if (refreshBtn) {
    refreshBtn.style.background = '#00F5A0';
    refreshBtn.style.color = '#04060A';
    refreshBtn.style.border = 'none';
    refreshBtn.style.fontWeight = '700';
  }
}

async function startDirectQrPairing(force = false) {
  // Guard: do NOT generate if already generating, already active, or expired waiting for refresh
  if (!force && directQrState !== 'IDLE') {
    return;
  }

  // Clear existing intervals if forcing
  if (activeDirectQrInterval) {
    clearInterval(activeDirectQrInterval);
    activeDirectQrInterval = null;
  }
  if (activeDirectQrCountdown) {
    clearInterval(activeDirectQrCountdown);
    activeDirectQrCountdown = null;
  }

  directQrState = 'GENERATING';
  currentDirectQrRequestId = null;
  qrSessionExpiresAt = 0;
  isQrExpired = false;

  const loadingEl = document.getElementById('qrLoadingState');
  const readyEl = document.getElementById('qrReadyState');
  const timerEl = document.getElementById('qrWaitingTimer');
  const canvas = document.getElementById('directPairingQrCanvas');
  const pulseDot = document.querySelector('.pulse-dot-amber');
  const refreshBtn = document.getElementById('refreshQrBtn');

  if (canvas) canvas.style.opacity = '1';
  if (pulseDot) pulseDot.style.background = '#F59E0B';
  if (refreshBtn) {
    refreshBtn.style.background = '#141E34';
    refreshBtn.style.color = '#8892B0';
    refreshBtn.style.border = '1px solid #1E293B';
    refreshBtn.style.fontWeight = '600';
  }

  if (!currentOAuthToken) {
    directQrState = 'IDLE';
    if (loadingEl) {
      loadingEl.style.display = 'block';
      loadingEl.innerHTML = `
        <div style="font-size: 24px; margin-bottom: 6px;">🔗</div>
        <div style="font-weight: 700; color: #F8FAFC; margin-bottom: 4px;">Sign in with Google First</div>
        <div style="font-size: 11px; color: #8892B0; line-height: 1.4;">
          Connect your Google Drive account above to generate a secure pairing QR code.
        </div>
      `;
    }
    if (readyEl) readyEl.style.display = 'none';
    return;
  }

  if (loadingEl) {
    loadingEl.style.display = 'block';
    loadingEl.innerHTML = `
      <div style="display: inline-block; width: 22px; height: 22px; border: 3px solid rgba(255, 255, 255, 0.1); border-top-color: #00F5A0; border-radius: 50%; animation: spin 0.8s linear infinite; margin-bottom: 8px;"></div>
      <div>Generating secure pairing QR code...</div>
    `;
  }
  if (readyEl) readyEl.style.display = 'none';

  try {
    const myDevice = cachedDesktopDeviceName || 'Windows PC';
    const startRes = await sendExtensionMessage({
      action: 'START_MOBILE_APPROVAL_REQUEST',
      payload: {
        token: currentOAuthToken,
        deviceName: myDevice,
        targetDeviceId: 'ALL',
        authMode: 'QR'
      }
    });

    if (directQrState !== 'GENERATING') {
      return;
    }

    if (!startRes || !startRes.success) {
      directQrState = 'IDLE';
      const errMsg = startRes?.error || 'Could not connect to Google Drive';
      const isAuthErr = errMsg.includes('401') || errMsg.includes('UNAUTHENTICATED') || errMsg.includes('AUTH_EXPIRED') || errMsg.includes('Invalid Credentials');

      if (isAuthErr) {
        currentOAuthToken = null;
        driveClient.setToken(null);
        if (typeof chrome !== 'undefined' && chrome.storage?.local) {
          chrome.storage.local.remove(['googleOAuthToken', 'googleAccountEmail', 'googleAccountPicture']).catch(() => {});
        }
      }

      if (loadingEl) {
        loadingEl.innerHTML = `
          <div style="color: #FF3366; font-weight: 700; font-size: 13px; margin-bottom: 6px;">
            ${isAuthErr ? '⚠️ Google Session Expired' : '⚠️ Pairing Setup Error'}
          </div>
          <div style="font-size: 11px; color: #8892B0; margin-bottom: 12px; line-height: 1.4;">
            ${isAuthErr ? 'Your Google authorization has expired or is invalid. Please sign in again to continue.' : escapeHtml(errMsg)}
          </div>
          ${isAuthErr ? `
            <button type="button" id="reauthGoogleBtn" class="btn btn-google" style="margin: 0 auto; display: flex; align-items: center; justify-content: center; gap: 8px;">
              <img src="icons/google_logo.svg" alt="G" class="google-logo" style="width: 16px; height: 16px;" />
              <span>Sign in with Google Account</span>
            </button>
          ` : `
            <button type="button" id="retryDirectQrBtn" class="btn-refresh-qr">🔄 Try Again</button>
          `}
        `;
        if (isAuthErr) {
          document.getElementById('reauthGoogleBtn')?.addEventListener('click', handleGoogleSignIn);
        } else {
          document.getElementById('retryDirectQrBtn')?.addEventListener('click', () => startDirectQrPairing(true));
        }
      }
      return;
    }

    const requestId = startRes.requestId;
    currentDirectQrRequestId = requestId;
    qrSessionExpiresAt = Date.now() + 30000; // Strictly 30 seconds
    isQrExpired = false;
    directQrState = 'ACTIVE';

    if (canvas && window.renderQRCode) {
      const pairUri = `tetherpass://pair?req=${encodeURIComponent(requestId)}&dev=${encodeURIComponent(myDevice)}`;
      window.renderQRCode(canvas, pairUri, { size: 140 });
    }

    if (loadingEl) loadingEl.style.display = 'none';
    if (readyEl) readyEl.style.display = 'block';

    const updateCountdown = () => {
      const remainingSecs = Math.max(0, Math.ceil((qrSessionExpiresAt - Date.now()) / 1000));
      if (timerEl && !isQrExpired) {
        timerEl.textContent = `Waiting for scan (${remainingSecs}s)...`;
      }
      return remainingSecs;
    };

    updateCountdown();

    activeDirectQrCountdown = setInterval(() => {
      const remaining = updateCountdown();
      if (remaining <= 0) {
        markQrCodeExpired();
      }
    }, 1000);

    // Poll for mobile scan approval (fast 800ms)
    activeDirectQrInterval = setInterval(async () => {
      if (!currentDirectQrRequestId || directQrState !== 'ACTIVE') return;
      const pollRes = await sendExtensionMessage({
        action: 'POLL_MOBILE_APPROVAL',
        payload: {
          token: currentOAuthToken,
          requestId,
          masterPassword: ''
        }
      });

      if (!pollRes) return;

      if (pollRes.status === 'APPROVED' && pollRes.success) {
        stopDirectQrPairing(true);
        hideMessages();
        const anim = showTransitionAnimation({
          mode: 'connect',
          title: 'Connecting to Phone...',
          subtitle: 'Mobile QR Verified! Decrypting vault...'
        });
        await new Promise(r => setTimeout(r, 650));
        applyUnlockedUI(pollRes);
        await anim.finish({
          title: 'Connected & Unlocked!',
          subtitle: 'Vault is active for 30 minutes.'
        });
      } else if (pollRes.status === 'DENIED') {
        stopDirectQrPairing(true);
        showError('Pairing request was denied on mobile phone.');
      } else if (pollRes.status === 'EXPIRED') {
        markQrCodeExpired();
      }
    }, 800);

  } catch (err) {
    directQrState = 'IDLE';
    const errMsg = err?.message || '';
    const isAuthErr = errMsg.includes('401') || errMsg.includes('UNAUTHENTICATED') || errMsg.includes('AUTH_EXPIRED') || errMsg.includes('Invalid Credentials');

    if (isAuthErr) {
      currentOAuthToken = null;
      driveClient.setToken(null);
      if (typeof chrome !== 'undefined' && chrome.storage?.local) {
        chrome.storage.local.remove(['googleOAuthToken', 'googleAccountEmail', 'googleAccountPicture']).catch(() => {});
      }
    }

    if (loadingEl) {
      loadingEl.style.display = 'block';
      if (readyEl) readyEl.style.display = 'none';
      loadingEl.innerHTML = `
        <div style="color: #FF3366; font-weight: 700; font-size: 13px; margin-bottom: 6px;">
          ${isAuthErr ? '⚠️ Google Session Expired' : '⚠️ Pairing Setup Error'}
        </div>
        <div style="color: #8892B0; font-size: 11px; margin-bottom: 12px; line-height: 1.4;">
          ${isAuthErr ? 'Your Google authorization has expired or is invalid. Please sign in again to continue.' : escapeHtml(errMsg)}
        </div>
        ${isAuthErr ? `
          <button type="button" id="reauthGoogleErrBtn" class="btn btn-google" style="margin: 0 auto; display: flex; align-items: center; justify-content: center; gap: 8px;">
            <img src="icons/google_logo.svg" alt="G" class="google-logo" style="width: 16px; height: 16px;" />
            <span>Sign in with Google Account</span>
          </button>
        ` : `
          <button type="button" id="retryDirectQrErrBtn" class="btn-refresh-qr">🔄 Try Again</button>
        `}
      `;
      if (isAuthErr) {
        document.getElementById('reauthGoogleErrBtn')?.addEventListener('click', handleGoogleSignIn);
      } else {
        document.getElementById('retryDirectQrErrBtn')?.addEventListener('click', () => startDirectQrPairing(true));
      }
    }
  }
}

let cachedAuthExpiresAt = null;

function updateCountdownDisplay() {
  if (!cachedAuthExpiresAt) return;
  const remainingMs = cachedAuthExpiresAt - Date.now();
  const timer = document.getElementById('sessionTimer');
  if (remainingMs <= 0) {
    if (timer) timer.textContent = 'Session Expired';
    cachedAuthExpiresAt = null;
    refreshStatus();
    return;
  }
  const mins = Math.floor(remainingMs / 60000);
  const secs = Math.floor((remainingMs % 60000) / 1000);
  if (timer) {
    timer.textContent = mins > 0 ? `Expires in ${mins}m ${secs}s` : `Expires in ${secs}s`;
  }
}

function normalizeRawVaultItems(rawItems) {
  const cards = [];
  const bankAccounts = [];
  const passwords = [];

  if (!Array.isArray(rawItems)) return { cards, bankAccounts, passwords };

  for (const item of rawItems) {
    const type = (item.type || '').toLowerCase();
    const isPassword = type === 'password';
    const rawCardNumber = String(item.card_number || item.cardNumber || item.number || item.cardNo || item.card_no || '').replace(/\s+/g, '');
    const isCard = !isPassword && (type === 'card' || (!type.includes('bank') && (rawCardNumber.length >= 12 || (item.card_network || item.cardNetwork))));

    if (isPassword) {
      passwords.push({
        id: item.id || String(Math.random()),
        nickname: item.nickname || item.bank_name || 'Website Password',
        website: item.website || '',
        username: item.user_id || item.userId || item.username || '',
        password: item.login_password || item.loginPassword || item.password || '',
        totpSecret: item.totp_secret || item.totpSecret || '',
        notes: item.notes || ''
      });
    } else if (isCard) {
      cards.push({
        id: item.id || String(Math.random()),
        nickname: item.nickname || item.name || item.card_holder || item.cardHolder || 'Card',
        bankName: item.bank_name || item.bankName || 'Card',
        cardNumber: rawCardNumber,
        cardHolder: item.card_holder || item.cardHolder || '',
        expiry: item.expiry || item.card_expiry || item.cardExpiry || '',
        cvv: item.cvv || item.card_cvv || item.cardCvv || '',
        cardNetwork: item.card_network || item.cardNetwork || 'Visa',
        isCredit: (item.card_type || item.cardType || '').toLowerCase().includes('credit') || !!item.isCredit,
        isDebit: (item.card_type || item.cardType || '').toLowerCase().includes('debit') || !!item.isDebit
      });
    } else {
      let rawAccounts = [];
      if (item.accounts) {
        try {
          rawAccounts = typeof item.accounts === 'string' ? JSON.parse(item.accounts) : item.accounts;
        } catch (_) {}
      }

      const normalizedAccounts = [];
      if (Array.isArray(rawAccounts) && rawAccounts.length > 0) {
        for (const a of rawAccounts) {
          const accNum = String(a.account_number || a.accountNumber || a.accountNo || a.acc_num || a.acc_no || a.accNo || '').trim();
          const ifsc = String(a.ifsc_code || a.ifscCode || a.ifsc || '').trim().toUpperCase();
          if (accNum || ifsc) {
            normalizedAccounts.push({
              accountNumber: accNum,
              ifscCode: ifsc,
              label: a.label || ''
            });
          }
        }
      }

      const primaryAcc = String(item.account_number || item.accountNumber || item.accountNo || item.acc_num || item.acc_no || item.accNo || '').trim();
      const primaryIfsc = String(item.ifsc_code || item.ifscCode || item.ifsc || '').trim().toUpperCase();
      if ((primaryAcc || primaryIfsc) && !normalizedAccounts.some(a => a.accountNumber === primaryAcc && a.accountNumber !== '')) {
        normalizedAccounts.unshift({
          accountNumber: primaryAcc,
          ifscCode: primaryIfsc,
          label: 'Primary'
        });
      }

      bankAccounts.push({
        id: item.id || String(Math.random()),
        bankName: item.bank_name || item.bankName || item.nickname || 'Bank',
        nickname: item.nickname || '',
        website: item.website || item.url || '',
        accounts: normalizedAccounts,
        userId: item.user_id || item.userId || item.username || '',
        cifNumber: item.cif_number || item.cifNumber || item.cif || '',
        loginPassword: item.login_password || item.loginPassword || item.password || '',
        profilePassword: item.profile_password || item.profilePassword || '',
        mpin: item.mpin || '',
        notes: item.notes || ''
      });
    }
  }

  return { cards, bankAccounts, passwords };
}

function applyUnlockedUI(data) {
  if (!data) return;
  hideMessages();
  stopDirectQrPairing();
  cancelApprovalPolling();
  const statusBadge = document.getElementById('statusBadge');
  const statusText = document.getElementById('statusText');
  const lockedView = document.getElementById('lockedView');
  const unlockedView = document.getElementById('unlockedView');
  const unlinkedBox = document.getElementById('oauthUnlinkedBox');
  const linkedBox = document.getElementById('oauthLinkedBox');

  if (unlinkedBox) unlinkedBox.style.display = 'none';
  if (linkedBox) {
    linkedBox.classList.remove('hidden');
    linkedBox.style.display = 'flex';
  }

  if (statusBadge) statusBadge.className = 'status-badge unlocked';
  if (statusText) statusText.textContent = 'Unlocked';
  if (lockedView) {
    lockedView.style.display = 'none';
    lockedView.classList.remove('active');
  }
  if (unlockedView) {
    unlockedView.style.display = 'block';
    unlockedView.classList.add('active');
  }

  const expAt = data.authExpiresAt || data.expiresAt;
  if (expAt) {
    cachedAuthExpiresAt = expAt;
    updateCountdownDisplay();
  }

  let items = data.suggestions || data.items;
  if (Array.isArray(items)) {
    items = normalizeRawVaultItems(items);
  }

  if (items && (items.cards || items.bankAccounts || items.passwords)) {
    currentVaultItems = items;
    updateCounts();

    // Context-sensitive tab selection: if the active page matches a bank or website password, switch to it automatically
    if (currentActiveTabDomain) {
      const hasBankMatch = (items.bankAccounts || []).some(b => doesDomainMatch(b.website, currentActiveTabDomain, [b.bankName, b.nickname].filter(Boolean).join(' ')));
      const hasPwdMatch = (items.passwords || []).some(p => doesDomainMatch(p.website, currentActiveTabDomain, p.nickname));

      if (hasBankMatch) {
        currentTab = 'banks';
      } else if (hasPwdMatch) {
        currentTab = 'passwords';
      }
      document.querySelectorAll('.tab-btn').forEach(btn => {
        if (btn.getAttribute('data-tab') === currentTab) {
          btn.classList.add('active');
        } else {
          btn.classList.remove('active');
        }
      });
    }

    renderVaultList();
  }
}

function applyLockedUI(autoStartQr = true) {
  cachedAuthExpiresAt = null;
  const statusBadge = document.getElementById('statusBadge');
  const statusText = document.getElementById('statusText');
  const lockedView = document.getElementById('lockedView');
  const unlockedView = document.getElementById('unlockedView');
  const unlinkedBox = document.getElementById('oauthUnlinkedBox');
  const linkedBox = document.getElementById('oauthLinkedBox');

  // If user has not connected Google Account, show ONLY the Sign In button!
  if (!currentGoogleAccount || !currentOAuthToken) {
    if (statusBadge) statusBadge.className = 'status-badge locked';
    if (statusText) statusText.textContent = 'Not Connected';
    if (unlinkedBox) unlinkedBox.style.display = 'block';
    if (linkedBox) {
      linkedBox.style.display = 'none';
      linkedBox.classList.add('hidden');
    }
    if (lockedView) {
      lockedView.style.display = 'none';
      lockedView.classList.remove('active');
    }
    if (unlockedView) {
      unlockedView.style.display = 'none';
      unlockedView.classList.remove('active');
    }
    stopDirectQrPairing(true);
    return;
  }

  // Account IS connected: Show account strip & unlock options
  if (unlinkedBox) unlinkedBox.style.display = 'none';
  if (linkedBox) {
    linkedBox.classList.remove('hidden');
    linkedBox.style.display = 'flex';
  }

  if (statusBadge) statusBadge.className = 'status-badge locked';
  if (statusText) statusText.textContent = 'Locked';
  if (lockedView) {
    lockedView.style.display = 'block';
    lockedView.classList.add('active');
  }
  if (unlockedView) {
    unlockedView.style.display = 'none';
    unlockedView.classList.remove('active');
  }
  currentVaultItems = { cards: [], bankAccounts: [], passwords: [] };
  const vaultList = document.getElementById('vaultList');
  if (vaultList) vaultList.innerHTML = '';

  const qrBtn = document.getElementById('tabModeQrBtn');
  if (autoStartQr && (!qrBtn || qrBtn.classList.contains('active')) && currentOAuthToken && directQrState === 'IDLE') {
    startDirectQrPairing(false);
  }
}

function fillPageWithCard(card, btn) {
  if (typeof chrome === 'undefined' || !chrome.tabs) return;
  chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
    if (tabs && tabs[0] && tabs[0].id) {
      chrome.tabs.sendMessage(tabs[0].id, {
        action: 'FILL_CARD_NOW',
        card: card
      }, (res) => {
        if (btn) {
          const original = btn.textContent;
          btn.textContent = res && res.count > 0 ? `✓ Filled (${res.count})` : '✓ Sent!';
          btn.classList.add('copied');
          setTimeout(() => {
            btn.textContent = original;
            btn.classList.remove('copied');
          }, 1800);
        }
      });
    }
  });
}

function fillPageWithBank(bank, btn) {
  if (typeof chrome === 'undefined' || !chrome.tabs) return;
  chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
    if (tabs && tabs[0] && tabs[0].id) {
      chrome.tabs.sendMessage(tabs[0].id, {
        action: 'FILL_BANK_NOW',
        bank: bank
      }, (res) => {
        if (btn) {
          const original = btn.textContent;
          btn.textContent = res && res.count > 0 ? `✓ Filled (${res.count})` : '✓ Sent!';
          btn.classList.add('copied');
          setTimeout(() => {
            btn.textContent = original;
            btn.classList.remove('copied');
          }, 1800);
        }
      });
    }
  });
}

function fillPageWithPassword(pwd, btn) {
  if (typeof chrome === 'undefined' || !chrome.tabs) return;
  chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
    if (tabs && tabs[0] && tabs[0].id) {
      chrome.tabs.sendMessage(tabs[0].id, {
        action: 'FILL_PASSWORD_NOW',
        password: pwd
      }, (res) => {
        if (btn) {
          const original = btn.textContent;
          btn.textContent = res && res.count > 0 ? `✓ Filled (${res.count})` : '✓ Sent!';
          btn.classList.add('copied');
          setTimeout(() => {
            btn.textContent = original;
            btn.classList.remove('copied');
          }, 1800);
        }
      });
    }
  });
}

async function refreshStatus() {
  if (!currentGoogleAccount || !currentOAuthToken) {
    applyLockedUI(false);
    return;
  }
  const status = await sendExtensionMessage({ action: 'GET_STATUS' });
  if (status && status.isAuthorized && status.isUnlocked) {
    applyUnlockedUI(status);
  } else if (status && !status.isUnlocked) {
    const lockedView = document.getElementById('lockedView');
    const isCurrentlyLocked = lockedView && lockedView.classList.contains('active');
    if (!isCurrentlyLocked) {
      applyLockedUI(true);
    }
  }
}

function handleLock() {
  const anim = showTransitionAnimation({
    mode: 'disconnect',
    title: 'Securing Vault...',
    subtitle: 'Locking session and clearing sensitive data from memory...'
  });

  stopDirectQrPairing(true);
  cancelApprovalPolling();
  currentVaultItems = { cards: [], bankAccounts: [], passwords: [] };

  // Notify background script to clear in-memory credentials and update Drive
  sendExtensionMessage({
    action: 'LOCK_VAULT',
    payload: { token: currentOAuthToken }
  }).then(async () => {
    await anim.finish({
      title: 'Vault Locked & Protected',
      subtitle: 'Session terminated. Point your phone camera to reconnect.'
    });
    applyLockedUI(false);
    startDirectQrPairing(true);
  }).catch(async () => {
    await anim.finish({
      title: 'Vault Locked',
      subtitle: 'Local cache cleared.'
    });
    applyLockedUI(false);
    startDirectQrPairing(true);
  });
}

function showError(msg) {
  const errorBanner = document.getElementById('authError');
  if (errorBanner) {
    errorBanner.textContent = msg;
    errorBanner.style.display = 'block';
  }
}

function showSuccess(msg) {
  const successBanner = document.getElementById('authSuccess');
  if (successBanner) {
    successBanner.textContent = msg;
    successBanner.style.display = 'block';
  }
}

function hideMessages() {
  const err = document.getElementById('authError');
  const succ = document.getElementById('authSuccess');
  if (err) err.style.display = 'none';
  if (succ) succ.style.display = 'none';
}

function updateCounts() {
  const cardsCount = document.getElementById('cardsCount');
  const banksCount = document.getElementById('banksCount');
  const pwdCount = document.getElementById('pwdCount');

  const cards = currentVaultItems.cards || [];
  const banks = currentVaultItems.bankAccounts || [];
  const passwords = currentVaultItems.passwords || [];
  const pwdBanks = banks.filter(b => b.loginPassword || b.profilePassword || b.mpin);

  if (cardsCount) cardsCount.textContent = cards.length;
  if (banksCount) banksCount.textContent = banks.reduce((sum, b) => sum + (b.accounts?.length || 1), 0);
  if (pwdCount) pwdCount.textContent = passwords.length + pwdBanks.length;
}

function renderVaultList(query = '') {
  const list = document.getElementById('vaultList');
  if (!list) return;

  list.innerHTML = '';

  if (currentTab === 'cards') {
    const cards = (currentVaultItems.cards || []).filter(c => {
      if (!query) return true;
      return (c.bankName || '').toLowerCase().includes(query) ||
             (c.nickname || '').toLowerCase().includes(query) ||
             (c.cardNumber || '').includes(query);
    });

    if (cards.length === 0) {
      list.innerHTML = '<div style="padding:20px;text-align:center;color:#8892B0;font-size:12px;">No matching cards found.</div>';
      return;
    }

    cards.forEach(card => {
      const tile = document.createElement('div');
      tile.className = 'card-tile';
      const rawNum = String(card.cardNumber || '').replace(/\s+/g, '');
      const formattedNum = rawNum.replace(/(\d{4})/g, '$1 ').trim();

      tile.innerHTML = `
        <div class="tile-header">
          <span class="tile-title">${escapeHtml(card.nickname)} (${escapeHtml(card.bankName)})</span>
          <span class="tile-badge">${card.isDebit ? 'DEBIT' : 'CREDIT'}</span>
        </div>
        <div class="tile-number">${formattedNum || '•••• •••• •••• ••••'}</div>
        <div class="tile-actions">
          <button class="copy-chip fill-page-chip" title="Autofill this card into current active web page">⚡ Fill Page</button>
          <button class="copy-chip" data-copy="${rawNum}">Copy Number</button>
          ${card.expiry ? `<button class="copy-chip" data-copy="${card.expiry}">Exp: ${card.expiry}</button>` : ''}
          ${card.cvv ? `<button class="copy-chip" data-copy="${card.cvv}">CVV</button>` : ''}
          <button class="copy-chip" data-copy="${rawNum} ${card.expiry || ''} ${card.cvv || ''}">📋 All</button>
        </div>
      `;

      const fillBtn = tile.querySelector('.fill-page-chip');
      if (fillBtn) {
        fillBtn.addEventListener('click', (e) => {
          e.stopPropagation();
          fillPageWithCard(card, fillBtn);
        });
      }

      list.appendChild(tile);
    });
  } else if (currentTab === 'banks') {
    const banks = (currentVaultItems.bankAccounts || []).filter(b => {
      if (!query) return true;
      const q = query.toLowerCase();
      const accMatch = (b.accounts || []).some(a => (a.accountNumber || '').includes(q) || (a.ifscCode || '').toLowerCase().includes(q));
      const credMatch = (b.userId || '').toLowerCase().includes(q) || (b.cifNumber || '').toLowerCase().includes(q);
      return (b.bankName || '').toLowerCase().includes(q) || (b.nickname || '').toLowerCase().includes(q) || accMatch || credMatch;
    });

    if (banks.length === 0) {
      list.innerHTML = '<div style="padding:20px;text-align:center;color:#8892B0;font-size:12px;">No matching bank accounts.</div>';
      return;
    }

    // Partition matching banks for this page vs other banks
    const matchingBanks = [];
    const otherBanks = [];
    banks.forEach(b => {
      if (currentActiveTabDomain && doesDomainMatch(b.website, currentActiveTabDomain, [b.bankName, b.nickname].filter(Boolean).join(' '))) {
        matchingBanks.push(b);
      } else {
        otherBanks.push(b);
      }
    });

    const renderBankTile = (bank, isMatch = false) => {
      const accs = Array.isArray(bank.accounts) && bank.accounts.length > 0 ? bank.accounts : [];
      const hasCreds = !!(bank.userId || bank.loginPassword || bank.profilePassword || bank.mpin || bank.cifNumber);
      const webUrl = bank.website ? (bank.website.startsWith('http') ? bank.website : 'https://' + bank.website) : '';

      const tile = document.createElement('div');
      tile.className = 'card-tile';
      if (isMatch) {
        tile.style.border = '1px solid #00F5A0';
        tile.style.backgroundColor = 'rgba(0, 245, 160, 0.08)';
      }

      let accountsHtml = '';
      if (accs.length > 0) {
        accountsHtml = accs.map((acc, i) => `
          <div style="background:#141E34;border:1px solid #1E293B;border-radius:6px;padding:6px 8px;margin-top:4px;">
            <div style="font-size:11px;font-weight:700;color:#F8FAFC;display:flex;justify-content:space-between;font-family:var(--font-mono);">
              <span>A/C: ${escapeHtml(acc.accountNumber || '—')}</span>
              ${acc.label ? `<span style="font-size:10px;color:#8892B0;">${escapeHtml(acc.label)}</span>` : ''}
            </div>
            <div style="font-size:11px;color:#8892B0;font-family:var(--font-mono);">IFSC: <strong style="color:#00E5FF;">${escapeHtml(acc.ifscCode || 'None')}</strong></div>
          </div>
        `).join('');
      }

      let credsHtml = '';
      if (hasCreds) {
        credsHtml = `
          <div style="background:#141E34;border:1px solid #1E293B;border-radius:6px;padding:6px 8px;margin-top:4px;font-size:11px;display:flex;flex-direction:column;gap:3px;font-family:var(--font-mono);">
            ${bank.userId ? `<div style="color:#F8FAFC;">👤 User / Customer ID: <strong style="color:#00F5A0;">${escapeHtml(bank.userId)}</strong></div>` : ''}
            ${bank.loginPassword ? `<div style="color:#8892B0;">🔑 Login Password: <strong>••••••••</strong></div>` : ''}
            ${bank.cifNumber ? `<div style="color:#8892B0;">🏷️ CIF: <strong style="color:#F8FAFC;">${escapeHtml(bank.cifNumber)}</strong></div>` : ''}
            ${bank.mpin ? `<div style="color:#8892B0;">🔢 MPIN: <strong style="color:#F8FAFC;">••••</strong></div>` : ''}
          </div>
        `;
      }

      // Action buttons
      let actionBtns = [];
      actionBtns.push(`<button class="copy-chip fill-page-chip bank-fill-btn">⚡ Fill Bank Page</button>`);
      if (bank.userId) {
        actionBtns.push(`<button class="copy-chip" data-copy="${escapeHtml(bank.userId)}">Copy User ID</button>`);
      }
      if (bank.loginPassword) {
        actionBtns.push(`<button class="copy-chip" data-copy="${escapeHtml(bank.loginPassword)}">Copy Password</button>`);
      }
      if (accs.length > 0) {
        if (accs[0].accountNumber) actionBtns.push(`<button class="copy-chip" data-copy="${escapeHtml(accs[0].accountNumber)}">Copy A/C</button>`);
        if (accs[0].ifscCode) actionBtns.push(`<button class="copy-chip" data-copy="${escapeHtml(accs[0].ifscCode)}">Copy IFSC</button>`);
        if (accs[0].accountNumber && accs[0].ifscCode) actionBtns.push(`<button class="copy-chip" data-copy="A/C: ${escapeHtml(accs[0].accountNumber)} | IFSC: ${escapeHtml(accs[0].ifscCode)}">Copy Both</button>`);
      }
      if (bank.cifNumber) {
        actionBtns.push(`<button class="copy-chip" data-copy="${escapeHtml(bank.cifNumber)}">Copy CIF</button>`);
      }
      if (webUrl) {
        actionBtns.push(`<button class="copy-chip open-site" data-url="${escapeHtml(webUrl)}" data-userid="${escapeHtml(bank.userId || '')}">🌐 Open Portal</button>`);
      }

      tile.innerHTML = `
        <div class="tile-header">
          <span class="tile-title">🏦 ${escapeHtml(bank.bankName || 'Bank')} ${bank.nickname && bank.nickname !== bank.bankName ? '(' + escapeHtml(bank.nickname) + ')' : ''}</span>
          ${isMatch ? '<span class="tile-badge badge-match">⭐ MATCHES TAB</span>' : '<span class="tile-badge">BANK</span>'}
        </div>
        ${webUrl ? `<div style="font-size:11px;color:#38BDF8;margin-bottom:2px;word-break:break-all;">🔗 ${escapeHtml(bank.website)}</div>` : ''}
        ${accountsHtml}
        ${credsHtml}
        <div class="tile-actions">
          ${actionBtns.join('')}
        </div>
      `;

      const fillBtn = tile.querySelector('.bank-fill-btn');
      if (fillBtn) {
        fillBtn.addEventListener('click', (e) => {
          e.stopPropagation();
          fillPageWithBank(bank, fillBtn);
        });
      }

      return tile;
    };

    if (matchingBanks.length > 0) {
      const matchHeader = document.createElement('div');
      matchHeader.style.cssText = 'padding:6px 10px;margin-bottom:6px;background:rgba(0,229,255,0.1);border:1px solid rgba(0,229,255,0.3);border-radius:8px;font-size:11px;font-weight:bold;color:#00E5FF;display:flex;align-items:center;gap:6px;';
      matchHeader.innerHTML = `<span>⭐ Suggested for <strong>${escapeHtml(currentActiveTabDomain)}</strong> (${matchingBanks.length})</span>`;
      list.appendChild(matchHeader);

      matchingBanks.forEach(b => list.appendChild(renderBankTile(b, true)));

      // If other banks exist, keep them collapsed behind a toggle button unless user searches
      if (otherBanks.length > 0) {
        if (query) {
          const otherHeader = document.createElement('div');
          otherHeader.style.cssText = 'padding:8px 4px 4px;font-size:11px;font-weight:bold;color:#8892B0;text-transform:uppercase;letter-spacing:0.8px;';
          otherHeader.textContent = `All Other Banks (${otherBanks.length})`;
          list.appendChild(otherHeader);
          otherBanks.forEach(b => list.appendChild(renderBankTile(b, false)));
        } else {
          const toggleWrap = document.createElement('div');
          toggleWrap.style.cssText = 'text-align:center;margin-top:14px;margin-bottom:8px;';
          const toggleBtn = document.createElement('button');
          toggleBtn.className = 'btn-toggle-others';
          toggleBtn.style.cssText = 'background:#141E34;border:1px dashed rgba(255,255,255,0.15);border-radius:8px;padding:8px 16px;color:#8892B0;font-size:11px;font-weight:600;cursor:pointer;width:100%;transition:all 0.15s ease;';
          toggleBtn.textContent = `▾ Show Other Bank Accounts (${otherBanks.length})`;

          const otherContainer = document.createElement('div');
          otherContainer.style.display = 'none';
          otherContainer.style.marginTop = '8px';
          otherBanks.forEach(b => otherContainer.appendChild(renderBankTile(b, false)));

          toggleBtn.addEventListener('click', () => {
            if (otherContainer.style.display === 'none') {
              otherContainer.style.display = 'block';
              toggleBtn.textContent = `▴ Hide Other Bank Accounts (${otherBanks.length})`;
            } else {
              otherContainer.style.display = 'none';
              toggleBtn.textContent = `▾ Show Other Bank Accounts (${otherBanks.length})`;
            }
          });

          toggleWrap.appendChild(toggleBtn);
          list.appendChild(toggleWrap);
          list.appendChild(otherContainer);
        }
      }
    } else {
      // No domain match (e.g. on new tab or unlisted domain) -> list all banks
      banks.forEach(b => list.appendChild(renderBankTile(b, false)));
    }
  } else if (currentTab === 'passwords') {
    const pwds = (currentVaultItems.passwords || []).filter(p => {
      if (!query) return true;
      const q = query.toLowerCase();
      return (p.nickname || '').toLowerCase().includes(q) ||
             (p.website || '').toLowerCase().includes(q) ||
             (p.username || '').toLowerCase().includes(q);
    });

    const banksWithCreds = (currentVaultItems.bankAccounts || []).filter(b => {
      const hasCreds = b.userId || b.loginPassword || b.profilePassword || b.mpin;
      if (!query) return hasCreds;
      const q = query.toLowerCase();
      return hasCreds &&
             ((b.bankName || '').toLowerCase().includes(q) ||
              (b.nickname || '').toLowerCase().includes(q) ||
              (b.userId || '').toLowerCase().includes(q) ||
              (b.cifNumber || '').toLowerCase().includes(q));
    });

    if (pwds.length === 0 && banksWithCreds.length === 0) {
      list.innerHTML = '<div style="padding:20px;text-align:center;color:#8892B0;font-size:12px;">No passwords saved in vault.</div>';
      return;
    }

    // Partition passwords and banks by active tab domain
    const matchingItems = [];
    const otherPwds = [];
    const otherBanks = [];

    pwds.forEach(p => {
      if (currentActiveTabDomain && doesDomainMatch(p.website, currentActiveTabDomain, p.nickname)) {
        matchingItems.push({ type: 'pwd', data: p });
      } else {
        otherPwds.push(p);
      }
    });

    banksWithCreds.forEach(b => {
      if (currentActiveTabDomain && doesDomainMatch(b.website, currentActiveTabDomain, [b.bankName, b.nickname].filter(Boolean).join(' '))) {
        matchingItems.push({ type: 'bank', data: b });
      } else {
        otherBanks.push(b);
      }
    });

    const renderPwdTile = (pwd, isMatch = false) => {
      const tile = document.createElement('div');
      tile.className = 'card-tile';
      if (isMatch) {
        tile.style.border = '1px solid #00F5A0';
        tile.style.backgroundColor = 'rgba(0, 245, 160, 0.08)';
      }
      const webUrl = pwd.website ? (pwd.website.startsWith('http') ? pwd.website : 'https://' + pwd.website) : '';
      const totpBtn = pwd.totpCode ? `<button class="copy-chip" style="background:rgba(0,245,160,0.12);color:#00F5A0;border:1px solid rgba(0,245,160,0.4);font-family:var(--font-mono);font-weight:bold;" data-copy="${escapeHtml(pwd.totpCode)}">⚡ ${escapeHtml(pwd.totpCode)} (${pwd.totpSeconds}s)</button>` : '';
      tile.innerHTML = `
        <div class="tile-header">
          <span class="tile-title">🌐 ${escapeHtml(pwd.nickname)}</span>
          ${isMatch ? '<span class="tile-badge badge-match">⭐ MATCHES TAB</span>' : '<span class="tile-badge badge-web">WEB</span>'}
        </div>
        ${pwd.website ? `<div style="font-size:11px;color:#38BDF8;margin-bottom:4px;word-break:break-all;">🔗 ${escapeHtml(pwd.website)}</div>` : ''}
        <div style="font-size:11px;color:#8892B0;margin-bottom:6px;font-family:var(--font-mono);">👤 User: <strong style="color:#F8FAFC;">${escapeHtml(pwd.username || 'N/A')}</strong></div>
        <div class="tile-actions">
          <button class="copy-chip fill-page-chip pwd-fill-btn">⚡ Fill Page</button>
          ${pwd.username ? `<button class="copy-chip" data-copy="${escapeHtml(pwd.username)}">Copy User</button>` : ''}
          ${pwd.password ? `<button class="copy-chip" data-copy="${escapeHtml(pwd.password)}">Copy Password</button>` : ''}
          ${totpBtn}
          ${pwd.password ? `<button class="copy-chip check-leak-btn" data-pwd="${escapeHtml(pwd.password)}">🛡️ Leak Check</button>` : ''}
          ${webUrl ? `<button class="copy-chip open-site" data-url="${escapeHtml(webUrl)}">Open Site</button>` : ''}
        </div>
      `;
      const fillBtn = tile.querySelector('.pwd-fill-btn');
      if (fillBtn) {
        fillBtn.addEventListener('click', (e) => {
          e.stopPropagation();
          fillPageWithPassword(pwd, fillBtn);
        });
      }
      return tile;
    };

    const renderBankLoginTile = (bank, isMatch = false) => {
      const tile = document.createElement('div');
      tile.className = 'card-tile';
      if (isMatch) {
        tile.style.border = '1px solid #00F5A0';
        tile.style.backgroundColor = 'rgba(0, 245, 160, 0.08)';
      }
      const webUrl = bank.website ? (bank.website.startsWith('http') ? bank.website : 'https://' + bank.website) : '';
      tile.innerHTML = `
        <div class="tile-header">
          <span class="tile-title">🏦 ${escapeHtml(bank.bankName)} NetBanking</span>
          ${isMatch ? '<span class="tile-badge badge-match">⭐ MATCHES TAB</span>' : '<span class="tile-badge">BANK LOGIN</span>'}
        </div>
        ${bank.website ? `<div style="font-size:11px;color:#38BDF8;margin-bottom:4px;word-break:break-all;">🔗 ${escapeHtml(bank.website)}</div>` : ''}
        <div style="font-size:11px;color:#8892B0;margin-bottom:4px;font-family:var(--font-mono);">👤 Customer / User ID: <strong style="color:#00F5A0;">${escapeHtml(bank.userId || 'N/A')}</strong></div>
        ${bank.loginPassword ? `<div style="font-size:11px;color:#8892B0;margin-bottom:6px;font-family:var(--font-mono);">🔑 Password: <strong>••••••••</strong></div>` : ''}
        <div class="tile-actions">
          <button class="copy-chip fill-page-chip bank-fill-btn">⚡ Fill Bank Page</button>
          ${bank.userId ? `<button class="copy-chip" data-copy="${escapeHtml(bank.userId)}">Copy Customer ID</button>` : ''}
          ${bank.loginPassword ? `<button class="copy-chip" data-copy="${escapeHtml(bank.loginPassword)}">Copy Password</button>` : ''}
          ${bank.mpin ? `<button class="copy-chip" data-copy="${escapeHtml(bank.mpin)}">Copy MPIN</button>` : ''}
          ${bank.cifNumber ? `<button class="copy-chip" data-copy="${escapeHtml(bank.cifNumber)}">Copy CIF</button>` : ''}
          ${webUrl ? `<button class="copy-chip open-site" data-url="${escapeHtml(webUrl)}" data-userid="${escapeHtml(bank.userId || '')}">🌐 Open Portal</button>` : ''}
        </div>
      `;
      const fillBtn = tile.querySelector('.bank-fill-btn');
      if (fillBtn) {
        fillBtn.addEventListener('click', (e) => {
          e.stopPropagation();
          fillPageWithBank(bank, fillBtn);
        });
      }
      return tile;
    };

    // 1. Suggested for Active Tab (prioritized at the top)
    if (matchingItems.length > 0) {
      const matchHeader = document.createElement('div');
      matchHeader.style.cssText = 'padding:6px 10px;margin-bottom:6px;background:rgba(0,229,255,0.1);border:1px solid rgba(0,229,255,0.3);border-radius:8px;font-size:11px;font-weight:bold;color:#00E5FF;display:flex;align-items:center;gap:6px;';
      matchHeader.innerHTML = `<span>⭐ Suggested for <strong>${escapeHtml(currentActiveTabDomain)}</strong> (${matchingItems.length})</span>`;
      list.appendChild(matchHeader);

      matchingItems.forEach(item => {
        if (item.type === 'pwd') list.appendChild(renderPwdTile(item.data, true));
        else if (item.type === 'bank') list.appendChild(renderBankLoginTile(item.data, true));
      });

      const totalOthers = otherPwds.length + otherBanks.length;
      if (totalOthers > 0) {
        if (query) {
          // When searching, display directly
          if (otherPwds.length > 0) {
            const pwdHeader = document.createElement('div');
            pwdHeader.style.cssText = 'padding:8px 4px 4px;font-size:11px;font-weight:bold;color:#8892B0;text-transform:uppercase;letter-spacing:0.8px;';
            pwdHeader.textContent = `Other Website Logins (${otherPwds.length})`;
            list.appendChild(pwdHeader);
            otherPwds.forEach(p => list.appendChild(renderPwdTile(p, false)));
          }
          if (otherBanks.length > 0) {
            const bankHeader = document.createElement('div');
            bankHeader.style.cssText = 'padding:8px 4px 4px;font-size:11px;font-weight:bold;color:#8892B0;text-transform:uppercase;letter-spacing:0.8px;';
            bankHeader.textContent = `Other Bank Logins (${otherBanks.length})`;
            list.appendChild(bankHeader);
            otherBanks.forEach(b => list.appendChild(renderBankLoginTile(b, false)));
          }
        } else {
          // Keep other logins collapsed so user sees ONLY what suits this website!
          const toggleWrap = document.createElement('div');
          toggleWrap.style.cssText = 'text-align:center;margin-top:14px;margin-bottom:8px;';
          const toggleBtn = document.createElement('button');
          toggleBtn.className = 'btn-toggle-others';
          toggleBtn.style.cssText = 'background:#141E34;border:1px dashed rgba(255,255,255,0.15);border-radius:8px;padding:8px 16px;color:#8892B0;font-size:11px;font-weight:600;cursor:pointer;width:100%;transition:all 0.15s ease;';
          toggleBtn.textContent = `▾ Show All Other Logins (${totalOthers})`;

          const otherContainer = document.createElement('div');
          otherContainer.style.display = 'none';
          otherContainer.style.marginTop = '8px';

          if (otherPwds.length > 0) {
            const pwdHeader = document.createElement('div');
            pwdHeader.style.cssText = 'padding:8px 4px 4px;font-size:11px;font-weight:bold;color:#8892B0;text-transform:uppercase;letter-spacing:0.8px;';
            pwdHeader.textContent = `Website Logins (${otherPwds.length})`;
            otherContainer.appendChild(pwdHeader);
            otherPwds.forEach(p => otherContainer.appendChild(renderPwdTile(p, false)));
          }
          if (otherBanks.length > 0) {
            const bankHeader = document.createElement('div');
            bankHeader.style.cssText = 'padding:8px 4px 4px;font-size:11px;font-weight:bold;color:#8892B0;text-transform:uppercase;letter-spacing:0.8px;';
            bankHeader.textContent = `Bank NetBanking Logins (${otherBanks.length})`;
            otherContainer.appendChild(bankHeader);
            otherBanks.forEach(b => otherContainer.appendChild(renderBankLoginTile(b, false)));
          }

          toggleBtn.addEventListener('click', () => {
            if (otherContainer.style.display === 'none') {
              otherContainer.style.display = 'block';
              toggleBtn.textContent = `▴ Hide Other Logins (${totalOthers})`;
            } else {
              otherContainer.style.display = 'none';
              toggleBtn.textContent = `▾ Show All Other Logins (${totalOthers})`;
            }
          });

          toggleWrap.appendChild(toggleBtn);
          list.appendChild(toggleWrap);
          list.appendChild(otherContainer);
        }
      }
    } else {
      // No domain match (e.g. on new tab or unlisted website) -> list all logins
      if (otherPwds.length > 0) {
        const pwdHeader = document.createElement('div');
        pwdHeader.style.cssText = 'padding:8px 4px 4px;font-size:11px;font-weight:bold;color:#8892B0;text-transform:uppercase;letter-spacing:0.8px;';
        pwdHeader.textContent = `Website Logins (${otherPwds.length})`;
        list.appendChild(pwdHeader);
        otherPwds.forEach(p => list.appendChild(renderPwdTile(p, false)));
      }
      if (otherBanks.length > 0) {
        const bankHeader = document.createElement('div');
        bankHeader.style.cssText = 'padding:8px 4px 4px;font-size:11px;font-weight:bold;color:#8892B0;text-transform:uppercase;letter-spacing:0.8px;';
        bankHeader.textContent = `Bank NetBanking Logins (${otherBanks.length})`;
        list.appendChild(bankHeader);
        otherBanks.forEach(b => list.appendChild(renderBankLoginTile(b, false)));
      }
    }
  }

  // Attach clipboard listener
  list.querySelectorAll('.copy-chip:not(.open-site):not(.fill-page-chip)').forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      const text = btn.getAttribute('data-copy');
      if (text) {
        navigator.clipboard.writeText(text);
        const original = btn.textContent;
        btn.textContent = 'Copied!';
        btn.classList.add('copied');
        setTimeout(() => {
          btn.textContent = original;
          btn.classList.remove('copied');
        }, 1200);
      }
    });
  });

  // Attach open-site listener with automatic credential staging
  list.querySelectorAll('.open-site').forEach(btn => {
    btn.addEventListener('click', async (e) => {
      e.stopPropagation();
      const url = btn.getAttribute('data-url');
      const userId = btn.getAttribute('data-userid');
      if (userId) {
        try {
          await navigator.clipboard.writeText(userId);
          const origText = btn.textContent;
          btn.textContent = '✓ ID Copied!';
          setTimeout(() => { btn.textContent = origText; }, 2500);
        } catch (_) {}
      }
      if (url) {
        chrome.tabs.create({ url });
      }
    });
  });

  // Attach leak check listener
  list.querySelectorAll('.check-leak-btn').forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      const pwd = btn.getAttribute('data-pwd');
      if (!pwd) return;
      btn.textContent = 'Checking...';
      chrome.runtime.sendMessage({ action: 'CHECK_BREACH', payload: { password: pwd } }, (res) => {
        if (res && res.isPwned) {
          btn.style.background = 'rgba(255, 51, 102, 0.15)';
          btn.style.color = '#FF3366';
          btn.style.borderColor = 'rgba(255, 51, 102, 0.4)';
          btn.textContent = `⚠️ Leaked (${res.breachCount})`;
        } else {
          btn.style.background = 'rgba(0, 245, 160, 0.15)';
          btn.style.color = '#00F5A0';
          btn.style.borderColor = 'rgba(0, 245, 160, 0.4)';
          btn.textContent = '✅ Safe';
        }
      });
    });
  });
}

function escapeHtml(str) {
  if (!str) return '';
  return str.replace(/[&<>'"]/g, t => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' }[t] || t));
}
