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

// ─── Fast In-Memory SHA-256 and HMAC-SHA-256 ─────────────────────────────────
// Performs 10,000 iterations in ~60ms synchronously without async promise overhead

const SHA256_K = [
  0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
  0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
  0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
  0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
  0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
  0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
  0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
  0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
];

function sha256_words(inputWords, inputLen) {
  let H = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
  const words = inputWords.slice();
  words[inputLen >> 2] |= 0x80 << (24 - (inputLen % 4) * 8);
  const totalWords = (((inputLen + 8) >> 6) + 1) * 16;
  while (words.length < totalWords) words.push(0);
  words[totalWords - 1] = inputLen * 8;
  const W = new Int32Array(64);
  for (let i = 0; i < words.length; i += 16) {
    for (let t = 0; t < 16; t++) W[t] = words[i + t];
    for (let t = 16; t < 64; t++) {
      const s0 = ((W[t - 15] >>> 7) | (W[t - 15] << 25)) ^ ((W[t - 15] >>> 18) | (W[t - 15] << 14)) ^ (W[t - 15] >>> 3);
      const s1 = ((W[t - 2] >>> 17) | (W[t - 2] << 15)) ^ ((W[t - 2] >>> 19) | (W[t - 2] << 13)) ^ (W[t - 2] >>> 10);
      W[t] = (W[t - 16] + s0 + W[t - 7] + s1) | 0;
    }
    let a = H[0], b = H[1], c = H[2], d = H[3], e = H[4], f = H[5], g = H[6], h = H[7];
    for (let t = 0; t < 64; t++) {
      const S1 = ((e >>> 6) | (e << 26)) ^ ((e >>> 11) | (e << 21)) ^ ((e >>> 25) | (e << 7));
      const ch = (e & f) ^ ((~e) & g);
      const temp1 = (h + S1 + ch + SHA256_K[t] + W[t]) | 0;
      const S0 = ((a >>> 2) | (a << 30)) ^ ((a >>> 13) | (a << 19)) ^ ((a >>> 22) | (a << 10));
      const maj = (a & b) ^ (a & c) ^ (b & c);
      const temp2 = (S0 + maj) | 0;
      h = g; g = f; f = e; e = (d + temp1) | 0; d = c; c = b; b = a; a = (temp1 + temp2) | 0;
    }
    H[0] = (H[0] + a) | 0; H[1] = (H[1] + b) | 0; H[2] = (H[2] + c) | 0; H[3] = (H[3] + d) | 0;
    H[4] = (H[4] + e) | 0; H[5] = (H[5] + f) | 0; H[6] = (H[6] + g) | 0; H[7] = (H[7] + h) | 0;
  }
  return H;
}

function bytesToWords(bytes) {
  const words = [];
  for (let i = 0; i < bytes.length; i++) {
    words[i >> 2] |= (bytes[i] & 0xff) << (24 - (i % 4) * 8);
  }
  return words;
}

function wordsToBytes(words) {
  const bytes = new Uint8Array(words.length * 4);
  for (let i = 0; i < words.length; i++) {
    bytes[i * 4] = (words[i] >>> 24) & 0xff;
    bytes[i * 4 + 1] = (words[i] >>> 16) & 0xff;
    bytes[i * 4 + 2] = (words[i] >>> 8) & 0xff;
    bytes[i * 4 + 3] = words[i] & 0xff;
  }
  return bytes;
}

function hmacSha256(keyBytes, msgBytes) {
  let k = keyBytes;
  if (k.length > 64) {
    k = wordsToBytes(sha256_words(bytesToWords(k), k.length));
  }
  const oKeyPad = new Uint8Array(64);
  const iKeyPad = new Uint8Array(64);
  for (let i = 0; i < 64; i++) {
    const b = i < k.length ? k[i] : 0;
    oKeyPad[i] = b ^ 0x5c;
    iKeyPad[i] = b ^ 0x36;
  }
  const innerMsg = new Uint8Array(64 + msgBytes.length);
  innerMsg.set(iKeyPad, 0);
  innerMsg.set(msgBytes, 64);
  const innerHash = wordsToBytes(sha256_words(bytesToWords(innerMsg), innerMsg.length));
  const outerMsg = new Uint8Array(64 + 32);
  outerMsg.set(oKeyPad, 0);
  outerMsg.set(innerHash, 64);
  return wordsToBytes(sha256_words(bytesToWords(outerMsg), outerMsg.length));
}

function fastDeriveKeyBytes(password, saltBytes, rounds = 10000) {
  const pwdBytes = typeof password === 'string' ? new TextEncoder().encode(password) : password;
  let cur = saltBytes;
  for (let i = 0; i < rounds; i++) {
    cur = hmacSha256(pwdBytes, cur);
  }
  return cur;
}

/**
 * Derives a 256-bit AES key matching CardVault's Flutter SecureBackupExportService
 * using synchronous HMAC-SHA256 iterations (runs in ~60ms instead of 6+ seconds).
 */
async function deriveKeyCardVaultDart(masterPassword, saltBytes) {
  const derivedBytes = fastDeriveKeyBytes(masterPassword, saltBytes, 10000);
  return await crypto.subtle.importKey(
    'raw',
    derivedBytes,
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
 * Decrypts a master password sealed with a secret (requestId for Push Approval)
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

  const current = fastDeriveKeyBytes(masterPassword, salt, 10000);

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
