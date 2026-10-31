/**
 * TetherPass Extension Service Worker (Manifest V3)
 * Manages encrypted session cache of vault items and enforces Mobile Authorization.
 */

importScripts('crypto_utils.js', 'drive_client.js');

const driveClient = new DriveClient();

// Restrict session storage access strictly to trusted extension contexts (background & popup)
if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.session) {
  if (chrome.storage.session.setAccessLevel) {
    chrome.storage.session.setAccessLevel({ accessLevel: 'TRUSTED_CONTEXTS' }).catch(() => {});
  }
}

// In-memory cache (restored from chrome.storage.session across service worker restarts)
let memoryVault = {
  isAuthorized: false,
  isUnlocked: false,
  items: [],
  lastSyncedAt: null,
  authExpiresAt: null,
  masterPassword: null,
  activePin: null,
  authMode: null,
  sessionStartTime: null,
  activeRequestId: null,
};

// ── Session Storage Persistence (Survives Service Worker Restarts & Inactivity) ──
async function persistSession() {
  if (typeof chrome === 'undefined' || !chrome.storage?.session) return;
  try {
    await chrome.storage.session.set({
      tetherpass_session: {
        isAuthorized: memoryVault.isAuthorized,
        isUnlocked: memoryVault.isUnlocked,
        items: memoryVault.items,
        lastSyncedAt: memoryVault.lastSyncedAt,
        authExpiresAt: memoryVault.authExpiresAt,
        masterPassword: memoryVault.masterPassword,
        activePin: memoryVault.activePin,
        authMode: memoryVault.authMode,
        sessionStartTime: memoryVault.sessionStartTime,
        activeRequestId: memoryVault.activeRequestId,
      }
    });
  } catch (err) {
    console.warn('[TetherPass] Session persist warning:', err);
  }
}

async function restoreSessionIfNeeded() {
  const now = Date.now();

  // If already unlocked in RAM, verify expiry timestamp
  if (memoryVault.isAuthorized && memoryVault.isUnlocked) {
    if (memoryVault.authExpiresAt && now > memoryVault.authExpiresAt) {
      await lockVault('Authorization session expired.');
      return false;
    }
    return true;
  }

  // Restore session from RAM-backed chrome.storage.session if service worker restarted
  if (typeof chrome !== 'undefined' && chrome.storage?.session) {
    try {
      const data = await chrome.storage.session.get('tetherpass_session');
      const sess = data?.tetherpass_session;
      if (sess && sess.isAuthorized && sess.isUnlocked) {
        if (sess.authExpiresAt && now > sess.authExpiresAt) {
          await lockVault('Authorization session expired.');
          return false;
        }

        memoryVault = {
          isAuthorized: true,
          isUnlocked: true,
          items: sess.items || [],
          lastSyncedAt: sess.lastSyncedAt || now,
          authExpiresAt: sess.authExpiresAt,
          masterPassword: sess.masterPassword || null,
          activePin: sess.activePin || null,
          authMode: sess.authMode || null,
          sessionStartTime: sess.sessionStartTime || now,
          activeRequestId: sess.activeRequestId || null,
        };
        return true;
      }
    } catch (err) {
      console.warn('[TetherPass] Session restore notice:', err);
    }
  }

  return false;
}

async function clearPersistedSession() {
  if (typeof chrome !== 'undefined' && chrome.storage?.session) {
    try {
      await chrome.storage.session.remove('tetherpass_session');
    } catch (_) {}
  }
}

// Auto-lock timer / Periodic validation of mobile auth status
async function verifyMobileAuth() {
  await restoreSessionIfNeeded();
  if (!memoryVault.isAuthorized || !memoryVault.isUnlocked) return;

  // Check expiration timestamp
  if (memoryVault.authExpiresAt && Date.now() > memoryVault.authExpiresAt) {
    await lockVault('Mobile authorization session expired.');
    return;
  }

  // Poll Google Drive revocation or status with cooldown
  try {
    const isRevoked = await driveClient.isAuthorizationRevoked(
      memoryVault.authMode,
      memoryVault.sessionStartTime
    );
    if (isRevoked) {
      await lockVault('Authorization revoked from TetherPass mobile application.');
      return;
    }

    if (memoryVault.authMode === 'PIN' && memoryVault.activePin) {
      const authStatus = await driveClient.checkMobileAuthorization();
      // Only lock if explicitly REVOKED from mobile settings, NOT on network/rate-limit/local lock
      if (!authStatus.authorized && authStatus.reason === 'REVOKED') {
        await lockVault('Authorization revoked from TetherPass mobile application.');
        return;
      }
    }
  } catch (_) {
    // Soft error, rely on local timeout
  }
}

async function lockVault(reason = 'Vault locked') {
  memoryVault.isAuthorized = false;
  memoryVault.isUnlocked = false;
  memoryVault.items = [];
  memoryVault.masterPassword = null;
  memoryVault.authExpiresAt = null;
  memoryVault.activePin = null;
  memoryVault.authMode = null;
  memoryVault.sessionStartTime = null;
  memoryVault.activeRequestId = null;

  await clearPersistedSession();
  console.log('[TetherPass]', reason);
  notifyAllTabsStatusChange();

  // Internal runtime message to instantly notify popup if open
  chrome.runtime.sendMessage({
    action: 'VAULT_STATUS_CHANGED',
    isAuthorized: false,
    isUnlocked: false,
    reason
  }).catch(() => {});
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

  (async () => {
    // Always restore session state first before processing any message
    await restoreSessionIfNeeded();

    if (action === 'GET_STATUS') {
      sendResponse({
        isAuthorized: memoryVault.isAuthorized,
        isUnlocked: memoryVault.isUnlocked,
        itemCount: memoryVault.items.length,
        lastSyncedAt: memoryVault.lastSyncedAt,
        authExpiresAt: memoryVault.authExpiresAt,
        activePin: memoryVault.activePin,
        authMode: memoryVault.authMode,
      });
      return;
    }

    if (action === 'LOCK_VAULT') {
      await lockVault('User requested desktop lock');
      sendResponse({ success: true });
      return;
    }

    if (action === 'GET_REGISTERED_DEVICES') {
      if (payload?.token) driveClient.setToken(payload.token);
      try {
        const devices = await driveClient.fetchRegisteredDevices();
        sendResponse({ success: true, devices });
      } catch (err) {
        sendResponse({ success: false, devices: [], error: err.message });
      }
      return;
    }

    if (action === 'REMOVE_REGISTERED_DEVICE') {
      if (payload?.token) driveClient.setToken(payload.token);
      try {
        const devices = await driveClient.removeRegisteredDevice(payload.deviceId);
        sendResponse({ success: true, devices });
      } catch (err) {
        sendResponse({ success: false, error: err.message });
      }
      return;
    }

    if (action === 'RENAME_REGISTERED_DEVICE') {
      if (payload?.token) driveClient.setToken(payload.token);
      try {
        const devices = await driveClient.renameRegisteredDevice(payload.deviceId, payload.newName);
        sendResponse({ success: true, devices });
      } catch (err) {
        sendResponse({ success: false, error: err.message });
      }
      return;
    }

    if (action === 'START_MOBILE_APPROVAL_REQUEST') {
      try {
        const res = await handleStartMobileApprovalRequest(payload);
        sendResponse(res);
      } catch (err) {
        sendResponse({ success: false, error: err.message });
      }
      return;
    }

    if (action === 'POLL_MOBILE_APPROVAL') {
      try {
        const res = await handlePollMobileApproval(payload);
        sendResponse(res);
      } catch (err) {
        sendResponse({ status: 'ERROR', error: err.message });
      }
      return;
    }

    if (action === 'SYNC_AND_UNLOCK') {
      try {
        const res = await handleSyncAndUnlock(payload);
        sendResponse(res);
      } catch (err) {
        sendResponse({ success: false, error: err.message });
      }
      return;
    }

    if (action === 'AUTHORIZE_WITH_PIN') {
      try {
        const res = await handleAuthorizeWithPin(payload);
        sendResponse(res);
      } catch (err) {
        sendResponse({ success: false, error: err.message });
      }
      return;
    }

    if (action === 'GET_AUTOFILL_SUGGESTIONS') {
      try {
        const res = await handleGetAutofillSuggestions(payload);
        sendResponse(res);
      } catch (_) {
        sendResponse({ authorized: false, items: [] });
      }
      return;
    }

    if (action === 'SAVE_NEW_PASSWORD') {
      try {
        const res = await handleSaveNewPassword(payload);
        sendResponse(res);
      } catch (err) {
        sendResponse({ success: false, error: err.message });
      }
      return;
    }

    if (action === 'CHECK_BREACH') {
      try {
        const res = await checkPasswordBreached(payload.password);
        sendResponse(res);
      } catch (err) {
        sendResponse({ isPwned: false, error: err.message });
      }
      return;
    }
  })();

  return true; // Asynchronous sendResponse channel
});

async function handleStartMobileApprovalRequest({ token, deviceName, targetDeviceId }) {
  if (token) driveClient.setToken(token);
  const req = await driveClient.sendAccessRequestToMobile(
    deviceName || 'Windows PC (TetherPass Extension)',
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
    let effectivePassword = masterPassword;
    if (!effectivePassword && check.request_sealed_key) {
      try {
        effectivePassword = await decryptSealedMasterPassword(check.request_sealed_key, requestId);
      } catch (e) {
        console.warn('[CardVault] Could not decrypt request_sealed_key:', e.message);
      }
    }

    if (!effectivePassword) {
      return {
        status: 'APPROVED',
        success: false,
        error: 'PASSWORD_REQUIRED',
        message: 'Master Password required to decrypt vault. Please re-enter your password or re-authorize.'
      };
    }

    // Mobile approved with biometrics! Download backup from Drive
    const backupPayload = await driveClient.fetchEncryptedVaultBackup();
    const decryptedItems = await decryptCardVaultBackup(backupPayload, effectivePassword);

    // Save in RAM and session storage with a full 30-minute desktop session
    const desktopSessionDurationMs = 30 * 60 * 1000;
    memoryVault.isAuthorized = true;
    memoryVault.isUnlocked = true;
    memoryVault.items = decryptedItems;
    memoryVault.lastSyncedAt = Date.now();
    memoryVault.authExpiresAt = Date.now() + desktopSessionDurationMs;
    memoryVault.masterPassword = effectivePassword;
    memoryVault.activeRequestId = requestId;
    memoryVault.authMode = 'PUSH';
    memoryVault.sessionStartTime = Date.now();

    await persistSession();

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
      message: 'Please enter the 6-digit PIN displayed on your TetherPass mobile app (Settings → Browser Extension).'
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
    console.warn('[TetherPass] Drive auth check notice:', e.message);
  }

  // If Drive auth was checked:
  if (authCheckAttempted) {
    if (!authResult.authorized) {
      return {
        success: false,
        error: 'MOBILE_AUTH_REQUIRED',
        message: authResult.message || 'Desktop extension is NOT authorized on your mobile app. Open TetherPass on your phone → Settings → Browser Extension and tap Authorize.'
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

  // 4. Resolve Master Password (auto-decrypt from pin_sealed_key if not entered)
  let effectivePassword = masterPassword;
  if (!effectivePassword && authResult.pin_sealed_key) {
    try {
      effectivePassword = await decryptSealedMasterPassword(authResult.pin_sealed_key, cleanPin);
    } catch (e) {
      console.warn('[CardVault] Could not decrypt pin_sealed_key:', e.message);
    }
  }

  if (!effectivePassword) {
    return {
      success: false,
      error: 'PASSWORD_REQUIRED',
      message: 'PIN authorization key not found on Google Drive. Please tap "Authorize Desktop Extension" in TetherPass on your phone to generate a fresh pairing session.'
    };
  }

  // 5. Decrypt Vault with Master Password
  const decryptedItems = await decryptCardVaultBackup(backupPayload, effectivePassword);

  // 5. Store in RAM and session storage with a full 30-minute desktop session
  const desktopSessionDurationMs = 30 * 60 * 1000;
  memoryVault.isAuthorized = true;
  memoryVault.isUnlocked = true;
  memoryVault.items = decryptedItems;
  memoryVault.lastSyncedAt = Date.now();
  memoryVault.authExpiresAt = Date.now() + desktopSessionDurationMs;
  memoryVault.masterPassword = effectivePassword;
  memoryVault.activePin = cleanPin;
  memoryVault.authMode = 'PIN';
  memoryVault.sessionStartTime = Date.now();

  await persistSession();

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

function extractDomain(urlOrHost) {
  if (!urlOrHost) return '';
  let str = urlOrHost.trim().toLowerCase();
  str = str.replace(/^[a-zA-Z]+:\/\//, '');
  str = str.split('/')[0].split('?')[0].split('#')[0];
  str = str.split(':')[0];
  return str.replace(/^www\./, '');
}

function doesDomainMatch(itemWebsite, pageHost) {
  if (!itemWebsite || !pageHost) return false;
  const itemDom = extractDomain(itemWebsite);
  const pageDom = extractDomain(pageHost);
  if (!itemDom || !pageDom) return false;
  if (itemDom === pageDom) return true;
  if (pageDom.endsWith('.' + itemDom)) return true;
  if (itemDom.endsWith('.' + pageDom)) return true;
  return false;
}

async function handleGetAutofillSuggestions({ fieldType, domain }) {
  // CRITICAL SECURITY CATCH: Check authorization from mobile application
  if (!memoryVault.isAuthorized || !memoryVault.isUnlocked) {
    return {
      authorized: false,
      message: 'Authorize on TetherPass mobile app to enable autofill',
      cards: [],
      bankAccounts: [],
      passwords: []
    };
  }

  // Check expiration
  if (memoryVault.authExpiresAt && Date.now() > memoryVault.authExpiresAt) {
    await lockVault('Session expired');
    return {
      authorized: false,
      message: 'Mobile session expired. Please re-authorize on phone.',
      cards: [],
      bankAccounts: [],
      passwords: []
    };
  }

  // Group items using universal normalizer for Flutter VaultItem maps
  const cards = [];
  const bankAccounts = [];
  const passwords = [];

  for (const item of memoryVault.items) {
    const type = (item.type || '').toLowerCase();
    const isPassword = type === 'password';
    const rawCardNumber = (item.card_number || item.cardNumber || '').replace(/\s+/g, '');
    const isCard = !isPassword && (type === 'card' || (!type.includes('bank') && rawCardNumber.length >= 12));

    if (isPassword) {
      const totpKey = item.totp_secret || item.totpSecret || '';
      let totpCode = '';
      let totpSeconds = 0;
      if (totpKey) {
        try {
          totpCode = await generateTotpCode(totpKey);
          totpSeconds = getTotpRemainingSeconds();
        } catch (_) {}
      }

      const pwdItem = {
        id: item.id || String(Math.random()),
        nickname: item.nickname || item.bank_name || 'Website Password',
        website: item.website || '',
        username: item.user_id || item.userId || item.username || '',
        password: item.login_password || item.loginPassword || item.password || '',
        totpSecret: totpKey,
        totpCode: totpCode,
        totpSeconds: totpSeconds,
        notes: item.notes || ''
      };

      // Strict domain matching for website logins:
      // If requested by webpage autofill on a specific domain, only suggest matching credentials!
      if (domain && fieldType !== 'ALL') {
        if (doesDomainMatch(pwdItem.website, domain)) {
          passwords.push(pwdItem);
        }
      } else {
        passwords.push(pwdItem);
      }
    } else if (isCard) {
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
    bankAccounts,
    passwords
  };
}

async function handleSaveNewPassword({ website, username, password, nickname, totpSecret }) {
  if (!memoryVault.isUnlocked || !memoryVault.masterPassword) {
    return { success: false, error: 'VAULT_LOCKED', message: 'TetherPass extension is locked.' };
  }

  const cleanDomain = extractDomain(website) || 'login';
  const now = new Date().toISOString();

  // Find if already present
  let existingIndex = memoryVault.items.findIndex(it => {
    const isPwd = (it.type || '').toLowerCase() === 'password';
    if (!isPwd) return false;
    const sameDomain = doesDomainMatch(it.website, cleanDomain);
    const sameUser = (it.user_id || it.userId || it.username || '').toLowerCase() === (username || '').toLowerCase();
    return sameDomain && sameUser;
  });

  const newItem = {
    id: existingIndex >= 0 ? memoryVault.items[existingIndex].id : 'item_' + Date.now(),
    type: 'password',
    bank_name: nickname || cleanDomain,
    nickname: nickname || cleanDomain,
    website: (website || '').startsWith('http') ? website : `https://${website || cleanDomain}`,
    user_id: username,
    login_password: password,
    totp_secret: totpSecret || (existingIndex >= 0 ? (memoryVault.items[existingIndex].totp_secret || '') : ''),
    notes: existingIndex >= 0 ? (memoryVault.items[existingIndex].notes || '') : 'Saved via TetherPass Chrome Extension',
    created_at: existingIndex >= 0 ? memoryVault.items[existingIndex].created_at : now,
    updated_at: now
  };

  if (existingIndex >= 0) {
    memoryVault.items[existingIndex] = newItem;
  } else {
    memoryVault.items.push(newItem);
  }

  // Encrypt and persist to Google Drive if connected
  try {
    const encryptedPayload = await encryptTetherPassBackup(memoryVault.items, memoryVault.masterPassword);
    await driveClient.uploadOrUpdateFile(DRIVE_BACKUP_FILENAME, encryptedPayload);
    if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.local) {
      await chrome.storage.local.set({ cachedBackupPayload: encryptedPayload });
    }
  } catch (err) {
    console.warn('[TetherPass] Could not upload updated backup to Drive:', err);
  }

  // Persist updated vault items into session storage
  await persistSession();

  notifyAllTabsStatusChange();
  return { success: true, updated: existingIndex >= 0, title: newItem.nickname };
}

// Periodic check every 25 seconds so revocations from mobile take effect without spamming Drive
setInterval(verifyMobileAuth, 25000);
