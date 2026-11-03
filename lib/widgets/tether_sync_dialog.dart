import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum TetherSyncMode {
  connecting,
  disconnecting,
}

class TetherSyncDialog extends StatefulWidget {
  final TetherSyncMode mode;
  final String deviceName;
  final String? customTitle;

  const TetherSyncDialog({
    super.key,
    required this.mode,
    required this.deviceName,
    this.customTitle,
  });

  /// Runs an asynchronous task while showing the animated connection/disconnection dialog.
  /// Automatically transitions to the success state before closing.
  static Future<T?> run<T>({
    required BuildContext context,
    required TetherSyncMode mode,
    required String deviceName,
    required Future<T> Function() task,
    String? customTitle,
  }) async {
    final GlobalKey<_TetherSyncDialogState> dialogKey = GlobalKey<_TetherSyncDialogState>();

    // Show non-dismissible dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: TetherSyncDialog(
          key: dialogKey,
          mode: mode,
          deviceName: deviceName,
          customTitle: customTitle,
        ),
      ),
    );

    try {
      final result = await task();

      // Trigger success animation if mounted
      if (dialogKey.currentState != null && dialogKey.currentState!.mounted) {
        await dialogKey.currentState!.markComplete(isSuccess: true);
      }

      await Future.delayed(const Duration(milliseconds: 650));
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      return result;
    } catch (e) {
      if (dialogKey.currentState != null && dialogKey.currentState!.mounted) {
        await dialogKey.currentState!.markComplete(isSuccess: false, errorMessage: e.toString());
      }
      await Future.delayed(const Duration(milliseconds: 1000));
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      return null;
    }
  }

  @override
  State<TetherSyncDialog> createState() => _TetherSyncDialogState();
}

class _TetherSyncDialogState extends State<TetherSyncDialog> with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _rotationController;
  late final AnimationController _scaleController;

  bool _isFinished = false;
  bool _isSuccess = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotationController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  Future<void> markComplete({required bool isSuccess, String? errorMessage}) async {
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _isFinished = true;
      _isSuccess = isSuccess;
      _errorMessage = errorMessage;
    });

    _pulseController.stop();
    _rotationController.stop();

    await _scaleController.reverse();
    if (mounted) {
      if (isSuccess) {
        HapticFeedback.heavyImpact();
      }
      await _scaleController.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isConnecting = widget.mode == TetherSyncMode.connecting;
    final primaryColor = isConnecting ? const Color(0xFFFF6F00) : const Color(0xFFEF4444);

    final title = _isFinished
        ? (_isSuccess
            ? (isConnecting ? 'Connected & Paired!' : 'Session Terminated & Locked')
            : 'Operation Failed')
        : (widget.customTitle ??
            (isConnecting ? 'Connecting to Desktop...' : 'Disconnecting Desktop...'));

    final subtitle = _isFinished
        ? (_isSuccess
            ? (isConnecting
                ? 'Desktop extension on "${widget.deviceName}" is unlocked.'
                : 'Session on "${widget.deviceName}" has been secured.')
            : (_errorMessage ?? 'Could not complete synchronization.'))
        : (isConnecting
            ? 'Transmitting encrypted biometric link to "${widget.deviceName}"...'
            : 'Locking session and revoking credentials on "${widget.deviceName}"...');

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Center(
        child: Container(
          width: 320,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.14),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Animated Radar Waves & Center Icon ──
              SizedBox(
                height: 120,
                width: 120,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (!_isFinished) ...[
                      // Expanding ripple wave 1
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          final progress = _pulseController.value;
                          return Container(
                            width: 60 + (progress * 55),
                            height: 60 + (progress * 55),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: primaryColor.withOpacity((1.0 - progress) * 0.45),
                                width: 2,
                              ),
                            ),
                          );
                        },
                      ),
                      // Expanding ripple wave 2
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          final progress = (_pulseController.value + 0.5) % 1.0;
                          return Container(
                            width: 60 + (progress * 55),
                            height: 60 + (progress * 55),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: primaryColor.withOpacity((1.0 - progress) * 0.35),
                                width: 1.5,
                              ),
                            ),
                          );
                        },
                      ),
                      // Rotating dotted spinner ring
                      AnimatedBuilder(
                        animation: _rotationController,
                        builder: (context, child) {
                          return Transform.rotate(
                            angle: _rotationController.value * 2 * math.pi,
                            child: SizedBox(
                              width: 86,
                              height: 86,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  primaryColor.withOpacity(0.85),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],

                    // Central Icon Circle
                    ScaleTransition(
                      scale: _scaleController,
                      child: Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: _isFinished
                                ? (_isSuccess
                                    ? [const Color(0xFF10B981), const Color(0xFF059669)]
                                    : [const Color(0xFFEF4444), const Color(0xFFB91C1C)])
                                : (isConnecting
                                    ? [const Color(0xFFFF8F00), const Color(0xFFFF6F00)]
                                    : [const Color(0xFFF87171), const Color(0xFFEF4444)]),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: (_isFinished
                                      ? (_isSuccess ? const Color(0xFF10B981) : const Color(0xFFEF4444))
                                      : primaryColor)
                                  .withOpacity(0.35),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Icon(
                          _isFinished
                              ? (_isSuccess
                                  ? Icons.check_rounded
                                  : Icons.close_rounded)
                              : (isConnecting
                                  ? Icons.wifi_tethering_rounded
                                  : Icons.phonelink_erase_rounded),
                          color: Colors.white,
                          size: 34,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // Title
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.3,
                ),
              ),

              const SizedBox(height: 8),

              // Subtitle
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: _isFinished && !_isSuccess
                      ? const Color(0xFFDC2626)
                      : const Color(0xFF64748B),
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 18),

              // Status Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: _isFinished
                      ? (_isSuccess ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2))
                      : (isConnecting ? const Color(0xFFFFFBEB) : const Color(0xFFFEF2F2)),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _isFinished
                        ? (_isSuccess ? const Color(0xFFA7F3D0) : const Color(0xFFFECACA))
                        : (isConnecting ? const Color(0xFFFDE68A) : const Color(0xFFFECACA)),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!_isFinished) ...[
                      SizedBox(
                        width: 8,
                        height: 8,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.8,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isConnecting ? const Color(0xFFD97706) : const Color(0xFFDC2626),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isConnecting ? 'Syncing...' : 'Disconnecting...',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isConnecting ? const Color(0xFFB45309) : const Color(0xFFB91C1C),
                        ),
                      ),
                    ] else ...[
                      Icon(
                        _isSuccess ? Icons.check_circle_rounded : Icons.error_rounded,
                        size: 14,
                        color: _isSuccess ? const Color(0xFF059669) : const Color(0xFFDC2626),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _isSuccess ? 'Completed' : 'Failed',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _isSuccess ? const Color(0xFF059669) : const Color(0xFFDC2626),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
