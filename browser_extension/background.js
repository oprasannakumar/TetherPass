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
  sessionId: null,
};

// Universal normalizer for raw decrypted vault items into structured suggestions
function organizeVaultItems(rawItems) {
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
      const totpKey = item.totp_secret || item.totpSecret || '';
      passwords.push({
        id: item.id || String(Math.random()),
        nickname: item.nickname || item.bank_name || 'Website Password',
        website: item.website || '',
        username: item.user_id || item.userId || item.username || '',
        password: item.login_password || item.loginPassword || item.password || '',
        totpSecret: totpKey,
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

// ── Persistent Storage (Survives Service Worker Restarts & Inactivity for full 30 mins) ──
async function persistSession() {
  const suggestions = organizeVaultItems(memoryVault.items);
  const sessionData = {
    isAuthorized: memoryVault.isAuthorized,
    isUnlocked: memoryVault.isUnlocked,
    items: memoryVault.items,
    suggestions: suggestions,
    lastSyncedAt: memoryVault.lastSyncedAt,
    authExpiresAt: memoryVault.authExpiresAt,
    masterPassword: memoryVault.masterPassword,
    activePin: memoryVault.activePin,
    authMode: memoryVault.authMode,
    sessionStartTime: memoryVault.sessionStartTime,
    activeRequestId: memoryVault.activeRequestId,
    sessionId: memoryVault.sessionId,
  };

  try {
    if (typeof chrome !== 'undefined' && chrome.storage?.session) {
      await chrome.storage.session.set({ tetherpass_session: sessionData });
    }
  } catch (_) {}

  try {
    if (typeof chrome !== 'undefined' && chrome.storage?.local) {
      await chrome.storage.local.set({ tetherpass_session: sessionData });
    }
  } catch (err) {
    console.warn('[TetherPass] Session persist warning:', err);
  }
}

async function restoreSessionIfNeeded() {
  const now = Date.now();

  // If already unlocked in RAM, verify expiry timestamp (guaranteed 30 minutes)
  if (memoryVault.isAuthorized && memoryVault.isUnlocked) {
    if (memoryVault.authExpiresAt && now > memoryVault.authExpiresAt) {
      await lockVault('Authorization session expired.');
      return false;
    }
    return true;
  }

  // Restore session from chrome.storage.session or chrome.storage.local when service worker wakes up
  try {
    let sess = null;
    if (typeof chrome !== 'undefined' && chrome.storage?.session) {
      const data = await chrome.storage.session.get('tetherpass_session');
      sess = data?.tetherpass_session;
    }
    if (!sess && typeof chrome !== 'undefined' && chrome.storage?.local) {
      const data = await chrome.storage.local.get('tetherpass_session');
      sess = data?.tetherpass_session;
    }

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
        sessionId: sess.sessionId || null,
      };
      return true;
    }
  } catch (err) {
    console.warn('[TetherPass] Session restore notice:', err);
  }

  return false;
}

async function clearPersistedSession() {
  try {
    if (typeof chrome !== 'undefined' && chrome.storage?.session) {
      await chrome.storage.session.remove('tetherpass_session');
    }
  } catch (_) {}
  try {
    if (typeof chrome !== 'undefined' && chrome.storage?.local) {
      await chrome.storage.local.remove('tetherpass_session');
    }
  } catch (_) {}
}

// Auto-lock timer / Periodic validation of mobile auth status
async function verifyMobileAuth() {
  await restoreSessionIfNeeded();
  if (!memoryVault.isAuthorized || !memoryVault.isUnlocked) return;

  // Poll Google Drive for intentional remote revocation or termination from mobile
  try {
    const isRevoked = await driveClient.isAuthorizationRevoked(
      memoryVault.authMode,
      memoryVault.sessionStartTime,
      memoryVault.sessionId
    );
    if (isRevoked) {
      await lockVault('Session terminated from TetherPass mobile application.');
      return;
    }

    // Check if session was extended remotely from mobile
    const remoteExpiresAt = await driveClient.getRemoteSessionExpiresAt(
      memoryVault.sessionId,
      memoryVault.authMode
    );
    if (remoteExpiresAt && remoteExpiresAt > (memoryVault.authExpiresAt || 0)) {
      memoryVault.authExpiresAt = remoteExpiresAt;
      await persistSession();
      notifyAllTabsStatusChange();
    }
  } catch (_) {
    // Soft error, rely on local timeout
  }

  // Enforce desktop session expiration timestamp (full duration or extended)
  if (memoryVault.authExpiresAt && Date.now() > memoryVault.authExpiresAt) {
    await lockVault('Mobile authorization session expired.');
    return;
  }
}

async function lockVault(reason = 'Vault locked') {
  let sessionIdToLock = memoryVault.sessionId || memoryVault.activeRequestId;

  if (!sessionIdToLock) {
    try {
      const sessData = await chrome.storage.local.get('tetherpass_session');
      sessionIdToLock = sessData?.tetherpass_session?.sessionId || sessData?.tetherpass_session?.activeRequestId;
    } catch (_) {}
  }

  memoryVault.isAuthorized = false;
  memoryVault.isUnlocked = false;
  memoryVault.items = [];
  memoryVault.masterPassword = null;
  memoryVault.authExpiresAt = null;
  memoryVault.activePin = null;
  memoryVault.authMode = null;
  memoryVault.sessionStartTime = null;
  memoryVault.activeRequestId = null;
  memoryVault.sessionId = null;

  await clearPersistedSession();
  console.log('[TetherPass]', reason);

  // ── Mark session as LOCKED in Google Drive so mobile app sees it immediately ──
  try {
    if (!driveClient.token) {
      const stored = await chrome.storage.local.get('googleOAuthToken');
      if (stored?.googleOAuthToken) {
        driveClient.setToken(stored.googleOAuthToken);
      }
    }
    if (driveClient.token) {
      await driveClient.markSessionLocked(sessionIdToLock);
      console.log('[TetherPass] Session marked LOCKED on Drive:', sessionIdToLock);
    } else {
      console.warn('[TetherPass] No token available — cannot mark session LOCKED on Drive');
    }
  } catch (e) {
    console.warn('[TetherPass] Could not mark session locked on Drive:', e.message);
  }

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
      const suggestions = (memoryVault.isAuthorized && memoryVault.isUnlocked)
        ? organizeVaultItems(memoryVault.items)
        : { cards: [], bankAccounts: [], passwords: [] };

      sendResponse({
        isAuthorized: memoryVault.isAuthorized,
        isUnlocked: memoryVault.isUnlocked,
        itemCount: memoryVault.items.length,
        lastSyncedAt: memoryVault.lastSyncedAt,
        authExpiresAt: memoryVault.authExpiresAt,
        activePin: memoryVault.activePin,
        authMode: memoryVault.authMode,
        suggestions: suggestions,
      });
      return;
    }

    if (action === 'LOCK_VAULT') {
      if (payload?.token) driveClient.setToken(payload.token);
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

    if (action === 'SYNC_AND_UNLOCK' || action === 'AUTHORIZE_WITH_PIN') {
      sendResponse({ success: false, error: 'PIN_AUTH_REMOVED', message: 'PIN authorization has been removed. Please use Mobile Push Approval.' });
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

let lastRequestedDeviceName = null;

async function getDesktopDeviceName(fallback = 'Windows PC (Chrome)') {
  if (lastRequestedDeviceName) return lastRequestedDeviceName;
  try {
    if (typeof chrome !== 'undefined' && chrome.storage?.local) {
      const stored = await chrome.storage.local.get(['customDesktopName', 'desktopDeviceTag']);
      if (stored.customDesktopName) return stored.customDesktopName;
      if (stored.desktopDeviceTag) return `Windows PC (Chrome • ${stored.desktopDeviceTag})`;
    }
  } catch (_) {}
  return fallback;
}

async function handleStartMobileApprovalRequest({ token, deviceName, targetDeviceId }) {
  if (token) driveClient.setToken(token);
  if (deviceName) lastRequestedDeviceName = deviceName;
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
    const sessionId = requestId || ('sess_' + Date.now());
    memoryVault.isAuthorized = true;
    memoryVault.isUnlocked = true;
    memoryVault.items = decryptedItems;
    memoryVault.lastSyncedAt = Date.now();
    memoryVault.authExpiresAt = Date.now() + desktopSessionDurationMs;
    memoryVault.masterPassword = effectivePassword;
    memoryVault.activeRequestId = requestId;
    memoryVault.sessionId = sessionId;
    memoryVault.authMode = 'PUSH';
    memoryVault.sessionStartTime = Date.now();

    await persistSession();

    // Register active session in Google Drive
    try {
      const devName = await getDesktopDeviceName('Windows PC (Chrome)');
      await driveClient.recordActiveSession({
        sessionId,
        deviceName: devName,
        authMode: 'PUSH',
        createdAt: memoryVault.sessionStartTime,
        expiresAt: memoryVault.authExpiresAt
      });
    } catch (_) {}

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

  const isCredentialField = ['USER_ID', 'PASSWORD', 'TOTP'].includes(fieldType);
  const isCardField = ['CARD_NUMBER', 'EXPIRY', 'CVV', 'CARD_HOLDER'].includes(fieldType);
  const isBankField = ['ACCOUNT_NUMBER', 'IFSC'].includes(fieldType);

  // Group items using universal normalizer for Flutter VaultItem maps
  const cards = [];
  const bankAccounts = [];
  const passwords = [];

  for (const item of memoryVault.items) {
    const type = (item.type || '').toLowerCase();
    const isPassword = type === 'password';
    const rawCardNumber = String(item.card_number || item.cardNumber || item.number || item.cardNo || item.card_no || '').replace(/\s+/g, '');
    const isCard = !isPassword && (type === 'card' || (!type.includes('bank') && (rawCardNumber.length >= 12 || (item.card_network || item.cardNetwork))));

    if (isPassword) {
      if (isCardField || isBankField) continue; // Don't include passwords when filling card or bank number

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
      // Only suggest passwords matching the current website!
      if (domain && fieldType !== 'ALL') {
        if (doesDomainMatch(pwdItem.website, domain, pwdItem.nickname)) {
          passwords.push(pwdItem);
        }
      } else {
        passwords.push(pwdItem);
      }
    } else if (isCard) {
      if (isCredentialField || isBankField) continue; // Don't include cards for login or bank fields
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
      // NetBanking & Bank Accounts
      if (isCardField) continue; // Don't include bank accounts for card payment fields

      // If user is on a login/password field on an external site (e.g. Amazon),
      // ONLY include bank credentials if this website is actually that bank's website!
      if (isCredentialField && domain && fieldType !== 'ALL') {
        const matchesBank = doesDomainMatch('', domain, item.bank_name || item.nickname || '');
        if (!matchesBank) {
          continue; // Do NOT suggest bank accounts on Amazon, Netflix, etc.!
        }
      }

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
