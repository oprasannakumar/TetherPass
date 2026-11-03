/**
 * CardVault Google Drive Client
 * Interacts with Google Drive API v3 to fetch encrypted vault backups
 * and handles live Mobile Confirmation Pop-up authorization handshake.
 */

const GOOGLE_CLIENT_ID = '455353267035-ikc7gak770ubpgvdru3p1lo3j88i0f1s.apps.googleusercontent.com';
const DRIVE_BACKUP_FILENAME = 'card_vault_backup_v2.json';
const DRIVE_REQUEST_FILENAME = 'card_vault_access_request.json';
const DRIVE_DEVICES_FILENAME = 'card_vault_devices.json';
const DRIVE_SESSIONS_FILENAME = 'card_vault_active_sessions.json';

class DriveClient {
  constructor() {
    this.token = null;
    this.clientId = GOOGLE_CLIENT_ID;
    this._fileIdCache = new Map();
  }

  setToken(token) {
    this.token = token;
  }

  /**
   * Performs real Google OAuth 2.0 Sign-In via chrome.identity.getAuthToken
   * or chrome.identity.launchWebAuthFlow when interactive is explicitly requested.
   */
  async signInWithGoogle() {
    return new Promise((resolve, reject) => {
      if (typeof chrome === 'undefined' || !chrome.identity) {
        return reject(new Error('chrome.identity API unavailable'));
      }

      // 1. Try getAuthToken first (seamless if account already authorized)
      chrome.identity.getAuthToken({ interactive: true }, (token) => {
        if (!chrome.runtime.lastError && token) {
          this.token = token;
          if (typeof chrome !== 'undefined' && chrome.storage?.local) {
            chrome.storage.local.set({ googleOAuthToken: token });
          }
          return resolve(token);
        }

        // 2. Fallback to launchWebAuthFlow with select_account
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
          `&prompt=select_account`;

        chrome.identity.launchWebAuthFlow({ url: authUrl, interactive: true }, (responseUrl) => {
          if (!chrome.runtime.lastError && responseUrl) {
            try {
              const url = new URL(responseUrl);
              const hash = url.hash.substring(1);
              const params = new URLSearchParams(hash);
              const accessToken = params.get('access_token');
              if (accessToken) {
                this.token = accessToken;
                if (typeof chrome !== 'undefined' && chrome.storage?.local) {
                  chrome.storage.local.set({ googleOAuthToken: accessToken });
                }
                return resolve(accessToken);
              }
            } catch (_) {}
          }
          reject(new Error(chrome.runtime.lastError ? chrome.runtime.lastError.message : 'Google Sign-In was cancelled'));
        });
      });
    });
  }

  async getAuthToken(interactive = false) {
    if (this.token) return this.token;

    // Check storage for persisted token
    if (typeof chrome !== 'undefined' && chrome.storage?.local) {
      try {
        const stored = await chrome.storage.local.get('googleOAuthToken');
        if (stored?.googleOAuthToken) {
          this.token = stored.googleOAuthToken;
          return this.token;
        }
      } catch (_) {}
    }

    if (!interactive) {
      // Strictly non-interactive: try silent retrieval without opening any window
      if (typeof chrome !== 'undefined' && chrome.identity?.getAuthToken) {
        try {
          const silentToken = await new Promise((resolve) => {
            chrome.identity.getAuthToken({ interactive: false }, (t) => {
              if (chrome.runtime.lastError || !t) resolve(null);
              else resolve(t);
            });
          });
          if (silentToken) {
            this.token = silentToken;
            if (chrome.storage?.local) {
              chrome.storage.local.set({ googleOAuthToken: silentToken });
            }
            return silentToken;
          }
        } catch (_) {}
      }
      return null; // Return null safely — NEVER pop up interactive prompt on startup!
    }

    // Only launch interactive sign-in flow if explicitly requested by user click
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
    if (this._fileIdCache.has(filename)) {
      return { id: this._fileIdCache.get(filename), name: filename };
    }
    const token = await this.getAuthToken(false);
    if (!token) return null;
    const query = encodeURIComponent(`name = '${filename}' and trashed = false`);
    const url = `https://www.googleapis.com/drive/v3/files?q=${query}&spaces=drive,appDataFolder&fields=files(id,name,modifiedTime)`;

    const res = await fetch(url, {
      cache: 'no-store',
      headers: {
        Authorization: `Bearer ${token}`,
        'Cache-Control': 'no-cache, no-store'
      }
    });

    if (!res.ok) {
      if (res.status === 401) this.token = null;
      throw new Error(`Drive search failed HTTP ${res.status}: ${await res.text()}`);
    }

    const data = await res.json();
    const file = data.files && data.files.length > 0 ? data.files[0] : null;
    if (file && file.id) {
      this._fileIdCache.set(filename, file.id);
    }
    return file;
  }

  async downloadFileContent(fileId) {
    const token = await this.getAuthToken(false);
    if (!token) throw new Error('Not connected to Google Drive');
    const url = `https://www.googleapis.com/drive/v3/files/${fileId}?alt=media&_t=${Date.now()}`;

    const res = await fetch(url, {
      cache: 'no-store',
      headers: {
        Authorization: `Bearer ${token}`,
        'Cache-Control': 'no-cache, no-store, must-revalidate',
        'Pragma': 'no-cache'
      }
    });

    if (!res.ok) {
      if (res.status === 404) {
        for (const [k, v] of this._fileIdCache.entries()) {
          if (v === fileId) this._fileIdCache.delete(k);
        }
      }
      throw new Error(`Drive download failed HTTP ${res.status}`);
    }

    return await res.text();
  }

  /**
   * Uploads or updates a file in Google Drive AppData folder
   */
  async uploadOrUpdateFile(filename, textContent) {
    const token = await this.getAuthToken(false);
    if (!token) throw new Error('Not connected to Google Drive');
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
      if (res.status === 404) {
        this._fileIdCache.delete(filename);
      }
      throw new Error(`Drive upload failed HTTP ${res.status}: ${await res.text()}`);
    }

    const uploadResult = await res.json();
    if (uploadResult && uploadResult.id) {
      this._fileIdCache.set(filename, uploadResult.id);
    }
    return uploadResult;
  }

  async uploadAppDataFile(filename, textContent) {
    return await this.uploadOrUpdateFile(filename, textContent);
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
  async sendAccessRequestToMobile(deviceName = 'Windows PC (TetherPass Extension)', targetDeviceId = 'ALL', authMode = 'PUSH') {
    const requestId = 'req_' + Date.now() + '_' + Math.floor(Math.random() * 10000);
    const durationMs = 60000; // 60s timeout for desktop pairing
    const expiresAt = Date.now() + durationMs;

    const payload = JSON.stringify({
      requestId,
      status: 'PENDING',
      requestedAt: Date.now(),
      expiresAt,
      device: deviceName,
      targetDeviceId: targetDeviceId || 'ALL',
      authMode: authMode,
      mode: authMode
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
      message: req.message,
      request_sealed_key: req.request_sealed_key
    };
  }

  /**
   * Fetches latest encrypted backup payload from Drive
   */
  async fetchEncryptedVaultBackup() {
    const file = await this.findFile(DRIVE_BACKUP_FILENAME);
    if (!file) {
      throw new Error(`Vault backup '${DRIVE_BACKUP_FILENAME}' not found in Google Drive. Please tap 'Backup to Google Drive' in TetherPass mobile app.`);
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

      // Track in removedDevices list so the removed mobile app clears/wipes its local data
      const currentRemoved = Array.isArray(data.removedDevices) ? data.removedDevices : [];
      const updatedRemoved = [
        ...currentRemoved.filter(r => r.deviceId !== deviceId),
        { deviceId, removedAt: Date.now() }
      ];

      const payload = JSON.stringify({ devices: updatedList, removedDevices: updatedRemoved }, null, 2);
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
   * Checks if desktop authorization was explicitly revoked or terminated from the mobile app.
   * @param {string} authMode 'PUSH'
   * @param {number} sessionStartTime timestamp when current session was unlocked
   * @param {string} sessionId unique ID of this session
   */
  async isAuthorizationRevoked(authMode, sessionStartTime, sessionId) {
    const now = Date.now();
    // Cache revocation check results for 2.5 seconds to prevent spamming Google Drive while remaining responsive
    if (this._lastRevokeCheckTime && (now - this._lastRevokeCheckTime < 2500)) {
      return this._lastRevokeResult || false;
    }
    this._lastRevokeCheckTime = now;

    try {
      // 0. Inspect card_vault_active_sessions.json (multi-session registry)
      const sessionsFile = await this.findFile(DRIVE_SESSIONS_FILENAME);
      if (sessionsFile) {
        try {
          const content = await this.downloadFileContent(sessionsFile.id);
          const data = JSON.parse(content);
          const sessions = data.sessions || [];
          let foundSession = false;
          for (const s of sessions) {
            if (!s) continue;
            // Check matching sessionId
            if (sessionId && s.sessionId === sessionId) {
              foundSession = true;
              const sStatus = (s.status || '').toUpperCase();
              if (sStatus === 'TERMINATED' || sStatus === 'REVOKED' || sStatus === 'LOCKED') {
                this._lastRevokeResult = true;
                return true;
              }
            }
            // Check if terminated recently after session began
            const sStatus = (s.status || '').toUpperCase();
            if (sStatus === 'TERMINATED' && s.terminatedAt && sessionStartTime && s.terminatedAt > (sessionStartTime + 1000)) {
              if (!sessionId || s.sessionId === sessionId || s.authMode === authMode) {
                this._lastRevokeResult = true;
                return true;
              }
            }
          }
          // If sessionId was actively registered, but the sessions file was updated after session began
          // and sessionId is now completely missing from the list, mobile has removed/terminated it!
          if (sessionId && !foundSession && data.updatedAt && sessionStartTime && data.updatedAt > (sessionStartTime + 1000)) {
            console.log('[TetherPass] Session', sessionId, 'purged from active sessions on Drive; revoking.');
            this._lastRevokeResult = true;
            return true;
          }
        } catch (_) {}
      }

      // 1. Inspect access request record (card_vault_access_request.json)
      const reqFile = await this.findFile(DRIVE_REQUEST_FILENAME);
      if (reqFile) {
        try {
          const reqContent = await this.downloadFileContent(reqFile.id);
          const req = JSON.parse(reqContent);
          const reqStatus = (req.status || '').toUpperCase();
          if (reqStatus === 'REVOKED' || reqStatus === 'LOCKED' || reqStatus === 'TERMINATED') {
            const reqTime = req.locked_at || req.revoked_at || req.terminated_at || 0;
            if ((sessionId && req.requestId === sessionId) || (reqTime && sessionStartTime && reqTime > (sessionStartTime + 1000))) {
              this._lastRevokeResult = true;
              return true;
            }
          }
        } catch (_) {}
      }

      this._lastRevokeResult = false;
      return false;
    } catch (_) {
      // Soft error (network timeout or rate limit) - do NOT falsely revoke
      return false;
    }
  }

  /**
   * Records active desktop session into Google Drive session registry
   */
  async recordActiveSession({ sessionId, deviceName, authMode, createdAt, expiresAt }) {
    if (!this.token) return;
    try {
      let sessions = [];
      const file = await this.findFile(DRIVE_SESSIONS_FILENAME);
      if (file) {
        try {
          const content = await this.downloadFileContent(file.id);
          const data = JSON.parse(content);
          sessions = data.sessions || [];
        } catch (_) {}
      }

      sessions = sessions.filter(s => s && s.sessionId !== sessionId);
      sessions.unshift({
        sessionId,
        deviceName: deviceName || 'Windows PC (TetherPass Extension)',
        authMode: authMode || 'PUSH',
        createdAt: createdAt || Date.now(),
        expiresAt: expiresAt || (Date.now() + 30 * 60 * 1000),
        status: 'ACTIVE'
      });

      if (sessions.length > 20) sessions = sessions.slice(0, 20);

      const payload = JSON.stringify({
        version: 1,
        updatedAt: Date.now(),
        sessions
      });

      await this.uploadAppDataFile(DRIVE_SESSIONS_FILENAME, payload);
    } catch (e) {
      console.warn('[TetherPass] Could not record active session:', e.message);
    }
  }

  /**
   * Immediately removes the desktop session from Google Drive and marks the access request as LOCKED.
   * Called as soon as the user manually locks the browser extension.
   * This ensures the session is instantly removed from the mobile phone screen.
   */
  async markSessionLocked(sessionId = null) {
    if (!this.token) {
      if (typeof chrome !== 'undefined' && chrome.storage?.local) {
        try {
          const stored = await chrome.storage.local.get('googleOAuthToken');
          if (stored?.googleOAuthToken) {
            this.token = stored.googleOAuthToken;
          }
        } catch (_) {}
      }
    }
    if (!this.token) return;

    try {
      // Execute both Drive updates in parallel for fast lock execution
      const taskRequest = (async () => {
        try {
          const reqFile = await this.findFile(DRIVE_REQUEST_FILENAME);
          if (reqFile) {
            try {
              const reqContent = await this.downloadFileContent(reqFile.id);
              const req = JSON.parse(reqContent);
              // CRITICAL: Protect fresh QR pairing requests.
              // If a new pairing session is already PENDING with a different requestId,
              // DO NOT overwrite it with LOCKED!
              if (req?.status === 'PENDING' && req?.requestId && req.requestId !== sessionId) {
                console.log('[TetherPass] Newer pending request active on Drive, skipping lock overwrite:', req.requestId);
                return;
              }
              if (sessionId && req?.requestId && req.requestId !== sessionId && req.status !== 'APPROVED') {
                return;
              }
            } catch (_) {}
          }

          const reqClear = JSON.stringify({
            requestId: sessionId || '',
            status: 'LOCKED',
            locked_at: Date.now()
          });
          await this.uploadOrUpdateFile(DRIVE_REQUEST_FILENAME, reqClear);
          console.log('[TetherPass] Access request overwritten with LOCKED on Drive, reqId:', sessionId || 'all');
        } catch (e) {
          console.warn('[TetherPass] Could not overwrite access request:', e.message);
        }
      })();

      const taskSessions = (async () => {
        try {
          let sessions = [];
          const file = await this.findFile(DRIVE_SESSIONS_FILENAME);
          if (file) {
            try {
              const content = await this.downloadFileContent(file.id);
              const data = JSON.parse(content);
              sessions = data.sessions || [];
            } catch (_) {}
          }

          if (sessionId) {
            sessions = sessions.filter(s => s && s.sessionId !== sessionId);
          } else {
            sessions = [];
          }

          const payload = JSON.stringify({
            version: 1,
            updatedAt: Date.now(),
            sessions: sessions.slice(0, 20)
          });

          await this.uploadAppDataFile(DRIVE_SESSIONS_FILENAME, payload);
          console.log('[TetherPass] Sessions file updated on Drive for:', sessionId || 'all');
        } catch (e) {
          console.warn('[TetherPass] Could not update active sessions on lock:', e.message);
        }
      })();

      await Promise.allSettled([taskRequest, taskSessions]);
    } catch (e) {
      console.warn('[TetherPass] markSessionLocked error:', e.message);
    }
  }

  /**
   * Checks if session expiration was extended remotely from mobile app
   */
  async getRemoteSessionExpiresAt(sessionId, authMode) {
    if (!this.token) return null;
    try {
      const file = await this.findFile(DRIVE_SESSIONS_FILENAME);
      if (file) {
        const content = await this.downloadFileContent(file.id);
        const data = JSON.parse(content);
        const sessions = data.sessions || [];
        for (const s of sessions) {
          if (s && s.sessionId === sessionId && s.status === 'ACTIVE' && s.expiresAt) {
            return s.expiresAt;
          }
        }
      }

      if (authMode === 'PUSH' || !authMode) {
        const reqFile = await this.findFile(DRIVE_REQUEST_FILENAME);
        if (reqFile) {
          const reqContent = await this.downloadFileContent(reqFile.id);
          const req = JSON.parse(reqContent);
          if (req.status === 'APPROVED' && req.expiresAt) return req.expiresAt;
        }
      }
    } catch (_) {}
    return null;
  }
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    DriveClient,
    GOOGLE_CLIENT_ID,
    DRIVE_BACKUP_FILENAME,
    DRIVE_REQUEST_FILENAME
  };
}
