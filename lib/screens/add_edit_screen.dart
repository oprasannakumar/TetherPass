import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/vault_item.dart';
import '../services/bin_database_service.dart';
import '../services/card_detector.dart';
import '../services/card_scanner_service.dart';
import '../services/database_service.dart';
import '../services/drive_service.dart';
import '../services/nfc_card_scanner_service.dart';
import '../services/totp_service.dart';
import '../widgets/card_input_formatter.dart';
import '../widgets/card_widget.dart';
import '../widgets/totp_qr_scanner_dialog.dart';

class AddEditScreen extends StatefulWidget {
  final VaultItem? initialItem;

  const AddEditScreen({super.key, this.initialItem});

  @override
  State<AddEditScreen> createState() => _AddEditScreenState();
}

class BankAccountRowControllers {
  final TextEditingController accountCtrl;
  final TextEditingController ifscCtrl;
  String? accountError;
  String? ifscError;

  BankAccountRowControllers({
    required this.accountCtrl,
    required this.ifscCtrl,
    this.accountError,
    this.ifscError,
  });

  void dispose() {
    accountCtrl.dispose();
    ifscCtrl.dispose();
  }
}

class _AddEditScreenState extends State<AddEditScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // ── Card controllers ──
  final _cardNicknameCtrl = TextEditingController();
  final _cardBankCtrl = TextEditingController();
  final _cardNumberCtrl = TextEditingController();
  final _cardHolderCtrl = TextEditingController();
  final _cardExpiryCtrl = TextEditingController();
  final _cardCvvCtrl = TextEditingController();
  final _cardNotesCtrl = TextEditingController();
  final _creditLimitCtrl = TextEditingController();

  // ── Focus Nodes for Auto Clipboard Detection on Cursor Landing ──
  final _cardNumberFocusNode = FocusNode();
  final _cardHolderFocusNode = FocusNode();
  final _cardExpiryFocusNode = FocusNode();
  final _cardCvvFocusNode = FocusNode();
  int _statementDay = 0;
  int _dueDay = 0;
  String _cardNetwork = 'Visa';
  String _cardType = 'Credit'; // 'Credit' or 'Debit'
  CardTier _cardTier = CardTier.standard;
  bool _isLuhnValid = false;
  bool _networkAutoDetected = false;
  bool _bankAutoDetected = false;
  bool _tierAutoDetected = false;
  bool _cardTypeAutoDetected = false;

  static const List<String> _availableNetworks = [
    'RuPay',
    'Visa',
    'Mastercard',
    'Amex',
    'Discover',
    'Diners',
    'JCB',
    'UnionPay',
    'Maestro',
  ];

  // ── Bank controllers ──
  final _nbBankCtrl = TextEditingController();
  final _nbNicknameCtrl = TextEditingController();
  final List<BankAccountRowControllers> _accountRowControllers = [];
  final _nbUserIdCtrl = TextEditingController();
  final _nbLoginPasswordCtrl = TextEditingController();
  final _nbProfilePasswordCtrl = TextEditingController();
  final _nbMpinCtrl = TextEditingController();
  final _nbCifCtrl = TextEditingController();
  final _nbNotesCtrl = TextEditingController();
  int _nbExpiryMonths = 3;
  DateTime? _loginPasswordExpiry;
  DateTime? _profilePasswordExpiry;
  DateTime? _mpinExpiry;

  // ── Password Manager controllers ──
  final _pwdNicknameCtrl = TextEditingController();
  final _pwdWebsiteCtrl = TextEditingController();
  final _pwdUsernameCtrl = TextEditingController();
  final _pwdPasswordCtrl = TextEditingController();
  final _pwdTotpCtrl = TextEditingController();
  final _pwdNotesCtrl = TextEditingController();
  bool _pwdPasswordVisible = false;

  // ── Validation Errors ──
  String? _cardNicknameError;
  String? _cardBankError;
  String? _cardNumberError;
  String? _cardExpiryError;
  String? _cardCvvError;

  String? _nbBankError;
  String? _nbNicknameError;
  String? _nbUserIdError;
  String? _nbLoginPasswordError;

  String? _pwdNicknameError;
  String? _pwdWebsiteError;
  String? _pwdUsernameError;
  String? _pwdPasswordError;

  bool _isSaving = false;

  // Tour keys for Add/Edit Form
  final GlobalKey _tabBarKey = GlobalKey();
  final GlobalKey _cardTypeKey = GlobalKey();
  final GlobalKey _cardNumberKey = GlobalKey();
  final GlobalKey _nbBankSectionKey = GlobalKey();
  final GlobalKey _nbAccountsSectionKey = GlobalKey();
  final GlobalKey _nbAddAccountBtnKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    int initialTab = 0;
    if (widget.initialItem?.isPassword ?? false) {
      initialTab = 2;
    } else if (widget.initialItem?.isNetBanking ?? false) {
      initialTab = 1;
    }
    _tabController = TabController(length: 3, vsync: this, initialIndex: initialTab);

    if (widget.initialItem != null) {
      final it = widget.initialItem!;
      if (it.isPassword) {
        _pwdNicknameCtrl.text = it.nickname;
        _pwdWebsiteCtrl.text = it.website;
        _pwdUsernameCtrl.text = it.userId;
        _pwdPasswordCtrl.text = it.loginPassword;
        _pwdTotpCtrl.text = it.totpSecret;
        _pwdNotesCtrl.text = it.notes;
      } else if (it.isCard) {
        _cardNicknameCtrl.text = it.nickname;
        _cardBankCtrl.text = it.bankName;
        _cardNumberCtrl.text = it.cardNumber;
        _cardHolderCtrl.text = it.cardHolder;
        _cardExpiryCtrl.text = it.expiry;
        _cardCvvCtrl.text = it.cvv;
        _cardNotesCtrl.text = it.notes;
        if (it.creditLimit > 0) {
          _creditLimitCtrl.text = formatIndianNumber(it.creditLimit);
        }
        _statementDay = it.statementDay;
        _dueDay = it.dueDay;
        _cardNetwork = it.cardNetwork;
        _cardType = it.isDebit ? 'Debit' : 'Credit';
        _cardTier = it.cardTier;
        _isLuhnValid = CardDetector.isValidLuhn(it.cardNumber);
      } else {
        _nbBankCtrl.text = it.bankName;
        _nbNicknameCtrl.text = it.nickname;
        _nbUserIdCtrl.text = it.userId;
        _nbLoginPasswordCtrl.text = it.loginPassword;
        _nbProfilePasswordCtrl.text = it.profilePassword;
        _nbMpinCtrl.text = it.mpin;
        _nbCifCtrl.text = it.cifNumber;
        _nbNotesCtrl.text = it.notes;
        _nbExpiryMonths = it.passwordExpiryMonths;
        _loginPasswordExpiry = it.loginPasswordExpiry;
        if (_loginPasswordExpiry == null && it.passwordSetDate != null && it.passwordExpiryMonths > 0) {
          _loginPasswordExpiry = DateTime(it.passwordSetDate!.year, it.passwordSetDate!.month + it.passwordExpiryMonths, it.passwordSetDate!.day);
        }
        _profilePasswordExpiry = it.profilePasswordExpiry;
        _mpinExpiry = it.mpinExpiry;

        if (it.allAccounts.isNotEmpty) {
          for (final acc in it.allAccounts) {
            _accountRowControllers.add(BankAccountRowControllers(
              accountCtrl: TextEditingController(text: acc.accountNumber),
              ifscCtrl: TextEditingController(text: acc.ifscCode),
            ));
          }
        }
      }
    }

    if (_accountRowControllers.isEmpty) {
      _accountRowControllers.add(BankAccountRowControllers(
        accountCtrl: TextEditingController(),
        ifscCtrl: TextEditingController(),
      ));
    }

    _cardNumberCtrl.addListener(_onCardNumberChanged);

    // Attach FocusNode listeners for clipboard auto-detection on cursor focus
    _cardNumberFocusNode.addListener(() {
      if (_cardNumberFocusNode.hasFocus) {
        _checkClipboardForCardNumber();
      }
    });
    _cardHolderFocusNode.addListener(() {
      if (_cardHolderFocusNode.hasFocus) {
        _checkClipboardForCardholderName();
      }
    });
    _cardExpiryFocusNode.addListener(() {
      if (_cardExpiryFocusNode.hasFocus) {
        _checkClipboardForExpiry();
      }
    });
    _cardCvvFocusNode.addListener(() {
      if (_cardCvvFocusNode.hasFocus) {
        _checkClipboardForCvv();
      }
    });
  }

  @override
  void dispose() {
    _cardNumberCtrl.removeListener(_onCardNumberChanged);
    _cardNumberFocusNode.dispose();
    _cardHolderFocusNode.dispose();
    _cardExpiryFocusNode.dispose();
    _cardCvvFocusNode.dispose();
    _tabController.dispose();
    _cardNicknameCtrl.dispose();
    _cardBankCtrl.dispose();
    _cardNumberCtrl.dispose();
    _cardHolderCtrl.dispose();
    _cardExpiryCtrl.dispose();
    _cardCvvCtrl.dispose();
    _cardNotesCtrl.dispose();
    _creditLimitCtrl.dispose();
    _nbBankCtrl.dispose();
    _nbNicknameCtrl.dispose();
    for (final row in _accountRowControllers) {
      row.dispose();
    }
    _nbUserIdCtrl.dispose();
    _nbLoginPasswordCtrl.dispose();
    _nbProfilePasswordCtrl.dispose();
    _nbMpinCtrl.dispose();
    _nbCifCtrl.dispose();
    _nbNotesCtrl.dispose();
    _pwdNicknameCtrl.dispose();
    _pwdWebsiteCtrl.dispose();
    _pwdUsernameCtrl.dispose();
    _pwdPasswordCtrl.dispose();
    _pwdTotpCtrl.dispose();
    _pwdNotesCtrl.dispose();
    super.dispose();
  }

  void _onCardNumberChanged() {
    final raw = _cardNumberCtrl.text.replaceAll(' ', '');
    final detectedNet = CardDetector.detectNetwork(raw);
    final detectedBank = CardDetector.detectBank(raw);
    final detectedTier = CardDetector.detectTier(raw);
    final validLuhn = CardDetector.isValidLuhn(raw);

    setState(() {
      if (detectedNet != 'Unknown') {
        _cardNetwork = detectedNet;
        _networkAutoDetected = true;
      } else {
        _networkAutoDetected = false;
      }

      if (detectedBank != 'Unknown' && (_cardBankCtrl.text.isEmpty || _bankAutoDetected)) {
        _cardBankCtrl.text = detectedBank;
        _bankAutoDetected = true;
      }

      if (_tierAutoDetected || widget.initialItem == null) {
        _cardTier = detectedTier;
        _tierAutoDetected = true;
      }

      final detectedType = CardDetector.detectCardType(raw);
      if (detectedType != 'Unknown' && (_cardTypeAutoDetected || widget.initialItem == null)) {
        _cardType = detectedType;
        _cardTypeAutoDetected = true;
      }

      _isLuhnValid = validLuhn;
    });

    // ── Deep BIN lookup from bundled 374,000+ BIN Database ──
    if (raw.length >= 6) {
      BinDatabaseService.lookup(raw).then((record) {
        if (!mounted || record == null) return;
        // Verify current card number still matches to avoid race conditions
        final currentRaw = _cardNumberCtrl.text.replaceAll(' ', '');
        if (!currentRaw.startsWith(record.bin)) return;

        setState(() {
          if (record.brand != null && record.brand != 'Unknown') {
            if (_availableNetworks.contains(record.brand)) {
              _cardNetwork = record.brand!;
              _networkAutoDetected = true;
            }
          }
          if (record.issuer != null && record.issuer!.isNotEmpty && (_cardBankCtrl.text.isEmpty || _bankAutoDetected)) {
            _cardBankCtrl.text = record.issuer!;
            _bankAutoDetected = true;
          }
          if (record.tier != CardTier.standard && (_tierAutoDetected || widget.initialItem == null)) {
            _cardTier = record.tier;
            _tierAutoDetected = true;
          }
          if (record.cardType != null && record.cardType!.isNotEmpty && (_cardTypeAutoDetected || widget.initialItem == null)) {
            _cardType = record.cardType!.toLowerCase().contains('debit') ? 'Debit' : 'Credit';
            _cardTypeAutoDetected = true;
          }
        });
      });
    }
  }

  Future<void> _startCardScan() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              const Text('Smart Card Scanner', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
              const SizedBox(height: 8),
              const Text('Securely scan physical card details on-device using NFC tap, camera, or gallery photo.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFF10B981).withValues(alpha: 0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.contactless_rounded, color: Color(0xFF10B981)),
                ),
                title: const Text('Tap Contactless Card (NFC)', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                subtitle: const Text('Hold physical card against the back of phone to scan EMV chip', style: TextStyle(fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  _startNfcScan();
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFFFF6F00).withValues(alpha: 0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.camera_alt_rounded, color: Color(0xFFFF6F00)),
                ),
                title: const Text('Scan with Camera', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                subtitle: const Text('Point your phone camera at the front of your card', style: TextStyle(fontSize: 12)),
                onTap: () async {
                  Navigator.pop(ctx);
                  _processScan(await CardScannerService.scanCardFromCamera());
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.photo_library_rounded, color: Colors.blue),
                ),
                title: const Text('Pick from Gallery', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                subtitle: const Text('Select a saved card image or screenshot', style: TextStyle(fontSize: 12)),
                onTap: () async {
                  Navigator.pop(ctx);
                  _processScan(await CardScannerService.scanCardFromGallery());
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _scanTotpQrCode() async {
    final result = await TotpQrScannerDialog.scan(context);
    if (result != null) {
      setState(() {
        _pwdTotpCtrl.text = result.secret;
        if (result.issuer != null && _pwdNicknameCtrl.text.trim().isEmpty) {
          _pwdNicknameCtrl.text = result.issuer!;
        }
        if (result.account != null && _pwdUsernameCtrl.text.trim().isEmpty) {
          _pwdUsernameCtrl.text = result.account!;
        }
      });
      if (mounted) {
        final code = TotpService.generateCode(result.secret);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF0F172A),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '2FA Authenticator configured! Active code: $code',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }
  }

  Future<void> _startNfcScan() async {
    final availability = await NfcCardScannerService.checkAvailability();
    if (!mounted) return;

    if (availability == NfcAvailability.unsupported) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('NFC Not Supported', style: TextStyle(fontWeight: FontWeight.bold)),
          content: const Text('This device does not have an NFC sensor. You can still scan cards using the Camera or Gallery.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    if (availability == NfcAvailability.disabled) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('NFC Is Turned Off', style: TextStyle(fontWeight: FontWeight.bold)),
          content: const Text('Please turn on NFC in your phone Settings to scan contactless cards.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    String currentStatus = 'Hold your contactless card against the back of your phone...';
    StateSetter? dialogSetState;
    BuildContext? sheetContext;
    bool scanDone = false;

    showModalBottomSheet(
      context: context,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        sheetContext = ctx;
        return StatefulBuilder(
          builder: (innerCtx, setModalState) {
            dialogSetState = setModalState;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 44, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.contactless_rounded, size: 52, color: Color(0xFF10B981)),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Ready to Scan',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      currentStatus,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14, color: Color(0xFF64748B), height: 1.4),
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('Cancel Scan'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF64748B),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        NfcCardScannerService.cancelScan();
                        if (sheetContext != null && Navigator.canPop(sheetContext!)) {
                          Navigator.pop(sheetContext!);
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      if (!scanDone) {
        NfcCardScannerService.cancelScan();
      }
    });

    try {
      final cardData = await NfcCardScannerService.scanCard(
        onStatus: (status) {
          if (mounted && dialogSetState != null) {
            dialogSetState!(() {
              currentStatus = status;
            });
          }
        },
      );

      scanDone = true;
      if (sheetContext != null && Navigator.canPop(sheetContext!)) {
        Navigator.pop(sheetContext!);
      }
      if (mounted && cardData != null) {
        _processScan(cardData);
      }
    } catch (e) {
      scanDone = true;
      if (sheetContext != null && Navigator.canPop(sheetContext!)) {
        Navigator.pop(sheetContext!);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('NFC scan cancelled or interrupted: $e'), backgroundColor: Colors.orange),
        );
      }
    }
  }

  void _processScan(ScannedCardData? data) {
    if (!mounted || data == null || data.isEmpty) {
      if (mounted && data != null && data.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not detect card details clearly. Please align and try again.'), backgroundColor: Colors.orange),
        );
      }
      return;
    }

    setState(() {
      if (data.cardNumber != null && data.cardNumber!.isNotEmpty) {
        // Format with spaces
        final buffer = StringBuffer();
        for (int i = 0; i < data.cardNumber!.length; i++) {
          if (i > 0 && i % 4 == 0) buffer.write(' ');
          buffer.write(data.cardNumber![i]);
        }
        _cardNumberCtrl.text = buffer.toString();
        _onCardNumberChanged();
      }
      if (data.expiry != null && data.expiry!.isNotEmpty) {
        _cardExpiryCtrl.text = data.expiry!;
      }
      if (data.cardHolder != null && data.cardHolder!.isNotEmpty) {
        _cardHolderCtrl.text = data.cardHolder!;
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Card scanned successfully! Details auto-filled.'), backgroundColor: Colors.green),
    );
  }

  // ─── Clipboard Auto-Detection on Tap/Focus (Credit & Debit Cards Only) ───────────

  Future<void> _checkClipboardForCardNumber({bool isUserExplicitPaste = false}) async {
    if (_tabController.index != 0) return; // Only applied for credit and debit cards
    try {
      final clip = await Clipboard.getData(Clipboard.kTextPlain);
      final text = clip?.text;
      if (text == null || text.trim().isEmpty) {
        if (isUserExplicitPaste && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Clipboard is empty'), duration: Duration(seconds: 2)),
          );
        }
        return;
      }

      // 1. Normalize all unicode whitespace, non-breaking spaces, dashes, dots
      final cleanText = text
          .replaceAll(RegExp(r'[\u00A0\u1680\u2000-\u200B\u202F\u205F\u3000\uFEFF]'), ' ');

      final entries = <MapEntry<int, String>>[];

      // A. Match 16 digits formatted as 4-4-4-4 (with spaces, hyphens, or dots)
      final groupedRegex = RegExp(r'(?<!\d)(\d{4})[\s\-\.]+(\d{4})[\s\-\.]+(\d{4})[\s\-\.]+(\d{4})(?!\d)');
      for (final m in groupedRegex.allMatches(cleanText)) {
        final digits = '${m.group(1)}${m.group(2)}${m.group(3)}${m.group(4)}';
        entries.add(MapEntry(m.start, digits));
      }

      // B. Match continuous 15 to 19 digit numbers (e.g. 16 continuous digits)
      final continuousRegex = RegExp(r'(?<!\d)(\d{15,19})(?!\d)');
      for (final m in continuousRegex.allMatches(cleanText)) {
        final digits = m.group(1)!;
        if (!entries.any((e) => (e.key - m.start).abs() < 5)) {
          entries.add(MapEntry(m.start, digits));
        }
      }

      // C. Fallback: Any sequence of digits with optional single spaces/dashes having 15-19 digits
      if (entries.isEmpty) {
        final looseRegex = RegExp(r'(?<!\d)(?:\d[\s\-]?){15,19}(?!\d)');
        for (final m in looseRegex.allMatches(cleanText)) {
          final digits = m.group(0)!.replaceAll(RegExp(r'\D'), '');
          if (digits.length >= 15 && digits.length <= 19) {
            entries.add(MapEntry(m.start, digits));
          }
        }
      }

      if (entries.isEmpty) {
        if (isUserExplicitPaste && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No card number found in clipboard'), duration: Duration(seconds: 2)),
          );
        }
        return;
      }

      // Sort by appearance in the text so latest occurrence in clipboard is at the end
      entries.sort((a, b) => a.key.compareTo(b.key));

      // Prefer 16-digit numbers if available (as requested: search entire clipboard for 16-digit number; if more exist, pick latest)
      final sixteenDigits = entries.where((e) => e.value.length == 16).toList();
      final target = sixteenDigits.isNotEmpty ? sixteenDigits.last.value : entries.last.value;

      final currentDigits = _cardNumberCtrl.text.replaceAll(RegExp(r'\D'), '');
      if (currentDigits == target && !isUserExplicitPaste) return;

      // Format in groups of 4
      final buffer = StringBuffer();
      for (int i = 0; i < target.length; i++) {
        if (i > 0 && i % 4 == 0) buffer.write(' ');
        buffer.write(target[i]);
      }
      final formatted = buffer.toString();

      setState(() {
        _cardNumberCtrl.text = formatted;
        _cardNumberCtrl.selection = TextSelection.collapsed(offset: formatted.length);
        _cardNumberError = null;
      });
      _onCardNumberChanged();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.paste_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('Card number pasted: $formatted')),
              ],
            ),
            backgroundColor: const Color(0xFFFF6F00),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _checkClipboardForCardholderName() async {
    if (_tabController.index != 0) return; // Only applied for credit and debit cards
    try {
      final clip = await Clipboard.getData(Clipboard.kTextPlain);
      final text = clip?.text;
      if (text == null || text.trim().isEmpty) return;

      final cleanText = text
          .replaceAll(RegExp(r'[\u00A0\u1680\u2000-\u200B\u202F\u205F\u3000\uFEFF]'), ' ');

      String? matchedName;

      // 1. Check for labeled cardholder name: "Name: RAHUL SHARMA", "Cardholder: JANE DOE"
      final labeledRegex = RegExp(
        r'(?:name|cardholder|card\s*holder|holder\s*name|holder)[:\s\-]+([A-Za-z ]{3,30})(?=[\r\n,;]|$)',
        caseSensitive: false,
      );
      final labeledMatches = labeledRegex.allMatches(cleanText).toList();
      if (labeledMatches.isNotEmpty) {
        final candidate = labeledMatches.last.group(1)?.trim();
        if (candidate != null && candidate.isNotEmpty) {
          matchedName = candidate.toUpperCase();
        }
      } else {
        // 2. Scan lines for a person's name (2-4 words, alphabetic only)
        final lines = cleanText.split(RegExp(r'[\r\n]+'));
        for (final line in lines.reversed) {
          final trimmed = line.trim();
          if (RegExp(r'^[A-Za-z]{2,}(?:\s+[A-Za-z]{2,}){1,3}$').hasMatch(trimmed)) {
            final upper = trimmed.toUpperCase();
            if (!upper.contains('CARD') &&
                !upper.contains('BANK') &&
                !upper.contains('VALID') &&
                !upper.contains('EXPIRE') &&
                !upper.contains('DEBIT') &&
                !upper.contains('CREDIT') &&
                !upper.contains('TOTAL') &&
                !upper.contains('LIMIT')) {
              matchedName = upper;
              break;
            }
          }
        }
      }

      if (matchedName == null || matchedName.isEmpty) return;
      final upperName = matchedName.toUpperCase().trim();
      if (_cardHolderCtrl.text.trim() == upperName) return;

      setState(() {
        _cardHolderCtrl.text = upperName;
        _cardHolderCtrl.selection = TextSelection.collapsed(offset: upperName.length);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.paste_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('Cardholder name pasted: $upperName')),
              ],
            ),
            backgroundColor: const Color(0xFFFF6F00),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _checkClipboardForExpiry() async {
    if (_tabController.index != 0) return; // Only applied for credit and debit cards
    try {
      final clip = await Clipboard.getData(Clipboard.kTextPlain);
      final text = clip?.text;
      if (text == null || text.trim().isEmpty) return;

      final cleanText = text
          .replaceAll(RegExp(r'[\u00A0\u1680\u2000-\u200B\u202F\u205F\u3000\uFEFF]'), ' ');

      final entries = <MapEntry<int, String>>[];

      // A. Labeled expiry date: "Exp: 08/28", "Valid Thru: 12/26", "Expires 05/29", "Expiry: 28/08"
      final labeledRegex = RegExp(
        r'(?:exp|expiry|expires|valid\s*thru|valid\s*upto|valid\s*till|validity)[:\s\-]*([0-3]?\d[\/\-][0-3]?\d(?:[\/\-]\d{2,4})?)',
        caseSensitive: false,
      );
      for (final m in labeledRegex.allMatches(cleanText)) {
        final dateStr = m.group(1)!;
        final parts = dateStr.split(RegExp(r'[\/\-]'));
        if (parts.length == 2) {
          final p1 = parts[0].padLeft(2, '0');
          var p2 = parts[1];
          if (p2.length == 4) p2 = p2.substring(2);
          final p1Num = int.tryParse(p1) ?? 0;
          final p2Num = int.tryParse(p2) ?? 0;
          if (p1Num >= 1 && p1Num <= 12) {
            entries.add(MapEntry(m.start, '$p1/$p2'));
          } else if (p2Num >= 1 && p2Num <= 12) {
            entries.add(MapEntry(m.start, '${p2.padLeft(2, '0')}/$p1'));
          }
        }
      }

      // B. Standard full date DD/MM/YYYY or DD/MM/YY
      final fullDateRegex = RegExp(r'(?<!\d)([0-3]?\d)[\/\-]([0-1]?\d)[\/\-](\d{2,4})(?!\d)');
      for (final m in fullDateRegex.allMatches(cleanText)) {
        final part1 = int.tryParse(m.group(1)!) ?? 0;
        final part2 = int.tryParse(m.group(2)!) ?? 0;
        var yearStr = m.group(3)!;
        if (yearStr.length == 4) yearStr = yearStr.substring(2);

        int month = 0;
        if (part2 >= 1 && part2 <= 12) {
          month = part2;
        } else if (part1 >= 1 && part1 <= 12) {
          month = part1;
        }
        if (month >= 1 && month <= 12) {
          final mm = month.toString().padLeft(2, '0');
          entries.add(MapEntry(m.start, '$mm/$yearStr'));
        }
      }

      // C. MM/YY or MM/YYYY (standard card expiry format)
      final mmyyRegex = RegExp(r'(?<!\d)(0[1-9]|1[0-2])[\/\-](2[4-9]|[3-9]\d|\d{4})(?!\d|[\/\-]\d)');
      for (final m in mmyyRegex.allMatches(cleanText)) {
        final mm = m.group(1)!;
        var yy = m.group(2)!;
        if (yy.length == 4) yy = yy.substring(2);
        entries.add(MapEntry(m.start, '$mm/$yy'));
      }

      // D. DD/MM format (e.g. 28/08 or 15/12) without trailing year
      final ddmmRegex = RegExp(r'(?<!\d)([0-3]\d)[\/\-](0[1-9]|1[0-2])(?![\/\-]\d|\d)');
      for (final m in ddmmRegex.allMatches(cleanText)) {
        final month = m.group(2)!;
        final dayOrYear = m.group(1)!;
        final dayNum = int.tryParse(dayOrYear) ?? 0;
        if (dayNum >= 24 && dayNum <= 40) {
          entries.add(MapEntry(m.start, '$month/$dayOrYear'));
        } else {
          entries.add(MapEntry(m.start, '$month/${(DateTime.now().year % 100) + 4}'));
        }
      }

      if (entries.isEmpty) return;
      entries.sort((a, b) => a.key.compareTo(b.key));
      final formatted = entries.last.value;

      if (_cardExpiryCtrl.text.trim() == formatted) return;

      setState(() {
        _cardExpiryCtrl.text = formatted;
        _cardExpiryCtrl.selection = TextSelection.collapsed(offset: formatted.length);
        _cardExpiryError = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.paste_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text('Expiry pasted from clipboard: $formatted'),
              ],
            ),
            backgroundColor: const Color(0xFFFF6F00),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _checkClipboardForCvv() async {
    if (_tabController.index != 0) return; // Only applied for credit and debit cards
    try {
      final clip = await Clipboard.getData(Clipboard.kTextPlain);
      final text = clip?.text;
      if (text == null || text.trim().isEmpty) return;

      final cleanText = text
          .replaceAll(RegExp(r'[\u00A0\u1680\u2000-\u200B\u202F\u205F\u3000\uFEFF]'), ' ');

      // 1. Look for labeled CVV/CVC first
      final labeledRegex = RegExp(
        r'(?:cvv|cvc|cvv2|cvc2|security\s*code|cid|card\s*verification)[:\s\-]*(\d{3,4})(?!\d)',
        caseSensitive: false,
      );
      final labeledMatches = labeledRegex.allMatches(cleanText).toList();

      String? matchedCvv;
      if (labeledMatches.isNotEmpty) {
        matchedCvv = labeledMatches.last.group(1);
      } else {
        // 2. Otherwise look for standalone 3 or 4 digit numbers
        final standaloneRegex = RegExp(r'(?<!\d)(\d{3,4})(?!\d)');
        final allStandalone = standaloneRegex.allMatches(cleanText).map((m) => m.group(1)!).where((numStr) {
          final val = int.tryParse(numStr) ?? 0;
          if (numStr.length == 4 && val >= 2024 && val <= 2040) return false;
          return true;
        }).toList();

        if (allStandalone.isNotEmpty) {
          // If multiple 3-digit numbers exist, opt for the latest one
          final threeDigits = allStandalone.where((s) => s.length == 3).toList();
          matchedCvv = threeDigits.isNotEmpty ? threeDigits.last : allStandalone.last;
        }
      }

      if (matchedCvv == null || matchedCvv.isEmpty) return;
      if (_cardCvvCtrl.text.trim() == matchedCvv) return;
      final cvv = matchedCvv;

      setState(() {
        _cardCvvCtrl.text = cvv;
        _cardCvvCtrl.selection = TextSelection.collapsed(offset: cvv.length);
        _cardCvvError = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.paste_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text('CVV pasted from clipboard: $cvv'),
              ],
            ),
            backgroundColor: const Color(0xFFFF6F00),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    final isCardTab = _tabController.index == 0;
    bool hasError = false;

    if (isCardTab) {
      final nickname = _cardNicknameCtrl.text.trim();
      final bank = _cardBankCtrl.text.trim();
      final number = _cardNumberCtrl.text.replaceAll(' ', '').trim();
      final expiry = _cardExpiryCtrl.text.trim();
      final cvv = _cardCvvCtrl.text.trim();

      String? nickErr;
      String? bankErr;
      String? numErr;
      String? expErr;
      String? cvvErr;

      if (nickname.isEmpty) {
        nickErr = 'Card nickname is required (e.g. Salary Card)';
        hasError = true;
      }
      if (bank.isEmpty) {
        bankErr = 'Bank name is required (e.g. HDFC Bank, SBI)';
        hasError = true;
      }
      if (number.isEmpty) {
        numErr = 'Card number is required';
        hasError = true;
      } else if (number.length < 13 || number.length > 19) {
        numErr = 'Enter a valid card number (13-19 digits)';
        hasError = true;
      }
      if (expiry.isEmpty) {
        expErr = 'Expiry date is required';
        hasError = true;
      } else if (!RegExp(r'^(0[1-9]|1[0-2])\/\d{2}$').hasMatch(expiry)) {
        expErr = 'Enter valid expiry MM/YY (e.g. 08/28)';
        hasError = true;
      }
      if (cvv.isEmpty) {
        cvvErr = 'CVV is required';
        hasError = true;
      } else if (!RegExp(r'^\d{3,4}$').hasMatch(cvv)) {
        cvvErr = 'Enter 3 or 4-digit CVV';
        hasError = true;
      }

      setState(() {
        _cardNicknameError = nickErr;
        _cardBankError = bankErr;
        _cardNumberError = numErr;
        _cardExpiryError = expErr;
        _cardCvvError = cvvErr;
      });
    } else if (_tabController.index == 1) {
      final bank = _nbBankCtrl.text.trim();
      final nickname = _nbNicknameCtrl.text.trim();
      final userId = _nbUserIdCtrl.text.trim();

      String? bankErr;
      String? nickErr;

      if (bank.isEmpty) {
        bankErr = 'Bank name is required (e.g. State Bank of India)';
        hasError = true;
      }
      if (nickname.isEmpty) {
        nickErr = 'Account nickname is required (e.g. Salary Account)';
        hasError = true;
      }
      final hasAnyAccount = _accountRowControllers.any((c) => c.accountCtrl.text.trim().isNotEmpty);
      if (!hasAnyAccount && userId.isEmpty) {
        if (_accountRowControllers.isNotEmpty) {
          _accountRowControllers.first.accountError = 'Enter Account Number or User ID';
        }
        hasError = true;
      }

      setState(() {
        _nbBankError = bankErr;
        _nbNicknameError = nickErr;
        _nbUserIdError = null;
        _nbLoginPasswordError = null;
      });
    } else {
      final nickname = _pwdNicknameCtrl.text.trim();
      final username = _pwdUsernameCtrl.text.trim();
      final password = _pwdPasswordCtrl.text.trim();

      String? nickErr;
      String? userErr;

      if (nickname.isEmpty) {
        nickErr = 'Title / Service Name is required (e.g. Google, GitHub)';
        hasError = true;
      }
      if (username.isEmpty && password.isEmpty) {
        userErr = 'Enter Username/Email or Password';
        hasError = true;
      }

      setState(() {
        _pwdNicknameError = nickErr;
        _pwdUsernameError = userErr;
      });
    }

    if (hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline_rounded, color: Colors.white),
              SizedBox(width: 8),
              Expanded(child: Text('Please fill in all required fields before saving.')),
            ],
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    final now = DateTime.now();
    final db = context.read<DatabaseService>();

    try {
      if (isCardTab) {
        // ── Check for Duplicate Card Number ──
        final rawInputDigits = _cardNumberCtrl.text.replaceAll(RegExp(r'\D'), '');
        final existingItems = await db.getAllItems();
        VaultItem? duplicateCard;
        for (final item in existingItems) {
          if (item.isCard && (widget.initialItem == null || item.id != widget.initialItem!.id)) {
            final existingDigits = item.cardNumber.replaceAll(RegExp(r'\D'), '');
            if (existingDigits.isNotEmpty && existingDigits == rawInputDigits) {
              duplicateCard = item;
              break;
            }
          }
        }

        if (duplicateCard != null) {
          setState(() {
            _isSaving = false;
            _cardNumberError = 'Card already exists with the same number';
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.white),
                    SizedBox(width: 8),
                    Expanded(child: Text('Card already exists with the same number')),
                  ],
                ),
                backgroundColor: Colors.redAccent,
                behavior: SnackBarBehavior.floating,
                duration: Duration(seconds: 3),
              ),
            );
            _showDuplicateCardDialog(duplicateCard);
          }
          return;
        }

        final card = VaultItem(
          id: widget.initialItem?.id ?? const Uuid().v4(),
          type: VaultItemType.card,
          bankName: _cardBankCtrl.text.trim().toUpperCase(),
          nickname: _cardNicknameCtrl.text.trim().toUpperCase(),
          notes: _cardNotesCtrl.text.trim(), // notes preserved as-is
          createdAt: widget.initialItem?.createdAt ?? now,
          updatedAt: now,
          cardNumber: _cardNumberCtrl.text.trim(),
          cardHolder: _cardHolderCtrl.text.trim().isEmpty ? 'CARDHOLDER' : _cardHolderCtrl.text.trim().toUpperCase(),
          cardNetwork: _cardNetwork.toUpperCase(),
          cardType: _cardType.toUpperCase(),
          expiry: _cardExpiryCtrl.text.trim().toUpperCase(),
          cvv: _cardCvvCtrl.text.trim(),
          cardTier: _cardTier,
          creditLimit: _cardType == 'Debit' ? 0.0 : (double.tryParse(_creditLimitCtrl.text.replaceAll(',', '').trim()) ?? 0.0),
          statementDay: _cardType == 'Debit' ? 0 : _statementDay,
          dueDay: _cardType == 'Debit' ? 0 : _dueDay,
        );

        if (widget.initialItem == null) {
          await db.insertItem(card);
        } else {
          await db.updateItem(card);
        }
      } else if (_tabController.index == 1) {
        final accounts = <BankAccount>[];
        for (final pair in _accountRowControllers) {
          final accNum = pair.accountCtrl.text.trim().toUpperCase();
          final ifsc = pair.ifscCtrl.text.trim().toUpperCase();
          if (accNum.isNotEmpty || ifsc.isNotEmpty) {
            accounts.add(BankAccount(accountNumber: accNum, ifscCode: ifsc));
          }
        }
        final primaryAcc = accounts.isNotEmpty ? accounts.first.accountNumber : '';
        final primaryIfsc = accounts.isNotEmpty ? accounts.first.ifscCode : '';

        final nb = VaultItem(
          id: widget.initialItem?.id ?? const Uuid().v4(),
          type: VaultItemType.netBanking,
          bankName: _nbBankCtrl.text.trim().toUpperCase(),
          nickname: _nbNicknameCtrl.text.trim().toUpperCase(),
          notes: _nbNotesCtrl.text.trim(), // notes preserved as-is
          createdAt: widget.initialItem?.createdAt ?? now,
          updatedAt: now,
          accountNumber: primaryAcc,
          ifscCode: primaryIfsc,
          accounts: accounts,
          userId: _nbUserIdCtrl.text.trim(), // User ID preserved with exact casing as entered
          loginPassword: _nbLoginPasswordCtrl.text.trim(), // passwords preserved as-is
          profilePassword: _nbProfilePasswordCtrl.text.trim(), // passwords preserved as-is
          mpin: _nbMpinCtrl.text.trim(), // pin preserved as-is
          cifNumber: _nbCifCtrl.text.trim().toUpperCase(),
          passwordExpiryMonths: _nbExpiryMonths,
          passwordSetDate: widget.initialItem?.passwordSetDate ?? now,
          loginPasswordExpiry: _loginPasswordExpiry,
          profilePasswordExpiry: _profilePasswordExpiry,
          mpinExpiry: _mpinExpiry,
        );

        if (widget.initialItem == null) {
          await db.insertItem(nb);
        } else {
          await db.updateItem(nb);
        }
      } else {
        final rawWebsite = _pwdWebsiteCtrl.text.replaceAll(' ', '').trim();
        final newPassword = _pwdPasswordCtrl.text.trim();

        // Build password version history timeline
        final history = List<PasswordHistoryEntry>.from(widget.initialItem?.passwordHistory ?? []);
        if (widget.initialItem != null &&
            widget.initialItem!.isPassword &&
            widget.initialItem!.password.isNotEmpty &&
            widget.initialItem!.password != newPassword) {
          history.insert(
            0,
            PasswordHistoryEntry(
              password: widget.initialItem!.password,
              changedAt: now,
            ),
          );
          if (history.length > 10) {
            history.removeRange(10, history.length);
          }
        }

        final pwd = VaultItem(
          id: widget.initialItem?.id ?? const Uuid().v4(),
          type: VaultItemType.password,
          bankName: _pwdNicknameCtrl.text.trim(),
          nickname: _pwdNicknameCtrl.text.trim(),
          website: rawWebsite,
          userId: _pwdUsernameCtrl.text.trim(),
          loginPassword: newPassword,
          totpSecret: TotpService.cleanKey(_pwdTotpCtrl.text),
          notes: _pwdNotesCtrl.text.trim(),
          createdAt: widget.initialItem?.createdAt ?? now,
          updatedAt: now,
          passwordHistory: history,
        );

        if (widget.initialItem == null) {
          await db.insertItem(pwd);
        } else {
          await db.updateItem(pwd);
        }
      }

      // Automatically initiate backup to Google Drive
      final drive = context.read<DriveService>();
      if (drive.isSignedIn) {
        drive.backup().then((_) {
          debugPrint('Auto-backup to Google Drive finished successfully.');
        }).catchError((err) {
          debugPrint('Auto-backup error: $err');
        });
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialItem != null;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          isEditing ? 'Edit Item' : 'Add to Vault',
          style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 18),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            key: _tabBarKey,
            child: TabBar(
              controller: _tabController,
              indicatorColor: const Color(0xFFFF6F00),
              indicatorWeight: 3,
              labelColor: const Color(0xFFFF6F00),
              unselectedLabelColor: const Color(0xFF64748B),
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              tabs: const [
                Tab(icon: Icon(Icons.credit_card_rounded), text: 'Card'),
                Tab(icon: Icon(Icons.account_balance_rounded), text: 'Bank'),
                Tab(icon: Icon(Icons.vpn_key_rounded), text: 'Password'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCardForm(),
          _buildNetBankingForm(),
          _buildPasswordForm(),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: ElevatedButton(
            onPressed: _isSaving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6F00),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 54),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 3,
            ),
            child: _isSaving
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text(isEditing ? 'Save Changes' : 'Save Item to Vault', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      ),
    );
  }

  // ─── Card Tab Form ─────────────────────────────────────────────────────────

  Widget _buildCardForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Live Card Preview
          CardWidget(
            cardNumber: _cardNumberCtrl.text,
            cardHolder: _cardHolderCtrl.text,
            expiry: _cardExpiryCtrl.text,
            cvv: _cardCvvCtrl.text,
            cardNetwork: _cardNetwork,
            cardType: _cardType,
            bankName: _cardBankCtrl.text,
            cardTier: _cardTier,
            showFullNumber: true,
          ),
          const SizedBox(height: 16),

          // Card Type Selector (Credit Card vs Debit Card)
          Container(
            key: _cardTypeKey,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      setState(() {
                        _cardType = 'Credit';
                        _cardTypeAutoDetected = false;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _cardType == 'Credit' ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: _cardType == 'Credit'
                            ? const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))]
                            : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.credit_card_rounded,
                            size: 18,
                            color: _cardType == 'Credit' ? const Color(0xFFFF6F00) : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Credit Card',
                            style: TextStyle(
                              color: _cardType == 'Credit' ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                              fontWeight: _cardType == 'Credit' ? FontWeight.bold : FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      setState(() {
                        _cardType = 'Debit';
                        _cardTypeAutoDetected = false;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _cardType == 'Debit' ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: _cardType == 'Debit'
                            ? const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))]
                            : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.account_balance_wallet_rounded,
                            size: 18,
                            color: _cardType == 'Debit' ? const Color(0xFF10B981) : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Debit Card',
                            style: TextStyle(
                              color: _cardType == 'Debit' ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                              fontWeight: _cardType == 'Debit' ? FontWeight.bold : FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Nickname & Bank
          _buildTextField(
            _cardNicknameCtrl,
            'Nickname',
            'e.g. Primary Salary Card',
            Icons.bookmark_border_rounded,
            errorText: _cardNicknameError,
            onChanged: (val) {
              if (_cardNicknameError != null) setState(() => _cardNicknameError = null);
            },
          ),
          const SizedBox(height: 14),
          _buildTextField(
            _cardBankCtrl,
            'Bank Name',
            'e.g. HDFC Bank, SBI, ICICI',
            Icons.account_balance_rounded,
            errorText: _cardBankError,
            onChanged: (val) {
              _bankAutoDetected = false;
              if (_cardBankError != null) setState(() => _cardBankError = null);
            },
          ),
          const SizedBox(height: 14),

          // Card Number with Smart Scanner button, Paste button & Luhn indicator
          Container(
            key: _cardNumberKey,
            child: TextField(
              controller: _cardNumberCtrl,
              focusNode: _cardNumberFocusNode,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              inputFormatters: [CardNumberInputFormatter()],
              onTap: _checkClipboardForCardNumber,
              onChanged: (val) {
                if (_cardNumberError != null) setState(() => _cardNumberError = null);
              },
              style: const TextStyle(color: Color(0xFF0F172A), fontFamily: 'Courier', letterSpacing: 1.5, fontWeight: FontWeight.bold),
              decoration: _buildInputDecoration(
                labelText: 'Card Number',
                hintText: 'e.g. 4532 1148 9023 5410',
                errorText: _cardNumberError,
                prefixIcon: Icon(Icons.credit_card_rounded, color: _cardNumberError != null ? Colors.redAccent : const Color(0xFFFF6F00)),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.document_scanner_rounded, color: Color(0xFFFF6F00)),
                      tooltip: 'Smart Card Scanner (NFC / Camera / Gallery)',
                      onPressed: _startCardScan,
                    ),
                    if (_cardNumberCtrl.text.replaceAll(' ', '').length >= 13)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Tooltip(
                          message: _isLuhnValid ? 'Valid card number (Luhn Check passed)' : 'Invalid check digit',
                          child: Icon(
                            _isLuhnValid ? Icons.check_circle_rounded : Icons.cancel_rounded,
                            color: _isLuhnValid ? Colors.green : Colors.redAccent,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Card Type Dropdown Alert (shown if app fails to auto-detect network)
          if (!_networkAutoDetected && _cardNumberCtrl.text.replaceAll(' ', '').length >= 3) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED), // Warm light orange
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFEDD5)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: Color(0xFFC2410C), size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Card type not identified. Please select from the dropdown below:',
                      style: TextStyle(color: Color(0xFF9A3412), fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],

          // Card Type & Card Tier Side-by-Side (labels permanently on top of the border)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Card Type (Network) Selector
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _availableNetworks.contains(_cardNetwork) ? _cardNetwork : 'Visa',
                  isExpanded: true,
                  dropdownColor: Colors.white,
                  icon: const Icon(Icons.arrow_drop_down, color: Color(0xFFFF6F00)),
                  style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 14),
                  decoration: _buildInputDecoration(
                    labelText: 'Card Type',
                    helperText: (!_networkAutoDetected && _cardNumberCtrl.text.replaceAll(' ', '').length >= 3)
                        ? 'Select network'
                        : null,
                    helperStyle: const TextStyle(color: Color(0xFFC2410C), fontSize: 10, fontWeight: FontWeight.bold),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  ),
                  items: _availableNetworks.map((net) {
                    return DropdownMenuItem(
                      value: net,
                      child: Text(net, overflow: TextOverflow.ellipsis),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _cardNetwork = val;
                      });
                    }
                  },
                ),
              ),

              const SizedBox(width: 12),

              // Card Tier Selector
              Expanded(
                child: DropdownButtonFormField<CardTier>(
                  value: _cardTier,
                  isExpanded: true,
                  dropdownColor: Colors.white,
                  icon: const Icon(Icons.arrow_drop_down, color: Color(0xFFFF6F00)),
                  style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 14),
                  decoration: _buildInputDecoration(
                    labelText: 'Card Tier',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  ),
                  items: CardTier.values.map((tier) {
                    return DropdownMenuItem(
                      value: tier,
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(colors: tier.gradientColors),
                            ),
                          ),
                          Flexible(
                            child: Text(
                              tier == CardTier.standard ? 'Classic' : tier.displayName,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _cardTier = val);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Cardholder Name
          _buildTextField(
            _cardHolderCtrl,
            'Cardholder Name',
            'e.g. RAHUL SHARMA',
            Icons.person_outline_rounded,
            focusNode: _cardHolderFocusNode,
            onTap: _checkClipboardForCardholderName,
          ),
          const SizedBox(height: 14),

          // Expiry & CVV
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _cardExpiryCtrl,
                  focusNode: _cardExpiryFocusNode,
                  keyboardType: TextInputType.datetime,
                  inputFormatters: [ExpiryDateInputFormatter()],
                  textInputAction: TextInputAction.next,
                  onTap: _checkClipboardForExpiry,
                  onChanged: (val) {
                    if (_cardExpiryError != null) setState(() => _cardExpiryError = null);
                  },
                  style: const TextStyle(color: Color(0xFF0F172A)),
                  decoration: _buildInputDecoration(
                    labelText: 'Expiry (MM/YY)',
                    hintText: 'e.g. 08/28',
                    errorText: _cardExpiryError,
                    prefixIcon: Icon(Icons.date_range_rounded, color: _cardExpiryError != null ? Colors.redAccent : const Color(0xFFFF6F00)),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: TextField(
                  controller: _cardCvvCtrl,
                  focusNode: _cardCvvFocusNode,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  maxLength: 4,
                  obscureText: true,
                  onTap: _checkClipboardForCvv,
                  onChanged: (val) {
                    if (_cardCvvError != null) setState(() => _cardCvvError = null);
                  },
                  style: const TextStyle(color: Color(0xFF0F172A)),
                  decoration: _buildInputDecoration(
                    labelText: 'CVV',
                    hintText: 'e.g. 842',
                    errorText: _cardCvvError,
                    prefixIcon: Icon(Icons.security_rounded, color: _cardCvvError != null ? Colors.redAccent : const Color(0xFFFF6F00)),
                  ).copyWith(counterText: ''),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── Credit Limit & Billing Cycle Tracker (Only for Credit Cards) ──
          if (_cardType == 'Credit') ...[
            _buildTextField(
              _creditLimitCtrl,
              'Credit Limit (Optional)',
              'e.g. 1,50,000',
              Icons.speed_rounded,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              inputFormatters: [IndianNumberInputFormatter()],
            ),
            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _statementDay,
                    dropdownColor: Colors.white,
                    icon: const Icon(Icons.arrow_drop_down, color: Color(0xFFFF6F00)),
                    style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 13),
                    decoration: _buildInputDecoration(
                      labelText: 'Bill Statement Day',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    ),
                    items: [
                      const DropdownMenuItem(value: 0, child: Text('Not Set')),
                      ...List.generate(31, (i) => i + 1).map((d) => DropdownMenuItem(value: d, child: Text('$d of month'))),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _statementDay = val);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _dueDay,
                    dropdownColor: Colors.white,
                    icon: const Icon(Icons.arrow_drop_down, color: Color(0xFFFF6F00)),
                    style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 13),
                    decoration: _buildInputDecoration(
                      labelText: 'Payment Due Day',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    ),
                    items: [
                      const DropdownMenuItem(value: 0, child: Text('Not Set')),
                      ...List.generate(31, (i) => i + 1).map((d) => DropdownMenuItem(value: d, child: Text('$d of month'))),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _dueDay = val);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],

          // Secure Notes
          _buildTextField(
            _cardNotesCtrl,
            'Secure Notes',
            'e.g. International transactions enabled, billing address...',
            Icons.notes_rounded,
            isNotes: true,
            textInputAction: TextInputAction.done,
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  // ─── NetBanking Tab Form ───────────────────────────────────────────────────

  Widget _buildNetBankingForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            key: _nbBankSectionKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTextField(
                  _nbBankCtrl,
                  'Bank Name',
                  'e.g. State Bank of India, HDFC, ICICI',
                  Icons.account_balance_rounded,
                  errorText: _nbBankError,
                  onChanged: (val) {
                    if (_nbBankError != null) setState(() => _nbBankError = null);
                  },
                ),
                const SizedBox(height: 14),
                _buildTextField(
                  _nbNicknameCtrl,
                  'Nickname',
                  'e.g. Primary Bank Account',
                  Icons.bookmark_border_rounded,
                  errorText: _nbNicknameError,
                  onChanged: (val) {
                    if (_nbNicknameError != null) setState(() => _nbNicknameError = null);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── Bank Accounts Section (Multiple Accounts with IFSC on the same row) ──
          Container(
            key: _nbAccountsSectionKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_accountRowControllers.length > 1)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Icon(Icons.swipe_left_rounded, size: 14, color: Color(0xFF94A3B8)),
                        SizedBox(width: 4),
                        Text(
                          'Swipe left on an account row to delete it',
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontStyle: FontStyle.italic),
                        ),
                      ],
                    ),
                  ),

                ...List.generate(_accountRowControllers.length, (index) {
                  final row = _accountRowControllers[index];
                  final rowWidget = Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Account Number (Maximized width)
                        Expanded(
                          flex: 7,
                          child: _buildTextField(
                            row.accountCtrl,
                            _accountRowControllers.length == 1 ? 'Account Number' : 'Account #${index + 1}',
                            'e.g. 501002345678',
                            Icons.numbers_rounded,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.next,
                            errorText: row.accountError,
                            onChanged: (val) {
                              if (row.accountError != null) setState(() => row.accountError = null);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        // IFSC Code (On the same row with maximized width)
                        Expanded(
                          flex: 5,
                          child: _buildTextField(
                            row.ifscCtrl,
                            'IFSC Code',
                            'e.g. HDFC0001234',
                            Icons.domain_rounded,
                            textInputAction: TextInputAction.next,
                            errorText: row.ifscError,
                            onChanged: (val) {
                              if (row.ifscError != null) setState(() => row.ifscError = null);
                            },
                          ),
                        ),
                      ],
                    ),
                  );

                  if (_accountRowControllers.length <= 1) {
                    return rowWidget;
                  }

                  return Dismissible(
                    key: ObjectKey(row),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.centerRight,
                      decoration: BoxDecoration(
                        color: Colors.red.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.shade300),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                          SizedBox(width: 6),
                          Text('Delete', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
                        ],
                      ),
                    ),
                    onDismissed: (_) {
                      setState(() {
                        final removed = _accountRowControllers.removeAt(index);
                        removed.dispose();
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Account removed from form'),
                          duration: Duration(seconds: 1),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    child: rowWidget,
                  );
                }),
              ],
            ),
          ),

          // + Add Another Account Button
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                key: _nbAddAccountBtnKey,
                child: TextButton.icon(
                icon: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFFFF6F00), size: 18),
                label: const Text(
                  '+ Add Another Account Number',
                  style: TextStyle(color: Color(0xFFFF6F00), fontWeight: FontWeight.bold, fontSize: 13),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                ),
                onPressed: () {
                  setState(() {
                    final prevIfsc = _accountRowControllers.isNotEmpty ? _accountRowControllers.last.ifscCtrl.text.trim() : '';
                    _accountRowControllers.add(
                      BankAccountRowControllers(
                        accountCtrl: TextEditingController(),
                        ifscCtrl: TextEditingController(text: prevIfsc),
                      ),
                    );
                  });
                },
              ),
            ),
          ),
        ),
          const SizedBox(height: 14),
          _buildTextField(
            _nbUserIdCtrl,
            'User ID / Customer ID',
            'e.g. 104928374 or username',
            Icons.badge_rounded,
            errorText: _nbUserIdError,
            textCapitalization: TextCapitalization.none,
            autocorrect: false,
            keyboardType: TextInputType.text,
            onChanged: (val) {
              if (_nbUserIdError != null) setState(() => _nbUserIdError = null);
            },
          ),
          const SizedBox(height: 14),

          // 1. Login Password & Individual Expiry (Side-by-side in same row)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: _buildTextField(
                  _nbLoginPasswordCtrl,
                  'Login Password',
                  'e.g. ••••••••',
                  Icons.password_rounded,
                  isPassword: true,
                  errorText: _nbLoginPasswordError,
                  onChanged: (val) {
                    if (_nbLoginPasswordError != null) setState(() => _nbLoginPasswordError = null);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _buildPasswordExpiryPicker(
                  label: 'Login Expiry',
                  expiryDate: _loginPasswordExpiry,
                  onChanged: (newDate) => setState(() => _loginPasswordExpiry = newDate),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 2. Profile / Transaction Password & Individual Expiry (Side-by-side in same row)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: _buildTextField(
                  _nbProfilePasswordCtrl,
                  'Profile Password',
                  'e.g. ••••••••',
                  Icons.lock_outline_rounded,
                  isPassword: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _buildPasswordExpiryPicker(
                  label: 'Profile Expiry',
                  expiryDate: _profilePasswordExpiry,
                  onChanged: (newDate) => setState(() => _profilePasswordExpiry = newDate),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 3. MPIN (Mobile PIN) & Individual Expiry (Side-by-side in same row)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: _buildTextField(
                  _nbMpinCtrl,
                  'MPIN',
                  'e.g. 4 or 6 digits',
                  Icons.pin_rounded,
                  keyboardType: TextInputType.number,
                  isPassword: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _buildPasswordExpiryPicker(
                  label: 'MPIN Expiry',
                  expiryDate: _mpinExpiry,
                  onChanged: (newDate) => setState(() => _mpinExpiry = newDate),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          _buildTextField(_nbCifCtrl, 'CIF Number', 'e.g. 89234812301', Icons.numbers_rounded),
          const SizedBox(height: 14),

          // Secure Notes
          _buildTextField(
            _nbNotesCtrl,
            'Secure Notes',
            'e.g. Security questions, branch IFSC, customer care...',
            Icons.notes_rounded,
            isNotes: true,
            textInputAction: TextInputAction.done,
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  Future<DateTime?> _showCustomDaysMonthsDialog(DateTime? current) async {
    final now = DateTime.now();
    int initialDays = 0;
    int initialMonths = 3;
    if (current != null && current.isAfter(now)) {
      final totalDays = current.difference(now).inDays;
      initialMonths = totalDays ~/ 30;
      initialDays = totalDays % 30;
    }

    final monthsCtrl = TextEditingController(text: initialMonths.toString());
    final daysCtrl = TextEditingController(text: initialDays.toString());
    String? validationErr;

    return showDialog<DateTime>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          final m = int.tryParse(monthsCtrl.text.trim()) ?? 0;
          final d = int.tryParse(daysCtrl.text.trim()) ?? 0;
          final totalDays = (m * 30) + d;
          final calculatedDate = totalDays > 0 ? now.add(Duration(days: totalDays)) : null;

          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.edit_calendar_rounded, color: Color(0xFFFF6F00)),
                SizedBox(width: 8),
                Text('Custom Expiry Duration', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Specify validity duration in months and days from today:',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: monthsCtrl,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          onChanged: (_) => setDlgState(() {}),
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                          decoration: InputDecoration(
                            labelText: 'Months',
                            hintText: '0',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            suffixText: 'mos',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: daysCtrl,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          onChanged: (_) => setDlgState(() {}),
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                          decoration: InputDecoration(
                            labelText: 'Days',
                            hintText: '0',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            suffixText: 'days',
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (validationErr != null) ...[
                    const SizedBox(height: 8),
                    Text(validationErr!, style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFFEDD5)),
                    ),
                    child: Text(
                      calculatedDate != null
                          ? 'Expires on: ${DateFormat('dd MMM yyyy').format(calculatedDate)} ($totalDays days total)'
                          : 'Enter at least 1 day or month',
                      style: const TextStyle(color: Color(0xFFC2410C), fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
                onPressed: () => Navigator.pop(ctx),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6F00)),
                child: const Text('Set Expiry'),
                onPressed: () {
                  final m = int.tryParse(monthsCtrl.text.trim()) ?? 0;
                  final d = int.tryParse(daysCtrl.text.trim()) ?? 0;
                  final totalDays = (m * 30) + d;
                  if (totalDays <= 0) {
                    setDlgState(() => validationErr = 'Please enter at least 1 day or month');
                    return;
                  }
                  Navigator.pop(ctx, now.add(Duration(days: totalDays)));
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPasswordExpiryPicker({
    required String label,
    required DateTime? expiryDate,
    required ValueChanged<DateTime?> onChanged,
  }) {
    final now = DateTime.now();
    final daysRemaining = expiryDate != null ? expiryDate.difference(now).inDays : null;
    final isExpired = daysRemaining != null && daysRemaining < 0;
    final isSoon = daysRemaining != null && daysRemaining >= 0 && daysRemaining <= 15;

    String selectedValue = 'none';
    String displayPill = 'No Expiry';
    Color pillColor = const Color(0xFF64748B);
    Color pillBg = const Color(0xFFF1F5F9);

    if (expiryDate != null) {
      if (daysRemaining != null && daysRemaining >= 29 && daysRemaining <= 31) {
        selectedValue = '30';
        displayPill = '30 Days';
      } else if (daysRemaining != null && daysRemaining >= 88 && daysRemaining <= 92) {
        selectedValue = '90';
        displayPill = '90 Days';
      } else if (daysRemaining != null && daysRemaining >= 178 && daysRemaining <= 182) {
        selectedValue = '180';
        displayPill = '180 Days';
      } else if (daysRemaining != null && daysRemaining >= 363 && daysRemaining <= 367) {
        selectedValue = '365';
        displayPill = '1 Year';
      } else {
        selectedValue = 'custom';
        displayPill = '${daysRemaining != null ? "$daysRemaining" : ""}d Custom';
      }

      if (isExpired) {
        pillColor = const Color(0xFFDC2626);
        pillBg = const Color(0xFFFEF2F2);
        displayPill = 'Expired';
      } else if (isSoon) {
        pillColor = const Color(0xFFD97706);
        pillBg = const Color(0xFFFFFBEB);
      } else {
        pillColor = const Color(0xFF059669);
        pillBg = const Color(0xFFECFDF5);
      }
    }

    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFCBD5E1), width: 1.2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF64748B),
                ),
              ),
              if (expiryDate != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: pillBg,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    displayPill,
                    style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: pillColor),
                  ),
                ),
            ],
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isDense: true,
              isExpanded: true,
              value: selectedValue,
              dropdownColor: Colors.white,
              borderRadius: BorderRadius.circular(12),
              icon: const Icon(Icons.arrow_drop_down, color: Color(0xFFFF6F00), size: 18),
              style: const TextStyle(color: Color(0xFF0F172A), fontSize: 11, fontWeight: FontWeight.bold),
              items: [
                const DropdownMenuItem(value: 'none', child: Text('No Expiry')),
                const DropdownMenuItem(value: '30', child: Text('30 Days (1 Mo)')),
                const DropdownMenuItem(value: '90', child: Text('90 Days (3 Mo)')),
                const DropdownMenuItem(value: '180', child: Text('180 Days (6 Mo)')),
                const DropdownMenuItem(value: '365', child: Text('365 Days (1 Yr)')),
                const DropdownMenuItem(
                  value: 'custom',
                  child: Text('Custom (Months/Days)...', style: TextStyle(color: Color(0xFFFF6F00))),
                ),
              ],
              onChanged: (val) async {
                if (val == 'none') {
                  onChanged(null);
                } else if (val == '30') {
                  onChanged(DateTime.now().add(const Duration(days: 30)));
                } else if (val == '90') {
                  onChanged(DateTime.now().add(const Duration(days: 90)));
                } else if (val == '180') {
                  onChanged(DateTime.now().add(const Duration(days: 180)));
                } else if (val == '365') {
                  onChanged(DateTime.now().add(const Duration(days: 365)));
                } else if (val == 'custom') {
                  final picked = await _showCustomDaysMonthsDialog(expiryDate);
                  if (picked != null) {
                    onChanged(picked);
                  }
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner introducing Password Manager
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF4F46E5).withValues(alpha: 0.1),
                  const Color(0xFF6366F1).withValues(alpha: 0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4F46E5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.vpn_key_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Password Manager',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Save website & app logins. TetherPass will suggest them automatically when you visit the website.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 1. Nickname / Service Title (e.g. Google, GitHub, Netflix)
          _buildTextField(
            _pwdNicknameCtrl,
            'Account / Service Title',
            'e.g. Google, GitHub, Netflix, Amazon',
            Icons.label_outline_rounded,
            errorText: _pwdNicknameError,
            onChanged: (val) {
              if (_pwdNicknameError != null) setState(() => _pwdNicknameError = null);
            },
          ),
          const SizedBox(height: 16),

          // 2. Website Address / URL
          _buildTextField(
            _pwdWebsiteCtrl,
            'Website Address / URL',
            'e.g. https://github.com or amazon.in',
            Icons.language_rounded,
            errorText: _pwdWebsiteError,
            keyboardType: TextInputType.url,
            textCapitalization: TextCapitalization.none,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (val) {
              if (_pwdWebsiteError != null) setState(() => _pwdWebsiteError = null);
            },
          ),
          const Padding(
            padding: EdgeInsets.only(left: 4, top: 4),
            child: Text(
              'Domain is matched automatically when you open this website or mobile app.',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontStyle: FontStyle.italic),
            ),
          ),
          const SizedBox(height: 16),

          // 3. Username / Email
          _buildTextField(
            _pwdUsernameCtrl,
            'Username / Email Address',
            'e.g. name@example.com or user123',
            Icons.alternate_email_rounded,
            errorText: _pwdUsernameError,
            keyboardType: TextInputType.emailAddress,
            textCapitalization: TextCapitalization.none,
            autocorrect: false,
            enableSuggestions: true,
            onChanged: (val) {
              if (_pwdUsernameError != null) setState(() => _pwdUsernameError = null);
            },
          ),
          const SizedBox(height: 16),

          // 4. Password Field with Reveal Toggle & Generator
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _pwdPasswordError != null ? Colors.redAccent : const Color(0xFFCBD5E1),
                width: _pwdPasswordError != null ? 1.6 : 1.2,
              ),
            ),
            child: Column(
              children: [
                TextField(
                  controller: _pwdPasswordCtrl,
                  obscureText: !_pwdPasswordVisible,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    hintText: 'Enter account password',
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    prefixIcon: const Icon(Icons.lock_outline_rounded, color: Color(0xFF64748B)),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            _pwdPasswordVisible ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                            color: const Color(0xFF64748B),
                          ),
                          tooltip: _pwdPasswordVisible ? 'Hide Password' : 'Show Password',
                          onPressed: () => setState(() => _pwdPasswordVisible = !_pwdPasswordVisible),
                        ),
                        IconButton(
                          icon: const Icon(Icons.paste_rounded, color: Color(0xFF64748B)),
                          tooltip: 'Paste Password',
                          onPressed: () async {
                            final data = await Clipboard.getData('text/plain');
                            if (data?.text != null && data!.text!.isNotEmpty) {
                              setState(() {
                                _pwdPasswordCtrl.text = data.text!;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    errorText: _pwdPasswordError,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(11),
                      bottomRight: Radius.circular(11),
                    ),
                    border: Border(top: BorderSide(color: Colors.grey.shade200)),
                  ),
                  child: Row(
                    children: [
                      TextButton.icon(
                        onPressed: _generateStrongPassword,
                        icon: const Icon(Icons.auto_awesome_rounded, size: 16, color: Color(0xFFFF6F00)),
                        label: const Text(
                          'Generate Strong Password',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFFF6F00),
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      const Spacer(),
                      if (_pwdPasswordCtrl.text.isNotEmpty)
                        Text(
                          '${_pwdPasswordCtrl.text.length} chars',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 4b. Two-Factor Authentication (TOTP / 2FA)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6F00).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.lock_clock_rounded, color: Color(0xFFFF6F00), size: 18),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Two-Factor Authentication (2FA / TOTP)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          Text(
                            'Optional: Generates rolling 6-digit authenticator codes',
                            style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _scanTotpQrCode,
                        icon: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 18),
                        label: const Text(
                          'Scan 2FA Setup QR Code',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6F00),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _pwdTotpCtrl,
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                    fontSize: 13,
                    color: Color(0xFF0F172A),
                  ),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: '2FA Secret Key or URI',
                    hintText: 'e.g. JBSWY3DPEHPK3PXP or otpauth://...',
                    hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.qr_code_scanner_rounded, color: Color(0xFFFF6F00), size: 20),
                          tooltip: 'Scan QR Code',
                          onPressed: _scanTotpQrCode,
                        ),
                        IconButton(
                          icon: const Icon(Icons.paste_rounded, color: Color(0xFF64748B), size: 20),
                          tooltip: 'Paste 2FA Secret Key',
                          onPressed: () async {
                            final data = await Clipboard.getData(Clipboard.kTextPlain);
                            if (data?.text != null) {
                              final parsed = TotpService.cleanKey(data!.text!);
                              setState(() {
                                _pwdTotpCtrl.text = parsed;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                if (TotpService.isValidSecret(_pwdTotpCtrl.text)) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFA7F3D0)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 16),
                            const SizedBox(width: 6),
                            Text(
                              'Active Code: ${TotpService.generateCode(_pwdTotpCtrl.text)}',
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF065F46),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '${TotpService.getRemainingSeconds()}s left',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF059669), fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 5. Notes
          _buildTextField(
            _pwdNotesCtrl,
            'Notes (Optional)',
            'Security questions, backup codes, recovery email, etc.',
            Icons.notes_rounded,
            isNotes: true,
            maxLines: 3,
            keyboardType: TextInputType.multiline,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _generateStrongPassword() {
    const chars = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#%&*+=-';
    final rand = DateTime.now().microsecondsSinceEpoch;
    final buffer = StringBuffer();
    var seed = rand;
    for (int i = 0; i < 16; i++) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      buffer.write(chars[seed % chars.length]);
    }
    final generated = buffer.toString();
    setState(() {
      _pwdPasswordCtrl.text = generated;
      _pwdPasswordVisible = true;
    });
    Clipboard.setData(ClipboardData(text: generated));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Expanded(child: Text('Strong 16-character password generated and copied to clipboard!')),
          ],
        ),
        backgroundColor: Color(0xFF10B981),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  InputDecoration _buildInputDecoration({
    required String labelText,
    String? hintText,
    Widget? prefixIcon,
    Widget? suffixIcon,
    String? helperText,
    TextStyle? helperStyle,
    String? errorText,
    EdgeInsetsGeometry? contentPadding,
  }) {
    return InputDecoration(
      floatingLabelBehavior: FloatingLabelBehavior.always,
      labelText: labelText,
      hintText: hintText,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      helperText: helperText,
      helperStyle: helperStyle,
      errorText: errorText,
      errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
      errorMaxLines: 2,
      filled: true,
      fillColor: Colors.white,
      contentPadding: contentPadding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      labelStyle: const TextStyle(
        color: Color(0xFF64748B),
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
      floatingLabelStyle: TextStyle(
        color: errorText != null ? Colors.redAccent : const Color(0xFFFF6F00),
        fontWeight: FontWeight.bold,
        fontSize: 13,
      ),
      hintStyle: const TextStyle(
        color: Color(0xFF94A3B8),
        fontSize: 13,
        fontStyle: FontStyle.italic,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: errorText != null ? Colors.redAccent : const Color(0xFFCBD5E1),
          width: errorText != null ? 1.6 : 1.2,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: errorText != null ? Colors.redAccent : const Color(0xFFFF6F00),
          width: 1.8,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.6),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent, width: 2.0),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    String hint,
    IconData icon, {
    bool isPassword = false,
    bool isNotes = false,
    TextInputType keyboardType = TextInputType.text,
    TextInputAction textInputAction = TextInputAction.next,
    TextCapitalization? textCapitalization,
    bool? autocorrect,
    bool? enableSuggestions,
    int maxLines = 1,
    String? errorText,
    ValueChanged<String>? onChanged,
    VoidCallback? onTap,
    FocusNode? focusNode,
    List<TextInputFormatter>? inputFormatters,
  }) {
    final bool isUrlOrEmail = keyboardType == TextInputType.emailAddress || keyboardType == TextInputType.url;
    final bool effectiveAutocorrect = autocorrect ?? (!isPassword && !isUrlOrEmail);
    final TextCapitalization effectiveCapitalization = textCapitalization ??
        ((isPassword || isNotes || isUrlOrEmail) ? TextCapitalization.none : TextCapitalization.characters);

    return TextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: isPassword,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textCapitalization: effectiveCapitalization,
      autocorrect: effectiveAutocorrect,
      enableSuggestions: enableSuggestions ?? !isPassword,
      maxLines: maxLines,
      onChanged: onChanged,
      onTap: onTap,
      inputFormatters: inputFormatters,
      style: const TextStyle(color: Color(0xFF0F172A)),
      decoration: _buildInputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: errorText != null ? Colors.redAccent : const Color(0xFFFF6F00)),
        errorText: errorText,
      ),
    );
  }

  void _showDuplicateCardDialog(VaultItem duplicateCard) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          clipBehavior: Clip.antiAlias,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Warning header banner
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red.shade100,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 22),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Card Already Exists',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF991B1B),
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'A card with this exact number is already saved in your vault.',
                                style: TextStyle(fontSize: 12, color: Color(0xFF7F1D1D)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Real card representation
                  CardWidget(
                    cardNumber: duplicateCard.cardNumber,
                    cardHolder: duplicateCard.cardHolder,
                    expiry: duplicateCard.expiry,
                    cvv: duplicateCard.cvv,
                    cardNetwork: duplicateCard.cardNetwork,
                    cardType: duplicateCard.isDebit ? 'Debit' : 'Credit',
                    bankName: duplicateCard.bankName,
                    cardTier: duplicateCard.cardTier,
                    showFullNumber: true,
                  ),
                  const SizedBox(height: 8),
                  const Center(
                    child: Text(
                      'Tap card to flip and view CVV & magnetic strip',
                      style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontStyle: FontStyle.italic),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Data breakdown table
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        _buildDuplicateRow('Nickname', duplicateCard.nickname),
                        const Divider(height: 16),
                        _buildDuplicateRow('Bank Name', duplicateCard.bankName),
                        const Divider(height: 16),
                        _buildDuplicateRow('Card Number', duplicateCard.cardNumber),
                        const Divider(height: 16),
                        _buildDuplicateRow('Cardholder', duplicateCard.cardHolder),
                        const Divider(height: 16),
                        _buildDuplicateRow('Expiry Date', duplicateCard.expiry.isEmpty ? '—' : duplicateCard.expiry),
                        const Divider(height: 16),
                        _buildDuplicateRow('CVV', duplicateCard.cvv.isEmpty ? '—' : duplicateCard.cvv),
                        const Divider(height: 16),
                        _buildDuplicateRow('Card Type', '${duplicateCard.isDebit ? "Debit" : "Credit"} (${duplicateCard.cardNetwork})'),
                        const Divider(height: 16),
                        _buildDuplicateRow('Card Tier', duplicateCard.cardTier.displayName),
                        if (duplicateCard.isCredit && duplicateCard.creditLimit > 0) ...[
                          const Divider(height: 16),
                          _buildDuplicateRow('Credit Limit', '₹${formatIndianNumber(duplicateCard.creditLimit)}'),
                        ],
                        if (duplicateCard.isCredit && duplicateCard.statementDay > 0) ...[
                          const Divider(height: 16),
                          _buildDuplicateRow('Statement Day', '${duplicateCard.statementDay}th of month'),
                        ],
                        if (duplicateCard.isCredit && duplicateCard.dueDay > 0) ...[
                          const Divider(height: 16),
                          _buildDuplicateRow('Due Day', '${duplicateCard.dueDay}th of month'),
                        ],
                        if (duplicateCard.notes.isNotEmpty) ...[
                          const Divider(height: 16),
                          _buildDuplicateRow('Notes', duplicateCard.notes),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Actions
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFFCBD5E1)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text(
                            'Change Number',
                            style: TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.edit_rounded, size: 16),
                          label: const Text('Edit This Card', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF6F00),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(builder: (_) => AddEditScreen(initialItem: duplicateCard)),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDuplicateRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 95,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 12, color: Color(0xFF0F172A), fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
