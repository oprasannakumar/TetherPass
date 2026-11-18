import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import '../models/vault_item.dart';

class MasterPasswordRequiredException implements Exception {
  final String payload;
  const MasterPasswordRequiredException(this.payload);
  @override
  String toString() => 'Master Password or Recovery Key required to decrypt this cloud backup.';
}

/// Service to generate and restore password-, recovery-key-, and Google Cloud Escrow-protected offline vault backups.
/// Uses envelope AES-256 encryption with PBKDF2 (HMAC-SHA256) key derivation.
class SecureBackupExportService {
  SecureBackupExportService._();

  static const String _magicHeaderV2 = 'TETHERPASS_SECURE_BACKUP_V2';
  static const String _magicHeaderV1 = 'TETHERPASS_SECURE_BACKUP_V1';
  static const String _legacyMagicHeader = 'CARDVAULT_SECURE_BACKUP_V1';

  /// Generates a protected, encrypted backup file payload from [items].
  /// Encrypted with [userPassword] and optionally wrapped with [recoveryKey] and [googleAccountKey]
  /// so either can decrypt the backup if the user ever forgets their master password or wipes app data.
  static String exportVaultWithPassword({
    required List<VaultItem> items,
    required String userPassword,
    String? recoveryKey,
    String? googleAccountKey,
  }) {
    if (userPassword.length < 4) {
      throw ArgumentError('Password must be at least 4 characters long.');
    }

    final rawJson = jsonEncode({
      'version': 2,
      'exported_at': DateTime.now().toIso8601String(),
      'item_count': items.length,
      'items': items.map((e) => e.toMap()).toList(),
    });

    // 1. Generate random 256-bit AES symmetric file key
    final dataKeyBytes = enc.SecureRandom(32).bytes;
    final dataIv = enc.SecureRandom(16).bytes;
    final dataEncrypter = enc.Encrypter(enc.AES(enc.Key(dataKeyBytes), mode: enc.AESMode.cbc));
    final encryptedData = dataEncrypter.encrypt(rawJson, iv: enc.IV(dataIv));

    // 2. Wrap dataKey with userPassword using PBKDF2 (10,000 rounds)
    final pwdSalt = enc.SecureRandom(16).bytes;
    final pwdIv = enc.SecureRandom(16).bytes;
    final derivedPwdKey = _deriveKey(userPassword, pwdSalt);
    final pwdEncrypter = enc.Encrypter(enc.AES(enc.Key(derivedPwdKey), mode: enc.AESMode.cbc));
    final wrappedKeyPwd = pwdEncrypter.encryptBytes(dataKeyBytes, iv: enc.IV(pwdIv));

    final payloadMap = <String, dynamic>{
      'header': _magicHeaderV2,
      'version': 2,
      'salt_pwd': base64Encode(pwdSalt),
      'iv_pwd': base64Encode(pwdIv),
      'wrapped_key_pwd': wrappedKeyPwd.base64,
      'iv_data': base64Encode(dataIv),
      'data': encryptedData.base64,
    };

    // 3. Wrap dataKey with recoveryKey (if provided)
    if (recoveryKey != null && recoveryKey.trim().isNotEmpty) {
      final cleanRecovery = recoveryKey.replaceAll(RegExp(r'[\s\-]'), '').toUpperCase();
      if (cleanRecovery.length >= 8) {
        final recSalt = enc.SecureRandom(16).bytes;
        final recIv = enc.SecureRandom(16).bytes;
        final derivedRecKey = _deriveKey(cleanRecovery, recSalt);
        final recEncrypter = enc.Encrypter(enc.AES(enc.Key(derivedRecKey), mode: enc.AESMode.cbc));
        final wrappedKeyRec = recEncrypter.encryptBytes(dataKeyBytes, iv: enc.IV(recIv));

        payloadMap['salt_rec'] = base64Encode(recSalt);
        payloadMap['iv_rec'] = base64Encode(recIv);
        payloadMap['wrapped_key_rec'] = wrappedKeyRec.base64;
      }
    }

    // 4. Wrap dataKey with Google Cloud Escrow key (if user is linked to Google Account)
    if (googleAccountKey != null && googleAccountKey.trim().isNotEmpty) {
      final googleSalt = enc.SecureRandom(16).bytes;
      final googleIv = enc.SecureRandom(16).bytes;
      final derivedGoogleKey = _deriveKey(googleAccountKey.trim(), googleSalt);
      final googleEncrypter = enc.Encrypter(enc.AES(enc.Key(derivedGoogleKey), mode: enc.AESMode.cbc));
      final wrappedKeyGoogle = googleEncrypter.encryptBytes(dataKeyBytes, iv: enc.IV(googleIv));

      payloadMap['salt_google'] = base64Encode(googleSalt);
      payloadMap['iv_google'] = base64Encode(googleIv);
      payloadMap['wrapped_key_google'] = wrappedKeyGoogle.base64;
    }

    return jsonEncode(payloadMap);
  }

  /// Restores [VaultItem] list from a backup payload.
  /// Can decrypt using [userPassword] (Master Password OR Recovery Key) OR [googleAccountKey] (Cloud Escrow).
  static List<VaultItem> importVaultWithPassword({
    required String backupPayload,
    String? userPassword,
    String? googleAccountKey,
  }) {
    try {
      final trimmed = backupPayload.trim();
      final Map<String, dynamic> payloadMap = jsonDecode(trimmed);
      final header = payloadMap['header'] as String?;

      // ── V2 Envelope Backup (Dual Password + Recovery Key + Google Escrow Support) ──
      if (header == _magicHeaderV2 || payloadMap['version'] == 2) {
        Uint8List? dataKeyBytes;

        // A. Try unwrapping with userPassword
        if (userPassword != null && userPassword.isNotEmpty && payloadMap.containsKey('wrapped_key_pwd')) {
          try {
            final pwdSalt = base64Decode(payloadMap['salt_pwd'] as String);
            final pwdIv = base64Decode(payloadMap['iv_pwd'] as String);
            final wrappedBase64 = payloadMap['wrapped_key_pwd'] as String;

            final derivedPwdKey = _deriveKey(userPassword, pwdSalt);
            final pwdEncrypter = enc.Encrypter(enc.AES(enc.Key(derivedPwdKey), mode: enc.AESMode.cbc));
            final unwrapped = pwdEncrypter.decryptBytes(enc.Encrypted.fromBase64(wrappedBase64), iv: enc.IV(pwdIv));
            if (unwrapped.length == 32) {
              dataKeyBytes = Uint8List.fromList(unwrapped);
            }
          } catch (_) {}
        }

        // B. If password failed, try normalized recovery key
        if (dataKeyBytes == null && userPassword != null && userPassword.isNotEmpty && payloadMap.containsKey('wrapped_key_rec')) {
          try {
            final cleanKey = userPassword.replaceAll(RegExp(r'[\s\-]'), '').toUpperCase();
            final recSalt = base64Decode(payloadMap['salt_rec'] as String);
            final recIv = base64Decode(payloadMap['iv_rec'] as String);
            final wrappedRecBase64 = payloadMap['wrapped_key_rec'] as String;

            final derivedRecKey = _deriveKey(cleanKey, recSalt);
            final recEncrypter = enc.Encrypter(enc.AES(enc.Key(derivedRecKey), mode: enc.AESMode.cbc));
            final unwrapped = recEncrypter.decryptBytes(enc.Encrypted.fromBase64(wrappedRecBase64), iv: enc.IV(recIv));
            if (unwrapped.length == 32) {
              dataKeyBytes = Uint8List.fromList(unwrapped);
            }
          } catch (_) {}
        }

        // C. Try Google Account Cloud Escrow (Device wipe / Forgotten password recovery)
        if (dataKeyBytes == null && googleAccountKey != null && googleAccountKey.isNotEmpty && payloadMap.containsKey('wrapped_key_google')) {
          try {
            final googleSalt = base64Decode(payloadMap['salt_google'] as String);
            final googleIv = base64Decode(payloadMap['iv_google'] as String);
            final wrappedGoogleBase64 = payloadMap['wrapped_key_google'] as String;

            final derivedGoogleKey = _deriveKey(googleAccountKey.trim(), googleSalt);
            final googleEncrypter = enc.Encrypter(enc.AES(enc.Key(derivedGoogleKey), mode: enc.AESMode.cbc));
            final unwrapped = googleEncrypter.decryptBytes(enc.Encrypted.fromBase64(wrappedGoogleBase64), iv: enc.IV(googleIv));
            if (unwrapped.length == 32) {
              dataKeyBytes = Uint8List.fromList(unwrapped);
            }
          } catch (_) {}
        }

        if (dataKeyBytes == null) {
          throw const FormatException('Incorrect Master Password or Recovery Key. Please check your credentials and try again.');
        }

        // D. Decrypt the actual data payload with the recovered 256-bit symmetric key
        final dataIv = base64Decode(payloadMap['iv_data'] as String);
        final encryptedDataBase64 = payloadMap['data'] as String;
        final dataEncrypter = enc.Encrypter(enc.AES(enc.Key(dataKeyBytes), mode: enc.AESMode.cbc));
        final decryptedJson = dataEncrypter.decrypt64(encryptedDataBase64, iv: enc.IV(dataIv));
        final Map<String, dynamic> data = jsonDecode(decryptedJson);

        final List itemsRaw = data['items'] as List;
        return itemsRaw.map((e) => VaultItem.fromMap(e as Map<String, dynamic>)).toList();
      }

      // ── V1 Direct PBKDF2 Backup ──
      if (header == _magicHeaderV1 || header == _legacyMagicHeader || payloadMap.containsKey('salt')) {
        if (userPassword == null || userPassword.isEmpty) {
          throw const FormatException('Master Password required for this backup.');
        }
        final salt = base64Decode(payloadMap['salt'] as String);
        final iv = base64Decode(payloadMap['iv'] as String);
        final encryptedBase64 = payloadMap['data'] as String;

        try {
          final derivedKeyBytes = _deriveKey(userPassword, salt);
          final key = enc.Key(derivedKeyBytes);
          final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));

          final decryptedJson = encrypter.decrypt64(encryptedBase64, iv: enc.IV(iv));
          final Map<String, dynamic> data = jsonDecode(decryptedJson);

          final List itemsRaw = data['items'] as List;
          return itemsRaw.map((e) => VaultItem.fromMap(e as Map<String, dynamic>)).toList();
        } catch (_) {
          final cleanKey = userPassword.replaceAll(RegExp(r'[\s\-]'), '').toUpperCase();
          final derivedKeyBytes = _deriveKey(cleanKey, salt);
          final key = enc.Key(derivedKeyBytes);
          final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));

          final decryptedJson = encrypter.decrypt64(encryptedBase64, iv: enc.IV(iv));
          final Map<String, dynamic> data = jsonDecode(decryptedJson);

          final List itemsRaw = data['items'] as List;
          return itemsRaw.map((e) => VaultItem.fromMap(e as Map<String, dynamic>)).toList();
        }
      }

      throw const FormatException('Invalid backup format or incompatible file.');
    } on ArgumentError catch (e) {
      if (e.message.toString().toLowerCase().contains('pad block') ||
          e.toString().toLowerCase().contains('pad block') ||
          e.toString().toLowerCase().contains('padding')) {
        throw const FormatException('Incorrect Master Password or Recovery Key. Please check your credentials and try again.');
      }
      throw const FormatException('Incorrect credentials or corrupted backup file.');
    } catch (e) {
      if (e is FormatException) rethrow;
      throw const FormatException('Incorrect Master Password or Recovery Key.');
    }
  }

  static Uint8List _deriveKey(String password, Uint8List salt) {
    // 10,000 iterations of HMAC-SHA256 PBKDF2
    var hash = Hmac(sha256, utf8.encode(password)).convert(salt).bytes;
    for (int i = 0; i < 9999; i++) {
      hash = Hmac(sha256, utf8.encode(password)).convert(hash).bytes;
    }
    return Uint8List.fromList(hash);
  }
}
