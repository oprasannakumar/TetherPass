import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Manages dynamic auto-lock timer preference and background pause tracking.
class AutoLockService {
  AutoLockService._();

  static const _keyAutoLockSeconds = 'vault_auto_lock_seconds';
  static const int defaultAutoLockSeconds = 60; // 1 minute default

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static DateTime? _pausedAt;

  /// Returns configured auto-lock duration in seconds:
  /// 0 = Immediately on app switch
  /// 30, 60, 300, 900 = seconds
  /// -1 = Disabled / Never
  static Future<int> getAutoLockSeconds() async {
    final val = await _storage.read(key: _keyAutoLockSeconds);
    if (val == null) return defaultAutoLockSeconds;
    return int.tryParse(val) ?? defaultAutoLockSeconds;
  }

  /// Sets auto-lock duration in seconds.
  static Future<void> setAutoLockSeconds(int seconds) async {
    await _storage.write(key: _keyAutoLockSeconds, value: seconds.toString());
  }

  /// Invoked when app transitions to paused or inactive in lifecycle
  static void markPaused() {
    _pausedAt = DateTime.now();
  }

  /// Clears the paused state
  static void clearPaused() {
    _pausedAt = null;
  }

  /// Returns true if app has spent enough time in background to mandate locking.
  static Future<bool> shouldLock() async {
    if (_pausedAt == null) return false;
    final timeout = await getAutoLockSeconds();
    if (timeout < 0) return false; // Never lock
    if (timeout == 0) return true; // Immediately

    final elapsed = DateTime.now().difference(_pausedAt!).inSeconds;
    return elapsed >= timeout;
  }
}
