import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'drive_service.dart';

class ExtensionAuthSession {
  final bool isAuthorized;
  final String? pairingPin;
  final DateTime? expiresAt;
  final String status;

  ExtensionAuthSession({
    required this.isAuthorized,
    this.pairingPin,
    this.expiresAt,
    required this.status,
  });
}

class ExtensionAuthService extends ChangeNotifier {
  static const String authFileName = 'card_vault_extension_auth.json';

  final DriveService driveService;

  bool _isAuthorized = false;
  String _currentPin = '';
  DateTime? _expiresAt;
  bool _isLoading = false;

  bool get isAuthorized => _isAuthorized && (_expiresAt != null && DateTime.now().isBefore(_expiresAt!));
  String get currentPin => _currentPin;
  DateTime? get expiresAt => _expiresAt;
  bool get isLoading => _isLoading;

  ExtensionAuthService({required this.driveService}) {
    _generateNewPin();
  }

  void _generateNewPin() {
    final rng = Random();
    _currentPin = (100000 + rng.nextInt(900000)).toString();
    notifyListeners();
  }

  String regeneratePin() {
    _generateNewPin();
    return _currentPin;
  }

  /// Authorizes the browser extension for [durationMinutes] (default 30 mins)
  Future<bool> authorizeExtension({
    int durationMinutes = 30,
    String? masterPassword,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      final now = DateTime.now();
      final expiry = now.add(Duration(minutes: durationMinutes));

      if (_currentPin.isEmpty) _generateNewPin();

      Map<String, dynamic>? pinSealedKey;
      if (masterPassword != null && masterPassword.isNotEmpty) {
        final salt = enc.SecureRandom(16).bytes;
        final iv = enc.SecureRandom(16).bytes;
        final derived = _deriveKeyFromSecret(_currentPin, salt);
        final key = enc.Key(derived);
        final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
        final encrypted = encrypter.encrypt(masterPassword, iv: enc.IV(iv));
        pinSealedKey = {
          'salt': base64Encode(salt),
          'iv': base64Encode(iv),
          'ciphertext': encrypted.base64,
        };
      }

      final payloadMap = <String, dynamic>{
        'status': 'AUTHORIZED',
        'authorized_at': now.millisecondsSinceEpoch,
        'expires_at': expiry.millisecondsSinceEpoch,
        'pairing_pin': _currentPin,
        'device': 'Windows Browser Extension',
      };
      if (pinSealedKey != null) {
        payloadMap['pin_sealed_key'] = pinSealedKey;
      }

      final payload = jsonEncode(payloadMap);

      if (driveService.isSignedIn) {
        await driveService.uploadTextFile(authFileName, payload);
      }

      _isAuthorized = true;
      _expiresAt = expiry;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error authorizing extension: ');
      _isLoading = false;
      notifyListeners();
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

  Future<void> revokeExtension() async {
    _isLoading = true;
    notifyListeners();

    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final payload = jsonEncode({
        'status': 'REVOKED',
        'authorized_at': null,
        'expires_at': null,
        'pairing_pin': null,
        'device': 'Windows Browser Extension',
        'revoked_at': now,
      });

      if (driveService.isSignedIn) {
        // 1. Mark the auth record as REVOKED
        await driveService.uploadTextFile(authFileName, payload);

        // 2. ALSO mark access request record as REVOKED so push approvals lock immediately
        final reqPayload = jsonEncode({
          'status': 'REVOKED',
          'message': 'Authorization revoked from CardVault mobile application.',
          'revoked_at': now,
        });
        await driveService.uploadTextFile(DriveService.accessRequestFileName, reqPayload);
      }
    } catch (e) {
      debugPrint('Error revoking extension: $e');
    } finally {
      _isAuthorized = false;
      _expiresAt = null;
      _generateNewPin();
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Called when the mobile vault locks to secure desktop sessions
  Future<void> onMobileVaultLocked() async {
    if (!_isAuthorized) return;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final payload = jsonEncode({
        'status': 'LOCKED',
        'authorized_at': null,
        'expires_at': null,
        'pairing_pin': null,
        'device': 'Windows Browser Extension',
        'revoked_at': now,
      });
      if (driveService.isSignedIn) {
        await driveService.uploadTextFile(authFileName, payload);
        final reqPayload = jsonEncode({
          'status': 'LOCKED',
          'message': 'Mobile CardVault was locked.',
          'revoked_at': now,
        });
        await driveService.uploadTextFile(DriveService.accessRequestFileName, reqPayload);
      }
    } catch (_) {}
    _isAuthorized = false;
    _expiresAt = null;
    notifyListeners();
  }
}
