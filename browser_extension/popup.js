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

function extractBaseBrand(domain) {
  if (!domain) return '';
  const clean = extractDomain(domain);
  const parts = clean.split('.');
  if (parts.length <= 1) return parts[0];
  const multiTlds = ['co', 'com', 'org', 'net', 'edu', 'gov', 'ac'];
  if (parts.length >= 3 && multiTlds.includes(parts[parts.length - 2])) {
    return parts[parts.length - 3];
  }
  return parts[parts.length - 2];
}

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
      if (itemBrand && pageBrand && itemBrand === pageBrand && itemBrand.length >= 3) {
        return true;
      }
    }

    const rawClean = itemWebsite.trim().toLowerCase().replace(/^[a-zA-Z]+:\/\//, '').replace(/^www\./, '');
    if (rawClean.length >= 3) {
      if (pageDom.includes(rawClean) || rawClean.includes(pageDom)) return true;
      if (pageBrand && (pageBrand === rawClean || pageBrand.includes(rawClean) || rawClean.includes(pageBrand))) {
        return true;
      }
    }
  }

  // 2. Nickname match against page brand (e.g. nickname "Amazon", "Amazon India", "Flipkart" on amazon.in)
  if (itemNickname && itemNickname.trim() && pageBrand && pageBrand.length >= 3) {
    const nick = itemNickname.trim().toLowerCase();
    const nickClean = nick.replace(/[^a-z0-9]/g, '');
    if (nickClean === pageBrand || (nickClean.length >= 4 && (pageBrand.includes(nickClean) || nickClean.includes(pageBrand)))) {
      return true;
    }
    const stopWords = ['bank', 'banking', 'netbanking', 'login', 'portal', 'app', 'account', 'card', 'pass', 'password', 'online', 'store'];
    const tokens = nick.split(/[\s\-_.]+/).filter(t => t.length >= 3 && !stopWords.includes(t));
    if (tokens.includes(pageBrand)) return true;
    for (const t of tokens) {
      if (pageBrand === t || (t.length >= 4 && (pageBrand.includes(t) || t.includes(pageBrand)))) {
        return true;
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

  // Instant 0ms session recovery from local storage cache (ZERO delay, NO locked screen flicker)
  try {
    if (typeof chrome !== 'undefined' && chrome.storage?.local) {
      const data = await chrome.storage.local.get(['tetherpass_session', 'google_account']);
      const sess = data?.tetherpass_session;
      const now = Date.now();
      if (sess && sess.isAuthorized && sess.isUnlocked && (!sess.authExpiresAt || now < sess.authExpiresAt)) {
        applyUnlockedUI(sess);
      } else {
        applyLockedUI();
      }
    }
  } catch (_) {}

  await detectActiveTabDomain();
  await initDesktopDeviceName();
  await loadSavedGoogleAccount();
  await refreshStatus();

  // If locked and QR tab is active, automatically generate pairing QR code
  const lockedView = document.getElementById('lockedView');
  if (lockedView && lockedView.classList.contains('active')) {
    startDirectQrPairing();
  }

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
    chrome.runtime.onMessage.addListener((message) => {
      if (message && message.action === 'VAULT_STATUS_CHANGED') {
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
        'cachedBackupPayload',
        'preferredAuthMethod'
      ]);
      if (data.googleOAuthToken) {
        currentOAuthToken = data.googleOAuthToken;
        driveClient.setToken(data.googleOAuthToken);
      }
      if (data.googleAccountPicture) {
        currentGooglePicture = data.googleAccountPicture;
      }
      if (data.googleAccountEmail) {
        setConnectedGoogleAccount(data.googleAccountEmail, data.googleAccountPicture || null, false);
      } else {
        const unlinked = document.getElementById('oauthUnlinkedBox');
        if (unlinked) unlinked.style.display = 'block';
      }
      if (data.cachedBackupPayload) {
        localBackupPayload = data.cachedBackupPayload;
      }
      if (data.preferredAuthMethod) {
        setAuthMethod(data.preferredAuthMethod, false);
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
  if (linkedBox) linkedBox.style.display = 'flex';
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

  // If locked, kick off QR generation now that account is connected
  const lockedView = document.getElementById('lockedView');
  if (lockedView && lockedView.classList.contains('active')) {
    const qrBtn = document.getElementById('tabModeQrBtn');
    if (!qrBtn || qrBtn.classList.contains('active')) {
      startDirectQrPairing();
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
      setConnectedGoogleAccount('Google Drive Connected');
    }
  } catch (err) {
    showError(`Google Sign-In notice: ${err.message}`);
  } finally {
    if (btn) {
      btn.disabled = false;
      btn.innerHTML = '<img src="icons/google_logo.svg" alt="G" class="google-logo" /><span>Sign in with Google Account</span>';
    }
  }
}

async function handleDisconnectOAuth() {
  stopDirectQrPairing();
  currentOAuthToken = null;
  currentGoogleAccount = null;
  currentGooglePicture = null;
  driveClient.setToken(null);

  const profileImg = document.getElementById('accountProfileImg');
  if (profileImg) profileImg.style.display = 'none';

  if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.local) {
    await chrome.storage.local.remove(['googleAccountEmail', 'googleAccountPicture', 'googleOAuthToken']);
  }

  const unlinkedBox = document.getElementById('oauthUnlinkedBox');
  const linkedBox = document.getElementById('oauthLinkedBox');
  const step1Sub = document.getElementById('step1Subtitle');
  if (step1Sub) step1Sub.style.display = 'block';
  if (unlinkedBox) unlinkedBox.style.display = 'block';
  if (linkedBox) linkedBox.style.display = 'none';
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
    if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.local) {
      await chrome.storage.local.set({ cachedBackupPayload: localBackupPayload });
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
    let secondsLeft = 60;

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

    // 3. Start Polling for Approval
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
        showSuccess('✓ Mobile approved with Biometrics! Vault unlocked.');
        if (passwordInput) passwordInput.value = '';
        setTimeout(() => refreshStatus(), 600);
      } else if (pollRes.status === 'DENIED') {
        cancelApprovalPolling();
        showError('Access request was denied on your mobile phone.');
      } else if (pollRes.status === 'EXPIRED') {
        cancelApprovalPolling();
        showError('Access request expired on your mobile phone.');
      }
    }, 1500);

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

    // Start direct QR pairing (only if not already running a valid 30s session)
    startDirectQrPairing(false);
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
  }
}

async function startDirectQrPairing(force = false) {
  const now = Date.now();
  // Strictly enforce: regenerate ONLY after 30s or when user hits refresh
  if (!force && currentDirectQrRequestId && qrSessionExpiresAt > now) {
    return; // Current QR code is still valid and actively counting down
  }

  stopDirectQrPairing(true);

  const loadingEl = document.getElementById('qrLoadingState');
  const readyEl = document.getElementById('qrReadyState');
  const timerEl = document.getElementById('qrWaitingTimer');
  const canvas = document.getElementById('directPairingQrCanvas');

  if (!currentOAuthToken) {
    if (loadingEl) {
      loadingEl.style.display = 'block';
      loadingEl.innerHTML = `
        <div style="font-size: 24px; margin-bottom: 6px;">🔗</div>
        <div style="font-weight: 700; color: #0F172A; margin-bottom: 4px;">Sign in with Google First</div>
        <div style="font-size: 11px; color: #64748B; line-height: 1.4;">
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
      <div style="display: inline-block; width: 22px; height: 22px; border: 3px solid #E2E8F0; border-top-color: #FF6F00; border-radius: 50%; animation: spin 0.8s linear infinite; margin-bottom: 8px;"></div>
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
        authMode: 'QR' // Specifically QR mode: mobile app won't pop up unsolicited push dialog
      }
    });

    if (!startRes || !startRes.success) {
      if (loadingEl) {
        loadingEl.innerHTML = `
          <div style="color: #EF4444; font-weight: 600; margin-bottom: 6px;">⚠️ Pairing Setup Error</div>
          <div style="font-size: 11px; color: #64748B; margin-bottom: 8px;">${escapeHtml(startRes?.error || 'Could not connect to Google Drive')}</div>
          <button type="button" id="retryDirectQrBtn" class="btn-refresh-qr">🔄 Try Again</button>
        `;
        document.getElementById('retryDirectQrBtn')?.addEventListener('click', () => startDirectQrPairing(true));
      }
      return;
    }

    const requestId = startRes.requestId;
    currentDirectQrRequestId = requestId;
    qrSessionExpiresAt = Date.now() + 30000; // Exact 30-second validity window

    // Render pairing QR for mobile scan
    if (canvas && window.renderQRCode) {
      const pairUri = `tetherpass://pair?req=${encodeURIComponent(requestId)}&dev=${encodeURIComponent(myDevice)}`;
      window.renderQRCode(canvas, pairUri, { size: 140 });
    }

    if (loadingEl) loadingEl.style.display = 'none';
    if (readyEl) readyEl.style.display = 'block';

    const updateCountdown = () => {
      const remainingSecs = Math.max(0, Math.ceil((qrSessionExpiresAt - Date.now()) / 1000));
      if (timerEl) timerEl.textContent = `Waiting for scan (${remainingSecs}s)...`;
      return remainingSecs;
    };

    updateCountdown();

    activeDirectQrCountdown = setInterval(() => {
      const remaining = updateCountdown();
      if (remaining <= 0) {
        // Exactly after 30 seconds: automatically regenerate a fresh QR code
        stopDirectQrPairing(true);
        startDirectQrPairing(true);
      }
    }, 1000);

    // Poll for mobile biometric approval
    activeDirectQrInterval = setInterval(async () => {
      if (!currentDirectQrRequestId) return;
      const pollRes = await sendExtensionMessage({
        action: 'POLL_MOBILE_APPROVAL',
        payload: {
          token: currentOAuthToken,
          requestId,
          masterPassword: '' // Mobile phone provides request_sealed_key upon scan!
        }
      });

      if (!pollRes) return;

      if (pollRes.status === 'APPROVED' && pollRes.success) {
        stopDirectQrPairing(true);
        showSuccess('✓ Mobile QR Verified! Vault unlocked.');
        setTimeout(() => refreshStatus(), 400);
      } else if (pollRes.status === 'DENIED') {
        stopDirectQrPairing(true);
        showError('Pairing request was denied on mobile phone.');
      } else if (pollRes.status === 'EXPIRED') {
        stopDirectQrPairing(true);
        startDirectQrPairing(true);
      }
    }, 1200);

  } catch (err) {
    if (loadingEl) {
      loadingEl.style.display = 'block';
      if (readyEl) readyEl.style.display = 'none';
      loadingEl.innerHTML = `
        <div style="color: #EF4444; font-weight: 700; font-size: 12px; margin-bottom: 4px;">⚠️ Pairing Setup Error</div>
        <div style="color: #64748B; font-size: 11px; margin-bottom: 10px;">${escapeHtml(err.message)}</div>
        <button type="button" id="retryDirectQrErrBtn" class="btn-refresh-qr">🔄 Try Again</button>
      `;
      document.getElementById('retryDirectQrErrBtn')?.addEventListener('click', () => startDirectQrPairing(true));
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
          normalizedAccounts.push({
            accountNumber: a.account_number || a.accountNumber || '',
            ifscCode: (a.ifsc_code || a.ifscCode || '').toUpperCase(),
            label: a.label || ''
          });
        }
      }

      const primaryAcc = item.account_number || item.accountNumber || '';
      const primaryIfsc = (item.ifsc_code || item.ifscCode || '').toUpperCase();
      if (primaryAcc && !normalizedAccounts.some(a => a.accountNumber === primaryAcc)) {
        normalizedAccounts.unshift({
          accountNumber: primaryAcc,
          ifscCode: primaryIfsc,
          label: 'Primary'
        });
      }

      bankAccounts.push({
        id: item.id || String(Math.random()),
        bankName: item.bank_name || item.bankName || 'Bank',
        nickname: item.nickname || '',
        accounts: normalizedAccounts,
        userId: item.user_id || item.userId || '',
        cifNumber: item.cif_number || item.cifNumber || '',
        loginPassword: item.login_password || item.loginPassword || '',
        profilePassword: item.profile_password || item.profilePassword || '',
        mpin: item.mpin || ''
      });
    }
  }

  return { cards, bankAccounts, passwords };
}

function applyUnlockedUI(data) {
  if (!data) return;
  stopDirectQrPairing();
  cancelApprovalPolling();
  const statusBadge = document.getElementById('statusBadge');
  const statusText = document.getElementById('statusText');
  const lockedView = document.getElementById('lockedView');
  const unlockedView = document.getElementById('unlockedView');

  if (statusBadge) statusBadge.className = 'status-badge unlocked';
  if (statusText) statusText.textContent = 'Unlocked';
  lockedView?.classList.remove('active');
  unlockedView?.classList.add('active');

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
    renderVaultList();
  }
}

function applyLockedUI() {
  cachedAuthExpiresAt = null;
  const statusBadge = document.getElementById('statusBadge');
  const statusText = document.getElementById('statusText');
  const lockedView = document.getElementById('lockedView');
  const unlockedView = document.getElementById('unlockedView');

  if (statusBadge) statusBadge.className = 'status-badge locked';
  if (statusText) statusText.textContent = 'Locked';
  lockedView?.classList.add('active');
  unlockedView?.classList.remove('active');
  currentVaultItems = { cards: [], bankAccounts: [], passwords: [] };
  const vaultList = document.getElementById('vaultList');
  if (vaultList) vaultList.innerHTML = '';

  const qrBtn = document.getElementById('tabModeQrBtn');
  if ((!qrBtn || qrBtn.classList.contains('active')) && currentOAuthToken && !currentDirectQrRequestId) {
    startDirectQrPairing();
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

async function refreshStatus() {
  const status = await sendExtensionMessage({ action: 'GET_STATUS' });
  if (status && status.isAuthorized && status.isUnlocked) {
    applyUnlockedUI(status);

    // Fetch fresh dynamic TOTPs and suggestions if needed
    const res = await sendExtensionMessage({
      action: 'GET_AUTOFILL_SUGGESTIONS',
      payload: { fieldType: 'ALL' }
    });
    if (res && res.authorized) {
      applyUnlockedUI(res);
    }
  } else if (status && !status.isUnlocked) {
    applyLockedUI();
  }
}

async function handleLock() {
  stopDirectQrPairing();
  cancelApprovalPolling();
  currentVaultItems = { cards: [], bankAccounts: [], passwords: [] };
  if (currentOAuthToken) {
    driveClient.setToken(currentOAuthToken);
    try {
      await driveClient.markSessionLocked();
    } catch (_) {}
  }
  await sendExtensionMessage({
    action: 'LOCK_VAULT',
    payload: { token: currentOAuthToken }
  });
  applyLockedUI();
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
      list.innerHTML = '<div style="padding:20px;text-align:center;color:#94A3B8;font-size:12px;">No matching cards found.</div>';
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
      const accMatch = (b.accounts || []).some(a => (a.accountNumber || '').includes(query) || (a.ifscCode || '').toLowerCase().includes(query));
      return (b.bankName || '').toLowerCase().includes(query) || accMatch;
    });

    if (banks.length === 0) {
      list.innerHTML = '<div style="padding:20px;text-align:center;color:#94A3B8;font-size:12px;">No matching bank accounts.</div>';
      return;
    }

    banks.forEach(bank => {
      const accs = bank.accounts && bank.accounts.length > 0 ? bank.accounts : [{ accountNumber: 'N/A', ifscCode: '' }];
      accs.forEach((acc, i) => {
        const tile = document.createElement('div');
        tile.className = 'card-tile';
        tile.innerHTML = `
          <div class="tile-header">
            <span class="tile-title">${escapeHtml(bank.bankName)} ${accs.length > 1 ? '#' + (i + 1) : ''}</span>
            <span class="tile-badge">BANK</span>
          </div>
          <div class="tile-number">A/C: ${escapeHtml(acc.accountNumber)}</div>
          <div style="font-size:11px;color:#64748B;">IFSC: ${escapeHtml(acc.ifscCode || 'None')}</div>
          <div class="tile-actions">
            <button class="copy-chip" data-copy="${acc.accountNumber}">Copy A/C</button>
            ${acc.ifscCode ? `<button class="copy-chip" data-copy="${acc.ifscCode}">Copy IFSC</button>` : ''}
            <button class="copy-chip" data-copy="A/C: ${acc.accountNumber} | IFSC: ${acc.ifscCode}">Copy Both</button>
          </div>
        `;
        list.appendChild(tile);
      });
    });
  } else if (currentTab === 'passwords') {
    const pwds = (currentVaultItems.passwords || []).filter(p => {
      if (!query) return true;
      return (p.nickname || '').toLowerCase().includes(query) ||
             (p.website || '').toLowerCase().includes(query) ||
             (p.username || '').toLowerCase().includes(query);
    });

    const banks = (currentVaultItems.bankAccounts || []).filter(b => {
      const hasCreds = b.loginPassword || b.profilePassword || b.mpin;
      if (!query) return hasCreds;
      return hasCreds &&
             ((b.bankName || '').toLowerCase().includes(query) || (b.userId || '').toLowerCase().includes(query));
    });

    if (pwds.length === 0 && banks.length === 0) {
      list.innerHTML = '<div style="padding:20px;text-align:center;color:#94A3B8;font-size:12px;">No passwords saved in vault.</div>';
      return;
    }

    // Partition passwords by active tab domain
    const matchingPwds = [];
    const otherPwds = [];
    pwds.forEach(p => {
      if (currentActiveTabDomain && doesDomainMatch(p.website, currentActiveTabDomain, p.nickname)) {
        matchingPwds.push(p);
      } else {
        otherPwds.push(p);
      }
    });

    const renderPwdTile = (pwd, isMatch = false) => {
      const tile = document.createElement('div');
      tile.className = 'card-tile';
      if (isMatch) {
        tile.style.border = '1px solid #93C5FD';
        tile.style.backgroundColor = '#F0F9FF';
      }
      const webUrl = pwd.website ? (pwd.website.startsWith('http') ? pwd.website : 'https://' + pwd.website) : '';
      const totpBtn = pwd.totpCode ? `<button class="copy-chip" style="background:#ECFDF5;color:#059669;border-color:#A7F3D0;font-weight:bold;" data-copy="${pwd.totpCode}">⚡ ${pwd.totpCode} (${pwd.totpSeconds}s)</button>` : '';
      tile.innerHTML = `
        <div class="tile-header">
          <span class="tile-title">🌐 ${escapeHtml(pwd.nickname)}</span>
          ${isMatch ? '<span class="tile-badge" style="background:#DBEAFE;color:#1D4ED8;border-color:#93C5FD;">⭐ MATCHES TAB</span>' : '<span class="tile-badge" style="background:#EEF2FF;color:#4338CA;border-color:#C7D2FE;">WEB</span>'}
        </div>
        ${pwd.website ? `<div style="font-size:11px;color:#3B82F6;margin-bottom:4px;word-break:break-all;">🔗 ${escapeHtml(pwd.website)}</div>` : ''}
        <div style="font-size:11px;color:#475569;margin-bottom:6px;">👤 User: <strong>${escapeHtml(pwd.username || 'N/A')}</strong></div>
        <div class="tile-actions">
          ${pwd.username ? `<button class="copy-chip" data-copy="${pwd.username}">Copy User</button>` : ''}
          ${pwd.password ? `<button class="copy-chip" data-copy="${pwd.password}">Copy Password</button>` : ''}
          ${totpBtn}
          ${pwd.password ? `<button class="copy-chip check-leak-btn" data-pwd="${pwd.password}">🛡️ Leak Check</button>` : ''}
          ${webUrl ? `<button class="copy-chip open-site" data-url="${webUrl}">Open Site</button>` : ''}
        </div>
      `;
      return tile;
    };

    // If tab matches exist, prioritize them at the top
    if (matchingPwds.length > 0) {
      const matchHeader = document.createElement('div');
      matchHeader.style.cssText = 'padding:6px 10px;margin-bottom:6px;background:#EFF6FF;border-radius:6px;font-size:11px;font-weight:bold;color:#1E40AF;display:flex;align-items:center;gap:6px;';
      matchHeader.innerHTML = `<span>⭐ Suggested for <strong>${escapeHtml(currentActiveTabDomain)}</strong> (${matchingPwds.length})</span>`;
      list.appendChild(matchHeader);

      matchingPwds.forEach(p => list.appendChild(renderPwdTile(p, true)));

      if (otherPwds.length > 0) {
        const otherHeader = document.createElement('div');
        otherHeader.style.cssText = 'padding:8px 4px 4px;font-size:11px;font-weight:bold;color:#64748B;text-transform:uppercase;letter-spacing:0.5px;';
        otherHeader.textContent = `All Other Logins (${otherPwds.length})`;
        list.appendChild(otherHeader);
      }
    }

    // Render other passwords
    otherPwds.forEach(p => list.appendChild(renderPwdTile(p, false)));

    // 2. Bank Credentials (shown if searching, or if bank matches domain, or if no tab match exists)
    const shouldShowBanks = query || !currentActiveTabDomain || (matchingPwds.length === 0 && otherPwds.length === 0);
    if (shouldShowBanks && banks.length > 0) {
      if (matchingPwds.length > 0 || otherPwds.length > 0) {
        const bankHeader = document.createElement('div');
        bankHeader.style.cssText = 'padding:8px 4px 4px;font-size:11px;font-weight:bold;color:#64748B;text-transform:uppercase;letter-spacing:0.5px;';
        bankHeader.textContent = `Bank Logins (${banks.length})`;
        list.appendChild(bankHeader);
      }

      banks.forEach(bank => {
        const tile = document.createElement('div');
        tile.className = 'card-tile';
        tile.innerHTML = `
          <div class="tile-header">
            <span class="tile-title">🏦 ${escapeHtml(bank.bankName)} Credentials</span>
            <span class="tile-badge">BANK</span>
          </div>
          <div style="font-size:11px;color:#475569;margin-bottom:4px;">User: ${escapeHtml(bank.userId || 'N/A')}</div>
          <div class="tile-actions">
            ${bank.userId ? `<button class="copy-chip" data-copy="${bank.userId}">Copy User ID</button>` : ''}
            ${bank.loginPassword ? `<button class="copy-chip" data-copy="${bank.loginPassword}">Copy Password</button>` : ''}
            ${bank.mpin ? `<button class="copy-chip" data-copy="${bank.mpin}">Copy MPIN</button>` : ''}
          </div>
        `;
        list.appendChild(tile);
      });
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

  // Attach open-site listener
  list.querySelectorAll('.open-site').forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      const url = btn.getAttribute('data-url');
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
          btn.style.background = '#FEE2E2';
          btn.style.color = '#DC2626';
          btn.style.borderColor = '#FCA5A5';
          btn.textContent = `⚠️ Leaked (${res.breachCount})`;
        } else {
          btn.style.background = '#DCFCE7';
          btn.style.color = '#15803D';
          btn.style.borderColor = '#86EFAC';
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
