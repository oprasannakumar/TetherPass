import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

class DeviceIdentityService {
  static const _storage = FlutterSecureStorage();
  static const _deviceIdKey = 'card_vault_persistent_device_id';
  static const _deviceNameKey = 'card_vault_persistent_device_name';

  static Future<String> getDeviceId() async {
    var id = await _storage.read(key: _deviceIdKey);
    if (id == null || id.isEmpty) {
      id = 'dev_${const Uuid().v4().substring(0, 8)}';
      await _storage.write(key: _deviceIdKey, value: id);
    }
    return id;
  }

  static Future<String> getDeviceName() async {
    var name = await _storage.read(key: _deviceNameKey);
    if (name == null || name.isEmpty) {
      final os = Platform.isAndroid ? 'Android' : (Platform.isIOS ? 'iPhone' : Platform.operatingSystem);
      name = 'Mobile Device ($os)';
    }
    return name;
  }

  static Future<void> setDeviceName(String newName) async {
    await _storage.write(key: _deviceNameKey, value: newName.trim());
  }
}
