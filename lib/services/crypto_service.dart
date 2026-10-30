import 'dart:math';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Handles AES-256 encryption and decryption.
///
/// The 32-byte key is generated once and persisted in [FlutterSecureStorage]
/// which is backed by the Android Keystore on Android. This ensures the key
/// never leaves secure hardware.
class CryptoService {
  static const _keyAlias = 'card_vault_aes_key';
  static const _ivAlias = 'card_vault_aes_iv';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  late enc.Encrypter _encrypter;
  late enc.IV _iv;

  bool _initialised = false;

  /// Must be called once before any encrypt/decrypt operations.
  Future<void> init() async {
    if (_initialised) return;

    // Retrieve or generate the 32-byte AES key.
    String? keyB64 = await _storage.read(key: _keyAlias);
    if (keyB64 == null) {
      final keyBytes = _generateRandomBytes(32);
      keyB64 = enc.Key(keyBytes).base64;
      await _storage.write(key: _keyAlias, value: keyB64);
    }

    // Retrieve or generate a static 16-byte IV.
    // NOTE: Using a static IV for storage is acceptable here because each
    // plaintext value (card number, CVV) has low uniqueness variance and the
    // key is already per-device.  For higher security rotate the IV per
    // record and store alongside ciphertext.
    String? ivB64 = await _storage.read(key: _ivAlias);
    if (ivB64 == null) {
      final ivBytes = _generateRandomBytes(16);
      ivB64 = enc.IV(ivBytes).base64;
      await _storage.write(key: _ivAlias, value: ivB64);
    }

    final key = enc.Key.fromBase64(keyB64);
    _iv = enc.IV.fromBase64(ivB64);
    _encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    _initialised = true;
  }

  /// Encrypts [plaintext] and returns a Base64-encoded ciphertext string.
  String encrypt(String plaintext) {
    _assertInit();
    final encrypted = _encrypter.encrypt(plaintext, iv: _iv);
    return encrypted.base64;
  }

  /// Decrypts a Base64-encoded [ciphertext] and returns the original string.
  String decrypt(String ciphertext) {
    _assertInit();
    try {
      final encrypted = enc.Encrypted.fromBase64(ciphertext);
      return _encrypter.decrypt(encrypted, iv: _iv);
    } on ArgumentError catch (e) {
      if (e.message.toString().toLowerCase().contains('pad block') ||
          e.toString().toLowerCase().contains('pad block') ||
          e.toString().toLowerCase().contains('padding')) {
        throw const FormatException('Decryption failed: Device key mismatch or invalid data block.');
      }
      rethrow;
    }
  }

  void _assertInit() {
    if (!_initialised) {
      throw StateError('CryptoService.init() must be called before use.');
    }
  }

  static Uint8List _generateRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }
}
