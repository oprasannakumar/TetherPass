import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Handles secure clipboard copying with an automated purge/clear timer.
class ClipboardService {
  ClipboardService._();

  static const _keyClipboardPurgeSeconds = 'vault_clipboard_purge_seconds';
  static const int defaultPurgeSeconds = 30; // 30 seconds default

  static Timer? _purgeTimer;
  static String? _lastCopiedValue;
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Returns configured purge duration in seconds (-1 means disabled).
  static Future<int> getPurgeSeconds() async {
    final val = await _storage.read(key: _keyClipboardPurgeSeconds);
    if (val == null) return defaultPurgeSeconds;
    return int.tryParse(val) ?? defaultPurgeSeconds;
  }

  /// Sets purge duration in seconds (-1 to disable).
  static Future<void> setPurgeSeconds(int seconds) async {
    await _storage.write(key: _keyClipboardPurgeSeconds, value: seconds.toString());
  }

  /// Securely copies [value] to system clipboard and schedules an auto-clear wiper.
  static Future<void> copySecure(
    BuildContext context,
    String value, {
    String label = 'Copied',
  }) async {
    if (value.isEmpty) return;

    await Clipboard.setData(ClipboardData(text: value));
    _lastCopiedValue = value;

    final purgeSeconds = await getPurgeSeconds();

    // Cancel existing timer
    _purgeTimer?.cancel();

    if (purgeSeconds > 0) {
      _purgeTimer = Timer(Duration(seconds: purgeSeconds), () async {
        try {
          final current = await Clipboard.getData(Clipboard.kTextPlain);
          // Only clear if user hasn't copied a different text in the interim
          if (current?.text == _lastCopiedValue) {
            await Clipboard.setData(const ClipboardData(text: ''));
            debugPrint('[ClipboardService] Clipboard auto-purged securely after ${purgeSeconds}s.');
          }
        } catch (_) {}
      });
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF0F172A),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 3),
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  purgeSeconds > 0
                      ? '$label copied (auto-clears in ${purgeSeconds}s)'
                      : '$label copied to clipboard',
                  style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 13),
                ),
              ),
              if (purgeSeconds > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6F00).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFFF6F00)),
                  ),
                  child: Text(
                    '${purgeSeconds}s',
                    style: const TextStyle(color: Color(0xFFFF6F00), fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
        ),
      );
    }
  }
}
