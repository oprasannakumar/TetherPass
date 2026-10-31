import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// RFC 6238 Time-Based One-Time Password (TOTP) generator.
/// Fully offline, pure Dart cryptographic implementation.
class TotpService {
  TotpService._();

  static const int defaultPeriod = 30; // seconds
  static const int defaultDigits = 6;

  /// Standard Base32 alphabet (RFC 4648)
  static const String _base32Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  /// Generates the current 6-digit TOTP code for the given [secretKey].
  /// Returns empty string if the secret key is invalid.
  static String generateCode(String secretKey, {DateTime? time, int digits = defaultDigits, int period = defaultPeriod}) {
    final cleanSecret = cleanKey(secretKey);
    if (cleanSecret.isEmpty) return '';

    try {
      final keyBytes = _decodeBase32(cleanSecret);
      if (keyBytes.isEmpty) return '';

      final targetTime = time ?? DateTime.now();
      final epochSeconds = targetTime.millisecondsSinceEpoch ~/ 1000;
      final counter = epochSeconds ~/ period;

      return _generateOtp(keyBytes, counter, digits);
    } catch (_) {
      return '';
    }
  }

  /// Returns remaining seconds until the current 30-second window expires (1 to 30).
  static int getRemainingSeconds({int period = defaultPeriod}) {
    final epochSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final elapsed = epochSeconds % period;
    final remaining = period - elapsed;
    return remaining == 0 ? period : remaining;
  }

  /// Returns progress from 0.0 to 1.0 of the current 30-second time window.
  static double getProgress({int period = defaultPeriod}) {
    return getRemainingSeconds(period: period) / period;
  }

  /// Strips formatting, spaces, and dashes from secret key.
  static String cleanKey(String raw) {
    var key = raw.trim().toUpperCase().replaceAll(' ', '').replaceAll('-', '').replaceAll('=', '');
    if (key.startsWith('OTPAUTH://')) {
      final uri = parseTotpUri(raw);
      if (uri != null && uri.secret.isNotEmpty) {
        key = uri.secret;
      }
    }
    return key;
  }

  /// Verifies if a given string is a valid Base32 secret key.
  static bool isValidSecret(String secret) {
    final clean = cleanKey(secret);
    if (clean.length < 8) return false;
    for (int i = 0; i < clean.length; i++) {
      if (!_base32Alphabet.contains(clean[i])) return false;
    }
    return true;
  }

  /// Parses an `otpauth://totp/...` URI from a QR code or manual input.
  static TotpUriInfo? parseTotpUri(String rawUri) {
    try {
      final trimmed = rawUri.trim();
      if (!trimmed.toLowerCase().startsWith('otpauth://totp/')) return null;

      final uri = Uri.parse(trimmed);
      final secret = uri.queryParameters['secret'] ?? '';
      final issuer = uri.queryParameters['issuer'] ?? '';
      var account = uri.path.replaceFirst('/', '');
      if (account.contains(':')) {
        final parts = account.split(':');
        account = parts.length > 1 ? parts[1].trim() : parts[0].trim();
      }

      if (secret.isEmpty) return null;

      return TotpUriInfo(
        secret: cleanKey(secret),
        issuer: issuer.isNotEmpty ? issuer : null,
        account: account.isNotEmpty ? account : null,
      );
    } catch (_) {
      return null;
    }
  }

  /// Decodes Base32 string to Uint8List byte array.
  static Uint8List _decodeBase32(String input) {
    final clean = input.toUpperCase().replaceAll('=', '');
    int buffer = 0;
    int bitsLeft = 0;
    final result = <int>[];

    for (int i = 0; i < clean.length; i++) {
      final char = clean[i];
      final val = _base32Alphabet.indexOf(char);
      if (val == -1) continue;

      buffer = (buffer << 5) | val;
      bitsLeft += 5;

      if (bitsLeft >= 8) {
        bitsLeft -= 8;
        result.add((buffer >> bitsLeft) & 0xFF);
      }
    }

    return Uint8List.fromList(result);
  }

  /// RFC 4226 / RFC 6238 core OTP generation.
  static String _generateOtp(Uint8List keyBytes, int counter, int digits) {
    // 8-byte big-endian counter
    final counterBytes = Uint8List(8);
    for (int i = 7; i >= 0; i--) {
      counterBytes[i] = counter & 0xFF;
      counter = counter >> 8;
    }

    // HMAC-SHA1
    final hmac = Hmac(sha1, keyBytes);
    final hash = hmac.convert(counterBytes).bytes;

    // Dynamic Truncation (RFC 4226 section 5.4)
    final offset = hash[hash.length - 1] & 0x0F;
    final binary = ((hash[offset] & 0x7F) << 24) |
        ((hash[offset + 1] & 0xFF) << 16) |
        ((hash[offset + 2] & 0xFF) << 8) |
        (hash[offset + 3] & 0xFF);

    int mod = 1;
    for (int i = 0; i < digits; i++) {
      mod *= 10;
    }

    final otp = binary % mod;
    return otp.toString().padLeft(digits, '0');
  }
}

class TotpUriInfo {
  final String secret;
  final String? issuer;
  final String? account;

  const TotpUriInfo({
    required this.secret,
    this.issuer,
    this.account,
  });
}
