import 'package:flutter/material.dart';

/// Target definition for a step in the spotlight tour.
class SpotlightTourStep {
  final GlobalKey targetKey;
  final String title;
  final String description;
  final IconData icon;
  final bool isCircle;
  final double borderRadius;
  final EdgeInsets extraPadding;

  const SpotlightTourStep({
    required this.targetKey,
    required this.title,
    required this.description,
    required this.icon,
    this.isCircle = true,
    this.borderRadius = 14.0,
    this.extraPadding = const EdgeInsets.all(6),
  });
}

/// Fullscreen interactive spotlight tour that points directly to each button with an arrow,
/// highlights it with an orange ring cut-out, and explains what it does.
class SpotlightTourOverlay extends StatefulWidget {
  final List<SpotlightTourStep> steps;
  final VoidCallback onFinish;

  const SpotlightTourOverlay({
    super.key,
    required this.steps,
    required this.onFinish,
  });

  /// Helper to display the tour over any screen
  static void show({
    required BuildContext context,
    required List<SpotlightTourStep> steps,
    VoidCallback? onFinish,
  }) {
    if (steps.isEmpty) return;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => SpotlightTourOverlay(
        steps: steps,
        onFinish: () {
          entry.remove();
          onFinish?.call();
        },
      ),
    );

    Overlay.of(context).insert(entry);
  }

  @override
  State<SpotlightTourOverlay> createState() => _SpotlightTourOverlayState();
}

class _SpotlightTourOverlayState extends State<SpotlightTourOverlay> with SingleTickerProviderStateMixin {
  int _currentStepIndex = 0;
  Rect? _targetRect;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.0, end: 6.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _calculateTargetRect();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _calculateTargetRect() {
    if (!mounted) return;
    if (_currentStepIndex >= widget.steps.length) return;

    final step = widget.steps[_currentStepIndex];
    final context = step.targetKey.currentContext;

    if (context != null) {
      final renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox != null && renderBox.hasSize) {
        final position = renderBox.localToGlobal(Offset.zero);
        final size = renderBox.size;

        setState(() {
          _targetRect = Rect.fromLTWH(
            position.dx - step.extraPadding.left,
            position.dy - step.extraPadding.top,
            size.width + step.extraPadding.horizontal,
            size.height + step.extraPadding.vertical,
          );
        });
        return;
      }
    }

    // Fallback if target is offscreen
    setState(() {
      _targetRect = null;
    });
  }

  void _nextStep() {
    if (_currentStepIndex < widget.steps.length - 1) {
      setState(() {
        _currentStepIndex++;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _calculateTargetRect();
      });
    } else {
      widget.onFinish();
    }
  }

  void _prevStep() {
    if (_currentStepIndex > 0) {
      setState(() {
        _currentStepIndex--;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _calculateTargetRect();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final currentStep = widget.steps[_currentStepIndex];
    final rect = _targetRect;

    // Decide if card sits above or below the target
    final showAbove = rect != null ? rect.center.dy > screenSize.height * 0.52 : false;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // ── Dark Scrim with Spotlight Hole ──
          if (rect != null)
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, _) {
                return CustomPaint(
                  size: screenSize,
                  painter: _SpotlightPainter(
                    targetRect: rect,
                    isCircle: currentStep.isCircle,
                    borderRadius: currentStep.borderRadius,
                    pulseExpand: _pulseAnimation.value,
                  ),
                );
              },
            )
          else
            Container(color: const Color(0xCC0F172A)),

          // ── Gesture detector to prevent tapping underlying widgets ──
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                // Tapping scrim proceeds to next step
                _nextStep();
              },
              child: const SizedBox.expand(),
            ),
          ),

          // ── Animated Arrow & Spotlight Tooltip Card ──
          if (rect != null) ...[
            // Arrow pointing directly at target
            _buildPointingArrow(rect, showAbove),

            // Tooltip Card
            _buildTooltipCard(context, rect, currentStep, showAbove),
          ] else
            // Center fallback if target rect not found
            Center(
              child: _buildCardContent(context, currentStep),
            ),
        ],
      ),
    );
  }

  // ─── Pointing Arrow ────────────────────────────────────────────────────────

  Widget _buildPointingArrow(Rect target, bool showAbove) {
    final arrowX = target.center.dx.clamp(30.0, MediaQuery.of(context).size.width - 30.0);
    final arrowY = showAbove ? target.top - 24 : target.bottom + 4;

    return Positioned(
      left: arrowX - 16,
      top: arrowY,
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          final dy = showAbove ? -_pulseAnimation.value : _pulseAnimation.value;
          return Transform.translate(
            offset: Offset(0, dy),
            child: Icon(
              showAbove ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
              color: const Color(0xFFFF6F00),
              size: 32,
              shadows: const [
                Shadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 2)),
              ],
            ),
          );
        },
      ),
    );
  }

  // ─── Tooltip Card ──────────────────────────────────────────────────────────

  Widget _buildTooltipCard(
    BuildContext context,
    Rect target,
    SpotlightTourStep step,
    bool showAbove,
  ) {
    final screenHeight = MediaQuery.of(context).size.height;

    double topPos;
    if (showAbove) {
      topPos = (target.top - 220).clamp(50.0, screenHeight - 250);
    } else {
      topPos = (target.bottom + 36).clamp(50.0, screenHeight - 250);
    }

    return Positioned(
      left: 20,
      right: 20,
      top: topPos,
      child: GestureDetector(
        onTap: () {}, // Prevent taps inside card from closing
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFFF6F00), width: 1.8),
            boxShadow: const [
              BoxShadow(
                color: Colors.black45,
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: _buildCardContent(context, step),
        ),
      ),
    );
  }

  Widget _buildCardContent(BuildContext context, SpotlightTourStep step) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top Row: Step Pill + Icon + Skip
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6F00).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(step.icon, color: const Color(0xFFFF6F00), size: 20),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Text(
                    'Step ${_currentStepIndex + 1} of ${widget.steps.length}',
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            TextButton(
              onPressed: widget.onFinish,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('Skip Tour', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Title
        Text(
          step.title,
          style: const TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 6),

        // Description
        Text(
          step.description,
          style: const TextStyle(
            color: Color(0xFF475569),
            fontSize: 13,
            height: 1.4,
          ),
        ),

        const SizedBox(height: 16),

        // Bottom Controls: Back, Dots, Next
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (_currentStepIndex > 0)
              TextButton(
                onPressed: _prevStep,
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                child: const Text(
                  'Back',
                  style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold, fontSize: 13),
                ),
              )
            else
              const SizedBox(width: 48),

            // Step dots
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(widget.steps.length, (i) {
                final isActive = i == _currentStepIndex;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: isActive ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: isActive ? const Color(0xFFFF6F00) : const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),

            // Next / Done button
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6F00),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              onPressed: _nextStep,
              child: Text(
                _currentStepIndex == widget.steps.length - 1 ? 'Got it! 👍' : 'Next ➔',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Custom Painter for Spotlight Hole & Glowing Orange Ring ─────────────────

class _SpotlightPainter extends CustomPainter {
  final Rect targetRect;
  final bool isCircle;
  final double borderRadius;
  final double pulseExpand;

  _SpotlightPainter({
    required this.targetRect,
    required this.isCircle,
    required this.borderRadius,
    required this.pulseExpand,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPaint = Paint()..color = const Color(0xD90A0E1A); // Deep translucent scrim
    final bgPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final holePath = Path();
    if (isCircle) {
      final center = targetRect.center;
      final holeRadius = (targetRect.width > targetRect.height ? targetRect.width : targetRect.height) / 2 + 4;
      holePath.addOval(Rect.fromCircle(center: center, radius: holeRadius));
    } else {
      holePath.addRRect(
        RRect.fromRectAndRadius(targetRect.inflate(4), Radius.circular(borderRadius)),
      );
    }

    // Cut out the spotlight hole
    final scrimPath = Path.combine(PathOperation.difference, bgPath, holePath);
    canvas.drawPath(scrimPath, backgroundPaint);

    // Glowing pulsating orange ring around the target button
    final ringPaint = Paint()
      ..color = const Color(0xFFFF6F00)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final glowPaint = Paint()
      ..color = const Color(0xFFFF6F00).withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 + pulseExpand;

    if (isCircle) {
      final center = targetRect.center;
      final holeRadius = (targetRect.width > targetRect.height ? targetRect.width : targetRect.height) / 2 + 4;
      canvas.drawCircle(center, holeRadius, ringPaint);
      canvas.drawCircle(center, holeRadius + pulseExpand, glowPaint);
    } else {
      final rrect = RRect.fromRectAndRadius(targetRect.inflate(4), Radius.circular(borderRadius));
      canvas.drawRRect(rrect, ringPaint);
      final pulseRRect = RRect.fromRectAndRadius(targetRect.inflate(4 + pulseExpand), Radius.circular(borderRadius + pulseExpand));
      canvas.drawRRect(pulseRRect, glowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) {
    return oldDelegate.targetRect != targetRect ||
        oldDelegate.isCircle != isCircle ||
        oldDelegate.pulseExpand != pulseExpand;
  }
}
