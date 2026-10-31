import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/vault_item.dart';
import 'crypto_service.dart';
import 'secure_backup_export_service.dart';

/// SQLite persistence layer with AES-256 field-level encryption.
///
/// Sensitive fields (card numbers, CVV, passwords, PINs, CIF, notes) are
/// encrypted before writing and decrypted upon reading.
class DatabaseService {
  static const _dbName = 'card_vault_v2.db';
  static const _tableName = 'vault_items';
  static const _dbVersion = 8;

  final CryptoService cryptoService;
  Database? _db;

  DatabaseService({required this.cryptoService});

  Future<void> init() async {
    if (_db != null) return;
    final dbPath = join(await getDatabasesPath(), _dbName);
    _db = await openDatabase(
      dbPath,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_tableName (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        bank_name TEXT NOT NULL,
        nickname TEXT NOT NULL,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        card_number TEXT,
        card_holder TEXT,
        card_network TEXT,
        expiry TEXT,
        cvv TEXT,
        card_tier TEXT,
        card_type TEXT,
        credit_limit REAL,
        statement_day INTEGER,
        due_day INTEGER,
        user_id TEXT,
        login_password TEXT,
        profile_password TEXT,
        mpin TEXT,
        cif_number TEXT,
        password_expiry_months INTEGER,
        password_set_date TEXT,
        login_password_expiry TEXT,
        profile_password_expiry TEXT,
        mpin_expiry TEXT,
        account_number TEXT,
        ifsc_code TEXT,
        accounts TEXT,
        website TEXT,
        totp_secret TEXT
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute('ALTER TABLE $_tableName ADD COLUMN credit_limit REAL DEFAULT 0');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE $_tableName ADD COLUMN statement_day INTEGER DEFAULT 0');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE $_tableName ADD COLUMN due_day INTEGER DEFAULT 0');
      } catch (_) {}
    }
    if (oldVersion < 3) {
      try {
        await db.execute('ALTER TABLE $_tableName ADD COLUMN card_type TEXT DEFAULT ""');
      } catch (_) {}
    }
    if (oldVersion < 4) {
      try {
        await db.execute('ALTER TABLE $_tableName ADD COLUMN login_password_expiry TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE $_tableName ADD COLUMN profile_password_expiry TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE $_tableName ADD COLUMN mpin_expiry TEXT');
      } catch (_) {}
    }
    if (oldVersion < 5) {
      try {
        await db.execute('ALTER TABLE $_tableName ADD COLUMN account_number TEXT DEFAULT ""');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE $_tableName ADD COLUMN ifsc_code TEXT DEFAULT ""');
      } catch (_) {}
    }
    if (oldVersion < 6) {
      try {
        await db.execute('ALTER TABLE $_tableName ADD COLUMN accounts TEXT DEFAULT ""');
      } catch (_) {}
    }
    if (oldVersion < 7) {
      try {
        await db.execute('ALTER TABLE $_tableName ADD COLUMN website TEXT DEFAULT ""');
      } catch (_) {}
    }
    if (oldVersion < 8) {
      try {
        await db.execute('ALTER TABLE $_tableName ADD COLUMN totp_secret TEXT DEFAULT ""');
      } catch (_) {}
    }
  }

  Database get _database {
    if (_db == null) throw StateError('DatabaseService not initialised.');
    return _db!;
  }

  // ─── CRUD ─────────────────────────────────────────────────────────────────

  Future<void> insertItem(VaultItem item) async {
    final map = _encryptItemMap(item);
    await _database.insert(
      _tableName,
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateItem(VaultItem item) async {
    final map = _encryptItemMap(item);
    await _database.update(
      _tableName,
      map,
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  Future<void> deleteItem(String id) async {
    await _database.delete(
      _tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Wipes all vault records from SQLite database
  Future<void> clearAllData() async {
    await _database.delete(_tableName);
  }

  Future<List<VaultItem>> getAllItems() async {
    final rows = await _database.query(
      _tableName,
      orderBy: 'bank_name COLLATE NOCASE ASC, nickname COLLATE NOCASE ASC',
    );
    return rows.map((row) => _decryptItemMap(row)).toList();
  }

  // ─── Backup & Restore (Encrypted) ──────────────────────────────────────────

  /// Serializes all items to JSON and encrypts the entire JSON payload using AES-256
  Future<String> exportEncryptedBackup() async {
    final items = await getAllItems();
    final list = items.map((i) => i.toMap()).toList();
    final jsonStr = json.encode({
      'version': 2,
      'exported_at': DateTime.now().toIso8601String(),
      'items': list,
    });
    return cryptoService.encrypt(jsonStr);
  }

  /// Decrypts the backup payload and restores all items to the database.
  /// Supports both Master Password-encrypted JSON backups and legacy backups.
  Future<int> importEncryptedBackup(String encryptedPayload, {String? masterPassword}) async {
    final trimmed = encryptedPayload.trim();

    // 1. Check if payload is encrypted with Master Password via SecureBackupExportService
    if (trimmed.startsWith('{') && (trimmed.contains('TETHERPASS_SECURE_BACKUP_V1') || trimmed.contains('CARDVAULT_SECURE_BACKUP_V1'))) {
      if (masterPassword == null || masterPassword.isEmpty) {
        throw MasterPasswordRequiredException(trimmed);
      }
      final items = SecureBackupExportService.importVaultWithPassword(
        backupPayload: trimmed,
        userPassword: masterPassword,
      );
      int count = 0;
      for (final item in items) {
        await insertItem(item);
        count++;
      }
      return count;
    }

    // 2. Legacy device-hardware-encrypted payload
    try {
      final jsonStr = cryptoService.decrypt(trimmed);
      final data = json.decode(jsonStr) as Map<String, dynamic>;
      final itemsList = data['items'] as List<dynamic>? ?? [];

      int count = 0;
      for (final raw in itemsList) {
        if (raw is Map<String, dynamic>) {
          final item = VaultItem.fromMap(raw);
          await insertItem(item);
          count++;
        }
      }
      return count;
    } on ArgumentError catch (e) {
      if (e.message.toString().toLowerCase().contains('pad block') ||
          e.toString().toLowerCase().contains('pad block')) {
        throw const FormatException(
          'Backup key mismatch. This file was encrypted with an older installation key. Please use "Import Backup from File" using your Master Password.',
        );
      }
      rethrow;
    } catch (e) {
      if (e.toString().toLowerCase().contains('pad block')) {
        throw const FormatException(
          'Backup key mismatch. Please restore using your Master Password.',
        );
      }
      rethrow;
    }
  }

  // ─── Encryption Helpers ───────────────────────────────────────────────────

  Map<String, dynamic> _encryptItemMap(VaultItem item) {
    return {
      'id': item.id,
      'type': item.type.name,
      'bank_name': item.bankName,
      'nickname': item.nickname,
      'notes': _safeEncrypt(item.notes),
      'created_at': item.createdAt.toIso8601String(),
      'updated_at': item.updatedAt.toIso8601String(),
      'website': _safeEncrypt(item.website),
      // Card
      'card_number': _safeEncrypt(item.cardNumber),
      'card_holder': item.cardHolder,
      'card_network': item.cardNetwork,
      'card_type': item.cardType,
      'expiry': item.expiry,
      'cvv': _safeEncrypt(item.cvv),
      'card_tier': item.cardTier.name,
      'credit_limit': item.creditLimit,
      'statement_day': item.statementDay,
      'due_day': item.dueDay,
      // NetBanking / Bank
      'account_number': _safeEncrypt(item.accountNumber),
      'ifsc_code': _safeEncrypt(item.ifscCode),
      'accounts': item.accounts.isNotEmpty ? _safeEncrypt(json.encode(item.accounts.map((a) => a.toMap()).toList())) : '',
      'user_id': _safeEncrypt(item.userId),
      'login_password': _safeEncrypt(item.loginPassword),
      'profile_password': _safeEncrypt(item.profilePassword),
      'mpin': _safeEncrypt(item.mpin),
      'cif_number': _safeEncrypt(item.cifNumber),
      'password_expiry_months': item.passwordExpiryMonths,
      'password_set_date': item.passwordSetDate?.toIso8601String(),
      'login_password_expiry': item.loginPasswordExpiry?.toIso8601String(),
      'profile_password_expiry': item.profilePasswordExpiry?.toIso8601String(),
      'mpin_expiry': item.mpinExpiry?.toIso8601String(),
      'totp_secret': _safeEncrypt(item.totpSecret),
    };
  }

  VaultItem _decryptItemMap(Map<String, dynamic> map) {
    return VaultItem(
      id: map['id'] as String,
      type: map['type'] == 'password'
          ? VaultItemType.password
          : (map['type'] == 'netBanking' ? VaultItemType.netBanking : VaultItemType.card),
      bankName: map['bank_name'] as String? ?? (map['type'] == 'password' ? 'Website Password' : 'Other Bank'),
      nickname: map['nickname'] as String? ?? 'My Item',
      notes: _safeDecrypt(map['notes'] as String?),
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ?? DateTime.now(),
      website: _safeDecrypt(map['website'] as String?),
      // Card
      cardNumber: _safeDecrypt(map['card_number'] as String?),
      cardHolder: map['card_holder'] as String? ?? '',
      cardNetwork: map['card_network'] as String? ?? 'Visa',
      cardType: map['card_type'] as String? ?? '',
      expiry: map['expiry'] as String? ?? '',
      cvv: _safeDecrypt(map['cvv'] as String?),
      cardTier: CardTier.values.firstWhere(
        (t) => t.name == map['card_tier'],
        orElse: () => CardTier.standard,
      ),
      creditLimit: (map['credit_limit'] as num?)?.toDouble() ?? 0.0,
      statementDay: (map['statement_day'] as num?)?.toInt() ?? 0,
      dueDay: (map['due_day'] as num?)?.toInt() ?? 0,
      // NetBanking / Bank
      accountNumber: _safeDecrypt(map['account_number'] as String?),
      ifscCode: _safeDecrypt(map['ifsc_code'] as String?),
      accounts: () {
        final raw = _safeDecrypt(map['accounts'] as String?);
        if (raw.isNotEmpty) {
          try {
            final list = json.decode(raw) as List;
            return list.map((e) => BankAccount.fromMap(Map<String, dynamic>.from(e as Map))).toList();
          } catch (_) {}
        }
        final acc = _safeDecrypt(map['account_number'] as String?);
        final ifsc = _safeDecrypt(map['ifsc_code'] as String?);
        if (acc.isNotEmpty || ifsc.isNotEmpty) {
          return [BankAccount(accountNumber: acc, ifscCode: ifsc)];
        }
        return <BankAccount>[];
      }(),
      userId: _safeDecrypt(map['user_id'] as String?),
      loginPassword: _safeDecrypt(map['login_password'] as String?),
      profilePassword: _safeDecrypt(map['profile_password'] as String?),
      mpin: _safeDecrypt(map['mpin'] as String?),
      cifNumber: _safeDecrypt(map['cif_number'] as String?),
      passwordExpiryMonths: (map['password_expiry_months'] as num?)?.toInt() ?? 3,
      passwordSetDate: map['password_set_date'] != null
          ? DateTime.tryParse(map['password_set_date'] as String)
          : null,
      loginPasswordExpiry: map['login_password_expiry'] != null
          ? DateTime.tryParse(map['login_password_expiry'] as String)
          : null,
      profilePasswordExpiry: map['profile_password_expiry'] != null
          ? DateTime.tryParse(map['profile_password_expiry'] as String)
          : null,
      mpinExpiry: map['mpin_expiry'] != null
          ? DateTime.tryParse(map['mpin_expiry'] as String)
          : null,
      totpSecret: _safeDecrypt(map['totp_secret'] as String?),
    );
  }

  String _safeEncrypt(String? text) {
    if (text == null || text.isEmpty) return '';
    return cryptoService.encrypt(text);
  }

  String _safeDecrypt(String? cipherText) {
    if (cipherText == null || cipherText.isEmpty) return '';
    try {
      return cryptoService.decrypt(cipherText);
    } catch (_) {
      return '';
    }
  }
}
