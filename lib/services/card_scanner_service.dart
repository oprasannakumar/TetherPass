import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'card_detector.dart';

/// Scanned credit card result model
class ScannedCardData {
  final String? cardNumber;
  final String? expiry;
  final String? cardHolder;

  const ScannedCardData({
    this.cardNumber,
    this.expiry,
    this.cardHolder,
  });

  bool get isEmpty => (cardNumber == null || cardNumber!.isEmpty) &&
      (expiry == null || expiry!.isEmpty) &&
      (cardHolder == null || cardHolder!.isEmpty);
}

/// Service to scan physical cards via device camera or gallery using Google ML Kit on-device OCR.
class CardScannerService {
  CardScannerService._();

  static final _picker = ImagePicker();

  /// Captures an image with the camera and extracts card number, expiry date, and holder name.
  static Future<ScannedCardData?> scanCardFromCamera() async {
    return _scanFromSource(ImageSource.camera);
  }

  /// Selects an image from the gallery and extracts card details.
  static Future<ScannedCardData?> scanCardFromGallery() async {
    return _scanFromSource(ImageSource.gallery);
  }

  static Future<ScannedCardData?> _scanFromSource(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 90,
      );

      if (image == null) return null;

      final inputImage = InputImage.fromFilePath(image.path);
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

      try {
        final recognizedText = await textRecognizer.processImage(inputImage);
        return _extractCardData(recognizedText);
      } finally {
        await textRecognizer.close();
      }
    } catch (e) {
      debugPrint('[CardScannerService] Error scanning card: $e');
      return null;
    }
  }

  static ScannedCardData _extractCardData(RecognizedText recognized) {
    String? foundCardNumber;
    String? foundExpiry;
    String? foundHolder;

    final allLines = <String>[];
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        allLines.add(line.text.trim());
      }
    }

    // 1. Look for Card Number (13-19 digits, possibly grouped by 4 or 4-6-5)
    for (final line in allLines) {
      final clean = line.replaceAll(RegExp(r'[\s\-]'), '');
      if (RegExp(r'^\d{13,19}$').hasMatch(clean)) {
        if (CardDetector.isValidLuhn(clean)) {
          foundCardNumber = clean;
          break;
        }
      }
    }

    // Secondary scan across block text if grouped awkwardly
    if (foundCardNumber == null) {
      final fullText = recognized.text.replaceAll('\n', ' ');
      final cardMatches = RegExp(r'\b(?:\d[ -]*?){13,19}\b').allMatches(fullText);
      for (final match in cardMatches) {
        final candidate = match.group(0)!.replaceAll(RegExp(r'[\s\-]'), '');
        if (candidate.length >= 13 && candidate.length <= 19 && CardDetector.isValidLuhn(candidate)) {
          foundCardNumber = candidate;
          break;
        }
      }
    }

    // 2. Look for Expiry date (MM/YY or MM/YYYY)
    final expiryRegex = RegExp(r'\b(0[1-9]|1[0-2])[\/\-](2[4-9]|[3-4][0-9]|20[2-4][0-9])\b');
    for (final line in allLines) {
      final match = expiryRegex.firstMatch(line);
      if (match != null) {
        var exp = match.group(0)!.replaceAll('-', '/');
        // Convert YYYY to YY if needed
        final parts = exp.split('/');
        if (parts.length == 2 && parts[1].length == 4) {
          exp = '${parts[0]}/${parts[1].substring(2)}';
        }
        foundExpiry = exp;
        break;
      }
    }

    // 3. Look for Cardholder Name (Uppercase words, excluding common bank / card keywords)
    final ignoredWords = {
      'VALID', 'THRU', 'EXPIRES', 'MONTH', 'YEAR', 'GOOD', 'FROM',
      'VISA', 'MASTERCARD', 'RUPAY', 'DEBIT', 'CREDIT', 'PLATINUM',
      'SIGNATURE', 'GOLD', 'CLASSIC', 'BANK', 'MEMBER', 'SINCE',
      'CARD', 'ELECTRON', 'CORP', 'CORPORATE', 'BUSINESS', 'REWARDS',
      'CUSTOMER', 'VALUED', 'INTERNATIONAL', 'DOMESTIC',
    };

    for (final line in allLines) {
      final trimmed = line.trim();
      // Name usually 2-3 words, all caps or title case, alphabetic only
      if (RegExp(r'^[A-Z][A-Z\s\.\-]{3,28}$').hasMatch(trimmed)) {
        final words = trimmed.split(RegExp(r'\s+'));
        final containsIgnored = words.any((w) => ignoredWords.contains(w.toUpperCase()));
        if (!containsIgnored && words.length >= 2 && words.length <= 4) {
          foundHolder = trimmed;
          break;
        }
      }
    }

    return ScannedCardData(
      cardNumber: foundCardNumber,
      expiry: foundExpiry,
      cardHolder: foundHolder,
    );
  }
}
