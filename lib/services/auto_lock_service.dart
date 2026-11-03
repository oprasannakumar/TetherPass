import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'autofill_bridge_service.dart';

/// Manages dynamic auto-lock timer preference, in-app inactivity tracking,
/// and background pause tracking without getting stuck in infinite unlock loops.
class AutoLockService {
  AutoLockService._();

  static const _keyAutoLockSeconds = 'vault_auto_lock_seconds';
  static const int defaultAutoLockSeconds = 60; // 1 minute default

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static int _cachedTimeout = defaultAutoLockSeconds;
  static bool _initialized = false;

  /// Global state flags to prevent re-locking during unlock/biometric prompt
  static bool isLocked = true;
  static bool isAuthenticating = false;
  static DateTime? _unlockedAt;
  static DateTime? _pausedAt;
  static DateTime _lastActivityAt = DateTime.now();

  static Timer? _inactivityCheckTimer;
  static GlobalKey<NavigatorState>? _navKey;

  /// Initializes the service with navigator key and loads timeout from storage.
  static Future<void> init(GlobalKey<NavigatorState> navKey) async {
    _navKey = navKey;
    if (!_initialized) {
      _initialized = true;
      try {
        final val = await _storage.read(key: _keyAutoLockSeconds);
        if (val != null) {
          _cachedTimeout = int.tryParse(val) ?? defaultAutoLockSeconds;
        }
      } catch (_) {}
    }

    _inactivityCheckTimer?.cancel();
    // Inactivity ticker: checks every 2 seconds if in-app user has been idle
    _inactivityCheckTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      checkInAppInactivity();
    });
  }

  /// Records user touch interaction on screen (resets inactivity countdown)
  static void recordUserActivity() {
    _lastActivityAt = DateTime.now();
  }

  /// Marks vault as unlocked and starts fresh activity tracking
  static void markUnlocked() {
    isLocked = false;
    isAuthenticating = false;
    _unlockedAt = DateTime.now();
    _lastActivityAt = DateTime.now();
    _pausedAt = null;
  }

  /// Locks vault immediately, wipes sensitive memory, and presents /unlock
  static void lockVault() {
    if (isLocked) return;
    isLocked = true;
    _pausedAt = null;
    AutofillBridgeService.syncVaultState(isUnlocked: false);
    _navKey?.currentState?.pushNamedAndRemoveUntil('/unlock', (route) => false);
  }

  /// Checks in-app user inactivity. Called periodically while app is open.
  static void checkInAppInactivity() {
    if (isLocked || isAuthenticating) return;
    if (_cachedTimeout <= 0) return; // 0 is immediately on app switch, -1 is never

    final idleSeconds = DateTime.now().difference(_lastActivityAt).inSeconds;
    if (idleSeconds >= _cachedTimeout) {
      lockVault();
    }
  }

  /// Returns configured auto-lock duration in seconds
  static Future<int> getAutoLockSeconds() async {
    return _cachedTimeout;
  }

  /// Sets auto-lock duration in seconds.
  static Future<void> setAutoLockSeconds(int seconds) async {
    _cachedTimeout = seconds;
    _lastActivityAt = DateTime.now();
    await _storage.write(key: _keyAutoLockSeconds, value: seconds.toString());
  }

  /// Invoked ONLY when app transitions to paused (real app switch/screen off)
  static void markPaused() {
    // Only record if app is currently unlocked and not inside biometric prompt
    if (!isLocked && !isAuthenticating) {
      _pausedAt = DateTime.now();
    }
  }

  /// Clears the paused state
  static void clearPaused() {
    _pausedAt = null;
  }

  /// Returns true if app has spent enough time in background to mandate locking.
  static bool shouldLockOnResume() {
    // 1. If already locked, NEVER re-lock (prevents infinite unlock loop)
    if (isLocked) return false;

    // 2. If biometric prompt is currently active, do not lock
    if (isAuthenticating) return false;

    // 3. Grace period of 4 seconds after unlocking to allow lifecycle to settle
    if (_unlockedAt != null && DateTime.now().difference(_unlockedAt!).inSeconds < 4) {
      return false;
    }

    if (_pausedAt == null) return false;
    if (_cachedTimeout < 0) return false; // Never lock
    if (_cachedTimeout == 0) return true; // Immediately upon switching apps

    final elapsed = DateTime.now().difference(_pausedAt!).inSeconds;
    return elapsed >= _cachedTimeout;
  }
}
