import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class BreachResult {
  final bool isPwned;
  final int breachCount;
  final String? error;

  const BreachResult({
    required this.isPwned,
    required this.breachCount,
    this.error,
  });

  String get severityLabel {
    if (!isPwned) return 'Safe (0 Breaches)';
    if (breachCount > 10000) return 'Critical Risk ($breachCount leaks)';
    if (breachCount > 100) return 'High Risk ($breachCount leaks)';
    return 'Compromised ($breachCount leaks)';
  }
}

/// Zero-Knowledge Password Leak Scanner via HaveIBeenPwned's k-Anonymity API.
/// Your password NEVER leaves your device: only the first 5 characters of its SHA-1 hash are queried.
class BreachWatchService {
  BreachWatchService._();

  static final Map<String, BreachResult> _cache = {};

  /// Checks if [password] appears in public data breaches.
  static Future<BreachResult> checkPassword(String password) async {
    final clean = password.trim();
    if (clean.isEmpty) {
      return const BreachResult(isPwned: false, breachCount: 0);
    }

    if (_cache.containsKey(clean)) {
      return _cache[clean]!;
    }

    try {
      // 1. Calculate local SHA-1 hash
      final fullHash = sha1.convert(utf8.encode(clean)).toString().toUpperCase();
      final prefix = fullHash.substring(0, 5);
      final suffix = fullHash.substring(5);

      // 2. Query k-Anonymity range API (Zero-Knowledge)
      final url = Uri.parse('https://api.pwnedpasswords.com/range/$prefix');
      final response = await http.get(
        url,
        headers: {
          'Add-Padding': 'true', // Prevents traffic analysis
          'User-Agent': 'TetherPass-Security-Audit',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        return BreachResult(
          isPwned: false,
          breachCount: 0,
          error: 'Lookup failed (HTTP ${response.statusCode})',
        );
      }

      // 3. Search locally for matching suffix in the response
      final lines = const LineSplitter().convert(response.body);
      int matchedCount = 0;
      bool found = false;

      for (final line in lines) {
        final parts = line.split(':');
        if (parts.length >= 2) {
          final returnedSuffix = parts[0].trim().toUpperCase();
          if (returnedSuffix == suffix) {
            matchedCount = int.tryParse(parts[1].trim()) ?? 1;
            found = true;
            break;
          }
        }
      }

      final result = BreachResult(
        isPwned: found,
        breachCount: matchedCount,
      );

      _cache[clean] = result;
      return result;
    } catch (e) {
      return BreachResult(
        isPwned: false,
        breachCount: 0,
        error: 'Network check unavailable: $e',
      );
    }
  }

  static void clearCache() {
    _cache.clear();
  }
}
