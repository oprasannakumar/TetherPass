import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import 'crypto_service.dart';
import 'database_service.dart';
import 'secure_backup_export_service.dart';
import 'vault_security_service.dart';
import 'device_identity_service.dart';

class MasterPasswordRequiredException implements Exception {
  final String payload;
  const MasterPasswordRequiredException(this.payload);
  @override
  String toString() => 'Master Password required to decrypt this cloud backup.';
}

/// Handles Google Drive App Data backup and restore.
class DriveService extends ChangeNotifier {
  static const _backupFileName = 'card_vault_backup_v2.json';
  static const _scopes = ['https://www.googleapis.com/auth/drive.appdata'];

  final CryptoService cryptoService;
  final DatabaseService databaseService;
  final VaultSecurityService? vaultSecurityService;

  DriveService({
    required this.cryptoService,
    required this.databaseService,
    this.vaultSecurityService,
  }) {
    // Listen to Google Sign-In state changes in real time
    _googleSignIn.onCurrentUserChanged.listen((account) {
      _currentUser = account;
      notifyListeners();
    });

    // Automatically restore signed-in Google account silently on app launch
    trySilentSignIn();
  }

  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: _scopes);

  GoogleSignInAccount? _currentUser;
  bool get isSignedIn => _currentUser != null;
  String? get userEmail => _currentUser?.email;
  String? get userDisplayName => _currentUser?.displayName;
  String? get userPhotoUrl => _currentUser?.photoUrl;
  String? lastError;

  // ─── Auth ─────────────────────────────────────────────────────────────────

  Future<bool> signIn() async {
    lastError = null;
    try {
      _currentUser = await _googleSignIn.signIn();
      notifyListeners();
      return _currentUser != null;
    } catch (e) {
      lastError = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    _currentUser = null;
    notifyListeners();
  }

  /// Attempts silent sign-in using cached credentials.
  Future<bool> trySilentSignIn() async {
    try {
      _currentUser = await _googleSignIn.signInSilently();
      if (_currentUser != null) {
        notifyListeners();
      }
      return _currentUser != null;
    } catch (_) {
      return false;
    }
  }

  // ─── Drive API Client ─────────────────────────────────────────────────────

  Future<drive.DriveApi> _getDriveApi() async {
    final account = _currentUser;
    if (account == null) throw Exception('Not signed in to Google.');
    final authHeaders = await account.authHeaders;
    final client = _GoogleAuthClient(authHeaders);
    return drive.DriveApi(client);
  }

  // ─── Backup ───────────────────────────────────────────────────────────────

  Future<void> backup() async {
    final api = await _getDriveApi();
    
    // Encrypt with Master Password if available so backup can be restored across devices
    String encryptedData;
    final masterPwd = await vaultSecurityService?.getMasterPassword();
    if (masterPwd != null && masterPwd.isNotEmpty) {
      final items = await databaseService.getAllItems();
      encryptedData = SecureBackupExportService.exportVaultWithPassword(
        items: items,
        userPassword: masterPwd,
      );
    } else {
      encryptedData = await databaseService.exportEncryptedBackup();
    }

    final bytes = utf8.encode(encryptedData);
    final stream = Stream.value(bytes);

    final existing = await _findBackupFile(api);

    final fileMetadata = drive.File()
      ..name = _backupFileName
      ..parents = existing == null ? ['appDataFolder'] : null;

    final media = drive.Media(stream, bytes.length, contentType: 'text/plain');

    if (existing == null) {
      await api.files.create(fileMetadata, uploadMedia: media);
    } else {
      await api.files.update(
        fileMetadata,
        existing,
        uploadMedia: media,
      );
    }
  }

  // ─── Restore ──────────────────────────────────────────────────────────────

  /// Downloads raw backup payload string from Google Drive without decrypting
  Future<String> downloadRawBackupPayload() async {
    final api = await _getDriveApi();
    final fileId = await _findBackupFile(api);
    if (fileId == null) throw Exception('No backup file found in Google Drive.');

    final response = await api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;

    final chunks = <int>[];
    await for (final chunk in response.stream) {
      chunks.addAll(chunk);
    }

    return utf8.decode(chunks).trim();
  }

  Future<int> restore({String? masterPassword}) async {
    final encryptedPayload = await downloadRawBackupPayload();

    // 1. If encrypted with Master Password via SecureBackupExportService
    if (encryptedPayload.startsWith('{') && encryptedPayload.contains('CARDVAULT_SECURE_BACKUP_V1')) {
      final pwd = masterPassword ?? await vaultSecurityService?.getMasterPassword();
      if (pwd == null || pwd.isEmpty) {
        throw MasterPasswordRequiredException(encryptedPayload);
      }
      final items = SecureBackupExportService.importVaultWithPassword(
        backupPayload: encryptedPayload,
        userPassword: pwd,
      );
      int count = 0;
      for (final item in items) {
        await databaseService.insertItem(item);
        count++;
      }
      return count;
    }

    // 2. Legacy device-hardware-encrypted payload
    return await databaseService.importEncryptedBackup(encryptedPayload, masterPassword: masterPassword);
  }

  // ─── Custom Text File Management (for Browser Extension Auth) ─────────────

  Future<void> uploadTextFile(String fileName, String content) async {
    final api = await _getDriveApi();
    final bytes = utf8.encode(content);
    final stream = Stream.value(bytes);
    final existing = await _findNamedFile(api, fileName);

    final fileMetadata = drive.File()
      ..name = fileName
      ..parents = existing == null ? ['appDataFolder'] : null;

    final media = drive.Media(stream, bytes.length, contentType: 'application/json');

    if (existing == null) {
      await api.files.create(fileMetadata, uploadMedia: media);
    } else {
      await api.files.update(fileMetadata, existing, uploadMedia: media);
    }
  }

  Future<String?> downloadTextFile(String fileName) async {
    try {
      final api = await _getDriveApi();
      final fileId = await _findNamedFile(api, fileName);
      if (fileId == null) return null;

      final res = await api.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      final bytes = <int>[];
      await for (final chunk in res.stream) {
        bytes.addAll(chunk);
      }
      return utf8.decode(bytes);
    } catch (_) {
      return null;
    }
  }

  // ─── Desktop Access Request & Mobile Pop-up Handshake ─────────────────────

  static const accessRequestFileName = 'card_vault_access_request.json';
  static const devicesFileName = 'card_vault_devices.json';
  static const activeSessionsFileName = 'card_vault_active_sessions.json';

  /// Registers this mobile device in Google Drive so Windows Extension can detect multiple devices.
  /// Automatically clears any stale removal mark for this device, establishes fresh session time, and deduplicates.
  Future<void> registerDeviceOnDrive() async {
    if (!isSignedIn) return;
    try {
      final myId = await DeviceIdentityService.getDeviceId();
      final myName = await DeviceIdentityService.getDeviceName();
      final now = DateTime.now().millisecondsSinceEpoch;

      await DeviceIdentityService.updateSessionRegistrationTime(now);

      List<dynamic> deviceList = [];
      List<dynamic> removedList = [];
      final existingText = await downloadTextFile(devicesFileName);
      if (existingText != null && existingText.trim().isNotEmpty) {
        try {
          final data = jsonDecode(existingText) as Map<String, dynamic>;
          deviceList = (data['devices'] as List<dynamic>?) ?? [];
          removedList = (data['removedDevices'] as List<dynamic>?) ?? [];
        } catch (_) {}
      }

      // User logged into this device: clear any old removal mark so device is not blocked
      removedList.removeWhere((r) => r is Map && r['deviceId'] == myId);

      // Deduplicate: remove any stale device entry with matching deviceId or identical name
      deviceList.removeWhere((d) {
        if (d is! Map) return true;
        if (d['deviceId'] == myId) return true;
        if (d['deviceName'] == myName && d['deviceId'] != myId) {
          return true; // Stale duplicate entry from previous install
        }
        return false;
      });

      deviceList.add({
        'deviceId': myId,
        'deviceName': myName,
        'platform': Platform.isAndroid ? 'Android' : (Platform.isIOS ? 'iOS' : 'Mobile'),
        'lastActive': now,
      });

      final payload = jsonEncode({
        'devices': deviceList,
        'removedDevices': removedList,
      });
      await uploadTextFile(devicesFileName, payload);
    } catch (_) {}
  }

  /// Checks if this mobile phone was remotely removed AFTER this phone's current active session began.
  Future<bool> isCurrentDeviceRemoved() async {
    if (!isSignedIn) return false;
    try {
      final myId = await DeviceIdentityService.getDeviceId();
      final regTime = await DeviceIdentityService.getSessionRegistrationTime();
      final existingText = await downloadTextFile(devicesFileName);
      if (existingText == null || existingText.trim().isEmpty) return false;

      final data = jsonDecode(existingText) as Map<String, dynamic>;
      final removedList = (data['removedDevices'] as List<dynamic>?) ?? [];
      
      // Only trigger if removed timestamp is strictly newer than when this device logged in
      return removedList.any((r) {
        if (r is! Map || r['deviceId'] != myId) return false;
        final removedAt = (r['removedAt'] as num?)?.toInt() ?? 0;
        return removedAt > regTime;
      });
    } catch (_) {
      return false;
    }
  }

  /// Consumes and clears the remote wipe command from Google Drive after wipe is executed
  Future<void> acknowledgeAndClearDeviceWipe() async {
    if (!isSignedIn) return;
    try {
      final myId = await DeviceIdentityService.getDeviceId();
      final existingText = await downloadTextFile(devicesFileName);
      if (existingText == null || existingText.trim().isEmpty) return;

      final data = jsonDecode(existingText) as Map<String, dynamic>;
      final deviceList = (data['devices'] as List<dynamic>?) ?? [];
      final removedList = (data['removedDevices'] as List<dynamic>?) ?? [];

      removedList.removeWhere((r) => r is Map && r['deviceId'] == myId);

      final payload = jsonEncode({
        'devices': deviceList,
        'removedDevices': removedList,
      });
      await uploadTextFile(devicesFileName, payload);
    } catch (_) {}
  }

  /// Fetches the list of all registered mobile devices from Google Drive.
  Future<List<Map<String, dynamic>>> getRegisteredDevices() async {
    if (!isSignedIn) return [];
    try {
      final text = await downloadTextFile(devicesFileName);
      if (text == null || text.trim().isEmpty) return [];
      final data = jsonDecode(text) as Map<String, dynamic>;
      final list = (data['devices'] as List<dynamic>?) ?? [];
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Removes a registered device from Google Drive by its deviceId and logs it in removedDevices for remote wipe.
  Future<bool> removeRegisteredDevice(String deviceId) async {
    if (!isSignedIn) return false;
    try {
      final text = await downloadTextFile(devicesFileName);
      List<dynamic> deviceList = [];
      List<dynamic> removedList = [];
      if (text != null && text.trim().isNotEmpty) {
        try {
          final data = jsonDecode(text) as Map<String, dynamic>;
          deviceList = (data['devices'] as List<dynamic>?) ?? [];
          removedList = (data['removedDevices'] as List<dynamic>?) ?? [];
        } catch (_) {}
      }

      final updatedDevices = deviceList.where((d) => (d is Map && d['deviceId'] != deviceId)).toList();
      removedList.removeWhere((r) => r is Map && r['deviceId'] == deviceId);
      removedList.add({
        'deviceId': deviceId,
        'removedAt': DateTime.now().millisecondsSinceEpoch,
      });

      final payload = jsonEncode({
        'devices': updatedDevices,
        'removedDevices': removedList,
      });
      await uploadTextFile(devicesFileName, payload);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Renames a registered device in Google Drive.
  Future<bool> renameRegisteredDevice(String deviceId, String newName) async {
    if (!isSignedIn) return false;
    try {
      final list = await getRegisteredDevices();
      for (final d in list) {
        if (d['deviceId'] == deviceId) {
          d['deviceName'] = newName.trim();
        }
      }
      final payload = jsonEncode({'devices': list});
      await uploadTextFile(devicesFileName, payload);

      // If it's this device, also update local storage
      final myId = await DeviceIdentityService.getDeviceId();
      if (deviceId == myId) {
        await DeviceIdentityService.setDeviceName(newName);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Checks Google Drive for pending desktop extension access requests.
  /// Ignores requests targeted specifically at other mobile devices.
  Future<Map<String, dynamic>?> checkForPendingAccessRequest() async {
    if (!isSignedIn) return null;
    try {
      final text = await downloadTextFile(accessRequestFileName);
      if (text == null || text.trim().isEmpty) return null;
      final data = jsonDecode(text) as Map<String, dynamic>;
      final status = data['status'] as String?;
      final expiresAt = data['expiresAt'] as int?;
      final now = DateTime.now().millisecondsSinceEpoch;

      if (status == 'PENDING' && (expiresAt == null || now < expiresAt)) {
        // Multi-device targeting check:
        final targetDeviceId = data['targetDeviceId'] as String?;
        final myId = await DeviceIdentityService.getDeviceId();

        if (targetDeviceId != null &&
            targetDeviceId != 'ALL' &&
            targetDeviceId.isNotEmpty &&
            targetDeviceId != myId) {
          // Request is specifically intended for another mobile device
          return null;
        }

        return data;
      }
    } catch (_) {}
    return null;
  }

  /// Checks status of a specific access request (useful for multi-device sync)
  Future<String?> getAccessRequestStatus(String requestId) async {
    if (!isSignedIn) return null;
    try {
      final text = await downloadTextFile(accessRequestFileName);
      if (text == null || text.trim().isEmpty) return null;
      final data = jsonDecode(text) as Map<String, dynamic>;
      if (data['requestId'] == requestId) {
        return data['status'] as String?;
      }
    } catch (_) {}
    return null;
  }

  /// Responds to the pending desktop extension access request.
  /// Handles multi-mobile synchronization gracefully without conflicts.
  Future<bool> respondToAccessRequest({
    required String requestId,
    required bool approved,
    String? deviceName,
    String? masterPassword,
  }) async {
    if (!isSignedIn) return false;
    try {
      // Check if already approved or denied by another phone
      final currentStatus = await getAccessRequestStatus(requestId);
      if (currentStatus != null && currentStatus != 'PENDING') {
        return true; // Already processed by another linked mobile device
      }

      final now = DateTime.now();
      Map<String, dynamic>? requestSealedKey;
      if (approved && masterPassword != null && masterPassword.isNotEmpty) {
        final salt = enc.SecureRandom(16).bytes;
        final iv = enc.SecureRandom(16).bytes;
        final derived = _deriveKeyFromSecret(requestId, salt);
        final key = enc.Key(derived);
        final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
        final encrypted = encrypter.encrypt(masterPassword, iv: enc.IV(iv));
        requestSealedKey = {
          'salt': base64Encode(salt),
          'iv': base64Encode(iv),
          'ciphertext': encrypted.base64,
        };
      }

      final payloadMap = <String, dynamic>{
        'requestId': requestId,
        'status': approved ? 'APPROVED' : 'DENIED',
        'approvedAt': now.millisecondsSinceEpoch,
        'expiresAt': now.add(const Duration(minutes: 30)).millisecondsSinceEpoch,
        'device': deviceName ?? 'Windows PC (TetherPass Extension)',
        'approvedByDevice': 'TetherPass Mobile Client',
      };
      if (requestSealedKey != null) {
        payloadMap['request_sealed_key'] = requestSealedKey;
      }

      await uploadTextFile(accessRequestFileName, jsonEncode(payloadMap));

      if (approved) {
        await recordActiveSession(
          sessionId: requestId,
          deviceName: deviceName ?? 'Windows PC (TetherPass Extension)',
          authMode: 'PUSH',
          createdAt: now.millisecondsSinceEpoch,
          expiresAt: now.add(const Duration(minutes: 30)).millisecondsSinceEpoch,
        );
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  // ─── Active Desktop Sessions Management ────────────────────────────────────

  /// Fetches all active and recent desktop sessions from Google Drive.
  /// Merges records from activeSessionsFileName, accessRequestFileName, and card_vault_extension_auth.json.
  Future<List<Map<String, dynamic>>> getActiveDesktopSessions() async {
    if (!isSignedIn) return [];
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final Map<String, Map<String, dynamic>> sessionMap = {};

      // 1. Read from card_vault_active_sessions.json
      final text = await downloadTextFile(activeSessionsFileName);
      if (text != null && text.trim().isNotEmpty) {
        try {
          final data = jsonDecode(text) as Map<String, dynamic>;
          final list = (data['sessions'] as List<dynamic>?) ?? [];
          for (final item in list) {
            if (item is Map) {
              final map = Map<String, dynamic>.from(item);
              final id = map['sessionId'] as String? ?? '';
              if (id.isNotEmpty) {
                sessionMap[id] = map;
              }
            }
          }
        } catch (_) {}
      }

      // 2. Synthesize/merge from card_vault_access_request.json (Push approvals)
      final reqText = await downloadTextFile(accessRequestFileName);
      if (reqText != null && reqText.trim().isNotEmpty) {
        try {
          final req = jsonDecode(reqText) as Map<String, dynamic>;
          final reqId = req['requestId'] as String? ?? '';
          final status = req['status'] as String? ?? '';
          final approvedAt = (req['approvedAt'] as num?)?.toInt() ?? (req['timestamp'] as num?)?.toInt() ?? 0;
          final expiresAt = (req['expiresAt'] as num?)?.toInt() ?? 0;
          final device = req['device'] as String? ?? 'Windows PC (TetherPass Extension)';

          if (reqId.isNotEmpty) {
            if (status == 'APPROVED' && expiresAt > now) {
              if (!sessionMap.containsKey(reqId)) {
                sessionMap[reqId] = {
                  'sessionId': reqId,
                  'deviceName': device,
                  'authMode': 'PUSH',
                  'createdAt': approvedAt > 0 ? approvedAt : (expiresAt - 30 * 60 * 1000),
                  'expiresAt': expiresAt,
                  'status': 'ACTIVE',
                };
              }
            } else if (status == 'REVOKED') {
              if (sessionMap.containsKey(reqId)) {
                sessionMap[reqId]!['status'] = 'TERMINATED';
              }
            }
          }
        } catch (_) {}
      }

      // 3. Synthesize/merge from card_vault_extension_auth.json (PIN approvals)
      final authText = await downloadTextFile('card_vault_extension_auth.json');
      if (authText != null && authText.trim().isNotEmpty) {
        try {
          final auth = jsonDecode(authText) as Map<String, dynamic>;
          final status = auth['status'] as String? ?? '';
          final authAt = (auth['authorized_at'] as num?)?.toInt() ?? 0;
          final expiresAt = (auth['expires_at'] as num?)?.toInt() ?? 0;
          final device = auth['device'] as String? ?? 'Windows Browser Extension (PIN)';
          final pin = auth['pairing_pin'] as String? ?? '';

          if (pin.isNotEmpty) {
            final pinSessionId = 'pin_$pin';
            if (status == 'AUTHORIZED' && expiresAt > now) {
              if (!sessionMap.containsKey(pinSessionId)) {
                sessionMap[pinSessionId] = {
                  'sessionId': pinSessionId,
                  'deviceName': device,
                  'authMode': 'PIN',
                  'createdAt': authAt > 0 ? authAt : (expiresAt - 30 * 60 * 1000),
                  'expiresAt': expiresAt,
                  'status': 'ACTIVE',
                  'pin': pin,
                };
              }
            } else if (status == 'REVOKED') {
              if (sessionMap.containsKey(pinSessionId)) {
                sessionMap[pinSessionId]!['status'] = 'TERMINATED';
              }
            }
          }
        } catch (_) {}
      }

      // 4. Compute active status and minutes remaining for each session
      final List<Map<String, dynamic>> results = [];
      for (final s in sessionMap.values) {
        final expiresAt = (s['expiresAt'] as num?)?.toInt() ?? 0;
        final rawStatus = (s['status'] as String? ?? 'ACTIVE').toUpperCase();
        final bool isExpired = now > expiresAt;
        final bool isTerminated = rawStatus == 'TERMINATED' || rawStatus == 'REVOKED';
        final bool isActive = !isTerminated && !isExpired;

        s['isCurrentlyActive'] = isActive;
        if (isActive) {
          s['status'] = 'ACTIVE';
          s['minutesRemaining'] = ((expiresAt - now) / 60000).ceil().clamp(0, 30);
        } else if (isTerminated) {
          s['status'] = 'TERMINATED';
          s['minutesRemaining'] = 0;
        } else {
          s['status'] = 'EXPIRED';
          s['minutesRemaining'] = 0;
        }

        results.add(s);
      }

      // Sort: Active sessions first, then by createdAt descending
      results.sort((a, b) {
        final aActive = a['isCurrentlyActive'] == true ? 1 : 0;
        final bActive = b['isCurrentlyActive'] == true ? 1 : 0;
        if (aActive != bActive) return bActive.compareTo(aActive);
        final aCreated = (a['createdAt'] as num?)?.toInt() ?? 0;
        final bCreated = (b['createdAt'] as num?)?.toInt() ?? 0;
        return bCreated.compareTo(aCreated);
      });

      return results;
    } catch (_) {
      return [];
    }
  }

  /// Records an active desktop session on Drive
  Future<bool> recordActiveSession({
    required String sessionId,
    required String deviceName,
    required String authMode,
    required int createdAt,
    required int expiresAt,
  }) async {
    if (!isSignedIn) return false;
    try {
      List<dynamic> sessionList = [];
      final text = await downloadTextFile(activeSessionsFileName);
      if (text != null && text.trim().isNotEmpty) {
        try {
          final data = jsonDecode(text) as Map<String, dynamic>;
          sessionList = (data['sessions'] as List<dynamic>?) ?? [];
        } catch (_) {}
      }

      sessionList.removeWhere((s) => s is Map && s['sessionId'] == sessionId);
      sessionList.insert(0, {
        'sessionId': sessionId,
        'deviceName': deviceName,
        'authMode': authMode,
        'createdAt': createdAt,
        'expiresAt': expiresAt,
        'status': 'ACTIVE',
      });

      if (sessionList.length > 20) {
        sessionList = sessionList.sublist(0, 20);
      }

      await uploadTextFile(activeSessionsFileName, jsonEncode({
        'version': 1,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'sessions': sessionList,
      }));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Terminates a specific desktop session from the mobile phone
  Future<bool> terminateDesktopSession(String sessionId) async {
    if (!isSignedIn) return false;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;

      // 1. Update card_vault_active_sessions.json
      List<dynamic> sessionList = [];
      final text = await downloadTextFile(activeSessionsFileName);
      if (text != null && text.trim().isNotEmpty) {
        try {
          final data = jsonDecode(text) as Map<String, dynamic>;
          sessionList = (data['sessions'] as List<dynamic>?) ?? [];
        } catch (_) {}
      }

      bool found = false;
      String? authMode;
      for (final s in sessionList) {
        if (s is Map && s['sessionId'] == sessionId) {
          s['status'] = 'TERMINATED';
          s['terminatedAt'] = now;
          authMode = s['authMode'] as String?;
          found = true;
        }
      }

      if (!found) {
        sessionList.insert(0, {
          'sessionId': sessionId,
          'status': 'TERMINATED',
          'terminatedAt': now,
        });
      }

      await uploadTextFile(activeSessionsFileName, jsonEncode({
        'version': 1,
        'updatedAt': now,
        'sessions': sessionList,
      }));

      // 2. Clear / Revoke corresponding access request or auth file
      if (authMode == 'PUSH' || sessionId.startsWith('req_')) {
        final reqClear = jsonEncode({
          'requestId': sessionId,
          'status': 'REVOKED',
          'message': 'Session terminated from TetherPass mobile application.',
          'revoked_at': now,
        });
        await uploadTextFile(accessRequestFileName, reqClear);
      } else if (authMode == 'PIN' || sessionId.startsWith('pin_')) {
        final authClear = jsonEncode({
          'status': 'REVOKED',
          'revoked_at': now,
          'device': 'Windows Browser Extension',
        });
        await uploadTextFile('card_vault_extension_auth.json', authClear);
      } else {
        final revokePayload = jsonEncode({
          'status': 'REVOKED',
          'revoked_at': now,
          'revokedSessionId': sessionId,
        });
        await uploadTextFile(accessRequestFileName, revokePayload);
        await uploadTextFile('card_vault_extension_auth.json', revokePayload);
      }

      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Terminates all desktop sessions from the mobile phone
  Future<bool> terminateAllDesktopSessions() async {
    if (!isSignedIn) return false;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;

      // 1. Mark all sessions terminated in card_vault_active_sessions.json
      List<dynamic> sessionList = [];
      final text = await downloadTextFile(activeSessionsFileName);
      if (text != null && text.trim().isNotEmpty) {
        try {
          final data = jsonDecode(text) as Map<String, dynamic>;
          sessionList = (data['sessions'] as List<dynamic>?) ?? [];
        } catch (_) {}
      }

      for (final s in sessionList) {
        if (s is Map) {
          s['status'] = 'TERMINATED';
          s['terminatedAt'] = now;
        }
      }

      await uploadTextFile(activeSessionsFileName, jsonEncode({
        'version': 1,
        'updatedAt': now,
        'sessions': sessionList,
      }));

      // 2. Revoke access request record
      final reqClear = jsonEncode({
        'status': 'REVOKED',
        'message': 'All desktop sessions terminated from TetherPass mobile application.',
        'revoked_at': now,
      });
      await uploadTextFile(accessRequestFileName, reqClear);

      // 3. Revoke PIN authorization record
      final authClear = jsonEncode({
        'status': 'REVOKED',
        'revoked_at': now,
        'device': 'Windows Browser Extension',
      });
      await uploadTextFile('card_vault_extension_auth.json', authClear);

      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Uint8List _deriveKeyFromSecret(String secret, Uint8List salt) {
    var hash = Hmac(sha256, utf8.encode(secret)).convert(salt).bytes;
    for (int i = 0; i < 9999; i++) {
      hash = Hmac(sha256, utf8.encode(secret)).convert(hash).bytes;
    }
    return Uint8List.fromList(hash);
  }

  Future<String?> _findNamedFile(drive.DriveApi api, String fileName) async {
    try {
      final list = await api.files.list(
        spaces: 'appDataFolder',
        q: "name = '$fileName'",
        $fields: 'files(id, name)',
      );
      final files = list.files;
      if (files == null || files.isEmpty) return null;
      return files.first.id;
    } catch (_) {
      return null;
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  Future<String?> _findBackupFile(drive.DriveApi api) async {
    final list = await api.files.list(
      spaces: 'appDataFolder',
      q: "name = '$_backupFileName'",
      $fields: 'files(id, name)',
    );
    final files = list.files;
    if (files == null || files.isEmpty) return null;
    return files.first.id;
  }
}

class _GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _inner = http.Client();

  _GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }
}
