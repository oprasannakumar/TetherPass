import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'card_detector.dart';
import 'card_scanner_service.dart';

/// Service to read contactless EMV bank cards (Visa, Mastercard, RuPay, Amex, Discover)
/// via NFC directly from the card chip.
class NfcCardScannerService {
  NfcCardScannerService._();

  static bool _isScanning = false;

  /// Checks if NFC is supported and enabled on the current device.
  static Future<NfcAvailability> checkAvailability() async {
    try {
      return await NfcManager.instance.checkAvailability();
    } catch (e) {
      debugPrint('[NfcCardScannerService] checkAvailability error: $e');
      return NfcAvailability.unsupported;
    }
  }

  /// Scans a contactless card via NFC.
  /// Notifies callers via [onStatus] as scanning progresses.
  static Future<ScannedCardData?> scanCard({
    required void Function(String status) onStatus,
  }) async {
    if (_isScanning) {
      await cancelScan();
    }

    final availability = await checkAvailability();
    if (availability == NfcAvailability.unsupported) {
      throw UnsupportedError('NFC is not supported on this device.');
    }
    if (availability == NfcAvailability.disabled) {
      throw StateError('NFC is turned off in device settings.');
    }

    _isScanning = true;
    final completer = Completer<ScannedCardData?>();

    try {
      onStatus('Ready to Scan. Hold your contactless card to the back of your phone...');

      await NfcManager.instance.startSession(
        pollingOptions: {NfcPollingOption.iso14443},
        onDiscovered: (NfcTag tag) async {
          if (!completer.isCompleted) {
            onStatus('Card detected! Reading card chip...');
            try {
              final result = await _readIsoDepCard(tag, onStatus);
              if (result != null && !result.isEmpty) {
                onStatus('Card read successfully!');
                await stopSession();
                if (!completer.isCompleted) completer.complete(result);
              } else {
                onStatus('Could not read card details. Try holding still or re-tapping...');
              }
            } catch (e) {
              debugPrint('[NfcCardScannerService] Error during tag read: $e');
              onStatus('Reading error. Please re-tap card.');
            }
          }
        },
      );
    } catch (e) {
      _isScanning = false;
      debugPrint('[NfcCardScannerService] Failed to start NFC session: $e');
      if (!completer.isCompleted) {
        completer.completeError(e);
      }
    }

    return completer.future;
  }

  /// Stops the current NFC session.
  static Future<void> cancelScan() async {
    _isScanning = false;
    try {
      await NfcManager.instance.stopSession();
    } catch (e) {
      debugPrint('[NfcCardScannerService] Stop session error: $e');
    }
  }

  static Future<void> stopSession() async {
    _isScanning = false;
    try {
      await NfcManager.instance.stopSession();
    } catch (_) {}
  }

  /// Reads an IsoDep contactless card using EMV APDUs
  static Future<ScannedCardData?> _readIsoDepCard(
    NfcTag tag,
    void Function(String status) onStatus,
  ) async {
    final isoDep = IsoDepAndroid.from(tag);
    if (isoDep == null) {
      debugPrint('[NfcCardScannerService] Tag is not IsoDep');
      return null;
    }

    try {
      await isoDep.setTimeout(5000);
    } catch (_) {}

    final parsed = _ParsedEmvData();

    // 1. Try PPSE (Proximity Payment System Environment: '2PAY.SYS.DDF01')
    final ppseApdu = Uint8List.fromList([
      0x00, 0xA4, 0x04, 0x00, 0x0E,
      0x32, 0x50, 0x41, 0x59, 0x2E, 0x53, 0x59, 0x53, 0x2E, 0x44, 0x44, 0x46, 0x30, 0x31,
      0x00,
    ]);

    final List<Uint8List> targetAids = [];
    try {
      final ppseRes = await isoDep.transceive(ppseApdu);
      _extractDataFromBytes(ppseRes, parsed);
      final discoveredAids = _extractAidsFromPpse(ppseRes);
      targetAids.addAll(discoveredAids);
    } catch (e) {
      debugPrint('[NfcCardScannerService] PPSE transceive note: $e');
    }

    // 2. Add well-known fallback AIDs if not already present
    for (final aid in _knownAids) {
      if (!targetAids.any((a) => _listEquals(a, aid))) {
        targetAids.add(Uint8List.fromList(aid));
      }
    }

    // 3. Iterate over AIDs to select application and read records
    for (final aid in targetAids) {
      if (parsed.isComplete) break;

      try {
        final selectApdu = Uint8List.fromList([
          0x00, 0xA4, 0x04, 0x00,
          aid.length,
          ...aid,
          0x00,
        ]);

        final selectRes = await isoDep.transceive(selectApdu);
        _extractDataFromBytes(selectRes, parsed);

        // Try GPO (Get Processing Options)
        try {
          final gpoEmpty = Uint8List.fromList([0x80, 0xA8, 0x00, 0x00, 0x02, 0x83, 0x00, 0x00]);
          final gpoRes = await isoDep.transceive(gpoEmpty);
          _extractDataFromBytes(gpoRes, parsed);
        } catch (_) {}

        // Read records across SFIs 1 to 4, records 1 to 5
        for (int sfi = 1; sfi <= 4; sfi++) {
          if (parsed.isComplete) break;
          for (int rec = 1; rec <= 5; rec++) {
            if (parsed.isComplete) break;
            try {
              final p2 = (sfi << 3) | 4;
              final readApdu = Uint8List.fromList([0x00, 0xB2, rec, p2, 0x00]);
              final readRes = await isoDep.transceive(readApdu);
              _extractDataFromBytes(readRes, parsed);
            } catch (_) {
              // Ignore record read miss
            }
          }
        }
      } catch (e) {
        debugPrint('[NfcCardScannerService] AID transceive note: $e');
      }
    }

    if (parsed.cardNumber != null) {
      return ScannedCardData(
        cardNumber: parsed.cardNumber,
        expiry: parsed.expiry,
        cardHolder: parsed.cardHolder,
      );
    }

    return null;
  }

  /// Parses Tag 4F (AID) from PPSE response
  static List<Uint8List> _extractAidsFromPpse(Uint8List bytes) {
    final aids = <Uint8List>[];
    for (int i = 0; i < bytes.length - 2; i++) {
      if (bytes[i] == 0x4F) {
        final len = bytes[i + 1];
        if (len >= 5 && len <= 16 && (i + 2 + len) <= bytes.length) {
          aids.add(Uint8List.fromList(bytes.sublist(i + 2, i + 2 + len)));
        }
      }
    }
    return aids;
  }

  /// Scans byte stream for EMV tags: 0x57 (Track 2), 0x5A (PAN), 0x5F24 (Expiry), 0x5F20 (Holder Name)
  static void _extractDataFromBytes(Uint8List bytes, _ParsedEmvData result) {
    if (bytes.length < 3) return;

    // Scan for tags
    for (int i = 0; i < bytes.length - 2; i++) {
      // 1. Tag 0x57: Track 2 Equivalent Data
      if (bytes[i] == 0x57) {
        final len = bytes[i + 1];
        if (len >= 8 && len <= 32 && (i + 2 + len) <= bytes.length) {
          final track2 = bytes.sublist(i + 2, i + 2 + len);
          _parseTrack2Bytes(track2, result);
        }
      }

      // 2. Tag 0x5A: Application PAN
      if (bytes[i] == 0x5A) {
        final len = bytes[i + 1];
        if (len >= 7 && len <= 10 && (i + 2 + len) <= bytes.length) {
          final panBytes = bytes.sublist(i + 2, i + 2 + len);
          _parsePanBytes(panBytes, result);
        }
      }

      // 3. Tag 0x5F24: Application Expiration Date (YYMMDD)
      if (bytes[i] == 0x5F && bytes[i + 1] == 0x24) {
        final len = bytes[i + 2];
        if (len == 3 && (i + 3 + len) <= bytes.length) {
          final expBytes = bytes.sublist(i + 3, i + 3 + len);
          _parseExpiryBytes(expBytes, result);
        }
      }

      // 4. Tag 0x5F20: Cardholder Name
      if (bytes[i] == 0x5F && bytes[i + 1] == 0x20) {
        final len = bytes[i + 2];
        if (len >= 2 && len <= 40 && (i + 3 + len) <= bytes.length) {
          final nameBytes = bytes.sublist(i + 3, i + 3 + len);
          _parseNameBytes(nameBytes, result);
        }
      }
    }

    // 5. Track 1 text scan (e.g. %B[PAN]^[NAME]^[YYMM]...)
    try {
      final asciiStr = ascii.decode(bytes, allowInvalid: true);
      final track1Match = RegExp(r'\b([0-9]{13,19})\^([^\^]+)\^([0-9]{2})([0-9]{2})').firstMatch(asciiStr);
      if (track1Match != null) {
        final pan = track1Match.group(1);
        final rawName = track1Match.group(2);
        final yy = track1Match.group(3);
        final mm = track1Match.group(4);
        if (pan != null && CardDetector.isValidLuhn(pan)) {
          result.cardNumber ??= pan;
        }
        if (mm != null && yy != null) {
          final mInt = int.tryParse(mm) ?? 0;
          if (mInt >= 1 && mInt <= 12) {
            result.expiry ??= '$mm/$yy';
          }
        }
        if (rawName != null && rawName.trim().isNotEmpty) {
          var name = rawName.trim();
          if (name.contains('/')) {
            final parts = name.split('/');
            name = '${parts[1].trim()} ${parts[0].trim()}'.trim();
          }
          result.cardHolder ??= name;
        }
      }
    } catch (_) {}
  }

  static void _parseTrack2Bytes(Uint8List bytes, _ParsedEmvData result) {
    final hex = _toHex(bytes).toUpperCase();
    if (hex.contains('D')) {
      final parts = hex.split('D');
      final pan = parts[0];
      if (pan.length >= 13 && pan.length <= 19 && CardDetector.isValidLuhn(pan)) {
        result.cardNumber ??= pan;
        if (parts.length > 1 && parts[1].length >= 4) {
          final yy = parts[1].substring(0, 2);
          final mm = parts[1].substring(2, 4);
          final mInt = int.tryParse(mm) ?? 0;
          if (mInt >= 1 && mInt <= 12) {
            result.expiry ??= '$mm/$yy';
          }
        }
      }
    }
  }

  static void _parsePanBytes(Uint8List bytes, _ParsedEmvData result) {
    var hex = _toHex(bytes).toUpperCase();
    if (hex.endsWith('F')) {
      hex = hex.substring(0, hex.length - 1);
    }
    if (hex.length >= 13 && hex.length <= 19 && CardDetector.isValidLuhn(hex)) {
      result.cardNumber ??= hex;
    }
  }

  static void _parseExpiryBytes(Uint8List bytes, _ParsedEmvData result) {
    final hex = _toHex(bytes);
    if (hex.length >= 4) {
      final yy = hex.substring(0, 2);
      final mm = hex.substring(2, 4);
      final mInt = int.tryParse(mm) ?? 0;
      if (mInt >= 1 && mInt <= 12) {
        result.expiry ??= '$mm/$yy';
      }
    }
  }

  static void _parseNameBytes(Uint8List bytes, _ParsedEmvData result) {
    try {
      var name = ascii.decode(bytes).trim();
      if (name.contains('/')) {
        final parts = name.split('/');
        if (parts.length >= 2) {
          name = '${parts[1].trim()} ${parts[0].trim()}'.trim();
        }
      }
      if (name.isNotEmpty && RegExp(r'^[a-zA-Z\s\.\-]+$').hasMatch(name)) {
        result.cardHolder ??= name;
      }
    } catch (_) {}
  }

  static String _toHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static final List<List<int>> _knownAids = [
    // Visa
    [0xA0, 0x00, 0x00, 0x00, 0x03, 0x10, 0x10],
    [0xA0, 0x00, 0x00, 0x00, 0x03, 0x20, 0x10],
    // Mastercard
    [0xA0, 0x00, 0x00, 0x00, 0x04, 0x10, 0x10],
    [0xA0, 0x00, 0x00, 0x00, 0x04, 0x30, 0x60],
    // RuPay
    [0xA0, 0x00, 0x00, 0x05, 0x24, 0x10, 0x10],
    [0xA0, 0x00, 0x00, 0x05, 0x24, 0x20, 0x10],
    [0xA0, 0x00, 0x00, 0x05, 0x24],
    // American Express
    [0xA0, 0x00, 0x00, 0x00, 0x25, 0x01],
    // Discover / Diners
    [0xA0, 0x00, 0x00, 0x01, 0x52, 0x30, 0x10],
    [0xA0, 0x00, 0x00, 0x03, 0x24, 0x10, 0x10],
  ];
}

class _ParsedEmvData {
  String? cardNumber;
  String? expiry;
  String? cardHolder;

  bool get isComplete => cardNumber != null && expiry != null;
  bool get isEmpty => cardNumber == null && expiry == null && cardHolder == null;
}
