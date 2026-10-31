import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/card_detector.dart';

enum VaultItemType { card, netBanking, password }

enum CardTier { standard, gold, platinum, infinite, signature }

extension CardTierExtension on CardTier {
  String get displayName {
    switch (this) {
      case CardTier.standard:
        return 'Standard';
      case CardTier.gold:
        return 'Gold';
      case CardTier.platinum:
        return 'Platinum';
      case CardTier.infinite:
        return 'Infinite';
      case CardTier.signature:
        return 'Signature';
    }
  }

  List<Color> get gradientColors {
    switch (this) {
      case CardTier.gold:
        return [const Color(0xFFD4AF37), const Color(0xFFAA771C), const Color(0xFF432A02)];
      case CardTier.platinum:
        return [const Color(0xFFE5E4E2), const Color(0xFF9E9E9E), const Color(0xFF37474F)];
      case CardTier.infinite:
        return [const Color(0xFF1E1E24), const Color(0xFF101014), const Color(0xFF000000)];
      case CardTier.signature:
        return [const Color(0xFF4A148C), const Color(0xFF6A1B9A), const Color(0xFF1A0933)];
      case CardTier.standard:
        return [const Color(0xFF1A237E), const Color(0xFF283593), const Color(0xFF0D123D)];
    }
  }
}

/// Represents an individual bank account (Account Number + IFSC Code)
class BankAccount {
  final String accountNumber;
  final String ifscCode;
  final String label;

  const BankAccount({
    required this.accountNumber,
    required this.ifscCode,
    this.label = '',
  });

  String get maskedAccountNumber {
    final clean = accountNumber.replaceAll(' ', '');
    if (clean.isEmpty) return '—';
    if (clean.length <= 4) return clean;
    final last4 = clean.substring(clean.length - 4);
    return '•••• $last4';
  }

  Map<String, dynamic> toMap() => {
    'account_number': accountNumber,
    'ifsc_code': ifscCode,
    'label': label,
  };

  factory BankAccount.fromMap(Map<String, dynamic> map) => BankAccount(
    accountNumber: map['account_number'] as String? ?? '',
    ifscCode: map['ifsc_code'] as String? ?? '',
    label: map['label'] as String? ?? '',
  );
}

/// Base class / union for Vault Items (Cards & NetBanking)
class VaultItem {
  final String id;
  final VaultItemType type;
  final String bankName;
  final String nickname;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String website; // URL or domain for website passwords / bank portals

  // ── Card Specific Fields ──
  final String cardNumber; // Plaintext when in memory, encrypted in DB
  final String cardHolder;
  final String cardNetwork; // Visa, Mastercard, RuPay, Amex, etc.
  final String cardType; // 'Credit', 'Debit', or ''
  final String expiry; // MM/YY
  final String cvv; // Plaintext when in memory, encrypted in DB
  final CardTier cardTier;
  final double creditLimit; // 0.0 if not set
  final int statementDay; // Day of month (1-31), 0 if not set
  final int dueDay; // Day of month (1-31), 0 if not set

  // ── NetBanking / Bank Specific Fields ──
  final String accountNumber; // Plaintext in memory, encrypted in DB (primary account)
  final String ifscCode; // Plaintext in memory, encrypted in DB (primary IFSC)
  final List<BankAccount> accounts; // All associated bank accounts
  final String userId; // Plaintext in memory, encrypted in DB
  final String loginPassword; // Plaintext in memory, encrypted in DB
  final String profilePassword; // Plaintext in memory, encrypted in DB
  final String mpin; // Plaintext in memory, encrypted in DB
  final String cifNumber; // Plaintext in memory, encrypted in DB
  final int passwordExpiryMonths; // 1, 2, 3, 6, 12 months (retained for backward compat)
  final DateTime? passwordSetDate;
  final DateTime? loginPasswordExpiry;
  final DateTime? profilePasswordExpiry;
  final DateTime? mpinExpiry;
  final String totpSecret; // Base32 2FA authenticator secret key (RFC 6238)

  VaultItem({
    required this.id,
    required this.type,
    required this.bankName,
    required this.nickname,
    this.notes = '',
    required this.createdAt,
    required this.updatedAt,
    this.website = '',
    // Card
    this.cardNumber = '',
    this.cardHolder = '',
    this.cardNetwork = 'Visa',
    this.cardType = 'Credit',
    this.expiry = '',
    this.cvv = '',
    this.cardTier = CardTier.standard,
    this.creditLimit = 0.0,
    this.statementDay = 0,
    this.dueDay = 0,
    // Bank / NetBanking
    this.accountNumber = '',
    this.ifscCode = '',
    this.accounts = const [],
    this.userId = '',
    this.loginPassword = '',
    this.profilePassword = '',
    this.mpin = '',
    this.cifNumber = '',
    this.passwordExpiryMonths = 3,
    this.passwordSetDate,
    this.loginPasswordExpiry,
    this.profilePasswordExpiry,
    this.mpinExpiry,
    this.totpSecret = '',
  });

  bool get isCard => type == VaultItemType.card;
  bool get isNetBanking => type == VaultItemType.netBanking;
  bool get isBank => type == VaultItemType.netBanking;
  bool get isPassword => type == VaultItemType.password;
  bool get hasTotp => totpSecret.trim().isNotEmpty;
  String get username => isPassword ? userId : '';
  String get password => isPassword ? loginPassword : '';

  /// Returns list of all bank accounts (at least one if accountNumber is present)
  List<BankAccount> get allAccounts {
    if (accounts.isNotEmpty) return accounts;
    if (accountNumber.isNotEmpty || ifscCode.isNotEmpty) {
      return [BankAccount(accountNumber: accountNumber, ifscCode: ifscCode)];
    }
    return const [];
  }

  /// Returns masked account number (e.g. •••• 1234)
  String get maskedAccountNumber {
    final target = accountNumber.isNotEmpty
        ? accountNumber
        : (accounts.isNotEmpty ? accounts.first.accountNumber : '');
    final clean = target.replaceAll(' ', '');
    if (clean.isEmpty) return '—';
    if (clean.length <= 4) return clean;
    final last4 = clean.substring(clean.length - 4);
    return '•••• $last4';
  }

  bool get isDebit {
    if (!isCard) return false;
    final lower = cardType.toLowerCase().trim();
    if (lower.contains('debit') || lower.contains('prepaid')) return true;
    if (lower.contains('credit') || lower.contains('charge')) return false;
    if (cardNumber.replaceAll(RegExp(r'\D'), '').length >= 6) {
      final inferred = CardDetector.detectCardType(cardNumber);
      if (inferred.toLowerCase().contains('debit')) return true;
    }
    return false;
  }

  bool get isCredit => isCard && !isDebit;

  /// Returns masked card number (e.g. •••• •••• •••• 1234)
  String get maskedCardNumber {
    final clean = cardNumber.replaceAll(' ', '');
    if (clean.length <= 4) return clean;
    final last4 = clean.substring(clean.length - 4);
    if (clean.length == 15) {
      return '•••• •••••• $last4';
    }
    return '•••• •••• •••• $last4';
  }

  /// Days remaining for Login Password
  int? get loginPasswordDaysRemaining {
    if (!isNetBanking) return null;
    DateTime? exp = loginPasswordExpiry;
    if (exp == null && passwordSetDate != null && passwordExpiryMonths > 0) {
      exp = DateTime(passwordSetDate!.year, passwordSetDate!.month + passwordExpiryMonths, passwordSetDate!.day);
    }
    if (exp == null) return null;
    return exp.difference(DateTime.now()).inDays;
  }

  /// Days remaining for Profile / Transaction Password
  int? get profilePasswordDaysRemaining {
    if (!isNetBanking || profilePasswordExpiry == null) return null;
    return profilePasswordExpiry!.difference(DateTime.now()).inDays;
  }

  /// Days remaining for MPIN
  int? get mpinDaysRemaining {
    if (!isNetBanking || mpinExpiry == null) return null;
    return mpinExpiry!.difference(DateTime.now()).inDays;
  }

  bool get isLoginPasswordExpired {
    final d = loginPasswordDaysRemaining;
    return d != null && d < 0;
  }

  bool get isProfilePasswordExpired {
    final d = profilePasswordDaysRemaining;
    return d != null && d < 0;
  }

  bool get isMpinExpired {
    final d = mpinDaysRemaining;
    return d != null && d < 0;
  }

  bool get isLoginPasswordExpiringSoon {
    final d = loginPasswordDaysRemaining;
    return d != null && d >= 0 && d <= 15;
  }

  bool get isProfilePasswordExpiringSoon {
    final d = profilePasswordDaysRemaining;
    return d != null && d >= 0 && d <= 15;
  }

  bool get isMpinExpiringSoon {
    final d = mpinDaysRemaining;
    return d != null && d >= 0 && d <= 15;
  }

  /// Any NetBanking password is expired
  bool get isAnyPasswordExpired => isLoginPasswordExpired || isProfilePasswordExpired || isMpinExpired;

  /// Any NetBanking password is close to expiry (within 15 days)
  bool get isAnyPasswordExpiringSoon => isLoginPasswordExpiringSoon || isProfilePasswordExpiringSoon || isMpinExpiringSoon;

  /// Legacy getter for backwards compatibility
  bool get isPasswordExpiringSoon => isAnyPasswordExpired || isAnyPasswordExpiringSoon;

  /// Calculates legacy password expiry remaining days for NetBanking
  int? get passwordDaysRemaining => loginPasswordDaysRemaining;

  /// Expiry status of the card:
  /// returns days remaining until expiry, negative if already expired.
  int? get cardExpiryDaysRemaining {
    if (!isCard || expiry.isEmpty || !expiry.contains('/')) return null;
    final parts = expiry.split('/');
    if (parts.length != 2) return null;
    final month = int.tryParse(parts[0]);
    final yearPart = int.tryParse(parts[1]);
    if (month == null || yearPart == null || month < 1 || month > 12) return null;
    final fullYear = yearPart < 100 ? 2000 + yearPart : yearPart;
    // Expiry date is the last day of the given month
    final lastDay = DateTime(fullYear, month + 1, 0, 23, 59, 59);
    return lastDay.difference(DateTime.now()).inDays;
  }

  /// True if card is already expired
  bool get isCardExpired {
    final days = cardExpiryDaysRemaining;
    return days != null && days < 0;
  }

  /// True if card expires in 2 to 3 months (within 90 days)
  bool get isCardExpiringSoon {
    final days = cardExpiryDaysRemaining;
    return days != null && days >= 0 && days <= 90;
  }

  /// Formatted expiry warning message
  String? get expiryStatusMessage {
    final days = cardExpiryDaysRemaining;
    if (days == null) return null;
    if (days < 0) return 'Card Expired';
    if (days == 0) return 'Expires Today';
    if (days <= 30) return 'Expires in $days days';
    if (days <= 45) return 'Expires next month';
    return null;
  }

  /// Next bill generation (statement) date calculation
  DateTime? get nextStatementDate {
    if (statementDay <= 0 || statementDay > 31) return null;
    final now = DateTime.now();
    final thisMonthDay = statementDay > DateTime(now.year, now.month + 1, 0).day
        ? DateTime(now.year, now.month + 1, 0).day
        : statementDay;
    final thisMonth = DateTime(now.year, now.month, thisMonthDay);
    if (now.isBefore(thisMonth) || now.isAtSameMomentAs(thisMonth)) {
      return thisMonth;
    }
    final nextMonthDay = statementDay > DateTime(now.year, now.month + 2, 0).day
        ? DateTime(now.year, now.month + 2, 0).day
        : statementDay;
    return DateTime(now.year, now.month + 1, nextMonthDay);
  }

  /// Next payment due date calculation
  DateTime? get nextDueDate {
    if (dueDay <= 0 || dueDay > 31) return null;
    final now = DateTime.now();
    final thisMonthDay = dueDay > DateTime(now.year, now.month + 1, 0).day
        ? DateTime(now.year, now.month + 1, 0).day
        : dueDay;
    final thisMonth = DateTime(now.year, now.month, thisMonthDay);
    if (now.isBefore(thisMonth) || now.isAtSameMomentAs(thisMonth)) {
      return thisMonth;
    }
    final nextMonthDay = dueDay > DateTime(now.year, now.month + 2, 0).day
        ? DateTime(now.year, now.month + 2, 0).day
        : dueDay;
    return DateTime(now.year, now.month + 1, nextMonthDay);
  }

  /// Days remaining until payment due date
  int? get daysUntilPaymentDue {
    final due = nextDueDate;
    if (due == null) return null;
    return due.difference(DateTime.now()).inDays;
  }

  VaultItem copyWith({
    String? id,
    VaultItemType? type,
    String? bankName,
    String? nickname,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? website,
    String? cardNumber,
    String? cardHolder,
    String? cardNetwork,
    String? cardType,
    String? expiry,
    String? cvv,
    CardTier? cardTier,
    double? creditLimit,
    int? statementDay,
    int? dueDay,
    String? accountNumber,
    String? ifscCode,
    List<BankAccount>? accounts,
    String? userId,
    String? loginPassword,
    String? profilePassword,
    String? mpin,
    String? cifNumber,
    int? passwordExpiryMonths,
    DateTime? passwordSetDate,
    DateTime? loginPasswordExpiry,
    DateTime? profilePasswordExpiry,
    DateTime? mpinExpiry,
    String? totpSecret,
  }) {
    return VaultItem(
      id: id ?? this.id,
      type: type ?? this.type,
      bankName: bankName ?? this.bankName,
      nickname: nickname ?? this.nickname,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      website: website ?? this.website,
      cardNumber: cardNumber ?? this.cardNumber,
      cardHolder: cardHolder ?? this.cardHolder,
      cardNetwork: cardNetwork ?? this.cardNetwork,
      cardType: cardType ?? this.cardType,
      expiry: expiry ?? this.expiry,
      cvv: cvv ?? this.cvv,
      cardTier: cardTier ?? this.cardTier,
      creditLimit: creditLimit ?? this.creditLimit,
      statementDay: statementDay ?? this.statementDay,
      dueDay: dueDay ?? this.dueDay,
      accountNumber: accountNumber ?? this.accountNumber,
      ifscCode: ifscCode ?? this.ifscCode,
      accounts: accounts ?? this.accounts,
      userId: userId ?? this.userId,
      loginPassword: loginPassword ?? this.loginPassword,
      profilePassword: profilePassword ?? this.profilePassword,
      mpin: mpin ?? this.mpin,
      cifNumber: cifNumber ?? this.cifNumber,
      passwordExpiryMonths: passwordExpiryMonths ?? this.passwordExpiryMonths,
      passwordSetDate: passwordSetDate ?? this.passwordSetDate,
      loginPasswordExpiry: loginPasswordExpiry ?? this.loginPasswordExpiry,
      profilePasswordExpiry: profilePasswordExpiry ?? this.profilePasswordExpiry,
      mpinExpiry: mpinExpiry ?? this.mpinExpiry,
      totpSecret: totpSecret ?? this.totpSecret,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type.name,
      'bank_name': bankName,
      'nickname': nickname,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'website': website,
      'card_number': cardNumber,
      'card_holder': cardHolder,
      'card_network': cardNetwork,
      'card_type': cardType,
      'expiry': expiry,
      'cvv': cvv,
      'card_tier': cardTier.name,
      'credit_limit': creditLimit,
      'statement_day': statementDay,
      'due_day': dueDay,
      'account_number': accountNumber,
      'ifsc_code': ifscCode,
      'accounts': json.encode(allAccounts.map((a) => a.toMap()).toList()),
      'user_id': userId,
      'login_password': loginPassword,
      'profile_password': profilePassword,
      'mpin': mpin,
      'cif_number': cifNumber,
      'password_expiry_months': passwordExpiryMonths,
      'password_set_date': passwordSetDate?.toIso8601String(),
      'login_password_expiry': loginPasswordExpiry?.toIso8601String(),
      'profile_password_expiry': profilePasswordExpiry?.toIso8601String(),
      'mpin_expiry': mpinExpiry?.toIso8601String(),
      'totp_secret': totpSecret,
    };
  }

  factory VaultItem.fromMap(Map<String, dynamic> map) {
    return VaultItem(
      id: map['id'] as String,
      type: map['type'] == 'password'
          ? VaultItemType.password
          : (map['type'] == 'netBanking' ? VaultItemType.netBanking : VaultItemType.card),
      bankName: map['bank_name'] as String? ?? (map['type'] == 'password' ? 'Website Password' : 'Other Bank'),
      nickname: map['nickname'] as String? ?? 'My Item',
      notes: map['notes'] as String? ?? '',
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ?? DateTime.now(),
      website: map['website'] as String? ?? '',
      cardNumber: map['card_number'] as String? ?? '',
      cardHolder: map['card_holder'] as String? ?? '',
      cardNetwork: map['card_network'] as String? ?? 'Visa',
      cardType: map['card_type'] as String? ?? '',
      expiry: map['expiry'] as String? ?? '',
      cvv: map['cvv'] as String? ?? '',
      cardTier: CardTier.values.firstWhere(
        (t) => t.name == map['card_tier'],
        orElse: () => CardTier.standard,
      ),
      creditLimit: (map['credit_limit'] as num?)?.toDouble() ?? 0.0,
      statementDay: (map['statement_day'] as num?)?.toInt() ?? 0,
      dueDay: (map['due_day'] as num?)?.toInt() ?? 0,
      accountNumber: map['account_number'] as String? ?? '',
      ifscCode: map['ifsc_code'] as String? ?? '',
      accounts: () {
        if (map['accounts'] != null) {
          try {
            final raw = map['accounts'];
            final list = raw is String ? (json.decode(raw) as List) : (raw as List);
            return list.map((e) => BankAccount.fromMap(Map<String, dynamic>.from(e as Map))).toList();
          } catch (_) {}
        }
        final acc = map['account_number'] as String? ?? '';
        final ifsc = map['ifsc_code'] as String? ?? '';
        if (acc.isNotEmpty || ifsc.isNotEmpty) {
          return [BankAccount(accountNumber: acc, ifscCode: ifsc)];
        }
        return <BankAccount>[];
      }(),
      userId: map['user_id'] as String? ?? '',
      loginPassword: map['login_password'] as String? ?? '',
      profilePassword: map['profile_password'] as String? ?? '',
      mpin: map['mpin'] as String? ?? '',
      cifNumber: map['cif_number'] as String? ?? '',
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
      totpSecret: map['totp_secret'] as String? ?? '',
    );
  }

  String toJson() => json.encode(toMap());
  factory VaultItem.fromJson(String source) => VaultItem.fromMap(json.decode(source));
}
