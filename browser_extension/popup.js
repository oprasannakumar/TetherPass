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
let currentAuthMethod = 'push'; // 'push' or 'pin'
let cachedDevices = [];

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
  await initDesktopDeviceName();
  await loadSavedGoogleAccount();
  await refreshStatus();
});

function initUI() {
  // Google OAuth connect
  document.getElementById('googleOAuthBtn')?.addEventListener('click', handleGoogleSignIn);
  document.getElementById('disconnectOAuthBtn')?.addEventListener('click', handleDisconnectOAuth);
  document.getElementById('editDesktopNameBtn')?.addEventListener('click', handleEditDesktopName);

  // Manual token & file fallback toggles
  document.getElementById('toggleManualTokenLink')?.addEventListener('click', (e) => {
    e.preventDefault();
    const box = document.getElementById('manualTokenBox');
    if (box) box.style.display = box.style.display === 'none' ? 'block' : 'none';
  });

  document.getElementById('saveCustomTokenBtn')?.addEventListener('click', handleSaveCustomToken);

  const pickFileBtn = document.getElementById('pickFileFallbackBtn');
  const fileInput = document.getElementById('localBackupFileInput');
  if (pickFileBtn && fileInput) {
    pickFileBtn.addEventListener('click', () => fileInput.click());
    fileInput.addEventListener('change', handleFileSelected);
  }

  // ── Auth Method Switching (Push vs PIN) ──
  document.getElementById('authMethodPushTab')?.addEventListener('click', () => setAuthMethod('push'));
  document.getElementById('authMethodPinTab')?.addEventListener('click', () => setAuthMethod('pin'));


  // Push confirmation to mobile phone
  document.getElementById('requestPushApprovalBtn')?.addEventListener('click', handleRequestMobilePushApproval);
  document.getElementById('cancelApprovalRequestBtn')?.addEventListener('click', cancelApprovalPolling);

  // Unlock with 6-digit PIN
  document.getElementById('unlockWithPinBtn')?.addEventListener('click', handleUnlockWithPin);

  // ── Device Manager Modal ──
  document.getElementById('openDeviceManagerBtn')?.addEventListener('click', openDeviceManagerModal);
  document.getElementById('openDeviceManagerFromHeaderBtn')?.addEventListener('click', openDeviceManagerModal);
  document.getElementById('openDeviceManagerFromUnlockedBtn')?.addEventListener('click', openDeviceManagerModal);
  document.getElementById('closeDeviceManagerBtn')?.addEventListener('click', closeDeviceManagerModal);
  document.getElementById('doneDeviceManagerBtn')?.addEventListener('click', closeDeviceManagerModal);
  document.getElementById('refreshDevicesModalBtn')?.addEventListener('click', refreshDeviceManagerModal);
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

  // Periodic poller while popup is open so revocations take effect immediately
  setInterval(async () => {
    const unlockedView = document.getElementById('unlockedView');
    if (unlockedView && unlockedView.classList.contains('active')) {
      await refreshStatus();
    }
  }, 2500);
}

function setAuthMethod(method, save = true) {
  currentAuthMethod = method;
  const pushTab = document.getElementById('authMethodPushTab');
  const pinTab = document.getElementById('authMethodPinTab');
  const pushModeContainer = document.getElementById('pushModeContainer');
  const pinBox = document.getElementById('manualPinBox');

  if (method === 'pin') {
    pushTab?.classList.remove('active');
    pinTab?.classList.add('active');
    // When in PIN mode, remove/hide push confirmation button and device selector completely
    if (pushModeContainer) pushModeContainer.style.display = 'none';
    if (pinBox) pinBox.style.display = 'block';
    // Clear any active push polling if user switches to PIN
    cancelApprovalPolling();
  } else {
    pinTab?.classList.remove('active');
    pushTab?.classList.add('active');
    if (pushModeContainer) pushModeContainer.style.display = 'block';
    if (pinBox) pinBox.style.display = 'none';
  }

  if (save && typeof chrome !== 'undefined' && chrome.storage && chrome.storage.local) {
    chrome.storage.local.set({ preferredAuthMethod: method });
  }
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

  if (unlinkedBox) unlinkedBox.style.display = 'none';
  if (linkedBox) linkedBox.style.display = 'block';
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

// ── Device Manager Modal Handlers ──
function openDeviceManagerModal() {
  const modal = document.getElementById('deviceManagerModal');
  if (modal) modal.style.display = 'flex';
  renderDeviceManagerList();
  refreshDeviceManagerModal();
}

function closeDeviceManagerModal() {
  const modal = document.getElementById('deviceManagerModal');
  if (modal) modal.style.display = 'none';
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
  const confirmed = confirm(`Are you sure you want to remove "${deviceName}"?\n\n⚠️ WARNING: This phone will immediately be revoked and all CardVault app data on that phone will be wiped clean!`);
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

    // 2. Start Countdown Timer UI
    activeCountdownInterval = setInterval(() => {
      secondsLeft--;
      if (waitingTimer) waitingTimer.textContent = `Waiting for mobile approval (${secondsLeft}s)...`;
      if (secondsLeft <= 0) {
        cancelApprovalPolling();
        showError('Request timed out. Please tap Authorize in CardVault on your phone.');
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

/**
 * 🔢 Fallback: Unlock using 6-digit PIN
 */
async function handleUnlockWithPin() {
  const pinInput = document.getElementById('pinInput');
  const passwordInput = document.getElementById('passwordInput');
  const pin = pinInput?.value.trim() || '';
  const password = passwordInput?.value.trim() || null;

  hideMessages();

  if (!pin || pin.length !== 6) {
    showError('Please enter the 6-digit PIN from CardVault on your phone.');
    return;
  }

  const btn = document.getElementById('unlockWithPinBtn');
  if (btn) btn.disabled = true;

  try {
    const response = await sendExtensionMessage({
      action: 'SYNC_AND_UNLOCK',
      payload: {
        token: currentOAuthToken,
        masterPassword: password,
        pairingPin: pin,
        rawBackupText: localBackupPayload
      }
    });

    if (response && response.success) {
      if (pinInput) pinInput.value = '';
      if (passwordInput) passwordInput.value = '';
      await refreshStatus();
    } else {
      showError(response?.message || response?.error || 'PIN authorization failed.');
    }
  } catch (err) {
    showError(`Error: ${err.message}`);
  } finally {
    if (btn) btn.disabled = false;
  }
}

async function refreshStatus() {
  const status = await sendExtensionMessage({ action: 'GET_STATUS' });

  const statusBadge = document.getElementById('statusBadge');
  const statusText = document.getElementById('statusText');
  const lockedView = document.getElementById('lockedView');
  const unlockedView = document.getElementById('unlockedView');

  if (status && status.isAuthorized && status.isUnlocked) {
    if (statusBadge) statusBadge.className = 'status-badge unlocked';
    if (statusText) statusText.textContent = 'Unlocked';
    lockedView?.classList.remove('active');
    unlockedView?.classList.add('active');

    if (status.authExpiresAt) {
      const remainingMs = status.authExpiresAt - Date.now();
      const mins = Math.max(1, Math.round(remainingMs / 60000));
      const timer = document.getElementById('sessionTimer');
      if (timer) timer.textContent = `Expires in ~${mins} min`;
    }

    const res = await sendExtensionMessage({ action: 'GET_AUTOFILL_SUGGESTIONS', payload: { fieldType: 'ALL' } });
    if (res && res.authorized) {
      currentVaultItems = res;
      updateCounts();
      renderVaultList();
    }
  } else {
    if (statusBadge) statusBadge.className = 'status-badge locked';
    if (statusText) statusText.textContent = 'Locked';
    lockedView?.classList.add('active');
    unlockedView?.classList.remove('active');
    currentVaultItems = { cards: [], bankAccounts: [] };
    const vaultList = document.getElementById('vaultList');
    if (vaultList) vaultList.innerHTML = '';
  }
}

async function handleLock() {
  currentVaultItems = { cards: [], bankAccounts: [] };
  await sendExtensionMessage({ action: 'LOCK_VAULT' });
  await refreshStatus();
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
  const pwdBanks = banks.filter(b => b.loginPassword || b.profilePassword || b.mpin);

  if (cardsCount) cardsCount.textContent = cards.length;
  if (banksCount) banksCount.textContent = banks.reduce((sum, b) => sum + (b.accounts?.length || 1), 0);
  if (pwdCount) pwdCount.textContent = pwdBanks.length;
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
      const formattedNum = (card.cardNumber || '').replace(/(\d{4})/g, '$1 ').trim();

      tile.innerHTML = `
        <div class="tile-header">
          <span class="tile-title">${escapeHtml(card.nickname)} (${escapeHtml(card.bankName)})</span>
          <span class="tile-badge">${card.isDebit ? 'DEBIT' : 'CREDIT'}</span>
        </div>
        <div class="tile-number">${formattedNum || '•••• •••• •••• ••••'}</div>
        <div class="tile-actions">
          <button class="copy-chip" data-copy="${card.cardNumber}">Copy Number</button>
          ${card.expiry ? `<button class="copy-chip" data-copy="${card.expiry}">Exp: ${card.expiry}</button>` : ''}
          ${card.cvv ? `<button class="copy-chip" data-copy="${card.cvv}">CVV</button>` : ''}
        </div>
      `;
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
    const banks = (currentVaultItems.bankAccounts || []).filter(b => b.loginPassword || b.profilePassword || b.mpin);
    if (banks.length === 0) {
      list.innerHTML = '<div style="padding:20px;text-align:center;color:#94A3B8;font-size:12px;">No passwords saved in vault.</div>';
      return;
    }

    banks.forEach(bank => {
      const tile = document.createElement('div');
      tile.className = 'card-tile';
      tile.innerHTML = `
        <div class="tile-header">
          <span class="tile-title">${escapeHtml(bank.bankName)} Credentials</span>
          <span class="tile-badge">CREDS</span>
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

  // Attach clipboard listener
  list.querySelectorAll('.copy-chip').forEach(btn => {
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
}

function escapeHtml(str) {
  if (!str) return '';
  return str.replace(/[&<>'"]/g, t => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' }[t] || t));
}
