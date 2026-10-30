import 'dart:math';
import 'package:flutter/material.dart';
import '../models/vault_item.dart';
import '../services/card_detector.dart';

/// Realistic credit card widget styled according to its tier (Gold, Platinum, Infinite, etc.)
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
      duration: const Duration(milliseconds: 400),
    );
    _flipAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOut),
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
    final gradient = CardDetector.getCardGradient(widget.bankName, widget.cardTier);
    final isLight = (widget.cardTier == CardTier.gold || widget.cardTier == CardTier.platinum) ||
        (gradient.first.computeLuminance() > 0.55);
    final textColor = isLight ? Colors.black87 : Colors.white;
    final subColor = isLight ? Colors.black54 : Colors.white70;

    return AspectRatio(
      aspectRatio: 85.60 / 53.98, // ISO/IEC 7810 ID-1 standard dimensions (85.60mm x 53.98mm)
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: gradient.first.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Stack(
        children: [
          // Background sheen circle
          Positioned(
            right: -40,
            bottom: -40,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top row: Bank name + Tier pill
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.bankName.isEmpty ? 'VAULT CARD' : widget.bankName.toUpperCase(),
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                        fontSize: 14,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.cardType.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: (widget.cardType.toLowerCase().contains('debit')
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFF6366F1))
                                  .withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: (widget.cardType.toLowerCase().contains('debit')
                                        ? const Color(0xFF10B981)
                                        : const Color(0xFF6366F1))
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                            child: Text(
                              widget.cardType.toUpperCase(),
                              style: TextStyle(
                                color: textColor,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: textColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: textColor.withValues(alpha: 0.2)),
                          ),
                          child: Text(
                            widget.cardTier.displayName.toUpperCase(),
                            style: TextStyle(
                              color: textColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // Chip + Contactless Icon
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 28,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFD54F), Color(0xFFFFB300), Color(0xFFFF8F00)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.black26, width: 0.5),
                      ),
                      child: Stack(
                        children: [
                          Positioned(
                            top: 8,
                            left: 0,
                            right: 0,
                            child: Container(height: 1, color: Colors.black26),
                          ),
                          Positioned(
                            top: 18,
                            left: 0,
                            right: 0,
                            child: Container(height: 1, color: Colors.black26),
                          ),
                          Positioned(
                            left: 19,
                            top: 0,
                            bottom: 0,
                            child: Container(width: 1, color: Colors.black26),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      Icons.contactless_rounded,
                      color: textColor.withValues(alpha: 0.7),
                      size: 24,
                    ),
                  ],
                ),

                // Card Number
                Text(
                  widget.showFullNumber
                      ? _formatNumber(widget.cardNumber)
                      : _maskNumber(widget.cardNumber),
                  style: TextStyle(
                    color: textColor,
                    fontFamily: 'Courier',
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2.2,
                  ),
                ),

                // Bottom row: Holder + Expiry + Network Logo
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CARDHOLDER',
                            style: TextStyle(
                              color: subColor,
                              fontSize: 8,
                              letterSpacing: 1,
                            ),
                          ),
                          Text(
                            widget.cardHolder.isEmpty
                                ? 'YOUR NAME'
                                : widget.cardHolder.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'EXPIRES',
                          style: TextStyle(
                            color: subColor,
                            fontSize: 8,
                            letterSpacing: 1,
                          ),
                        ),
                        Text(
                          widget.expiry.isEmpty ? 'MM/YY' : widget.expiry,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    _buildNetworkBadge(widget.cardNetwork, textColor),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _buildBackFace() {
    final gradient = CardDetector.getCardGradient(widget.bankName, widget.cardTier);
    final isLight = (widget.cardTier == CardTier.gold || widget.cardTier == CardTier.platinum) ||
        (gradient.first.computeLuminance() > 0.55);
    final subColor = isLight ? Colors.black54 : Colors.white70;

    return AspectRatio(
      aspectRatio: 85.60 / 53.98, // ISO/IEC 7810 ID-1 standard dimensions (85.60mm x 53.98mm)
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
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
          const SizedBox(height: 24),
          // Magnetic Stripe
          Container(
            height: 38,
            color: Colors.black.withValues(alpha: 0.85),
          ),
          const SizedBox(height: 20),
          // Signature + CVV box
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Container(
                    height: 34,
                    color: Colors.white70,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      'Authorized Signature',
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        fontSize: 10,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Container(
                    height: 34,
                    color: Colors.white,
                    alignment: Alignment.center,
                    child: Text(
                      widget.cvv.isEmpty ? '•••' : widget.cvv,
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
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
            padding: const EdgeInsets.all(16),
            child: Text(
              'CVV is masked for security. Tap to flip back.',
              style: TextStyle(
                color: subColor,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _buildNetworkBadge(String network, Color textColor) {
    String label = network.toUpperCase();
    if (label.contains('VISA')) {
      return Text('VISA', style: TextStyle(color: textColor, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, fontSize: 16));
    } else if (label.contains('MASTER')) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 14, height: 14, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.red)),
          Transform.translate(
            offset: const Offset(-5, 0),
            child: Container(width: 14, height: 14, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.amber)),
          ),
        ],
      );
    } else if (label.contains('RUPAY')) {
      return Text('RuPay❯', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 14));
    } else if (label.contains('AMEX')) {
      return Text('AMEX', style: TextStyle(color: textColor, fontWeight: FontWeight.w900, fontSize: 13));
    } else if (label.contains('DISCOVER')) {
      return Text('DISCOVER', style: TextStyle(color: textColor, fontWeight: FontWeight.w900, fontSize: 13));
    } else if (label.contains('DINERS')) {
      return Text('Diners Club', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 12));
    } else if (label.contains('JCB')) {
      return Text('JCB', style: TextStyle(color: textColor, fontWeight: FontWeight.w900, fontSize: 14));
    } else if (label.contains('UNION')) {
      return Text('UnionPay', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 13));
    } else if (label.contains('MAESTRO')) {
      return Text('maestro', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 13));
    }
    return Text(network, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 13));
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
