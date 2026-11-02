import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/vault_item.dart';
import '../services/card_detector.dart';
import '../services/database_service.dart';
import '../services/totp_service.dart';
import '../services/breach_watch_service.dart';
import '../services/clipboard_service.dart';
import '../widgets/card_input_formatter.dart';
import '../widgets/spotlight_tour.dart';
import 'add_edit_screen.dart';

class ItemDetailScreen extends StatefulWidget {
  final VaultItem item;

  const ItemDetailScreen({super.key, required this.item});

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  late VaultItem _item;
  bool _isCvvRevealed = false; // Only mask CVV; Card Number is always visible
  bool _isLoginPasswordRevealed = false;
  bool _isProfilePasswordRevealed = false;
  bool _isMpinRevealed = false;
  bool _isHistoryExpanded = false;
  final Set<int> _revealedHistoryIndexes = {};

  Timer? _totpTimer;
  BreachResult? _breachResult;
  bool _isCheckingBreach = false;

  // GlobalKeys for pointing directly to card and bank elements in the spotlight tour
  final GlobalKey _cardNumKey = GlobalKey();
  final GlobalKey _cvvEyeKey = GlobalKey();
  final GlobalKey _nbAccountRowKey = GlobalKey();
  final GlobalKey _nbCopyBothKey = GlobalKey();
  final GlobalKey _copyDockKey = GlobalKey();
  final GlobalKey _shareDockKey = GlobalKey();
  final GlobalKey _editDockKey = GlobalKey();
  final GlobalKey _deleteDockKey = GlobalKey();

  void _startSpotlightTour() {
    if (_item.isCard) {
      _startCardSpotlightTour();
    } else {
      _startBankSpotlightTour();
    }
  }

  void _startCardSpotlightTour() {
    final steps = <SpotlightTourStep>[
      SpotlightTourStep(
        targetKey: _cardNumKey,
        icon: Icons.pin_rounded,
        title: 'Card Number (Tap to Copy)',
        description: 'The card number is always visible for quick reading. Tap directly on the digits to copy only the number to your clipboard!',
        isCircle: false,
        borderRadius: 8,
      ),
      SpotlightTourStep(
        targetKey: _cvvEyeKey,
        icon: Icons.visibility_rounded,
        title: 'CVV Eye Reveal Button',
        description: 'Only the CVV is masked for privacy. Tap this eye icon directly beside the CVV to reveal or hide the 3-digit security code.',
        isCircle: true,
      ),
      SpotlightTourStep(
        targetKey: _copyDockKey,
        icon: Icons.copy_rounded,
        title: 'Quick Copy All Button',
        description: 'Tap this button to copy the entire card profile (Cardholder Name, Number, Expiry, and CVV) into your clipboard in one tap.',
        isCircle: true,
      ),
      SpotlightTourStep(
        targetKey: _shareDockKey,
        icon: Icons.share_rounded,
        title: 'Share Credentials Button',
        description: 'Opens native Android ShareSheet with clean formatted details (emojis included) for easy messaging.',
        isCircle: true,
      ),
      SpotlightTourStep(
        targetKey: _editDockKey,
        icon: Icons.edit_outlined,
        title: 'Edit Credentials Button',
        description: 'Tap here to change bank name, nickname, card tier, expiry date, network, or notes.',
        isCircle: true,
      ),
      SpotlightTourStep(
        targetKey: _deleteDockKey,
        icon: Icons.delete_outline_rounded,
        title: 'Delete Item Button',
        description: 'Permanently removes this credential from your encrypted local storage with a safety confirmation prompt.',
        isCircle: true,
      ),
    ];

    SpotlightTourOverlay.show(
      context: context,
      steps: steps,
    );
  }

  void _startBankSpotlightTour() {
    final steps = <SpotlightTourStep>[
      SpotlightTourStep(
        targetKey: _nbAccountRowKey,
        icon: Icons.account_balance_rounded,
        title: 'Account Number & IFSC Code',
        description: 'Compact high-density formatting fits full 18-digit numbers on a single line. Tap the Account Number or IFSC code to copy each individually!',
        isCircle: false,
        borderRadius: 14,
      ),
      SpotlightTourStep(
        targetKey: _nbCopyBothKey,
        icon: Icons.copy_all_rounded,
        title: 'Copy Both (A/C + IFSC)',
        description: 'Tap "Copy Both" to immediately copy both the Account Number and IFSC code together formatted for IMPS / NEFT transfer.',
        isCircle: false,
        borderRadius: 8,
      ),
      SpotlightTourStep(
        targetKey: _copyDockKey,
        icon: Icons.copy_rounded,
        title: 'Quick Copy All Button',
        description: 'Copies the complete bank profile (Bank Name, all Account Numbers, IFSC codes, User ID, and CIF) formatted cleanly in one tap.',
        isCircle: true,
      ),
      SpotlightTourStep(
        targetKey: _shareDockKey,
        icon: Icons.share_rounded,
        title: 'Share Bank Details',
        description: 'Opens native Android ShareSheet with formatted account and bank details for easy messaging via WhatsApp, SMS, or Email.',
        isCircle: true,
      ),
      SpotlightTourStep(
        targetKey: _editDockKey,
        icon: Icons.edit_outlined,
        title: 'Edit Bank Details',
        description: 'Add or remove account numbers, update passwords, MPIN, or change bank notes anytime.',
        isCircle: true,
      ),
      SpotlightTourStep(
        targetKey: _deleteDockKey,
        icon: Icons.delete_outline_rounded,
        title: 'Delete Item Button',
        description: 'Permanently removes this bank account entry from your encrypted local vault with a safety confirmation prompt.',
        isCircle: true,
      ),
    ];

    SpotlightTourOverlay.show(
      context: context,
      steps: steps,
    );
  }

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    if (_item.hasTotp) {
      _startTotpTimer();
    }
  }

  void _startTotpTimer() {
    _totpTimer?.cancel();
    _totpTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _totpTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkBreachStatus() async {
    if (_item.loginPassword.isEmpty) return;
    setState(() => _isCheckingBreach = true);
    final res = await BreachWatchService.checkPassword(_item.loginPassword);
    if (mounted) {
      setState(() {
        _breachResult = res;
        _isCheckingBreach = false;
      });
    }
  }

  void _copyToClipboard(String label, String value) {
    if (value.isEmpty) return;
    ClipboardService.copySecure(context, value, label: label);
  }

  String _formatCardNumber(String raw) {
    final clean = raw.replaceAll(' ', '');
    final buffer = StringBuffer();
    for (int i = 0; i < clean.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(clean[i]);
    }
    return buffer.toString().isEmpty ? '•••• •••• •••• ••••' : buffer.toString();
  }

  void _copyAllDetails() {
    if (_item.isPassword) {
      final text = '''
🏷️ Title: ${_item.nickname}
🌐 Website: ${_item.website}
👤 Username: ${_item.userId}
🔑 Password: ${_item.loginPassword}
${_item.notes.isNotEmpty ? '📝 Notes: ${_item.notes}' : ''}
'''.trim();
      _copyToClipboard('Credentials', text);
    } else if (_item.isCard) {
      final formattedNumber = _formatCardNumber(_item.cardNumber);
      final text = '''
👤 Name: ${_item.cardHolder.toUpperCase()}
💳 Card: ${_item.nickname.toUpperCase()}
🏦 Bank: ${_item.bankName.toUpperCase()}
🔢 Card No: $formattedNumber
📅 Exp: ${_item.expiry} | 🔑 CVV: ${_item.cvv}
${_item.notes.isNotEmpty ? '📝 Notes: ${_item.notes}' : ''}
'''.trim();
      _copyToClipboard('Card details', text);
    } else {
      final buffer = StringBuffer();
      buffer.writeln('🏦 Bank: ${_item.bankName.toUpperCase()}');
      buffer.writeln('🏷️ Nickname: ${_item.nickname}');
      if (_item.allAccounts.isNotEmpty) {
        if (_item.allAccounts.length == 1) {
          final acc = _item.allAccounts.first;
          if (acc.accountNumber.isNotEmpty) buffer.writeln('💳 Account No: ${acc.accountNumber}');
          if (acc.ifscCode.isNotEmpty) buffer.writeln('🏛️ IFSC Code: ${acc.ifscCode}');
        } else {
          buffer.writeln('💳 Accounts (${_item.allAccounts.length}):');
          for (int i = 0; i < _item.allAccounts.length; i++) {
            final acc = _item.allAccounts[i];
            buffer.writeln('   • Account #${i + 1}: ${acc.accountNumber}${acc.ifscCode.isNotEmpty ? " (IFSC: ${acc.ifscCode})" : ""}');
          }
        }
      }
      if (_item.userId.isNotEmpty) buffer.writeln('🆔 User ID: ${_item.userId}');
      if (_item.cifNumber.isNotEmpty) buffer.writeln('🔢 CIF Number: ${_item.cifNumber}');
      if (_item.loginPassword.isNotEmpty) buffer.writeln('🔑 Login Password: ${_item.loginPassword}');
      if (_item.profilePassword.isNotEmpty) buffer.writeln('🛡️ Profile Password: ${_item.profilePassword}');
      if (_item.mpin.isNotEmpty) buffer.writeln('📌 MPIN: ${_item.mpin}');
      if (_item.notes.isNotEmpty) buffer.writeln('📝 Notes: ${_item.notes}');
      _copyToClipboard('Bank details', buffer.toString().trim());
    }
  }

  void _shareDetails() {
    if (_item.isPassword) {
      final text = '''
🏷️ Title: ${_item.nickname}
🌐 Website: ${_item.website}
👤 Username: ${_item.userId}
🔑 Password: ${_item.loginPassword}
${_item.notes.isNotEmpty ? '📝 Notes: ${_item.notes}' : ''}
'''.trim();
      Share.share(text, subject: '${_item.nickname} Credentials');
    } else if (_item.isCard) {
      final formattedNumber = _formatCardNumber(_item.cardNumber);
      final text = '''
👤 Name: ${_item.cardHolder.toUpperCase()}
💳 Card: ${_item.nickname.toUpperCase()}
🏦 Bank: ${_item.bankName.toUpperCase()}
🔢 Card No: $formattedNumber
📅 Exp: ${_item.expiry} | 🔑 CVV: ${_item.cvv}
${_item.notes.isNotEmpty ? '📝 Notes: ${_item.notes}' : ''}
'''.trim();
      Share.share(text, subject: '${_item.nickname} Details');
    } else {
      final buffer = StringBuffer();
      buffer.writeln('🏦 Bank: ${_item.bankName.toUpperCase()}');
      buffer.writeln('🏷️ Nickname: ${_item.nickname}');
      if (_item.allAccounts.isNotEmpty) {
        if (_item.allAccounts.length == 1) {
          final acc = _item.allAccounts.first;
          if (acc.accountNumber.isNotEmpty) buffer.writeln('💳 Account No: ${acc.accountNumber}');
          if (acc.ifscCode.isNotEmpty) buffer.writeln('🏛️ IFSC Code: ${acc.ifscCode}');
        } else {
          buffer.writeln('💳 Accounts (${_item.allAccounts.length}):');
          for (int i = 0; i < _item.allAccounts.length; i++) {
            final acc = _item.allAccounts[i];
            buffer.writeln('   • Account #${i + 1}: ${acc.accountNumber}${acc.ifscCode.isNotEmpty ? " (IFSC: ${acc.ifscCode})" : ""}');
          }
        }
      }
      if (_item.userId.isNotEmpty) buffer.writeln('🆔 User ID: ${_item.userId}');
      if (_item.cifNumber.isNotEmpty) buffer.writeln('🔢 CIF Number: ${_item.cifNumber}');
      if (_item.loginPassword.isNotEmpty) buffer.writeln('🔑 Login Password: ${_item.loginPassword}');
      if (_item.profilePassword.isNotEmpty) buffer.writeln('🛡️ Profile Password: ${_item.profilePassword}');
      if (_item.mpin.isNotEmpty) buffer.writeln('📌 MPIN: ${_item.mpin}');
      if (_item.notes.isNotEmpty) buffer.writeln('📝 Notes: ${_item.notes}');
      Share.share(buffer.toString().trim(), subject: '${_item.nickname} Bank Details');
    }
  }

  Future<void> _editItem() async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddEditScreen(initialItem: _item),
      ),
    );

    if (updated == true && mounted) {
      final db = context.read<DatabaseService>();
      final items = await db.getAllItems();
      final refreshed = items.firstWhere(
        (i) => i.id == _item.id,
        orElse: () => _item,
      );
      setState(() => _item = refreshed);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Item?', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold)),
        content: Text(
          'Are you sure you want to delete "${_item.nickname}"? This action cannot be undone.',
          style: const TextStyle(color: Color(0xFF64748B)),
        ),
        actions: [
          TextButton(
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final db = context.read<DatabaseService>();
      await db.deleteItem(_item.id);
      if (mounted) Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA), // 100% Light Theme Canvas
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _item.nickname,
          style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded, color: Color(0xFF64748B)),
            tooltip: _item.isCard ? 'Card Features Tour' : 'Bank Account Tour',
            onPressed: _startSpotlightTour,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Column(
            children: [
              // ── Top Stylized Card (All details displayed on card itself) ──
              if (_item.isPassword) ...[
                _buildPasswordVisual(),
              ] else if (_item.isCard) ...[
                _buildCardVisual(),
                if (_item.isCardExpired || _item.isCardExpiringSoon) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: _item.isCardExpired ? Colors.red.shade50 : const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _item.isCardExpired ? Colors.red.shade200 : const Color(0xFFFDE68A),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _item.isCardExpired ? Icons.error_outline_rounded : Icons.warning_amber_rounded,
                          color: _item.isCardExpired ? Colors.red : const Color(0xFFD97706),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _item.isCardExpired
                                ? 'This card expired on ${_item.expiry}. Please contact ${_item.bankName} for a replacement.'
                                : 'Card Expiry Warning: Expires in ${_item.cardExpiryDaysRemaining} days (${_item.expiry}). Check renewal with your bank.',
                            style: TextStyle(
                              color: _item.isCardExpired ? Colors.red.shade900 : const Color(0xFF92400E),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_item.isCredit && (_item.creditLimit > 0 || _item.statementDay > 0 || _item.dueDay > 0)) ...[
                  const SizedBox(height: 14),
                  _buildCreditTrackerCard(),
                ],
              ] else ...[
                if (_item.isAnyPasswordExpired || _item.isAnyPasswordExpiringSoon) ...[
                  _buildNetBankingExpiryBanner(),
                  const SizedBox(height: 14),
                ],
                _buildNetBankingCardVisual(),
              ],

              const SizedBox(height: 28),

              // ── Quick Action Dock: 4 Circular Buttons (Light Theme) ──
              _buildQuickActionDock(),

              const SizedBox(height: 28),

              // ── Secure Notes Widget (Light Theme) ──
              _buildNotesWidget(),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Stylized Password Visual ──────────────────────────────────────────

  Widget _buildPasswordVisual() {
    const gradient = [
      Color(0xFF312E81), // Indigo 900
      Color(0xFF4338CA), // Indigo 700
      Color(0xFF1E1B4B), // Indigo 950
    ];
    const textColor = Colors.white;
    final hintColor = Colors.white.withValues(alpha: 0.6);
    const accentColor = Color(0xFF818CF8);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4338CA).withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Web Logo + Title + Badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.vpn_key_rounded, color: Color(0xFFFFB300), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _item.nickname.toUpperCase(),
                      style: const TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        letterSpacing: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'WEBSITE CREDENTIALS',
                      style: TextStyle(
                        color: hintColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: accentColor.withValues(alpha: 0.4)),
                ),
                child: const Text(
                  'PASSWORD',
                  style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Website Address Row (if present)
          if (_item.website.isNotEmpty) ...[
            InkWell(
              onTap: () => _copyToClipboard('Website URL', _item.website),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.language_rounded, color: Color(0xFF818CF8), size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('WEBSITE ADDRESS', style: TextStyle(color: hintColor, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
                          const SizedBox(height: 2),
                          Text(
                            _item.website,
                            style: const TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 18, color: Colors.white70),
                      tooltip: 'Copy URL',
                      onPressed: () => _copyToClipboard('Website URL', _item.website),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Username / Email
          InkWell(
            onTap: () => _copyToClipboard('Username', _item.userId),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_outline_rounded, color: Color(0xFF818CF8), size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('USERNAME / EMAIL', style: TextStyle(color: hintColor, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
                        const SizedBox(height: 2),
                        Text(
                          _item.userId.isEmpty ? '—' : _item.userId,
                          style: const TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 18, color: Colors.white70),
                    tooltip: 'Copy Username',
                    onPressed: () => _copyToClipboard('Username', _item.userId),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Password Field with Eye toggle and copy
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_outline_rounded, color: Color(0xFF818CF8), size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('PASSWORD', style: TextStyle(color: hintColor, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
                      const SizedBox(height: 2),
                      _isLoginPasswordRevealed
                          ? Text(
                              _item.loginPassword.isEmpty ? '—' : _item.loginPassword,
                              style: const TextStyle(color: Color(0xFFFFB300), fontFamily: 'Courier', fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.1),
                            )
                          : const Text(
                              '••••••••••••',
                              style: TextStyle(color: Colors.white70, fontSize: 16, letterSpacing: 3),
                            ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(_isLoginPasswordRevealed ? Icons.visibility_rounded : Icons.visibility_off_rounded, size: 18, color: Colors.white70),
                  tooltip: _isLoginPasswordRevealed ? 'Hide' : 'Reveal',
                  onPressed: () => setState(() => _isLoginPasswordRevealed = !_isLoginPasswordRevealed),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 18, color: Colors.white70),
                  tooltip: 'Copy Password',
                  onPressed: () => _copyToClipboard('Password', _item.loginPassword),
                ),
              ],
            ),
          ),

          // ── Two-Factor Authentication (TOTP / 2FA Live Card) ──
          if (_item.hasTotp) ...[
            const SizedBox(height: 12),
            Builder(builder: (context) {
              final code = TotpService.generateCode(_item.totpSecret);
              final remaining = TotpService.getRemainingSeconds();
              final progress = TotpService.getProgress();
              final formattedCode = code.length == 6
                  ? '${code.substring(0, 3)} ${code.substring(3)}'
                  : code;

              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(
                            value: progress,
                            strokeWidth: 3,
                            backgroundColor: Colors.white12,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              remaining <= 5 ? Colors.redAccent : const Color(0xFF10B981),
                            ),
                          ),
                        ),
                        Text(
                          '$remaining',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: remaining <= 5 ? Colors.redAccent : const Color(0xFF10B981),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text('2FA CODE (TOTP)', style: TextStyle(color: hintColor, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('ROLLING 30s', style: TextStyle(color: Color(0xFF34D399), fontSize: 8, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            formattedCode.isEmpty ? '— — —  — — —' : formattedCode,
                            style: const TextStyle(
                              color: Color(0xFF6EE7B7),
                              fontFamily: 'monospace',
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 20, color: Color(0xFF34D399)),
                      tooltip: 'Copy 2FA Code',
                      onPressed: () => _copyToClipboard('2FA Code', code),
                    ),
                  ],
                ),
              );
            }),
          ],

          // ── Breach Watch (HaveIBeenPwned k-Anonymity Scanner) ──
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: _isCheckingBreach
                ? const Row(
                    children: [
                      SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70)),
                      SizedBox(width: 10),
                      Text('Scanning 14+ billion leaked records...', style: TextStyle(color: Colors.white70, fontSize: 11)),
                    ],
                  )
                : _breachResult == null
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.security_rounded, size: 16, color: Color(0xFF818CF8)),
                              SizedBox(width: 8),
                              Text('Breach Watch', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                            ],
                          ),
                          InkWell(
                            onTap: _checkBreachStatus,
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF6F00),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text('Check Leaks', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Icon(
                            _breachResult!.isPwned ? Icons.warning_amber_rounded : Icons.verified_user_rounded,
                            size: 18,
                            color: _breachResult!.isPwned ? Colors.redAccent : const Color(0xFF34D399),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _breachResult!.isPwned
                                  ? 'Exposed in ${_breachResult!.breachCount} public breaches! Change recommended.'
                                  : 'Safe! Not found in any known public data leaks.',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: _breachResult!.isPwned ? const Color(0xFFFCA5A5) : const Color(0xFFA7F3D0),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh_rounded, size: 16, color: Colors.white70),
                            onPressed: _checkBreachStatus,
                            tooltip: 'Re-check',
                          ),
                        ],
                      ),
          ),

          // ── Password Version History Timeline ──
          if (_item.passwordHistory.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildPasswordHistoryTimeline(),
          ],
        ],
      ),
    );
  }

  Widget _buildPasswordHistoryTimeline() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _isHistoryExpanded = !_isHistoryExpanded),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.history_rounded, color: Color(0xFF818CF8), size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'PASSWORD VERSION HISTORY (${_item.passwordHistory.length})',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  Icon(
                    _isHistoryExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: Colors.white70,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (_isHistoryExpanded) ...[
            const Divider(color: Colors.white12, height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              child: Column(
                children: List.generate(_item.passwordHistory.length, (idx) {
                  final entry = _item.passwordHistory[idx];
                  final isRevealed = _revealedHistoryIndexes.contains(idx);
                  final dtStr = DateFormat('dd MMM yyyy, hh:mm a').format(entry.changedAt);

                  return Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: idx == 0 ? const Color(0xFFFF6F00) : const Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                idx == 0 ? 'Previous Password ($dtStr)' : 'Version ${idx + 1} ($dtStr)',
                                style: const TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isRevealed ? entry.password : '••••••••••••',
                                style: TextStyle(
                                  color: isRevealed ? const Color(0xFFFFB300) : Colors.white70,
                                  fontFamily: isRevealed ? 'Courier' : null,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: isRevealed ? 1 : 2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            isRevealed ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                            size: 16,
                            color: Colors.white70,
                          ),
                          tooltip: isRevealed ? 'Hide' : 'Reveal',
                          onPressed: () {
                            setState(() {
                              if (isRevealed) {
                                _revealedHistoryIndexes.remove(idx);
                              } else {
                                _revealedHistoryIndexes.add(idx);
                              }
                            });
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy_rounded, size: 16, color: Colors.white70),
                          tooltip: 'Copy Previous Password',
                          onPressed: () => _copyToClipboard('Previous Password', entry.password),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Stylized Credit Card Matching Reference Image ─────────────────────────

  Widget _buildCardVisual() {
    final formattedNumber = _formatCardNumber(_item.cardNumber);
    final tierName = _item.cardTier.displayName.toUpperCase();
    final gradient = CardDetector.getCardGradient(_item.bankName, _item.cardTier);
    final isLight = (_item.cardTier == CardTier.gold || _item.cardTier == CardTier.platinum) ||
        (gradient.first.computeLuminance() > 0.55);
    final textColor = isLight ? Colors.black87 : Colors.white;
    final subColor = isLight ? Colors.black54 : Colors.white70;
    final hintColor = isLight ? Colors.black38 : Colors.white54;

    return AspectRatio(
      aspectRatio: 85.60 / 53.98, // Real credit/debit card dimensions (ISO/IEC 7810 ID-1 standard)
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: textColor.withValues(alpha: 0.15), width: 1),
          boxShadow: [
            BoxShadow(
              color: gradient.first.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Row 0: Bank Name + Debit/Credit Badge + Tier Name
            Row(
              children: [
                Expanded(
                  child: Text(
                    _item.bankName.isEmpty ? 'VAULT CARD' : _item.bankName.toUpperCase(),
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      letterSpacing: 1.2,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: (_item.isDebit ? const Color(0xFF10B981) : const Color(0xFF6366F1)).withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: (_item.isDebit ? const Color(0xFF10B981) : const Color(0xFF6366F1)).withValues(alpha: 0.6),
                    ),
                  ),
                  child: Text(
                    _item.isDebit ? 'DEBIT' : 'CREDIT',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  tierName,
                  style: TextStyle(
                    color: subColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.6,
                  ),
                ),
              ],
            ),

            // Row 1: EMV Gold Chip + Contactless icon
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Realistic Gold EMV Chip
                Container(
                  width: 38,
                  height: 28,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFD54F), Color(0xFFFFB300), Color(0xFFFFA000)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.black26, width: 0.5),
                  ),
                  child: Stack(
                    children: [
                      Positioned(top: 8, left: 0, right: 0, child: Container(height: 1, color: Colors.black26)),
                      Positioned(top: 18, left: 0, right: 0, child: Container(height: 1, color: Colors.black26)),
                      Positioned(left: 18, top: 0, bottom: 0, child: Container(width: 1, color: Colors.black26)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  Icons.contactless_rounded,
                  color: textColor.withValues(alpha: 0.7),
                  size: 20,
                ),
              ],
            ),

            // Card Number: ALWAYS UNMASKED in full (Tapping copies card number)
            InkWell(
              key: _cardNumKey,
              onTap: () => _copyToClipboard('Card number', _item.cardNumber.replaceAll(' ', '')),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  formattedNumber,
                  style: TextStyle(
                    color: textColor,
                    fontFamily: 'Courier',
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.5,
                  ),
                ),
              ),
            ),

            // Cardholder Name (Tapping copies name)
            InkWell(
              onTap: () => _copyToClipboard('Cardholder name', _item.cardHolder),
              borderRadius: BorderRadius.circular(6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CARD HOLDER',
                    style: TextStyle(
                      color: hintColor,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _item.cardHolder.isEmpty ? 'VAULT USER' : _item.cardHolder.toUpperCase(),
                    style: TextStyle(
                      color: textColor,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            ),

            // Bottom Row: Expiry + CVV (with Eye button right beside CVV) + Network Logo
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // EXPIRES (Tapping copies expiry)
                InkWell(
                  onTap: () => _copyToClipboard('Expiry', _item.expiry),
                  borderRadius: BorderRadius.circular(6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'EXPIRES',
                        style: TextStyle(
                          color: hintColor,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _item.expiry.isEmpty ? 'MM/YY' : _item.expiry,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 24),

                // CVV: Masked by default, with EYE BUTTON right beside it!
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CVV',
                      style: TextStyle(
                        color: hintColor,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // CVV value (tap to copy)
                        InkWell(
                          onTap: () => _copyToClipboard('CVV', _item.cvv),
                          borderRadius: BorderRadius.circular(6),
                          child: _isCvvRevealed
                              ? Text(
                                  _item.cvv.isEmpty ? '•••' : _item.cvv,
                                  style: const TextStyle(
                                    color: Color(0xFFFFB300),
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 2,
                                  ),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Icon(Icons.lock_rounded, color: Color(0xFFFFB300), size: 12),
                                    SizedBox(width: 3),
                                    Text(
                                      'Protected',
                                      style: TextStyle(
                                        color: Color(0xFFFFB300),
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                        const SizedBox(width: 4),
                        // EYE BUTTON RIGHT BESIDE CVV
                        InkWell(
                          key: _cvvEyeKey,
                          onTap: () => setState(() => _isCvvRevealed = !_isCvvRevealed),
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.all(2.0),
                            child: Icon(
                              _isCvvRevealed ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                              color: _isCvvRevealed ? const Color(0xFFFFB300) : textColor.withValues(alpha: 0.7),
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const Spacer(),

                // Brand Logo (Visa, Mastercard, RuPay, etc.)
                _buildNetworkBadge(_item.cardNetwork),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── Stylized NetBanking Card Visual (Displays All Stored Fields) ───────────

  Widget _buildNetBankingCardVisual() {
    final gradient = CardDetector.getCardGradient(_item.bankName, CardTier.standard);
    final isLight = gradient.first.computeLuminance() > 0.55;
    final textColor = isLight ? Colors.black87 : Colors.white;
    final subColor = isLight ? Colors.black54 : Colors.white70;
    final hintColor = isLight ? Colors.black38 : Colors.white54;
    final accentColor = const Color(0xFFFFB300);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: textColor.withValues(alpha: 0.15), width: 1),
        boxShadow: [
          BoxShadow(
            color: gradient.first.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header: Bank Logo + Bank Name + Nickname Badge ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: textColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.account_balance_rounded, color: accentColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _item.bankName.toUpperCase(),
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        letterSpacing: 1.2,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_item.nickname.isNotEmpty)
                      Text(
                        _item.nickname,
                        style: TextStyle(
                          color: subColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: accentColor.withValues(alpha: 0.5)),
                ),
                child: const Text(
                  'BANK',
                  style: TextStyle(
                    color: Color(0xFFFFB300),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ── Bank Accounts (Account Number + IFSC Code on same row/card) ──
          if (_item.allAccounts.isNotEmpty) ...[
            ..._item.allAccounts.asMap().entries.map((entry) {
              final idx = entry.key;
              final acc = entry.value;
              return Container(
                key: idx == 0 ? _nbAccountRowKey : null,
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: textColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: textColor.withValues(alpha: 0.12)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _item.allAccounts.length > 1 ? 'ACCOUNT #${idx + 1}' : 'PRIMARY ACCOUNT',
                          style: const TextStyle(color: Color(0xFFFFB300), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                        ),
                        InkWell(
                          key: idx == 0 ? _nbCopyBothKey : null,
                          onTap: () => _copyToClipboard(
                            'Account Details',
                            'Account: ${acc.accountNumber}${acc.ifscCode.isNotEmpty ? " | IFSC: ${acc.ifscCode}" : ""}',
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.copy_rounded, size: 12, color: hintColor),
                              const SizedBox(width: 4),
                              Text('Copy Both', style: TextStyle(color: hintColor, fontSize: 10, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Account Number (Maximized width & reduced digit gap)
                        Expanded(
                          flex: 7,
                          child: InkWell(
                            onTap: () => _copyToClipboard('Account Number', acc.accountNumber),
                            borderRadius: BorderRadius.circular(8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('ACCOUNT NUMBER', style: TextStyle(color: hintColor, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.6)),
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        acc.accountNumber,
                                        style: TextStyle(
                                          color: textColor,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -0.3, // Reduced gap between numbers to fit max numbers on a single line
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(Icons.copy_rounded, size: 14, color: textColor.withValues(alpha: 0.6)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (acc.ifscCode.isNotEmpty) ...[
                          Container(
                            width: 1,
                            height: 32,
                            color: textColor.withValues(alpha: 0.15),
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          // IFSC Code (On the same row!)
                          Expanded(
                            flex: 5,
                            child: InkWell(
                              onTap: () => _copyToClipboard('IFSC Code', acc.ifscCode),
                              borderRadius: BorderRadius.circular(8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('IFSC CODE', style: TextStyle(color: hintColor, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.6)),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          acc.ifscCode,
                                          style: TextStyle(
                                            color: textColor,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.2,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(Icons.copy_rounded, size: 14, color: textColor.withValues(alpha: 0.6)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],

          // ── User ID / Customer ID ──
          InkWell(
            onTap: () => _copyToClipboard('User ID', _item.userId),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: textColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: textColor.withValues(alpha: 0.12)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('USER ID / CUSTOMER ID', style: TextStyle(color: hintColor, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                        const SizedBox(height: 3),
                        Text(
                          _item.userId.isEmpty ? '—' : _item.userId,
                          style: TextStyle(color: textColor, fontFamily: 'Courier', fontSize: 17, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.copy_rounded, size: 18, color: textColor.withValues(alpha: 0.7)),
                    tooltip: 'Copy User ID',
                    onPressed: () => _copyToClipboard('User ID', _item.userId),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ── CIF Number (if present) ──
          if (_item.cifNumber.isNotEmpty) ...[
            InkWell(
              onTap: () => _copyToClipboard('CIF Number', _item.cifNumber),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: textColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: textColor.withValues(alpha: 0.12)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('CIF NUMBER', style: TextStyle(color: hintColor, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                          const SizedBox(height: 3),
                          Text(
                            _item.cifNumber,
                            style: TextStyle(color: textColor, fontFamily: 'Courier', fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 1.1),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.copy_rounded, size: 18, color: textColor.withValues(alpha: 0.7)),
                      tooltip: 'Copy CIF Number',
                      onPressed: () => _copyToClipboard('CIF Number', _item.cifNumber),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── Login Password ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: textColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: textColor.withValues(alpha: 0.12)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('LOGIN PASSWORD', style: TextStyle(color: hintColor, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    _buildPasswordExpiryBadge(_item.loginPasswordDaysRemaining, _item.loginPasswordExpiry),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _copyToClipboard('Login Password', _item.loginPassword),
                        child: Text(
                          _isLoginPasswordRevealed ? _item.loginPassword : '••••••••••••',
                          style: TextStyle(
                            color: accentColor,
                            fontFamily: _isLoginPasswordRevealed ? 'Courier' : null,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: _isLoginPasswordRevealed ? 1 : 2,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _isLoginPasswordRevealed ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                        color: _isLoginPasswordRevealed ? accentColor : textColor.withValues(alpha: 0.7),
                        size: 20,
                      ),
                      tooltip: _isLoginPasswordRevealed ? 'Hide Password' : 'Show Password',
                      onPressed: () => setState(() => _isLoginPasswordRevealed = !_isLoginPasswordRevealed),
                    ),
                    IconButton(
                      icon: Icon(Icons.copy_rounded, size: 18, color: textColor.withValues(alpha: 0.7)),
                      tooltip: 'Copy Login Password',
                      onPressed: () => _copyToClipboard('Login Password', _item.loginPassword),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── Profile / Transaction Password (if stored) ──
          if (_item.profilePassword.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: textColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: textColor.withValues(alpha: 0.12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('PROFILE / TRANSACTION PASSWORD', style: TextStyle(color: hintColor, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                      _buildPasswordExpiryBadge(_item.profilePasswordDaysRemaining, _item.profilePasswordExpiry),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => _copyToClipboard('Profile Password', _item.profilePassword),
                          child: Text(
                            _isProfilePasswordRevealed ? _item.profilePassword : '••••••••••••',
                            style: TextStyle(
                              color: accentColor,
                              fontFamily: _isProfilePasswordRevealed ? 'Courier' : null,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: _isProfilePasswordRevealed ? 1 : 2,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          _isProfilePasswordRevealed ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                          color: _isProfilePasswordRevealed ? accentColor : textColor.withValues(alpha: 0.7),
                          size: 20,
                        ),
                        tooltip: _isProfilePasswordRevealed ? 'Hide Profile Password' : 'Show Profile Password',
                        onPressed: () => setState(() => _isProfilePasswordRevealed = !_isProfilePasswordRevealed),
                      ),
                      IconButton(
                        icon: Icon(Icons.copy_rounded, size: 18, color: textColor.withValues(alpha: 0.7)),
                        tooltip: 'Copy Profile Password',
                        onPressed: () => _copyToClipboard('Profile Password', _item.profilePassword),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── MPIN (Mobile PIN) (if stored) ──
          if (_item.mpin.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: textColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: textColor.withValues(alpha: 0.12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('MPIN (MOBILE BANKING PIN)', style: TextStyle(color: hintColor, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                      _buildPasswordExpiryBadge(_item.mpinDaysRemaining, _item.mpinExpiry),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => _copyToClipboard('MPIN', _item.mpin),
                          child: Text(
                            _isMpinRevealed ? _item.mpin : '••••••',
                            style: TextStyle(
                              color: accentColor,
                              fontFamily: 'Courier',
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: _isMpinRevealed ? 3 : 2,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          _isMpinRevealed ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                          color: _isMpinRevealed ? accentColor : textColor.withValues(alpha: 0.7),
                          size: 20,
                        ),
                        tooltip: _isMpinRevealed ? 'Hide MPIN' : 'Show MPIN',
                        onPressed: () => setState(() => _isMpinRevealed = !_isMpinRevealed),
                      ),
                      IconButton(
                        icon: Icon(Icons.copy_rounded, size: 18, color: textColor.withValues(alpha: 0.7)),
                        tooltip: 'Copy MPIN',
                        onPressed: () => _copyToClipboard('MPIN', _item.mpin),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPasswordExpiryBadge(int? daysRemaining, DateTime? expiryDate) {
    if (expiryDate == null) {
      return Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text('No Expiry', style: TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.w500)),
      );
    }

    final isExpired = daysRemaining != null && daysRemaining < 0;
    final isSoon = daysRemaining != null && daysRemaining >= 0 && daysRemaining <= 15;

    Color bg;
    Color border;
    Color text;
    String label;

    if (isExpired) {
      bg = Colors.red.withValues(alpha: 0.25);
      border = Colors.redAccent;
      text = const Color(0xFFFF8A80);
      label = 'EXPIRED (${DateFormat('dd/MM/yy').format(expiryDate)})';
    } else if (isSoon) {
      bg = Colors.amber.withValues(alpha: 0.25);
      border = Colors.amber;
      text = const Color(0xFFFFD54F);
      label = daysRemaining == 0 ? 'EXPIRES TODAY' : 'Expires in ${daysRemaining}d';
    } else {
      bg = const Color(0xFF10B981).withValues(alpha: 0.2);
      border = const Color(0xFF10B981);
      text = const Color(0xFFA7F3D0);
      label = 'Exp: ${DateFormat('dd/MM/yy').format(expiryDate)}';
    }

    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border.withValues(alpha: 0.6), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(color: text, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildNetBankingExpiryBanner() {
    final isExpired = _item.isAnyPasswordExpired;
    final expiredNames = <String>[];
    final soonNames = <String>[];

    if (_item.isLoginPasswordExpired) expiredNames.add('Login Password');
    if (_item.isProfilePasswordExpired) expiredNames.add('Profile Password');
    if (_item.isMpinExpired) expiredNames.add('MPIN');

    if (_item.isLoginPasswordExpiringSoon) soonNames.add('Login Password (${_item.loginPasswordDaysRemaining}d)');
    if (_item.isProfilePasswordExpiringSoon) soonNames.add('Profile Password (${_item.profilePasswordDaysRemaining}d)');
    if (_item.isMpinExpiringSoon) soonNames.add('MPIN (${_item.mpinDaysRemaining}d)');

    final message = isExpired
        ? 'Expired: ${expiredNames.join(", ")}. Please update your credentials with ${_item.bankName}.'
        : 'Expiring Soon: ${soonNames.join(", ")}. Change password before it expires.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isExpired ? const Color(0xFFFEF2F2) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isExpired ? Colors.red.shade200 : const Color(0xFFFDE68A),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isExpired ? Icons.error_outline_rounded : Icons.warning_amber_rounded,
            color: isExpired ? Colors.red : const Color(0xFFD97706),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: isExpired ? Colors.red.shade900 : const Color(0xFF92400E),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Quick Action Dock (4 Circular Buttons - Light Theme) ──────────────────

  Widget _buildQuickActionDock() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildCircularDockButton(
          key: _copyDockKey,
          icon: Icons.copy_rounded,
          label: 'Copy',
          onTap: _copyAllDetails,
        ),
        _buildCircularDockButton(
          key: _shareDockKey,
          icon: Icons.share_rounded,
          label: 'Share',
          onTap: _shareDetails,
        ),
        _buildCircularDockButton(
          key: _editDockKey,
          icon: Icons.edit_outlined,
          label: 'Edit',
          onTap: _editItem,
        ),
        _buildCircularDockButton(
          key: _deleteDockKey,
          icon: Icons.delete_outline_rounded,
          label: 'Delete',
          onTap: _confirmDelete,
          isDestructive: true,
        ),
      ],
    );
  }

  Widget _buildCircularDockButton({
    Key? key,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final iconColor = isDestructive ? const Color(0xFFEF4444) : const Color(0xFF0F172A);
    final circleBorder = isDestructive
        ? const Color(0xFFFCA5A5)
        : const Color(0xFFE2E8F0);
    final circleBg = isDestructive
        ? const Color(0xFFFEF2F2)
        : Colors.white;

    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: circleBg,
              border: Border.all(color: circleBorder, width: 1.5),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: isDestructive ? const Color(0xFFEF4444) : const Color(0xFF475569),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Secure Notes Widget (Light Theme) ────────────────────────────────────

  Widget _buildNotesWidget() {
    final hasNotes = _item.notes.trim().isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          hasNotes ? _item.notes : 'No notes saved. Tap Edit to add extra info.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: hasNotes ? const Color(0xFF1E293B) : const Color(0xFF94A3B8),
            fontStyle: FontStyle.italic,
            fontSize: 13,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _buildCreditTrackerCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.speed_rounded, color: Color(0xFFFF6F00), size: 18),
              SizedBox(width: 8),
              Text(
                'Credit Limit & Billing Tracker',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (_item.creditLimit > 0)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('TOTAL LIMIT', style: TextStyle(color: Color(0xFF64748B), fontSize: 10, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(
                        '₹${formatIndianNumber(_item.creditLimit)}',
                        style: const TextStyle(color: Color(0xFF0F172A), fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              if (_item.statementDay > 0)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('STATEMENT', style: TextStyle(color: Color(0xFF64748B), fontSize: 10, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(
                        '${_item.statementDay} of month',
                        style: const TextStyle(color: Color(0xFF0F172A), fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              if (_item.dueDay > 0)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('DUE DATE', style: TextStyle(color: Color(0xFF64748B), fontSize: 10, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(
                        '${_item.dueDay} of month',
                        style: TextStyle(
                          color: (_item.daysUntilPaymentDue != null && _item.daysUntilPaymentDue! <= 5)
                              ? Colors.red
                              : const Color(0xFF0F172A),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkBadge(String network) {
    final upper = network.toUpperCase();
    if (upper.contains('VISA')) {
      return const Text(
        'Visa',
        style: TextStyle(
          color: Colors.white,
          fontFamily: 'serif',
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w900,
          fontSize: 26,
        ),
      );
    } else if (upper.contains('MASTER')) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 18, height: 18, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.red)),
          Transform.translate(
            offset: const Offset(-6, 0),
            child: Container(width: 18, height: 18, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.amber)),
          ),
        ],
      );
    } else if (upper.contains('RUPAY')) {
      return const Text('RuPay❯', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16));
    } else if (upper.contains('AMEX')) {
      return const Text('AMEX', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16));
    } else if (upper.contains('DISCOVER')) {
      return const Text('DISCOVER', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16));
    } else if (upper.contains('DINERS')) {
      return const Text('Diners Club', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14));
    } else if (upper.contains('JCB')) {
      return const Text('JCB', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16));
    } else if (upper.contains('UNION')) {
      return const Text('UnionPay', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15));
    } else if (upper.contains('MAESTRO')) {
      return const Text('maestro', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15));
    }
    return Text(network, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15));
  }
}
