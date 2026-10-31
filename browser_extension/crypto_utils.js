/**
 * CardVault Web Cryptography Utilities
 * Decrypts AES-256-CBC matching CardVault mobile app (SecureBackupExportService).
 * Compatible with Dart's HMAC-SHA256 key derivation and standard PBKDF2.
 */

function base64ToUint8Array(base64) {
  const binaryString = atob(base64);
  const bytes = new Uint8Array(binaryString.length);
  for (let i = 0; i < binaryString.length; i++) {
    bytes[i] = binaryString.charCodeAt(i);
  }
  return bytes;
}

function uint8ArrayToBase64(bytes) {
  let binary = '';
  for (let i = 0; i < bytes.byteLength; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}

/**
 * Derives a 256-bit AES key using the exact iterative HMAC-SHA256 algorithm
 * used by CardVault's Flutter SecureBackupExportService (10,000 rounds).
 */
async function deriveKeyCardVaultDart(masterPassword, saltBytes) {
  const enc = new TextEncoder();
  const hmacKey = await crypto.subtle.importKey(
    'raw',
    enc.encode(masterPassword),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  );

  let current = saltBytes;
  for (let i = 0; i < 10000; i++) {
    current = new Uint8Array(await crypto.subtle.sign('HMAC', hmacKey, current));
  }

  return await crypto.subtle.importKey(
    'raw',
    current,
    { name: 'AES-CBC' },
    false,
    ['decrypt']
  );
}

/**
 * Fallback: Derives key using RFC 2898 standard PBKDF2.
 */
async function deriveKeyStandardPBKDF2(masterPassword, saltBytes) {
  const enc = new TextEncoder();
  const keyMaterial = await crypto.subtle.importKey(
    'raw',
    enc.encode(masterPassword),
    'PBKDF2',
    false,
    ['deriveKey']
  );

  return await crypto.subtle.deriveKey(
    {
      name: 'PBKDF2',
      salt: saltBytes,
      iterations: 10000,
      hash: 'SHA-256'
    },
    keyMaterial,
    { name: 'AES-CBC', length: 256 },
    false,
    ['decrypt']
  );
}

/**
 * Decrypts CardVault cloud/offline backup payload with the user's master password.
 * @param {string|object} rawPayload JSON string or object containing header, salt, iv, and data
 * @param {string} masterPassword Master password configured on mobile app
 * @returns {Promise<Array>} Array of decrypted vault items
 */
async function decryptCardVaultBackup(rawPayload, masterPassword) {
  let payload;
  try {
    payload = typeof rawPayload === 'string' ? JSON.parse(rawPayload.trim()) : rawPayload;
  } catch (err) {
    throw new Error('Invalid backup file format: Not valid JSON.');
  }

  // Handle unencrypted or legacy direct items
  if (payload.items && Array.isArray(payload.items) && !payload.data) {
    return payload.items;
  }

  if (!payload.salt || !payload.iv || !payload.data) {
    throw new Error('Invalid CardVault backup file: missing encryption metadata.');
  }

  const saltBytes = base64ToUint8Array(payload.salt);
  const ivBytes = base64ToUint8Array(payload.iv);
  const cipherBytes = base64ToUint8Array(payload.data);

  const dec = new TextDecoder();

  // 1. Primary Attempt: Match Dart's SecureBackupExportService key derivation
  try {
    const aesKey = await deriveKeyCardVaultDart(masterPassword, saltBytes);
    const decryptedBuffer = await crypto.subtle.decrypt(
      { name: 'AES-CBC', iv: ivBytes },
      aesKey,
      cipherBytes
    );
    const jsonString = dec.decode(decryptedBuffer);
    const parsed = JSON.parse(jsonString);
    return parsed.items || [];
  } catch (errDart) {
    console.warn('[CardVault] Dart HMAC key derivation attempt notice:', errDart);
  }

  // 2. Secondary Attempt: Standard RFC 2898 PBKDF2
  try {
    const aesKeyStd = await deriveKeyStandardPBKDF2(masterPassword, saltBytes);
    const decryptedBuffer = await crypto.subtle.decrypt(
      { name: 'AES-CBC', iv: ivBytes },
      aesKeyStd,
      cipherBytes
    );
    const jsonString = dec.decode(decryptedBuffer);
    const parsed = JSON.parse(jsonString);
    return parsed.items || [];
  } catch (errStd) {
    console.warn('[CardVault] Standard PBKDF2 attempt notice:', errStd);
  }

  throw new Error('Failed to decrypt vault: Incorrect Master Password or corrupted backup file.');
}

/**
 * Decrypts a master password sealed with a secret (6-digit PIN or requestId)
 */
async function decryptSealedMasterPassword(sealedKeyObj, secret) {
  if (!sealedKeyObj || !sealedKeyObj.salt || !sealedKeyObj.iv || !sealedKeyObj.ciphertext) {
    throw new Error('Missing sealed key metadata.');
  }
  const saltBytes = base64ToUint8Array(sealedKeyObj.salt);
  const ivBytes = base64ToUint8Array(sealedKeyObj.iv);
  const cipherBytes = base64ToUint8Array(sealedKeyObj.ciphertext);

  const aesKey = await deriveKeyCardVaultDart(String(secret).trim(), saltBytes);
  const decryptedBuffer = await crypto.subtle.decrypt(
    { name: 'AES-CBC', iv: ivBytes },
    aesKey,
    cipherBytes
  );
  return new TextDecoder().decode(decryptedBuffer);
}

// ─── TOTP (2FA Authenticator - RFC 6238) ───────────────────────────────────

const BASE32_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

function decodeBase32(str) {
  const clean = (str || '').trim().toUpperCase().replace(/[\s\-=]/g, '');
  let bits = 0;
  let value = 0;
  const output = [];

  for (let i = 0; i < clean.length; i++) {
    const idx = BASE32_ALPHABET.indexOf(clean[i]);
    if (idx === -1) continue;
    value = (value << 5) | idx;
    bits += 5;
    if (bits >= 8) {
      output.push((value >>> (bits - 8)) & 255);
      bits -= 8;
    }
  }
  return new Uint8Array(output);
}

/**
 * Generates current 6-digit TOTP code from a Base32 secret key.
 */
async function generateTotpCode(secretKey, customTimeMs = Date.now(), period = 30, digits = 6) {
  if (!secretKey) return '';
  let cleanKey = secretKey.trim();
  if (cleanKey.toLowerCase().startsWith('otpauth://')) {
    try {
      const url = new URL(cleanKey);
      cleanKey = url.searchParams.get('secret') || cleanKey;
    } catch (_) {}
  }

  const keyBytes = decodeBase32(cleanKey);
  if (keyBytes.length === 0) return '';

  const epoch = Math.floor(customTimeMs / 1000);
  let counter = Math.floor(epoch / period);

  // 8-byte big endian counter buffer
  const counterBuffer = new ArrayBuffer(8);
  const counterView = new DataView(counterBuffer);
  // Big-endian 64-bit int
  counterView.setUint32(0, Math.floor(counter / 0x100000000), false);
  counterView.setUint32(4, counter & 0xFFFFFFFF, false);

  try {
    const cryptoKey = await crypto.subtle.importKey(
      'raw',
      keyBytes,
      { name: 'HMAC', hash: { name: 'SHA-1' } },
      false,
      ['sign']
    );

    const signature = await crypto.subtle.sign('HMAC', cryptoKey, counterBuffer);
    const hash = new Uint8Array(signature);

    const offset = hash[hash.length - 1] & 0x0F;
    const binary =
      ((hash[offset] & 0x7F) << 24) |
      ((hash[offset + 1] & 0xFF) << 16) |
      ((hash[offset + 2] & 0xFF) << 8) |
      (hash[offset + 3] & 0xFF);

    const otp = binary % Math.pow(10, digits);
    return otp.toString().padStart(digits, '0');
  } catch (err) {
    console.warn('[TetherPass] TOTP error:', err);
    return '';
  }
}

function getTotpRemainingSeconds(period = 30) {
  const epoch = Math.floor(Date.now() / 1000);
  const elapsed = epoch % period;
  return period - elapsed;
}

// ─── Breach Watch (HaveIBeenPwned k-Anonymity) ─────────────────────────────

async function checkPasswordBreached(password) {
  if (!password) return { isPwned: false, breachCount: 0 };
  try {
    const enc = new TextEncoder();
    const digest = await crypto.subtle.digest('SHA-1', enc.encode(password));
    const hex = Array.from(new Uint8Array(digest))
      .map(b => b.toString(16).padStart(2, '0'))
      .join('')
      .toUpperCase();

    const prefix = hex.substring(0, 5);
    const suffix = hex.substring(5);

    const resp = await fetch(`https://api.pwnedpasswords.com/range/${prefix}`, {
      headers: { 'Add-Padding': 'true' }
    });

    if (!resp.ok) return { isPwned: false, breachCount: 0, error: 'Network check failed' };

    const text = await resp.text();
    const lines = text.split('\n');
    for (const line of lines) {
      const [lineSuffix, countStr] = line.split(':');
      if (lineSuffix && lineSuffix.trim() === suffix) {
        const count = parseInt(countStr.trim(), 10) || 1;
        return { isPwned: true, breachCount: count };
      }
    }
    return { isPwned: false, breachCount: 0 };
  } catch (e) {
    return { isPwned: false, breachCount: 0, error: e.message };
  }
}

// ─── Encrypt Backup for Sync ────────────────────────────────────────────────

async function encryptTetherPassBackup(items, masterPassword) {
  const enc = new TextEncoder();
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const iv = crypto.getRandomValues(new Uint8Array(16));

  const hmacKey = await crypto.subtle.importKey(
    'raw',
    enc.encode(masterPassword),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  );

  let current = salt;
  for (let i = 0; i < 10000; i++) {
    current = new Uint8Array(await crypto.subtle.sign('HMAC', hmacKey, current));
  }

  const aesKey = await crypto.subtle.importKey(
    'raw',
    current,
    { name: 'AES-CBC' },
    false,
    ['encrypt']
  );

  const payloadJson = JSON.stringify({
    version: 1,
    exported_at: new Date().toISOString(),
    kdf: 'pbkdf2_dart_hmac',
    items: items.map(it => it)
  });

  const encryptedBuffer = await crypto.subtle.encrypt(
    { name: 'AES-CBC', iv },
    aesKey,
    enc.encode(payloadJson)
  );

  return JSON.stringify({
    header: 'TETHERPASS_SECURE_BACKUP_V1',
    salt: uint8ArrayToBase64(salt),
    iv: uint8ArrayToBase64(iv),
    data: uint8ArrayToBase64(new Uint8Array(encryptedBuffer))
  }, null, 2);
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    decryptCardVaultBackup,
    decryptSealedMasterPassword,
    deriveKeyCardVaultDart,
    deriveKeyStandardPBKDF2,
    generateTotpCode,
    getTotpRemainingSeconds,
    checkPasswordBreached,
    encryptTetherPassBackup,
    base64ToUint8Array,
    uint8ArrayToBase64
  };
}
