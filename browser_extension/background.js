/**
 * CardVault Extension Service Worker (Manifest V3)
 * Manages volatile RAM cache of vault items and enforces Mobile Authorization.
 */

importScripts('crypto_utils.js', 'drive_client.js');

const driveClient = new DriveClient();

// Volatile in-memory cache (RAM only, destroyed on service worker termination / lock)
let memoryVault = {
  isAuthorized: false,
  isUnlocked: false,
  items: [],
  lastSyncedAt: null,
  authExpiresAt: null,
  masterPassword: null,
  activePin: null,
};

// Auto-lock timer / Periodic validation of mobile auth status
async function verifyMobileAuth() {
  if (!memoryVault.isAuthorized && !memoryVault.isUnlocked) return;

  // Check expiration timestamp
  if (memoryVault.authExpiresAt && Date.now() > memoryVault.authExpiresAt) {
    lockVault('Mobile authorization session expired.');
    return;
  }

  // Poll Google Drive auth record if token is available
  try {
    const authStatus = await driveClient.checkMobileAuthorization();
    if (!authStatus.authorized) {
      lockVault('Authorization revoked from CardVault mobile application.');
    }
  } catch (_) {
    // Soft error, rely on local timeout
  }
}

function lockVault(reason = 'Vault locked') {
  memoryVault.isAuthorized = false;
  memoryVault.isUnlocked = false;
  memoryVault.items = [];
  memoryVault.masterPassword = null;
  memoryVault.authExpiresAt = null;
  console.log('[CardVault]', reason);
  notifyAllTabsStatusChange();
}

function notifyAllTabsStatusChange() {
  chrome.tabs.query({}, (tabs) => {
    for (const tab of tabs) {
      if (tab.id) {
        chrome.tabs.sendMessage(tab.id, {
          action: 'VAULT_STATUS_CHANGED',
          isAuthorized: memoryVault.isAuthorized && memoryVault.isUnlocked
        }).catch(() => {});
      }
    }
  });
}

// Listen for messages from Content Script and Popup
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  const { action, payload } = message;

  if (action === 'GET_STATUS') {
    sendResponse({
      isAuthorized: memoryVault.isAuthorized,
      isUnlocked: memoryVault.isUnlocked,
      itemCount: memoryVault.items.length,
      lastSyncedAt: memoryVault.lastSyncedAt,
      authExpiresAt: memoryVault.authExpiresAt,
      activePin: memoryVault.activePin,
    });
    return true;
  }

  if (action === 'LOCK_VAULT') {
    lockVault('User requested desktop lock');
    sendResponse({ success: true });
    return true;
  }

  if (action === 'GET_REGISTERED_DEVICES') {
    if (payload?.token) driveClient.setToken(payload.token);
    driveClient.fetchRegisteredDevices()
      .then(devices => sendResponse({ success: true, devices }))
      .catch(err => sendResponse({ success: false, devices: [], error: err.message }));
    return true;
  }

  if (action === 'REMOVE_REGISTERED_DEVICE') {
    if (payload?.token) driveClient.setToken(payload.token);
    driveClient.removeRegisteredDevice(payload.deviceId)
      .then(devices => sendResponse({ success: true, devices }))
      .catch(err => sendResponse({ success: false, error: err.message }));
    return true;
  }

  if (action === 'RENAME_REGISTERED_DEVICE') {
    if (payload?.token) driveClient.setToken(payload.token);
    driveClient.renameRegisteredDevice(payload.deviceId, payload.newName)
      .then(devices => sendResponse({ success: true, devices }))
      .catch(err => sendResponse({ success: false, error: err.message }));
    return true;
  }

  if (action === 'START_MOBILE_APPROVAL_REQUEST') {
    handleStartMobileApprovalRequest(payload)
      .then(res => sendResponse(res))
      .catch(err => sendResponse({ success: false, error: err.message }));
    return true;
  }

  if (action === 'POLL_MOBILE_APPROVAL') {
    handlePollMobileApproval(payload)
      .then(res => sendResponse(res))
      .catch(err => sendResponse({ status: 'ERROR', error: err.message }));
    return true;
  }

  if (action === 'SYNC_AND_UNLOCK') {
    handleSyncAndUnlock(payload)
      .then(result => sendResponse(result))
      .catch(err => sendResponse({ success: false, error: err.message }));
    return true; // Asynchronous response
  }

  if (action === 'AUTHORIZE_WITH_PIN') {
    handleAuthorizeWithPin(payload)
      .then(result => sendResponse(result))
      .catch(err => sendResponse({ success: false, error: err.message }));
    return true;
  }

  if (action === 'GET_AUTOFILL_SUGGESTIONS') {
    handleGetAutofillSuggestions(payload)
      .then(result => sendResponse(result))
      .catch(err => sendResponse({ authorized: false, items: [] }));
    return true;
  }

  return false;
});

async function handleStartMobileApprovalRequest({ token, deviceName, targetDeviceId }) {
  if (token) driveClient.setToken(token);
  const req = await driveClient.sendAccessRequestToMobile(
    deviceName || 'Windows PC (CardVault Extension)',
    targetDeviceId || 'ALL'
  );
  return {
    success: true,
    requestId: req.requestId,
    expiresAt: req.expiresAt
  };
}

async function handlePollMobileApproval({ token, requestId, masterPassword }) {
  if (token) driveClient.setToken(token);

  const check = await driveClient.checkAccessRequestStatus(requestId);
  if (check.status === 'APPROVED') {
    // Mobile approved with biometrics! Download backup from Drive
    const backupPayload = await driveClient.fetchEncryptedVaultBackup();
    const decryptedItems = await decryptCardVaultBackup(backupPayload, masterPassword);

    // Save in RAM
    memoryVault.isAuthorized = true;
    memoryVault.isUnlocked = true;
    memoryVault.items = decryptedItems;
    memoryVault.lastSyncedAt = Date.now();
    memoryVault.authExpiresAt = check.expiresAt || (Date.now() + (30 * 60 * 1000));
    memoryVault.masterPassword = masterPassword;

    notifyAllTabsStatusChange();

    return {
      status: 'APPROVED',
      success: true,
      itemCount: decryptedItems.length,
      expiresAt: memoryVault.authExpiresAt
    };
  }

  return check;
}

async function handleSyncAndUnlock({ token, masterPassword, rawBackupText, pairingPin }) {
  if (token) driveClient.setToken(token);

  // 1. Validate entered PIN format
  if (!pairingPin || pairingPin.trim().length !== 6) {
    return {
      success: false,
      error: 'INVALID_PIN_LENGTH',
      message: 'Please enter the 6-digit PIN displayed on your CardVault mobile app (Settings → Browser Extension).'
    };
  }

  const cleanPin = pairingPin.trim();

  // 2. Strict Mobile Authorization Verification
  let authResult = { authorized: false };
  let authCheckAttempted = false;

  try {
    authResult = await driveClient.checkMobileAuthorization();
    authCheckAttempted = true;
  } catch (e) {
    console.warn('[CardVault] Drive auth check notice:', e.message);
  }

  // If Drive auth was checked:
  if (authCheckAttempted) {
    if (!authResult.authorized) {
      return {
        success: false,
        error: 'MOBILE_AUTH_REQUIRED',
        message: authResult.message || 'Desktop extension is NOT authorized on your mobile app. Open CardVault on your phone → Settings → Browser Extension and tap Authorize.'
      };
    }

    // STRICT CHECK: The entered PIN MUST match the active PIN generated on mobile!
    if (!authResult.pin || cleanPin !== String(authResult.pin).trim()) {
      return {
        success: false,
        error: 'INCORRECT_PIN',
        message: 'Access Denied: Incorrect 6-digit PIN. The PIN you entered does not match the active session on your phone.'
      };
    }
  } else {
    // Drive check could not be completed (e.g. no cloud token)
    // If rawBackupText is not provided either, we cannot proceed
    if (!rawBackupText) {
      return {
        success: false,
        error: 'NO_DATA_SOURCE',
        message: 'Could not connect to Google Drive or local backup file. Please provide a backup file or Google OAuth token.'
      };
    }
  }

  // 3. Fetch encrypted backup from Google Drive (or use provided backup text)
  let backupPayload = rawBackupText;
  if (!backupPayload) {
    backupPayload = await driveClient.fetchEncryptedVaultBackup();
  }

  // 4. Decrypt Vault with Master Password
  const decryptedItems = await decryptCardVaultBackup(backupPayload, masterPassword);

  // 5. Store exclusively in RAM
  memoryVault.isAuthorized = true;
  memoryVault.isUnlocked = true;
  memoryVault.items = decryptedItems;
  memoryVault.lastSyncedAt = Date.now();
  memoryVault.authExpiresAt = authResult.expiresAt || (Date.now() + (30 * 60 * 1000));
  memoryVault.masterPassword = masterPassword;
  memoryVault.activePin = cleanPin;

  notifyAllTabsStatusChange();

  return {
    success: true,
    itemCount: decryptedItems.length,
    expiresAt: memoryVault.authExpiresAt
  };
}

async function handleAuthorizeWithPin({ pin, masterPassword }) {
  return await handleSyncAndUnlock({ masterPassword, pairingPin: pin });
}

async function handleGetAutofillSuggestions({ fieldType, domain }) {
  // CRITICAL SECURITY CATCH: Check authorization from mobile application
  if (!memoryVault.isAuthorized || !memoryVault.isUnlocked) {
    return {
      authorized: false,
      message: 'Authorize on CardVault mobile app to enable autofill',
      cards: [],
      bankAccounts: []
    };
  }

  // Check expiration
  if (memoryVault.authExpiresAt && Date.now() > memoryVault.authExpiresAt) {
    lockVault('Session expired');
    return {
      authorized: false,
      message: 'Mobile session expired. Please re-authorize on phone.',
      cards: [],
      bankAccounts: []
    };
  }

  // Group items using universal normalizer for Flutter VaultItem maps
  const cards = [];
  const bankAccounts = [];

  for (const item of memoryVault.items) {
    const type = (item.type || '').toLowerCase();
    const rawCardNumber = (item.card_number || item.cardNumber || '').replace(/\s+/g, '');
    const isCard = type === 'card' || (!type.includes('bank') && rawCardNumber.length >= 12);

    if (isCard) {
      cards.push({
        id: item.id || String(Math.random()),
        nickname: item.nickname || item.card_holder || item.cardHolder || 'Card',
        bankName: item.bank_name || item.bankName || 'Card',
        cardNumber: rawCardNumber,
        cardHolder: item.card_holder || item.cardHolder || '',
        expiry: item.expiry || '',
        cvv: item.cvv || '',
        cardNetwork: item.card_network || item.cardNetwork || 'Visa',
        isCredit: (item.card_type || item.cardType || '').toLowerCase().includes('credit') || !!item.isCredit,
        isDebit: (item.card_type || item.cardType || '').toLowerCase().includes('debit') || !!item.isDebit
      });
    } else {
      // NetBanking & Bank Accounts
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

  return {
    authorized: true,
    cards,
    bankAccounts
  };
}

// Periodic check every 1 minute
setInterval(verifyMobileAuth, 60000);
