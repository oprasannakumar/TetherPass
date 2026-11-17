import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/vault_item.dart';
import 'card_detector.dart';

/// Offline lookup service backed by the bundled 458,000+ record BIN database
/// with local on-device self-learning and community delta sync capabilities.
class BinDatabaseService {
  BinDatabaseService._();

  static const String _dbFileName = 'bins_v2.db';
  static const String _deltaUrl =
      'https://raw.githubusercontent.com/oprasannakumar/TetherPass/main/data/bins_delta.json';

  static Database? _db;
  static bool _isInitializing = false;
  static final Map<String, BinRecord?> _memoryCache = {};

  /// Ensures the offline BIN database is initialized and ready.
  /// On first launch or after update, decompresses `assets/bins.db.gz` into `bins_v2.db`.
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
      final dbFilePath = p.join(databasesPath, _dbFileName);
      final dbFile = File(dbFilePath);

      // Clean up legacy bins_v1.db to reclaim disk space
      try {
        final legacyFile = File(p.join(databasesPath, 'bins_v1.db'));
        if (await legacyFile.exists()) {
          await legacyFile.delete();
          debugPrint('[BinDatabaseService] Deleted legacy bins_v1.db');
        }
      } catch (_) {}

      if (!await dbFile.exists() || await dbFile.length() < 1000000) {
        debugPrint('[BinDatabaseService] Unpacking expanded BIN database asset...');
        final byteData = await rootBundle.load('assets/bins.db.gz');
        final compressedBytes = byteData.buffer.asUint8List();
        final decompressedBytes = gzip.decode(compressedBytes);
        await dbFile.writeAsBytes(decompressedBytes, flush: true);
        debugPrint('[BinDatabaseService] Unpacked ${decompressedBytes.length} bytes to $dbFilePath');
      }

      _db = await openDatabase(
        dbFilePath,
        readOnly: false,
      );

      // Ensure local custom_bins table exists for on-device learned cards & community deltas
      await _db!.execute(
        'CREATE TABLE IF NOT EXISTS custom_bins ('
        'bin TEXT PRIMARY KEY, '
        'br TEXT, '
        'ty TEXT, '
        'ca TEXT, '
        'is_ TEXT, '
        'co TEXT'
        ');',
      );
      await _db!.execute(
        'CREATE INDEX IF NOT EXISTS idx_custom_bins ON custom_bins (bin);',
      );

      debugPrint('[BinDatabaseService] Expanded BIN database ready.');
    } catch (e) {
      debugPrint('[BinDatabaseService] Failed to initialize BIN database: $e');
    } finally {
      _isInitializing = false;
    }
  }

  /// Searches the local and bundled 458,000+ record BIN database for [number]
  /// (checks 8-digit and 6-digit prefixes).
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
        bool isCustom = false;

        // A. Check custom/learned bins first (overrides or additions)
        if (bin8 != null) {
          rows = await _db!.query('custom_bins', where: 'bin = ?', whereArgs: [bin8], limit: 1);
        }
        if (rows.isEmpty) {
          rows = await _db!.query('custom_bins', where: 'bin = ?', whereArgs: [bin6], limit: 1);
        }
        if (rows.isNotEmpty) {
          isCustom = true;
        } else {
          // B. Check bundled 458k table 'b'
          if (bin8 != null) {
            rows = await _db!.query('b', where: 'bin = ?', whereArgs: [bin8], limit: 1);
          }
          if (rows.isEmpty) {
            rows = await _db!.query('b', where: 'bin = ?', whereArgs: [bin6], limit: 1);
          }
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
            isCustomLearned: isCustom,
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
      isCustomLearned: false,
    );

    _memoryCache[bin6] = record;
    return record;
  }

  /// On-device self-learning: saves a newly identified or user-entered card prefix
  /// directly into the device's local database so it is recognized instantly offline.
  static Future<void> rememberBin({
    required String bin,
    String? issuer,
    String? brand,
    String? cardType,
    String? tier,
    String? country,
  }) async {
    final clean = bin.replaceAll(RegExp(r'\D'), '');
    if (clean.length < 6) return;
    final prefix = clean.length >= 8 ? clean.substring(0, 8) : clean.substring(0, 6);

    try {
      if (_db == null || !_db!.isOpen) await init();
      if (_db != null && _db!.isOpen) {
        await _db!.insert(
          'custom_bins',
          {
            'bin': prefix,
            'br': brand ?? '',
            'ty': cardType ?? '',
            'ca': tier ?? '',
            'is_': issuer ?? '',
            'co': country ?? '',
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        // Invalidate cache
        _memoryCache.remove(prefix);
        if (clean.length >= 6) _memoryCache.remove(clean.substring(0, 6));
        debugPrint('[BinDatabaseService] Locally learned BIN $prefix -> $issuer ($brand)');
      }
    } catch (e) {
      debugPrint('[BinDatabaseService] Error saving custom BIN: $e');
    }
  }

  /// Syncs online community delta updates from GitHub into `custom_bins`.
  /// Returns the number of synced records, or -1 if network failure.
  static Future<int> syncOnlineDeltas() async {
    try {
      if (_db == null || !_db!.isOpen) await init();
      if (_db == null || !_db!.isOpen) return -1;

      final resp = await http.get(Uri.parse(_deltaUrl)).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return -1;

      final List<dynamic> list = jsonDecode(resp.body) as List<dynamic>;
      if (list.isEmpty) return 0;

      int inserted = 0;
      final batch = _db!.batch();
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          final bin = (item['bin'] as String?)?.trim();
          if (bin == null || bin.length < 6) continue;
          batch.insert(
            'custom_bins',
            {
              'bin': bin,
              'br': item['br'] ?? item['brand'] ?? '',
              'ty': item['ty'] ?? item['type'] ?? '',
              'ca': item['ca'] ?? item['tier'] ?? '',
              'is_': item['is_'] ?? item['issuer'] ?? '',
              'co': item['co'] ?? item['country'] ?? '',
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          inserted++;
        }
      }

      await batch.commit(noResult: true);
      _memoryCache.clear();
      debugPrint('[BinDatabaseService] Synced $inserted delta BIN records from community repo.');
      return inserted;
    } catch (e) {
      debugPrint('[BinDatabaseService] OTA Sync error: $e');
      return -1;
    }
  }

  /// Retrieves record counts for UI display.
  static Future<Map<String, int>> getStats() async {
    int bundled = 458044;
    int custom = 0;
    try {
      if (_db == null || !_db!.isOpen) await init();
      if (_db != null && _db!.isOpen) {
        final bRes = await _db!.rawQuery('SELECT COUNT(*) as c FROM b;');
        if (bRes.isNotEmpty) {
          bundled = (bRes.first['c'] as int?) ?? bundled;
        }
        final cRes = await _db!.rawQuery('SELECT COUNT(*) as c FROM custom_bins;');
        if (cRes.isNotEmpty) {
          custom = (cRes.first['c'] as int?) ?? 0;
        }
      }
    } catch (_) {}
    return {'bundled': bundled, 'custom': custom};
  }

  /// Constructs a safe, privacy-preserving GitHub contribution URL containing ONLY
  /// the 6-digit prefix and bank name (zero card numbers, CVV, or PII).
  static String buildContributeUrl({
    required String binPrefix,
    required String bankName,
    String? brand,
    String? cardType,
  }) {
    final cleanBin = binPrefix.replaceAll(RegExp(r'\D'), '');
    final prefix = cleanBin.length >= 8 ? cleanBin.substring(0, 8) : (cleanBin.length >= 6 ? cleanBin.substring(0, 6) : cleanBin);
    final title = Uri.encodeComponent('[BIN Contribution] $prefix - $bankName');
    final body = Uri.encodeComponent('''### New Card BIN Contribution

- **BIN / IIN Prefix:** `$prefix` *(First 6-8 digits only)*
- **Issuing Bank:** $bankName
- **Card Brand:** ${brand ?? 'Unknown'}
- **Card Type:** ${cardType ?? 'Credit / Debit'}

> *Note: This submission contains only the public card issuer prefix. Never submit full card numbers, CVV, or cardholder names.*''');

    return 'https://github.com/oprasannakumar/TetherPass/issues/new?title=$title&body=$body';
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
    s = s.replaceAll(RegExp(r',?\s+(LTD|LIMITED|INC|CORP|LLC|PLC|CORP\.)\.?$', caseSensitive: false), '');
    if (s == s.toUpperCase() && s.length > 4) {
      s = s.split(' ').map((word) {
        if (word.isEmpty) return word;
        return word[0].toUpperCase() + word.substring(1).toLowerCase();
      }).join(' ');
    }
    return s;
  }
}

/// Represents a matched card BIN record from the 458,000+ database.
class BinRecord {
  final String bin;
  final String? brand;
  final String? cardType;
  final CardTier tier;
  final String? issuer;
  final String? country;
  final bool isFromDatabase;
  final bool isCustomLearned;

  const BinRecord({
    required this.bin,
    this.brand,
    this.cardType,
    this.tier = CardTier.standard,
    this.issuer,
    this.country,
    this.isFromDatabase = false,
    this.isCustomLearned = false,
  });
}
