import 'package:flutter/services.dart';

/// Formats a raw digit string into credit-card-style groups with spaces.
///
/// Default (16-digit): "1234 5678 9012 3456"
/// Amex (15-digit):    "3782 822463 10005"
class CardNumberInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final isAmex = digits.startsWith('34') || digits.startsWith('37');

    final buffer = StringBuffer();
    int offset = 0;

    if (isAmex) {
      // Amex: 4 – 6 – 5
      final groups = [4, 6, 5];
      int pos = 0;
      for (int g = 0; g < groups.length; g++) {
        final end = (pos + groups[g]).clamp(0, digits.length);
        buffer.write(digits.substring(pos, end));
        pos = end;
        if (pos < digits.length && g < groups.length - 1) buffer.write(' ');
        if (pos >= digits.length) break;
      }
    } else {
      // Default: 4 – 4 – 4 – 4 (supports up to 19 digits for RuPay / Maestro)
      for (int i = 0; i < digits.length && i < 19; i++) {
        if (i > 0 && i % 4 == 0) buffer.write(' ');
        buffer.write(digits[i]);
      }
    }

    final formatted = buffer.toString();
    offset = formatted.length;

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

/// Formats a raw digit string into "MM/YY" expiry format.
/// Strictly enforces month between 01 and 12 (rejects any entry above 12).
class ExpiryDateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // If user is deleting/backspacing, allow it immediately
    if (newValue.text.length < oldValue.text.length) {
      return newValue;
    }

    final raw = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (raw.isEmpty) {
      return newValue.copyWith(text: '');
    }

    String formattedMonth = '';
    String yearPart = '';

    if (raw.length == 1) {
      final firstDigit = int.tryParse(raw) ?? 0;
      if (firstDigit > 1) {
        // Digits 2 through 9 can never be followed by a digit without exceeding 12.
        // Auto-format to '0X/' (e.g. typing '3' becomes '03/')
        formattedMonth = '0$raw/';
      } else {
        // '0' and '1' are valid starting digits for month
        formattedMonth = raw;
      }
    } else {
      // 2 or more digits entered for month
      final monthDigits = raw.substring(0, 2);
      final month = int.tryParse(monthDigits) ?? 0;

      // Strictly allow only 1 to 12. Reject 00 or anything > 12!
      if (month < 1 || month > 12) {
        return oldValue;
      }

      formattedMonth = '$monthDigits/';
      if (raw.length > 2) {
        // Limit year to max 2 digits (YY)
        yearPart = raw.substring(2, raw.length.clamp(2, 4));
      }
    }

    final result = formattedMonth + yearPart;
    return TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: result.length),
    );
  }
}

/// Formats a number according to the Indian numbering system (e.g., 1,23,445 or 10,00,000).
String formatIndianNumber(num number) {
  final str = number.round().toString();
  if (str.length <= 3) return str;
  final last3 = str.substring(str.length - 3);
  final rest = str.substring(0, str.length - 3);
  final formattedRest = rest.replaceAllMapped(
    RegExp(r'\B(?=(\d{2})+(?!\d))'),
    (match) => ',',
  );
  return '$formattedRest,$last3';
}

/// Automatically formats numbers into Indian format "1,23,445" as the user types.
class IndianNumberInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return newValue.copyWith(text: '');
    }
    final number = int.tryParse(digits) ?? 0;
    final formatted = formatIndianNumber(number);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
