import 'dart:convert';
import 'dart:math';
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
  Future<bool> authorizeExtension({int durationMinutes = 30}) async {
    _isLoading = true;
    notifyListeners();

    try {
      final now = DateTime.now();
      final expiry = now.add(Duration(minutes: durationMinutes));

      if (_currentPin.isEmpty) _generateNewPin();

      final payload = jsonEncode({
        'status': 'AUTHORIZED',
        'authorized_at': now.millisecondsSinceEpoch,
        'expires_at': expiry.millisecondsSinceEpoch,
        'pairing_pin': _currentPin,
        'device': 'Windows Browser Extension',
      });

      if (driveService.isSignedIn) {
        await driveService.uploadTextFile(authFileName, payload);
      }

      _isAuthorized = true;
      _expiresAt = expiry;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error authorizing extension: $e');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Revokes desktop browser extension authorization immediately
  Future<void> revokeExtension() async {
    _isLoading = true;
    notifyListeners();

    try {
      final payload = jsonEncode({
        'status': 'REVOKED',
        'authorized_at': null,
        'expires_at': null,
        'pairing_pin': null,
        'device': 'Windows Browser Extension',
      });

      if (driveService.isSignedIn) {
        await driveService.uploadTextFile(authFileName, payload);
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
      final payload = jsonEncode({
        'status': 'LOCKED',
        'authorized_at': null,
        'expires_at': null,
        'pairing_pin': null,
        'device': 'Windows Browser Extension',
      });
      if (driveService.isSignedIn) {
        await driveService.uploadTextFile(authFileName, payload);
      }
    } catch (_) {}
    _isAuthorized = false;
    _expiresAt = null;
    notifyListeners();
  }
}
