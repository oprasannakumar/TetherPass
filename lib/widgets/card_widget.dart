import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/vault_item.dart';
import '../services/card_detector.dart';
import '../theme/cyber_theme.dart';

/// Futuristic Robotic Glassmorphism Credit Card Widget
/// Features frosted glass depth, holographic cyber EMV chip,
/// robotic telemetry tier badges, and 3D flip animation.
class CardWidget extends StatefulWidget {
  final String cardNumber;
  final String cardHolder;
  final String expiry;
  final String cvv;
  final String cardNetwork;
  final String bankName;
  final CardTier cardTier;
  final String cardType;
  final bool showFullNumber;
  final bool isInteractive;
  final VoidCallback? onTap;

  const CardWidget({
    super.key,
    required this.cardNumber,
    required this.cardHolder,
    required this.expiry,
    required this.cvv,
    required this.cardNetwork,
    required this.bankName,
    this.cardTier = CardTier.standard,
    this.cardType = '',
    this.showFullNumber = false,
    this.isInteractive = true,
    this.onTap,
  });

  @override
  State<CardWidget> createState() => _CardWidgetState();
}

class _CardWidgetState extends State<CardWidget> with SingleTickerProviderStateMixin {
  late AnimationController _flipController;
  late Animation<double> _flipAnimation;
  bool _showBack = false;

  @override
  void initState() {
    super.initState();
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _flipAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOutBack),
    );
  }

  @override
  void dispose() {
    _flipController.dispose();
    super.dispose();
  }

  void _flip() {
    if (!widget.isInteractive) return;
    if (_showBack) {
      _flipController.reverse();
    } else {
      _flipController.forward();
    }
    setState(() => _showBack = !_showBack);
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _flip,
      child: AnimatedBuilder(
        animation: _flipAnimation,
        builder: (context, child) {
          final angle = _flipAnimation.value * pi;
          final isUnder = angle > (pi / 2);

          return Transform(
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0015)
              ..rotateY(angle),
            alignment: Alignment.center,
            child: isUnder
                ? Transform(
                    transform: Matrix4.identity()..rotateY(pi),
                    alignment: Alignment.center,
                    child: _buildBackFace(),
                  )
                : _buildFrontFace(),
          );
        },
      ),
    );
  }

  Widget _buildFrontFace() {
    final baseGradient = CardDetector.getCardGradient(widget.bankName, widget.cardTier);
    final tierColor = _getTierAccentColor(widget.cardTier);

    return AspectRatio(
      aspectRatio: 85.60 / 53.98, // ISO/IEC 7810 ID-1 standard dimensions
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: tierColor.withValues(alpha: 0.28),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.7),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  colors: [
                    baseGradient.first.withValues(alpha: 0.88),
                    baseGradient.last.withValues(alpha: 0.72),
                    const Color(0xFF070B14).withValues(alpha: 0.92),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: tierColor.withValues(alpha: 0.45),
                  width: 1.2,
                ),
              ),
              child: Stack(
                children: [
                  // Futuristic Circuit Line Trace Overlay
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _CardCircuitPainter(accentColor: tierColor),
                    ),
                  ),

                  // Ambient Sheen Orb
                  Positioned(
                    right: -30,
                    top: -30,
                    child: Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            tierColor.withValues(alpha: 0.25),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Card Content
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Top Header: Bank Name & Robotic Tier Badges
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: tierColor,
                                    boxShadow: [
                                      BoxShadow(color: tierColor, blurRadius: 6),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Text(
                                  widget.bankName.isEmpty ? 'VAULT CARD' : widget.bankName.toUpperCase(),
                                  style: CyberTypography.hudTitle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: 1.4,
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (widget.cardType.isNotEmpty) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                    decoration: BoxDecoration(
                                      color: (widget.cardType.toLowerCase().contains('debit')
                                              ? CyberColors.electricMint
                                              : CyberColors.laserCyan)
                                          .withValues(alpha: 0.16),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: (widget.cardType.toLowerCase().contains('debit')
                                                ? CyberColors.electricMint
                                                : CyberColors.laserCyan)
                                            .withValues(alpha: 0.5),
                                        width: 0.8,
                                      ),
                                    ),
                                    child: Text(
                                      widget.cardType.toUpperCase(),
                                      style: CyberTypography.mono(
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.bold,
                                        color: widget.cardType.toLowerCase().contains('debit')
                                            ? CyberColors.electricMint
                                            : CyberColors.laserCyan,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                ],
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                                  decoration: BoxDecoration(
                                    color: tierColor.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: tierColor.withValues(alpha: 0.6), width: 1),
                                  ),
                                  child: Text(
                                    widget.cardTier.displayName.toUpperCase(),
                                    style: CyberTypography.mono(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        // Holographic Robotic EMV Chip + NFC Waves
                        Row(
                          children: [
                            _buildHoloChip(),
                            const SizedBox(width: 14),
                            Icon(
                              Icons.contactless_rounded,
                              color: tierColor.withValues(alpha: 0.85),
                              size: 24,
                            ),
                          ],
                        ),

                        // Monospace Card Number
                        Text(
                          widget.showFullNumber
                              ? _formatNumber(widget.cardNumber)
                              : _maskNumber(widget.cardNumber),
                          style: CyberTypography.mono(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.6,
                          ),
                        ),

                        // Bottom Row: Cardholder, Expiry, Network Badge
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'IDENTITY CORES',
                                    style: CyberTypography.mono(
                                      color: CyberColors.textMuted,
                                      fontSize: 7.5,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    widget.cardHolder.isEmpty
                                        ? 'SOVEREIGN KEY'
                                        : widget.cardHolder.toUpperCase(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: CyberTypography.hudTitle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'TTL VALID',
                                  style: CyberTypography.mono(
                                    color: CyberColors.textMuted,
                                    fontSize: 7.5,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  widget.expiry.isEmpty ? 'MM/YY' : widget.expiry,
                                  style: CyberTypography.mono(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 14),
                            _buildNetworkBadge(widget.cardNetwork),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackFace() {
    final baseGradient = CardDetector.getCardGradient(widget.bankName, widget.cardTier);
    final tierColor = _getTierAccentColor(widget.cardTier);

    return AspectRatio(
      aspectRatio: 85.60 / 53.98,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: tierColor.withValues(alpha: 0.25),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  colors: [
                    baseGradient.first.withValues(alpha: 0.88),
                    baseGradient.last.withValues(alpha: 0.75),
                    const Color(0xFF05080E).withValues(alpha: 0.95),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: tierColor.withValues(alpha: 0.45),
                  width: 1.2,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  // Frosted Cybernetic Magnetic Stripe
                  Container(
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.88),
                      border: const Border(
                        top: BorderSide(color: Color(0x3300E5FF), width: 0.8),
                        bottom: BorderSide(color: Color(0x3300E5FF), width: 0.8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Signature Strip & High-Tech Monospace CVV Terminal
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Container(
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E283C).withValues(alpha: 0.85),
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(6),
                                bottomLeft: Radius.circular(6),
                              ),
                              border: Border.all(color: CyberColors.glassBorderMuted, width: 0.8),
                            ),
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Text(
                              'HARDWARE ENCLAVE SIGNATURE',
                              style: CyberTypography.mono(
                                fontSize: 8.5,
                                color: CyberColors.textMuted,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Container(
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: const BorderRadius.only(
                                topRight: Radius.circular(6),
                                bottomRight: Radius.circular(6),
                              ),
                              border: Border.all(color: CyberColors.laserCyan, width: 1.2),
                              boxShadow: [
                                BoxShadow(
                                  color: CyberColors.laserCyan.withValues(alpha: 0.3),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              widget.cvv.isEmpty ? '•••' : widget.cvv,
                              style: CyberTypography.mono(
                                color: CyberColors.laserCyan,
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                                letterSpacing: 2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'VOLATILE CVV // AIR-GAP PROTECTED',
                          style: CyberTypography.mono(
                            color: CyberColors.textMuted,
                            fontSize: 8.5,
                            letterSpacing: 0.8,
                          ),
                        ),
                        Text(
                          'TAP TO FLIP ↩',
                          style: CyberTypography.mono(
                            color: CyberColors.laserCyan,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHoloChip() {
    return Container(
      width: 40,
      height: 30,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        gradient: const LinearGradient(
          colors: [
            Color(0xFFFFDF7A),
            Color(0xFFE5A93C),
            Color(0xFFB57D20),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.black38, width: 0.8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66FFDF7A),
            blurRadius: 6,
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: Container(height: 1, color: Colors.black38),
          ),
          Positioned(
            top: 19,
            left: 0,
            right: 0,
            child: Container(height: 1, color: Colors.black38),
          ),
          Positioned(
            left: 19,
            top: 0,
            bottom: 0,
            child: Container(width: 1, color: Colors.black38),
          ),
          Center(
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black45, width: 0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getTierAccentColor(CardTier tier) {
    switch (tier) {
      case CardTier.infinite:
        return CyberColors.laserCyan;
      case CardTier.signature:
        return CyberColors.quantumViolet;
      case CardTier.platinum:
        return const Color(0xFFE2E8F0);
      case CardTier.gold:
        return const Color(0xFFFBBF24);
      case CardTier.standard:
        return CyberColors.laserCyan;
    }
  }

  Widget _buildNetworkBadge(String network) {
    final net = network.toUpperCase();
    if (net.contains('VISA')) {
      return Text(
        'VISA',
        style: CyberTypography.hudTitle(
          fontSize: 16,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          letterSpacing: 1.2,
        ),
      );
    } else if (net.contains('MASTER')) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 15,
            height: 15,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFEB001B),
            ),
          ),
          Transform.translate(
            offset: const Offset(-6, 0),
            child: Container(
              width: 15,
              height: 15,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFF79E1B),
              ),
            ),
          ),
        ],
      );
    } else if (net.contains('RUPAY')) {
      return Text(
        'RuPay❯',
        style: CyberTypography.hudTitle(
          fontSize: 14,
          fontWeight: FontWeight.w900,
          color: CyberColors.laserCyan,
        ),
      );
    } else if (net.contains('AMEX')) {
      return Text(
        'AMEX',
        style: CyberTypography.hudTitle(
          fontSize: 14,
          fontWeight: FontWeight.w900,
          color: const Color(0xFF38BDF8),
        ),
      );
    }
    return Text(
      network.isEmpty ? 'VAULT' : network,
      style: CyberTypography.mono(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    );
  }

  String _formatNumber(String num) {
    final clean = num.replaceAll(' ', '');
    final buffer = StringBuffer();
    for (int i = 0; i < clean.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(clean[i]);
    }
    return buffer.toString().isEmpty ? '•••• •••• •••• ••••' : buffer.toString();
  }

  String _maskNumber(String num) {
    final clean = num.replaceAll(' ', '');
    if (clean.length <= 4) return '•••• •••• •••• ••••';
    final last4 = clean.substring(clean.length - 4);
    return '•••• •••• •••• $last4';
  }
}

class _CardCircuitPainter extends CustomPainter {
  final Color accentColor;

  _CardCircuitPainter({required this.accentColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = accentColor.withValues(alpha: 0.12)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(size.width * 0.45, 0);
    path.lineTo(size.width * 0.65, size.height * 0.4);
    path.lineTo(size.width, size.height * 0.4);

    path.moveTo(size.width * 0.3, size.height);
    path.lineTo(size.width * 0.55, size.height * 0.65);
    path.lineTo(size.width * 0.85, size.height * 0.65);

    canvas.drawPath(path, paint);
    canvas.drawCircle(Offset(size.width * 0.65, size.height * 0.4), 2.5, dotPaint);
    canvas.drawCircle(Offset(size.width * 0.55, size.height * 0.65), 2.5, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
