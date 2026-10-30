import 'dart:convert';

/// Represents a single stored credit / debit card.
class CardModel {
  final String id;

  /// Plaintext card number (16 or 15 digits). Stored encrypted in DB.
  final String cardNumber;
  final String cardHolder;
  final int expiryMonth;
  final int expiryYear;

  /// Plaintext CVV (3–4 digits). Stored encrypted in DB.
  final String cvv;

  final String cardType;   // e.g. 'Visa', 'Mastercard', 'Amex', …
  final String bankName;   // e.g. 'HDFC', 'Chase', 'Unknown'
  final List<String> bankColors; // gradient hex list
  final String networkLogoEmoji;

  final DateTime createdAt;
  final DateTime updatedAt;

  const CardModel({
    required this.id,
    required this.cardNumber,
    required this.cardHolder,
    required this.expiryMonth,
    required this.expiryYear,
    required this.cvv,
    required this.cardType,
    required this.bankName,
    required this.bankColors,
    required this.networkLogoEmoji,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Returns the card number masked as "•••• •••• •••• 1234".
  String get maskedNumber {
    if (cardNumber.length <= 4) return cardNumber;
    final last4 = cardNumber.substring(cardNumber.length - 4);
    if (cardNumber.length == 15) {
      // Amex: 4-6-5 layout
      return '•••• •••••• $last4';
    }
    return '•••• •••• •••• $last4';
  }

  /// Returns the formatted expiry as "MM/YY".
  String get formattedExpiry {
    final mm = expiryMonth.toString().padLeft(2, '0');
    final yy = (expiryYear % 100).toString().padLeft(2, '0');
    return '$mm/$yy';
  }

  /// Whether the card is expired.
  bool get isExpired {
    final now = DateTime.now();
    final expiry = DateTime(expiryYear, expiryMonth + 1, 1);
    return now.isAfter(expiry);
  }

  CardModel copyWith({
    String? id,
    String? cardNumber,
    String? cardHolder,
    int? expiryMonth,
    int? expiryYear,
    String? cvv,
    String? cardType,
    String? bankName,
    List<String>? bankColors,
    String? networkLogoEmoji,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CardModel(
      id: id ?? this.id,
      cardNumber: cardNumber ?? this.cardNumber,
      cardHolder: cardHolder ?? this.cardHolder,
      expiryMonth: expiryMonth ?? this.expiryMonth,
      expiryYear: expiryYear ?? this.expiryYear,
      cvv: cvv ?? this.cvv,
      cardType: cardType ?? this.cardType,
      bankName: bankName ?? this.bankName,
      bankColors: bankColors ?? this.bankColors,
      networkLogoEmoji: networkLogoEmoji ?? this.networkLogoEmoji,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // ─── Serialisation ─────────────────────────────────────────────────────────

  /// Converts to a map for SQLite storage.
  /// [encryptedNumber] and [encryptedCvv] are ciphertext blobs.
  Map<String, dynamic> toDbMap({
    required String encryptedNumber,
    required String encryptedCvv,
  }) {
    return {
      'id': id,
      'card_number': encryptedNumber,
      'card_holder': cardHolder,
      'expiry_month': expiryMonth,
      'expiry_year': expiryYear,
      'cvv': encryptedCvv,
      'card_type': cardType,
      'bank_name': bankName,
      'bank_colors': jsonEncode(bankColors),
      'network_logo_emoji': networkLogoEmoji,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  /// Creates a [CardModel] from a DB row. Requires already-decrypted fields.
  factory CardModel.fromDbMap(
    Map<String, dynamic> map, {
    required String decryptedNumber,
    required String decryptedCvv,
  }) {
    return CardModel(
      id: map['id'] as String,
      cardNumber: decryptedNumber,
      cardHolder: map['card_holder'] as String,
      expiryMonth: map['expiry_month'] as int,
      expiryYear: map['expiry_year'] as int,
      cvv: decryptedCvv,
      cardType: map['card_type'] as String,
      bankName: map['bank_name'] as String,
      bankColors: List<String>.from(
        jsonDecode(map['bank_colors'] as String) as List,
      ),
      networkLogoEmoji: map['network_logo_emoji'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }

  /// Converts to a JSON-serialisable map (plaintext — for Drive backup).
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cardNumber': cardNumber,
      'cardHolder': cardHolder,
      'expiryMonth': expiryMonth,
      'expiryYear': expiryYear,
      'cvv': cvv,
      'cardType': cardType,
      'bankName': bankName,
      'bankColors': bankColors,
      'networkLogoEmoji': networkLogoEmoji,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory CardModel.fromJson(Map<String, dynamic> json) {
    return CardModel(
      id: json['id'] as String,
      cardNumber: json['cardNumber'] as String,
      cardHolder: json['cardHolder'] as String,
      expiryMonth: json['expiryMonth'] as int,
      expiryYear: json['expiryYear'] as int,
      cvv: json['cvv'] as String,
      cardType: json['cardType'] as String,
      bankName: json['bankName'] as String,
      bankColors: List<String>.from(json['bankColors'] as List),
      networkLogoEmoji: json['networkLogoEmoji'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CardModel && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'CardModel(id: $id, cardHolder: $cardHolder, type: $cardType)';
}
