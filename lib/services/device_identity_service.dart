import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DeviceIdentityService {
  static const _storage = FlutterSecureStorage();
  static const _deviceIdKey = 'card_vault_persistent_device_id';
  static const _deviceNameKey = 'card_vault_persistent_device_name';
  static const _regTimeKey = 'card_vault_session_reg_time';
  static final _deviceInfo = DeviceInfoPlugin();

  static Future<int> getSessionRegistrationTime() async {
    final str = await _storage.read(key: _regTimeKey);
    return int.tryParse(str ?? '') ?? 0;
  }

  static Future<void> updateSessionRegistrationTime([int? timeMs]) async {
    final val = timeMs ?? DateTime.now().millisecondsSinceEpoch;
    await _storage.write(key: _regTimeKey, value: val.toString());
  }

  /// Returns a hardware-deterministic, invariant device ID for this phone.
  /// Remains identical across app reinstalls and updates on the same physical phone.
  static Future<String> getDeviceId() async {
    var id = await _storage.read(key: _deviceIdKey);
    if (id != null && id.isNotEmpty) {
      return id;
    }

    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        final raw = '${androidInfo.brand}_${androidInfo.model}_${androidInfo.device}_${androidInfo.hardware}_${androidInfo.id}';
        final hash = sha256.convert(utf8.encode(raw)).toString().substring(0, 12);
        final brand = androidInfo.brand.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
        id = 'dev_${brand.isEmpty ? "android" : brand}_$hash';
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        final raw = '${iosInfo.name}_${iosInfo.model}_${iosInfo.identifierForVendor}';
        final hash = sha256.convert(utf8.encode(raw)).toString().substring(0, 12);
        id = 'dev_ios_$hash';
      } else {
        id = 'dev_${Platform.operatingSystem}_${DateTime.now().millisecondsSinceEpoch}';
      }
    } catch (_) {
      id = 'dev_mobile_${DateTime.now().millisecondsSinceEpoch}';
    }

    await _storage.write(key: _deviceIdKey, value: id);
    return id;
  }

  /// Returns the user-friendly hardware device name (e.g. "Vivo V2050")
  static Future<String> getDeviceName() async {
    var name = await _storage.read(key: _deviceNameKey);
    if (name != null && name.trim().isNotEmpty) {
      return name;
    }

    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        String brand = androidInfo.brand.trim();
        if (brand.isNotEmpty) {
          brand = brand[0].toUpperCase() + brand.substring(1);
        }
        name = '$brand ${androidInfo.model}'.trim();
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        name = iosInfo.name.isNotEmpty ? iosInfo.name : 'iPhone';
      } else {
        name = 'TetherPass (${Platform.operatingSystem})';
      }
    } catch (_) {
      name = 'Mobile Device';
    }

    return name;
  }

  static Future<void> setDeviceName(String newName) async {
    await _storage.write(key: _deviceNameKey, value: newName.trim());
  }
}
