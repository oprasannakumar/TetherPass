import 'package:flutter/services.dart';

/// Service for air-gapped high-frequency (18 kHz - 19.5 kHz) acoustic tethering.
class UltrasonicHandshakeService {
  static const MethodChannel _channel = MethodChannel('com.example.card_vault/autofill_bridge');

  /// Transmits an acoustic FSK handshake packet to unlock the desktop extension
  static Future<bool> transmitChirp(String token) async {
    try {
      final res = await _channel.invokeMethod<bool>('playUltrasonicChirp', {
        'token': token,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }
}
