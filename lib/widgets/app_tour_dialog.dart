import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/vault_security_service.dart';

/// Interactive guided tour for new users to explore CardVault's features.
class AppTourDialog extends StatefulWidget {
  const AppTourDialog({super.key});

  /// Helper static method to show the tour modal sheet or dialog
  static Future<void> show(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: false,
      builder: (ctx) => const AppTourDialog(),
    );
  }

  @override
  State<AppTourDialog> createState() => _AppTourDialogState();
}

class _AppTourDialogState extends State<AppTourDialog> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  final int _totalPages = 7;

  late final String _randomFutureExpiry;
  late final String _randomCvv;
  late final String _randomCardNumber;
  late final String _randomAccountNum1;
  late final String _randomAccountNum2;
  late final String _randomIfsc1;
  late final String _randomIfsc2;

  @override
  void initState() {
    super.initState();
    final rng = math.Random();
    final now = DateTime.now();
    // Generate random future date: between 3 and 60 months ahead
    final monthsAhead = 3 + rng.nextInt(58);
    final futureYear = now.year + (now.month + monthsAhead - 1) ~/ 12;
    final futureMonth = ((now.month + monthsAhead - 1) % 12) + 1;
    final mm = futureMonth.toString().padLeft(2, '0');
    final yy = (futureYear % 100).toString().padLeft(2, '0');
    _randomFutureExpiry = '$mm/$yy';

    _randomCvv = (100 + rng.nextInt(900)).toString();
    final b2 = (1000 + rng.nextInt(9000)).toString();
    final b3 = (1000 + rng.nextInt(9000)).toString();
    final b4 = (1000 + rng.nextInt(9000)).toString();
    _randomCardNumber = '4532 $b2 $b3 $b4';

    // Random bank account digits (14 digits) and IFSC branches
    final a1 = (50000000 + rng.nextInt(49999999)).toString();
    final a2 = (100000 + rng.nextInt(900000)).toString();
    _randomAccountNum1 = '$a1$a2';
    final a3 = (50000000 + rng.nextInt(49999999)).toString();
    final a4 = (100000 + rng.nextInt(900000)).toString();
    _randomAccountNum2 = '$a3$a4';
    _randomIfsc1 = 'HDFC000${1000 + rng.nextInt(8999)}';
    _randomIfsc2 = 'HDFC000${1000 + rng.nextInt(8999)}';
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _finishTour() {
    final sec = context.read<VaultSecurityService>();
    sec.setTourSeen(true);
    Navigator.of(context).pop();
  }

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _finishTour();
    }
  }

  void _prevPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
        color: Color(0xFFF8F9FA),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // ── Drag Handle & Header ──
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xFFCBD5E1),
              borderRadius: BorderRadius.circular(3),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6F00).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Step ${_currentPage + 1} of $_totalPages',
                    style: const TextStyle(
                      color: Color(0xFFFF6F00),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _finishTour,
                  child: const Text(
                    'Skip Tour',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Progress Bar ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (_currentPage + 1) / _totalPages,
                backgroundColor: const Color(0xFFE2E8F0),
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFF6F00)),
                minHeight: 4,
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ── Pager Slides ──
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (index) => setState(() => _currentPage = index),
              children: [
                _buildSlide1Dashboard(),
                _buildSlide2RealisticCard(),
                _buildSlide3QuickDock(),
                _buildSlide4AddForm(),
                _buildSlide5BankAccounts(),
                _buildSlide6KeyboardAutofill(),
                _buildSlide7CloudSecurity(),
              ],
            ),
          ),

          // ── Bottom Navigation Bar ──
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Back Button
                if (_currentPage > 0)
                  TextButton(
                    onPressed: _prevPage,
                    child: const Text(
                      'Back',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  )
                else
                  const SizedBox(width: 60),

                // Indicator Dots
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(_totalPages, (i) {
                    final isActive = i == _currentPage;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: isActive ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isActive ? const Color(0xFFFF6F00) : const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),

                // Next or Get Started Button
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6F00),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _nextPage,
                  child: Text(
                    _currentPage == _totalPages - 1 ? "Let's Go! 🚀" : 'Next',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Slide 1: Dashboard Overview ──────────────────────────────────────────

  Widget _buildSlide1Dashboard() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Visual Mockup of Dashboard Header & Bank Group
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top App Bar Preview
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: Color(0xFFFFF7ED),
                      child: Icon(Icons.person_rounded, color: Color(0xFFFF6F00), size: 16),
                    ),
                    Text(
                      'My Vault',
                      style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    Row(
                      children: [
                        Icon(Icons.cloud_sync_rounded, color: Color(0xFFFF6F00), size: 18),
                        SizedBox(width: 8),
                        Icon(Icons.lock_rounded, color: Color(0xFF64748B), size: 18),
                      ],
                    ),
                  ],
                ),
                const Divider(height: 18, color: Color(0xFFF1F5F9)),
                // Bank Header
                const Row(
                  children: [
                    Icon(Icons.account_balance_rounded, color: Color(0xFFFF6F00), size: 15),
                    SizedBox(width: 6),
                    Text('HDFC BANK (2)', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 8),
                // Card item tile
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F9FA),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.credit_card_rounded, color: Color(0xFFFF6F00), size: 18),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text('Regalia Gold Card', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
                        child: const Text('GOLD', style: TextStyle(color: Color(0xFF475569), fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Title & Description
          const Text(
            'Welcome to Your Vault',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Your cards and Bank credentials are kept safe here, automatically organized alphabetically by Bank Name.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF64748B), fontSize: 13, height: 1.4),
          ),

          const SizedBox(height: 20),

          // Feature points
          _buildFeatureBullet(
            icon: Icons.sort_by_alpha_rounded,
            title: 'Bank-Grouped Dashboard',
            desc: 'Cards and accounts are automatically sorted under their bank headers for fast scanning.',
          ),
          _buildFeatureBullet(
            icon: Icons.add_circle_rounded,
            title: 'Quick Add Button (+)',
            desc: 'Tap the fixed orange (+) button on the bottom right to store new cards or Bank accounts.',
          ),
        ],
      ),
    );
  }

  // ─── Slide 2: Realistic Card & Tap-to-Copy ─────────────────────────────────

  Widget _buildSlide2RealisticCard() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Realistic Stylized Card Graphic
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF141C2E),
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Gold chip & waves
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 24,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Color(0xFFFFD54F), Color(0xFFFFB300)]),
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.wifi_rounded, color: Colors.white70, size: 16),
                      ],
                    ),
                    const Text('CLASSIC', style: TextStyle(color: Colors.white70, fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 14),
                // Monospace unmasked number
                Text(
                  _randomCardNumber,
                  style: const TextStyle(color: Colors.white, fontFamily: 'Courier', fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 2),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('CARD HOLDER', style: TextStyle(color: Colors.white54, fontSize: 8)),
                        Text('ALEX M MORGAN', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('EXPIRES', style: TextStyle(color: Colors.white54, fontSize: 8)),
                        Text(_randomFutureExpiry, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('CVV', style: TextStyle(color: Colors.white54, fontSize: 8)),
                        Row(
                          children: [
                            Icon(Icons.lock_rounded, color: Color(0xFFFFB300), size: 11),
                            SizedBox(width: 2),
                            Text('Protected', style: TextStyle(color: Color(0xFFFFB300), fontSize: 11, fontWeight: FontWeight.bold)),
                            SizedBox(width: 4),
                            Icon(Icons.visibility_off_rounded, color: Colors.white70, size: 13),
                          ],
                        ),
                      ],
                    ),
                    const Text('Visa', style: TextStyle(color: Colors.white, fontStyle: FontStyle.italic, fontSize: 16, fontWeight: FontWeight.w900)),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          const Text(
            'Realistic Card & Tap-to-Copy',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'All card information is embedded right inside the card itself. Tap any detail to copy it instantly.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF64748B), fontSize: 13, height: 1.4),
          ),

          const SizedBox(height: 20),

          _buildFeatureBullet(
            icon: Icons.touch_app_rounded,
            title: 'Individual Tap-to-Copy',
            desc: 'Tap the Card Number to copy only the digits. Tap Name, Expiry, or CVV to copy each individually.',
          ),
          _buildFeatureBullet(
            icon: Icons.remove_red_eye_rounded,
            title: 'Targeted CVV Eye Toggle',
            desc: 'Card number is always visible for fast entry. Only CVV is hidden behind the eye button beside it.',
          ),
        ],
      ),
    );
  }

  // ─── Slide 3: Quick Action Dock & Sharing ─────────────────────────────────

  Widget _buildSlide3QuickDock() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Action Dock Graphic
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildMiniDockIcon(Icons.copy_rounded, 'Copy', const Color(0xFF0F172A)),
                _buildMiniDockIcon(Icons.share_rounded, 'Share', const Color(0xFF0F172A)),
                _buildMiniDockIcon(Icons.edit_outlined, 'Edit', const Color(0xFF0F172A)),
                _buildMiniDockIcon(Icons.delete_outline_rounded, 'Delete', const Color(0xFFEF4444)),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Code/Preview snippet of shared format
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFFEDD5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('👤 Name: ALEX M MORGAN', style: TextStyle(color: Color(0xFF0F172A), fontSize: 12, fontWeight: FontWeight.bold)),
                const Text('💳 Card: HDFC MILLENNIA', style: TextStyle(color: Color(0xFF0F172A), fontSize: 12, fontWeight: FontWeight.bold)),
                Text('🔢 Card No: $_randomCardNumber', style: const TextStyle(color: Color(0xFF0F172A), fontSize: 12, fontWeight: FontWeight.bold)),
                Text('📅 Exp: $_randomFutureExpiry | 🔑 CVV: $_randomCvv.', style: const TextStyle(color: Color(0xFF0F172A), fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
          ),

          const SizedBox(height: 22),

          const Text(
            'Quick Action Dock & Sharing',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Manage every credential with 4 quick dock actions: Copy All, Share, Edit, or Delete.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF64748B), fontSize: 13, height: 1.4),
          ),

          const SizedBox(height: 18),

          _buildFeatureBullet(
            icon: Icons.share_rounded,
            title: 'Native Android ShareSheet',
            desc: 'Tap Share to send the complete formatted card info cleanly to WhatsApp or messaging apps.',
          ),
          _buildFeatureBullet(
            icon: Icons.copy_all_rounded,
            title: 'One-Tap Copy All',
            desc: 'Copies all details into your clipboard in the standard card template.',
          ),
        ],
      ),
    );
  }

  // ─── Slide 4: Smart Form Adding ───────────────────────────────────────────

  Widget _buildSlide4AddForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Graphic of Side-by-Side Dropdowns
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
            ),
            child: Column(
              children: [
                // Mock Card Type & Tier row
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Visa', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 12)),
                            Icon(Icons.arrow_drop_down, color: Color(0xFFFF6F00), size: 18),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Platinum', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 12)),
                            Icon(Icons.arrow_drop_down, color: Color(0xFFFF6F00), size: 18),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Expiry & CVV row
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: Text(_randomFutureExpiry, style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: const Text('•••', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          const Text(
            'Smart Card Adding & Validation',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Adding a card is effortless with real-time detection, compact inputs, and intelligent validation.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF64748B), fontSize: 13, height: 1.4),
          ),

          const SizedBox(height: 20),

          _buildFeatureBullet(
            icon: Icons.credit_score_rounded,
            title: 'BIN Auto-Detection & Dropdown',
            desc: 'Detects Visa, Mastercard, RuPay, etc. automatically. If unknown, choose easily from the dropdown.',
          ),
          _buildFeatureBullet(
            icon: Icons.calendar_month_rounded,
            title: 'Strict Expiry Month Check (01–12)',
            desc: 'Enforces valid months (01–12). Numbers above 12 or 00 are automatically rejected.',
          ),
        ],
      ),
    );
  }

  // ─── Slide 5: Bank Accounts & Multi-Account Rows ──────────────────────────

  Widget _buildSlide5BankAccounts() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Graphic of Multi-Account Bank Card with Swipe-to-Delete Action
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Bank Card Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6F00).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.account_balance_rounded, color: Color(0xFFFF6F00), size: 20),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'HDFC Bank Accounts',
                            style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          Text(
                            'Salary & Savings • 2 Accounts',
                            style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('BANK', style: TextStyle(color: Color(0xFF2563EB), fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Row 1: Primary Account (Side-by-side Account & IFSC)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Text(
                          'P1',
                          style: TextStyle(color: Colors.green.shade800, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 7,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('ACCOUNT NO', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 8, fontWeight: FontWeight.bold)),
                            Text(
                              _randomAccountNum1,
                              style: const TextStyle(
                                color: Color(0xFF0F172A),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 5,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('IFSC CODE', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 8, fontWeight: FontWeight.bold)),
                            Text(
                              _randomIfsc1,
                              style: const TextStyle(
                                color: Color(0xFF0F172A),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Row 2: Secondary Account with visual Swipe-to-Delete preview
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.red.shade600,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        // Swiped account row
                        Expanded(
                          flex: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              border: Border.all(color: const Color(0xFFCBD5E1)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text('#2', style: TextStyle(color: Color(0xFF64748B), fontSize: 9, fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 7,
                                  child: Text(
                                    _randomAccountNum2,
                                    style: const TextStyle(
                                      color: Color(0xFF0F172A),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 5,
                                  child: Text(
                                    _randomIfsc2,
                                    style: const TextStyle(
                                      color: Color(0xFF0F172A),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Revealed red delete action
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          alignment: Alignment.center,
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.delete_sweep_rounded, color: Colors.white, size: 16),
                              SizedBox(width: 3),
                              Text('Delete', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                // Swipe hint tag
                const Row(
                  children: [
                    Icon(Icons.swipe_left_rounded, size: 13, color: Color(0xFF94A3B8)),
                    SizedBox(width: 4),
                    Text('Swipe left on any extra account row to delete it', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontStyle: FontStyle.italic)),
                  ],
                ),
                const SizedBox(height: 12),

                // Action chips preview
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6F00).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.copy_all_rounded, size: 13, color: Color(0xFFFF6F00)),
                          SizedBox(width: 4),
                          Text('Copy Both (A/C + IFSC)', style: TextStyle(color: Color(0xFFFF6F00), fontSize: 10, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_rounded, size: 13, color: Color(0xFF0F172A)),
                          SizedBox(width: 4),
                          Text('Add Another A/C', style: TextStyle(color: Color(0xFF0F172A), fontSize: 10, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          const Text(
            'Bank Accounts & Multi-Rows',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Store all account numbers and IFSC codes under each bank in a unified entry with swipe-to-delete and instant copy.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF64748B), fontSize: 13, height: 1.4),
          ),

          const SizedBox(height: 20),

          _buildFeatureBullet(
            icon: Icons.account_balance_rounded,
            title: 'Multiple Accounts in Single Form',
            desc: 'Save your Salary, Savings, and Overdraft accounts for the same bank together using "+ Add Another Account Number".',
          ),
          _buildFeatureBullet(
            icon: Icons.swipe_left_rounded,
            title: 'Side-by-Side IFSC & Swipe to Delete',
            desc: 'Account Number and IFSC code share the same row with maximized space. Simply swipe left on any row to delete it.',
          ),
          _buildFeatureBullet(
            icon: Icons.copy_all_rounded,
            title: 'High-Density Display & 1-Tap Copy Both',
            desc: 'Compacted letter spacing displays full 18-digit account numbers on a single line. Tap "Copy Both" to copy Account and IFSC together.',
          ),
        ],
      ),
    );
  }

  // ─── Slide 6: Keyboard Payment Autofill (Gboard) ──────────────────────────

  Widget _buildSlide6KeyboardAutofill() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Graphic of Mobile Payment Page + Gboard Autofill Strip
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Simulated checkout browser bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.lock_rounded, size: 12, color: Colors.green),
                      SizedBox(width: 6),
                      Text('checkout.merchant.com', style: TextStyle(color: Color(0xFF64748B), fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Payment input field with blinking cursor
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFF6F00), width: 1.5),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.credit_card_rounded, size: 16, color: Color(0xFFFF6F00)),
                          SizedBox(width: 8),
                          Text('Card Number |', style: TextStyle(color: Color(0xFF0F172A), fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Icon(Icons.touch_app_rounded, size: 16, color: Color(0xFFFF6F00)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Simulated Gboard Suggestion Strip with Card Chips
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.keyboard_outlined, size: 14, color: Colors.white54),
                      const SizedBox(width: 8),
                      // Card Chip 1
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF6F00),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.credit_card, size: 12, color: Colors.white),
                              SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'HDFC Millennia',
                                  style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Card Chip 2
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF334155),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF475569)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.credit_card, size: 12, color: Colors.white70),
                              SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'Flipkart Axis',
                                  style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          const Text(
            'Keyboard Payment Autofill',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Pay online instantly in Chrome, Amazon, Swiggy, and other apps without switching back and forth to copy details.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF64748B), fontSize: 13, height: 1.4),
          ),

          const SizedBox(height: 20),

          _buildFeatureBullet(
            icon: Icons.keyboard_rounded,
            title: 'Inline Gboard Card Chips',
            desc: 'When you tap any payment field (Card No, Expiry, or CVV), your card nicknames appear right above the keyboard.',
          ),
          _buildFeatureBullet(
            icon: Icons.touch_app_rounded,
            title: 'Targeted Instant Filling',
            desc: 'Tapping a card chip fills the card number, expiry, and CVV into their respective fields seamlessly.',
          ),
          _buildFeatureBullet(
            icon: Icons.security_rounded,
            title: 'Active Only When Unlocked',
            desc: 'Suggestions ONLY show while CardVault is open and unlocked. When locked, suggestions are blocked for complete privacy.',
          ),
        ],
      ),
    );
  }

  // ─── Slide 7: Cloud Sync & Zero-Knowledge Security ────────────────────────

  Widget _buildSlide7CloudSecurity() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Graphic of Google Drive & Biometrics
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6F00).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.add_to_drive_rounded, color: Color(0xFFFF6F00), size: 28),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Google Drive Linked', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 13)),
                      Text('Auto-backs up on every card saved', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                    ],
                  ),
                ),
                const Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
              ],
            ),
          ),

          const SizedBox(height: 24),

          const Text(
            'Zero-Knowledge & Cloud Sync',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Your privacy is guaranteed with local AES-256 encryption, seamless Google Drive backups, and hardware biometrics.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF64748B), fontSize: 13, height: 1.4),
          ),

          const SizedBox(height: 20),

          _buildFeatureBullet(
            icon: Icons.backup_rounded,
            title: 'Automatic Cloud Backups',
            desc: 'Whenever you add or edit an item, CardVault silently syncs the encrypted file to your Google Drive.',
          ),
          _buildFeatureBullet(
            icon: Icons.fingerprint_rounded,
            title: 'Biometric Unlock & FLAG_SECURE',
            desc: 'Unlock swiftly with Fingerprint or Face ID without password prompts. App screenshots are blocked.',
          ),
        ],
      ),
    );
  }

  // ─── Helper Widgets ────────────────────────────────────────────────────────

  Widget _buildFeatureBullet({
    required IconData icon,
    required String title,
    required String desc,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6F00).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFFFF6F00), size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniDockIcon(IconData icon, String label, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFF8F9FA),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
