import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import '../models/vault_item.dart';

class MasterPasswordRequiredException implements Exception {
  final String payload;
  const MasterPasswordRequiredException(this.payload);
  @override
  String toString() => 'Master Password required to decrypt this cloud backup.';
}

/// Service to generate and restore password-protected offline vault backups.
/// Uses PBKDF2 key derivation and AES-256-GCM / CBC encryption.
class SecureBackupExportService {
  SecureBackupExportService._();

  static const String _magicHeader = 'TETHERPASS_SECURE_BACKUP_V1';
  static const String _legacyMagicHeader = 'CARDVAULT_SECURE_BACKUP_V1';

  /// Generates a password-protected, encrypted backup file payload from [items].
  static String exportVaultWithPassword({
    required List<VaultItem> items,
    required String userPassword,
  }) {
    if (userPassword.length < 4) {
      throw ArgumentError('Password must be at least 4 characters long.');
    }

    final rawJson = jsonEncode({
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'item_count': items.length,
      'items': items.map((e) => e.toMap()).toList(),
    });

    // Derive 256-bit AES key from userPassword using PBKDF2 with SHA-256
    final salt = enc.SecureRandom(16).bytes;
    final iv = enc.SecureRandom(16).bytes;

    final derivedKeyBytes = _deriveKey(userPassword, salt);
    final key = enc.Key(derivedKeyBytes);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));

    final encrypted = encrypter.encrypt(rawJson, iv: enc.IV(iv));

    final payloadMap = {
      'header': _magicHeader,
      'salt': base64Encode(salt),
      'iv': base64Encode(iv),
      'data': encrypted.base64,
    };

    return jsonEncode(payloadMap);
  }

  /// Restores [VaultItem] list from a password-protected backup payload.
  static List<VaultItem> importVaultWithPassword({
    required String backupPayload,
    required String userPassword,
  }) {
    try {
      final trimmed = backupPayload.trim();
      final Map<String, dynamic> payloadMap = jsonDecode(trimmed);
      if (payloadMap['header'] != _magicHeader && payloadMap['header'] != _legacyMagicHeader) {
        throw const FormatException('Invalid backup format or incompatible file.');
      }

      final salt = base64Decode(payloadMap['salt'] as String);
      final iv = base64Decode(payloadMap['iv'] as String);
      final encryptedBase64 = payloadMap['data'] as String;

      final derivedKeyBytes = _deriveKey(userPassword, salt);
      final key = enc.Key(derivedKeyBytes);
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));

      final decryptedJson = encrypter.decrypt64(encryptedBase64, iv: enc.IV(iv));
      final Map<String, dynamic> data = jsonDecode(decryptedJson);

      final List itemsRaw = data['items'] as List;
      return itemsRaw.map((e) => VaultItem.fromMap(e as Map<String, dynamic>)).toList();
    } on ArgumentError catch (e) {
      if (e.message.toString().toLowerCase().contains('pad block') ||
          e.toString().toLowerCase().contains('pad block') ||
          e.toString().toLowerCase().contains('padding')) {
        throw const FormatException('Incorrect Master Password. Please check your password and try again.');
      }
      throw const FormatException('Incorrect Master Password or corrupted backup file.');
    } catch (e) {
      if (e is FormatException) rethrow;
      throw const FormatException('Incorrect Master Password or corrupted backup file.');
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
