/**
 * CardVault Google Drive Client
 * Interacts with Google Drive API v3 to fetch encrypted vault backups
 * and handles live Mobile Confirmation Pop-up authorization handshake.
 */

const GOOGLE_CLIENT_ID = '455353267035-ikc7gak770ubpgvdru3p1lo3j88i0f1s.apps.googleusercontent.com';
const DRIVE_BACKUP_FILENAME = 'card_vault_backup_v2.json';
const DRIVE_AUTH_FILENAME = 'card_vault_extension_auth.json';
const DRIVE_REQUEST_FILENAME = 'card_vault_access_request.json';
const DRIVE_DEVICES_FILENAME = 'card_vault_devices.json';

class DriveClient {
  constructor() {
    this.token = null;
    this.clientId = GOOGLE_CLIENT_ID;
  }

  setToken(token) {
    this.token = token;
  }

  /**
   * Performs real Google OAuth 2.0 Sign-In via chrome.identity.launchWebAuthFlow
   * or chrome.identity.getAuthToken.
   */
  async signInWithGoogle() {
    return new Promise((resolve, reject) => {
      if (typeof chrome === 'undefined' || !chrome.identity) {
        return reject(new Error('chrome.identity API unavailable'));
      }

      const redirectUri = chrome.identity.getRedirectURL();
      const scopes = [
        'https://www.googleapis.com/auth/drive.appdata',
        'https://www.googleapis.com/auth/drive.file',
        'https://www.googleapis.com/auth/userinfo.email',
        'https://www.googleapis.com/auth/userinfo.profile'
      ].join(' ');

      const authUrl = `https://accounts.google.com/o/oauth2/v2/auth` +
        `?client_id=${encodeURIComponent(this.clientId)}` +
        `&response_type=token` +
        `&redirect_uri=${encodeURIComponent(redirectUri)}` +
        `&scope=${encodeURIComponent(scopes)}` +
        `&prompt=consent`;

      // 1. Try launchWebAuthFlow (supports custom redirect URI / standard OAuth)
      chrome.identity.launchWebAuthFlow({ url: authUrl, interactive: true }, (responseUrl) => {
        if (!chrome.runtime.lastError && responseUrl) {
          try {
            const url = new URL(responseUrl);
            const hash = url.hash.substring(1);
            const params = new URLSearchParams(hash);
            const token = params.get('access_token');
            if (token) {
              this.token = token;
              return resolve(token);
            }
          } catch (_) {}
        }

        // 2. Fallback to getAuthToken
        chrome.identity.getAuthToken({ interactive: true }, (token) => {
          if (chrome.runtime.lastError || !token) {
            return reject(new Error(chrome.runtime.lastError ? chrome.runtime.lastError.message : 'Google Sign-In was cancelled'));
          }
          this.token = token;
          resolve(token);
        });
      });
    });
  }

  async getAuthToken(interactive = false) {
    if (this.token) return this.token;
    return await this.signInWithGoogle();
  }

  async getUserInfo() {
    const token = await this.getAuthToken(false);
    const res = await fetch('https://www.googleapis.com/oauth2/v2/userinfo', {
      headers: { Authorization: `Bearer ${token}` }
    });
    if (!res.ok) throw new Error(`UserInfo failed: ${res.status}`);
    return await res.json();
  }

  async findFile(filename) {
    const token = await this.getAuthToken(false);
    const query = encodeURIComponent(`name = '${filename}' and trashed = false`);
    const url = `https://www.googleapis.com/drive/v3/files?q=${query}&spaces=drive,appDataFolder&fields=files(id,name,modifiedTime)`;

    const res = await fetch(url, {
      headers: { Authorization: `Bearer ${token}` }
    });

    if (!res.ok) {
      if (res.status === 401) this.token = null;
      throw new Error(`Drive search failed HTTP ${res.status}: ${await res.text()}`);
    }

    const data = await res.json();
    return data.files && data.files.length > 0 ? data.files[0] : null;
  }

  async downloadFileContent(fileId) {
    const token = await this.getAuthToken(false);
    const url = `https://www.googleapis.com/drive/v3/files/${fileId}?alt=media`;

    const res = await fetch(url, {
      headers: { Authorization: `Bearer ${token}` }
    });

    if (!res.ok) {
      throw new Error(`Drive download failed HTTP ${res.status}`);
    }

    return await res.text();
  }

  /**
   * Uploads or updates a file in Google Drive AppData folder
   */
  async uploadOrUpdateFile(filename, textContent) {
    const token = await this.getAuthToken(false);
    const existing = await this.findFile(filename);

    const boundary = '-------314159265358979323846';
    const delimiter = `\r\n--${boundary}\r\n`;
    const closeDelimiter = `\r\n--${boundary}--`;

    const metadata = {
      name: filename,
      mimeType: 'application/json',
      parents: existing ? undefined : ['appDataFolder']
    };

    const multipartRequestBody =
      delimiter +
      'Content-Type: application/json; charset=UTF-8\r\n\r\n' +
      JSON.stringify(metadata) +
      delimiter +
      'Content-Type: application/json\r\n\r\n' +
      textContent +
      closeDelimiter;

    let url;
    let method;
    if (existing) {
      url = `https://www.googleapis.com/upload/drive/v3/files/${existing.id}?uploadType=multipart`;
      method = 'PATCH';
    } else {
      url = `https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart`;
      method = 'POST';
    }

    const res = await fetch(url, {
      method,
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': `multipart/related; boundary=${boundary}`
      },
      body: multipartRequestBody
    });

    if (!res.ok) {
      throw new Error(`Drive upload failed HTTP ${res.status}: ${await res.text()}`);
    }

    return await res.json();
  }

  /**
   * Fetches the list of user's registered mobile phones from Google Drive.
   */
  async fetchRegisteredDevices() {
    try {
      const file = await this.findFile(DRIVE_DEVICES_FILENAME);
      if (!file) return [];
      const content = await this.downloadFileContent(file.id);
      const data = JSON.parse(content);
      return data.devices || [];
    } catch (_) {
      return [];
    }
  }

  /**
   * Sends a live access request to trigger the mobile phone confirmation pop-up.
   * If targetDeviceId is provided, only that specific phone will prompt.
   * Status starts as 'PENDING'.
   */
  async sendAccessRequestToMobile(deviceName = 'Windows PC (CardVault Extension)', targetDeviceId = 'ALL') {
    const requestId = 'req_' + Date.now() + '_' + Math.floor(Math.random() * 10000);
    const expiresAt = Date.now() + 60000; // 60s timeout

    const payload = JSON.stringify({
      requestId,
      status: 'PENDING',
      requestedAt: Date.now(),
      expiresAt,
      device: deviceName,
      targetDeviceId: targetDeviceId || 'ALL'
    }, null, 2);

    await this.uploadOrUpdateFile(DRIVE_REQUEST_FILENAME, payload);

    return {
      requestId,
      expiresAt
    };
  }

  /**
   * Polls Google Drive to check if mobile device approved the request.
   */
  async checkAccessRequestStatus(requestId) {
    const file = await this.findFile(DRIVE_REQUEST_FILENAME);
    if (!file) return { status: 'PENDING' };

    const content = await this.downloadFileContent(file.id);
    const req = JSON.parse(content);

    if (req.requestId !== requestId) {
      return { status: 'PENDING' };
    }

    const now = Date.now();
    if (req.expiresAt && now > req.expiresAt) {
      return { status: 'EXPIRED', message: 'Request timed out without response.' };
    }

    return {
      status: req.status, // 'PENDING', 'APPROVED', 'DENIED', 'LOCKED'
      approvedAt: req.approvedAt,
      expiresAt: req.expiresAt,
      message: req.message
    };
  }

  /**
   * Fetches latest encrypted backup payload from Drive
   */
  async fetchEncryptedVaultBackup() {
    const file = await this.findFile(DRIVE_BACKUP_FILENAME);
    if (!file) {
      throw new Error(`Vault backup '${DRIVE_BACKUP_FILENAME}' not found in Google Drive. Please tap 'Backup to Google Drive' in CardVault mobile app.`);
    }
    return await this.downloadFileContent(file.id);
  }

  /**
   * Removes a device from the registered devices list in Google Drive.
   */
  async removeRegisteredDevice(deviceId) {
    try {
      const file = await this.findFile(DRIVE_DEVICES_FILENAME);
      if (!file) return [];
      const content = await this.downloadFileContent(file.id);
      const data = JSON.parse(content);
      const currentList = Array.isArray(data.devices) ? data.devices : [];
      const updatedList = currentList.filter(d => d.deviceId !== deviceId);
      const payload = JSON.stringify({ devices: updatedList }, null, 2);
      await this.uploadOrUpdateFile(DRIVE_DEVICES_FILENAME, payload);
      return updatedList;
    } catch (err) {
      console.error('[DriveClient] Failed to remove device:', err);
      throw err;
    }
  }

  /**
   * Renames a device in the registered devices list in Google Drive.
   */
  async renameRegisteredDevice(deviceId, newName) {
    try {
      const file = await this.findFile(DRIVE_DEVICES_FILENAME);
      if (!file) return [];
      const content = await this.downloadFileContent(file.id);
      const data = JSON.parse(content);
      const currentList = Array.isArray(data.devices) ? data.devices : [];
      const updatedList = currentList.map(d => {
        if (d.deviceId === deviceId) {
          return { ...d, deviceName: newName.trim() };
        }
        return d;
      });
      const payload = JSON.stringify({ devices: updatedList }, null, 2);
      await this.uploadOrUpdateFile(DRIVE_DEVICES_FILENAME, payload);
      return updatedList;
    } catch (err) {
      console.error('[DriveClient] Failed to rename device:', err);
      throw err;
    }
  }

  /**
   * Checks authorization status record
   */
  async checkMobileAuthorization() {
    try {
      const file = await this.findFile(DRIVE_AUTH_FILENAME);
      if (!file) {
        return { authorized: false, reason: 'NO_AUTH_RECORD', message: 'No authorization request found. Please authorize extension in mobile app.' };
      }

      const content = await this.downloadFileContent(file.id);
      const auth = JSON.parse(content);

      const now = Date.now();
      const isExpired = auth.expires_at && now > auth.expires_at;

      if (auth.status === 'AUTHORIZED' && !isExpired) {
        return {
          authorized: true,
          pin: auth.pairing_pin,
          expiresAt: auth.expires_at,
          authorizedAt: auth.authorized_at,
          device: auth.device
        };
      } else {
        return {
          authorized: false,
          reason: isExpired ? 'EXPIRED' : (auth.status || 'LOCKED'),
          message: isExpired ? 'Authorization expired. Please re-authorize on your phone.' : 'Locked from mobile app.'
        };
      }
    } catch (err) {
      return { authorized: false, reason: 'ERROR', message: err.message };
    }
  }
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    DriveClient,
    GOOGLE_CLIENT_ID,
    DRIVE_BACKUP_FILENAME,
    DRIVE_AUTH_FILENAME,
    DRIVE_REQUEST_FILENAME
  };
}
