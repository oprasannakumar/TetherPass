import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/vault_item.dart';
import 'card_detector.dart';

/// Offline lookup service backed by the bundled 374,788+ record BIN database
/// (decompressed on first launch to app document directory).
class BinDatabaseService {
  BinDatabaseService._();

  static Database? _db;
  static bool _isInitializing = false;
  static final Map<String, BinRecord?> _memoryCache = {};

  /// Ensures the offline BIN database is initialized and ready.
  /// On first launch, decompresses `assets/bins.db.gz` into the app's databases folder.
  static Future<void> init() async {
    if (_db != null && _db!.isOpen) return;
    if (_isInitializing) {
      while (_isInitializing) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return;
    }

    _isInitializing = true;
    try {
      final databasesPath = await getDatabasesPath();
      final dbFilePath = p.join(databasesPath, 'bins_v1.db');
      final dbFile = File(dbFilePath);

      if (!await dbFile.exists() || await dbFile.length() < 1000000) {
        debugPrint('[BinDatabaseService] Unpacking BIN database asset...');
        final byteData = await rootBundle.load('assets/bins.db.gz');
        final compressedBytes = byteData.buffer.asUint8List();
        final decompressedBytes = gzip.decode(compressedBytes);
        await dbFile.writeAsBytes(decompressedBytes, flush: true);
        debugPrint('[BinDatabaseService] Unpacked ${decompressedBytes.length} bytes to $dbFilePath');
      }

      _db = await openDatabase(
        dbFilePath,
        readOnly: true,
      );
      debugPrint('[BinDatabaseService] BIN database ready.');
    } catch (e) {
      debugPrint('[BinDatabaseService] Failed to initialize BIN database: $e');
    } finally {
      _isInitializing = false;
    }
  }

  /// Searches the 374,000+ record BIN database for [number] (checks 8-digit and 6-digit prefixes).
  /// Falls back seamlessly to [CardDetector] heuristics if not found or DB unavailable.
  static Future<BinRecord?> lookup(String number) async {
    final d = number.replaceAll(RegExp(r'\D'), '');
    if (d.length < 6) return null;

    final bin8 = d.length >= 8 ? d.substring(0, 8) : null;
    final bin6 = d.substring(0, 6);

    // 1. Check in-memory cache
    if (bin8 != null && _memoryCache.containsKey(bin8)) {
      return _memoryCache[bin8];
    }
    if (_memoryCache.containsKey(bin6)) {
      return _memoryCache[bin6];
    }

    // 2. Query SQLite database
    try {
      if (_db == null || !_db!.isOpen) {
        await init();
      }

      if (_db != null && _db!.isOpen) {
        List<Map<String, Object?>> rows = const [];
        if (bin8 != null) {
          rows = await _db!.query('b', where: 'bin = ?', whereArgs: [bin8], limit: 1);
        }
        if (rows.isEmpty) {
          rows = await _db!.query('b', where: 'bin = ?', whereArgs: [bin6], limit: 1);
        }

        if (rows.isNotEmpty) {
          final r = rows.first;
          final rawBrand = (r['br'] as String?)?.trim() ?? '';
          final rawType = (r['ty'] as String?)?.trim() ?? '';
          final rawCategory = (r['ca'] as String?)?.trim() ?? '';
          final rawIssuer = (r['is_'] as String?)?.trim() ?? '';
          final rawCountry = (r['co'] as String?)?.trim() ?? '';

          final record = BinRecord(
            bin: (r['bin'] as String?) ?? bin6,
            brand: _normalizeBrand(rawBrand),
            cardType: _normalizeCardType(rawType),
            tier: _mapCategoryToTier(rawCategory),
            issuer: rawIssuer.isNotEmpty ? _cleanIssuerName(rawIssuer) : null,
            country: rawCountry.isNotEmpty ? rawCountry : null,
            isFromDatabase: true,
          );

          _memoryCache[bin6] = record;
          if (bin8 != null) _memoryCache[bin8] = record;
          return record;
        }
      }
    } catch (e) {
      debugPrint('[BinDatabaseService] Query error: $e');
    }

    // 3. Fallback to local CardDetector heuristic engine
    final fallback = CardDetector.detect(d);
    final record = BinRecord(
      bin: bin6,
      brand: fallback.network != 'Unknown' ? fallback.network : null,
      cardType: fallback.cardType != 'Unknown' ? fallback.cardType : null,
      tier: fallback.tier,
      issuer: fallback.bank != 'Unknown' ? fallback.bank : null,
      country: null,
      isFromDatabase: false,
    );

    _memoryCache[bin6] = record;
    return record;
  }

  static String _normalizeBrand(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('visa')) return 'Visa';
    if (lower.contains('master')) return 'Mastercard';
    if (lower.contains('rupay')) return 'RuPay';
    if (lower.contains('amex') || lower.contains('american')) return 'Amex';
    if (lower.contains('discover')) return 'Discover';
    if (lower.contains('diners')) return 'Diners';
    if (lower.contains('jcb')) return 'JCB';
    if (lower.contains('union')) return 'UnionPay';
    if (lower.contains('maestro')) return 'Maestro';
    if (raw.isEmpty) return 'Unknown';
    return raw[0].toUpperCase() + raw.substring(1).toLowerCase();
  }

  static String? _normalizeCardType(String raw) {
    final lower = raw.toLowerCase().trim();
    if (lower.contains('credit') || lower.contains('charge')) return 'Credit';
    if (lower.contains('debit')) return 'Debit';
    if (lower.contains('prepaid')) return 'Debit';
    if (raw.isNotEmpty) return raw[0].toUpperCase() + raw.substring(1).toLowerCase();
    return null;
  }

  static CardTier _mapCategoryToTier(String rawCategory) {
    final lower = rawCategory.toLowerCase();
    if (lower.contains('infinite') || lower.contains('world elite') || lower.contains('select')) {
      return CardTier.infinite;
    }
    if (lower.contains('signature') || lower.contains('world')) {
      return CardTier.signature;
    }
    if (lower.contains('platinum')) {
      return CardTier.platinum;
    }
    if (lower.contains('gold')) {
      return CardTier.gold;
    }
    return CardTier.standard;
  }

  static String _cleanIssuerName(String raw) {
    var s = raw.trim();
    // Trim extraneous corporate suffixes
    s = s.replaceAll(RegExp(r',?\s+(LTD|LIMITED|INC|CORP|LLC|PLC|CORP\.)\.?$', caseSensitive: false), '');
    // If capitalized like "HDFC BANK", convert to Title Case
    if (s == s.toUpperCase() && s.length > 4) {
      s = s.split(' ').map((word) {
        if (word.isEmpty) return word;
        return word[0].toUpperCase() + word.substring(1).toLowerCase();
      }).join(' ');
    }
    return s;
  }
}

/// Represents a matched card BIN record from the 374,000+ database.
class BinRecord {
  final String bin;
  final String? brand;
  final String? cardType;
  final CardTier tier;
  final String? issuer;
  final String? country;
  final bool isFromDatabase;

  const BinRecord({
    required this.bin,
    this.brand,
    this.cardType,
    this.tier = CardTier.standard,
    this.issuer,
    this.country,
    this.isFromDatabase = false,
  });
}
