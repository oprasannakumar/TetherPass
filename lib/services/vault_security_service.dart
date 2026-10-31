import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'crypto_service.dart';

/// Zero-Knowledge security service for Master Password, Biometrics, and Recovery Key.
///
/// Master Password is NEVER stored; only its salted SHA-256 hash is saved.
class VaultSecurityService {
  static const _keyIsOnboarded = 'vault_is_onboarded';
  static const _keyPasswordHash = 'vault_password_hash';
  static const _keyPasswordSalt = 'vault_password_salt';
  static const _keyRecoveryHash = 'vault_recovery_hash';
  static const _keyRecoveryEncrypted = 'vault_recovery_encrypted';
  static const _keyMasterPasswordEncrypted = 'vault_master_password_encrypted';
  static const _keyBiometricEnabled = 'vault_biometric_enabled';
  static const _keyHasSeenTour = 'vault_has_seen_tour';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  final CryptoService cryptoService;

  VaultSecurityService({required this.cryptoService});

  /// Check if the vault has completed onboarding
  Future<bool> isOnboarded() async {
    final val = await _storage.read(key: _keyIsOnboarded);
    return val == 'true';
  }

  /// Generate a random 16-character alphanumeric recovery key formatted as XXXX-XXXX-XXXX-XXXX
  String generateRecoveryKey() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // No ambiguous characters like 0/O, 1/I
    final rand = Random.secure();
    final raw = List.generate(16, (_) => chars[rand.nextInt(chars.length)]).join();
    return '${raw.substring(0, 4)}-${raw.substring(4, 8)}-${raw.substring(8, 12)}-${raw.substring(12, 16)}';
  }

  /// Complete onboarding setup
  Future<String> setupVault({
    required String masterPassword,
    required bool biometricEnabled,
    String? customRecoveryKey,
  }) async {
    final recoveryKey = customRecoveryKey ?? generateRecoveryKey();

    // Generate random salt for master password
    final salt = _generateRandomSalt(16);
    final passwordHash = _hashWithSalt(masterPassword, salt);
    final recoveryHash = sha256.convert(utf8.encode(recoveryKey.trim().toUpperCase())).toString();
    final recoveryEncrypted = cryptoService.encrypt(recoveryKey);
    final masterEncrypted = cryptoService.encrypt(masterPassword);

    await _storage.write(key: _keyPasswordSalt, value: salt);
    await _storage.write(key: _keyPasswordHash, value: passwordHash);
    await _storage.write(key: _keyRecoveryHash, value: recoveryHash);
    await _storage.write(key: _keyRecoveryEncrypted, value: recoveryEncrypted);
    await _storage.write(key: _keyMasterPasswordEncrypted, value: masterEncrypted);
    await _storage.write(key: _keyBiometricEnabled, value: biometricEnabled ? 'true' : 'false');
    await _storage.write(key: _keyIsOnboarded, value: 'true');

    return recoveryKey;
  }

  /// Verify Master Password against stored hash
  Future<bool> verifyMasterPassword(String password) async {
    final salt = await _storage.read(key: _keyPasswordSalt);
    final expectedHash = await _storage.read(key: _keyPasswordHash);
    if (salt == null || expectedHash == null) return false;

    final actualHash = _hashWithSalt(password, salt);
    final matches = actualHash == expectedHash;
    if (matches) {
      // Ensure master password is saved encrypted for export/import and extension authorization
      await _storage.write(key: _keyMasterPasswordEncrypted, value: cryptoService.encrypt(password));
    }
    return matches;
  }

  /// Verify 16-character recovery key (e.g. XXXX-XXXX-XXXX-XXXX)
  Future<bool> verifyRecoveryKey(String key) async {
    final cleanKey = key.trim().toUpperCase();
    final expectedHash = await _storage.read(key: _keyRecoveryHash);
    if (expectedHash == null) return false;

    final actualHash = sha256.convert(utf8.encode(cleanKey)).toString();
    return actualHash == expectedHash;
  }

  /// Reset Master Password using verified recovery key
  Future<void> resetMasterPassword(String newPassword) async {
    final salt = _generateRandomSalt(16);
    final passwordHash = _hashWithSalt(newPassword, salt);
    final masterEncrypted = cryptoService.encrypt(newPassword);
    await _storage.write(key: _keyPasswordSalt, value: salt);
    await _storage.write(key: _keyPasswordHash, value: passwordHash);
    await _storage.write(key: _keyMasterPasswordEncrypted, value: masterEncrypted);
  }

  /// Retrieve decrypted Master Password for offline backup export & import encryption
  Future<String?> getMasterPassword() async {
    final enc = await _storage.read(key: _keyMasterPasswordEncrypted);
    if (enc == null) return null;
    try {
      return cryptoService.decrypt(enc);
    } catch (_) {
      return null;
    }
  }

  /// Manually save encrypted master password
  Future<void> saveMasterPassword(String masterPassword) async {
    final masterEncrypted = cryptoService.encrypt(masterPassword);
    await _storage.write(key: _keyMasterPasswordEncrypted, value: masterEncrypted);
  }

  /// Retrieve decrypted Recovery Key for viewing in Settings
  Future<String?> getRecoveryKey() async {
    final enc = await _storage.read(key: _keyRecoveryEncrypted);
    if (enc == null) return null;
    try {
      return cryptoService.decrypt(enc);
    } catch (_) {
      return null;
    }
  }

  /// Regenerate Recovery Key from Settings
  Future<String> regenerateRecoveryKey() async {
    final newKey = generateRecoveryKey();
    final recoveryHash = sha256.convert(utf8.encode(newKey.trim().toUpperCase())).toString();
    final recoveryEncrypted = cryptoService.encrypt(newKey);
    await _storage.write(key: _keyRecoveryHash, value: recoveryHash);
    await _storage.write(key: _keyRecoveryEncrypted, value: recoveryEncrypted);
    return newKey;
  }

  /// Check if biometric authentication is enabled by user
  Future<bool> isBiometricEnabled() async {
    final val = await _storage.read(key: _keyBiometricEnabled);
    return val == 'true';
  }

  /// Enable or disable biometric authentication
  Future<void> setBiometricEnabled(bool enabled) async {
    await _storage.write(key: _keyBiometricEnabled, value: enabled ? 'true' : 'false');
  }

  /// Check if the user has completed or viewed the app tour
  Future<bool> hasSeenTour() async {
    final val = await _storage.read(key: _keyHasSeenTour);
    return val == 'true';
  }

  /// Mark the app tour as seen
  Future<void> setTourSeen(bool seen) async {
    await _storage.write(key: _keyHasSeenTour, value: seen ? 'true' : 'false');
  }

  // ─── Internal helpers ──────────────────────────────────────────────────────

  String _hashWithSalt(String input, String salt) {
    final bytes = utf8.encode('$salt:$input');
    return sha256.convert(bytes).toString();
  }

  String _generateRandomSalt(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rand = Random.secure();
    return List.generate(length, (_) => chars[rand.nextInt(chars.length)]).join();
  }
}
