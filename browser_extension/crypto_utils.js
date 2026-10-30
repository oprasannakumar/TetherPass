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

if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    decryptCardVaultBackup,
    deriveKeyCardVaultDart,
    deriveKeyStandardPBKDF2,
    base64ToUint8Array,
    uint8ArrayToBase64
  };
}
