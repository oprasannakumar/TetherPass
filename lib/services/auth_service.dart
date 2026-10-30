import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';

class AuthService {
  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> isDeviceSupported() async {
    return _auth.isDeviceSupported();
  }

  Future<bool> canAuthenticate() async {
    return _auth.isDeviceSupported();
  }

  Future<bool> isBiometricAvailable() async {
    final isSupported = await _auth.isDeviceSupported();
    if (!isSupported) return false;
    final biometrics = await _auth.getAvailableBiometrics();
    return biometrics.isNotEmpty;
  }

  Future<bool> authenticate({String? reason}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason ?? 'Scan fingerprint to unlock CardVault',
        authMessages: const [
          AndroidAuthMessages(
            signInTitle: 'CardVault Biometric Unlock',
            cancelButton: 'Cancel',
          ),
        ],
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true, // Strictly biometric only: disables device PIN/pattern/password fallback
          sensitiveTransaction: true,
          useErrorDialogs: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
