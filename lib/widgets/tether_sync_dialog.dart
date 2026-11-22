import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/cyber_theme.dart';

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

  /// Runs an asynchronous task while showing the animated cyber connection/disconnection dialog.
  /// Automatically transitions to the success state before closing.
  static Future<T?> run<T>({
    required BuildContext context,
    required TetherSyncMode mode,
    required String deviceName,
    required Future<T> Function() task,
    String? customTitle,
  }) async {
    final GlobalKey<_TetherSyncDialogState> dialogKey = GlobalKey<_TetherSyncDialogState>();

    // Show non-dismissible dialog with deep obsidian barrier
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.88),
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
    final primaryColor = isConnecting ? CyberColors.electricMint : CyberColors.crimsonAlert;

    final title = _isFinished
        ? (_isSuccess
            ? (isConnecting ? 'ENCLAVE TETHER ACTIVE' : 'SESSION TERMINATED & ZEROED')
            : 'TRANSMISSION FAILED')
        : (widget.customTitle ??
            (isConnecting ? 'ESTABLISHING TETHER...' : 'TERMINATING RELAY...'));

    final subtitle = _isFinished
        ? (_isSuccess
            ? (isConnecting
                ? 'Desktop extension on "${widget.deviceName}" unlocked via E2EE sync pipe.'
                : 'Volatile session on "${widget.deviceName}" purged from RAM.')
            : (_errorMessage ?? 'Could not complete cryptographic handshake.'))
        : (isConnecting
            ? 'Streaming AES-GCM ephemeral handshake to "${widget.deviceName}"...'
            : 'Revoking ephemeral keys & zeroing RAM on "${widget.deviceName}"...');

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      shape: const RoundedRectangleBorder(side: BorderSide.none),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Center(
        child: Container(
          width: 320,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          decoration: BoxDecoration(
            color: CyberColors.cardSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: primaryColor,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: primaryColor.withValues(alpha: 0.2),
                blurRadius: 24,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Animated Cyber Radar Waves & Center Icon ──
              SizedBox(
                height: 110,
                width: 110,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (!_isFinished) ...[
                      // Rotating neon spinner ring
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
                                valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
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
                        width: 66,
                        height: 66,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: CyberColors.elevatedSurface,
                          border: Border.all(color: primaryColor, width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: primaryColor.withValues(alpha: 0.3),
                              blurRadius: 14,
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
                          color: primaryColor,
                          size: 32,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Title
              Text(
                title,
                textAlign: TextAlign.center,
                style: CyberTypography.cyberHeader.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.0,
                ),
              ),

              const SizedBox(height: 8),

              // Subtitle
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: CyberTypography.bodySmall.copyWith(
                  fontSize: 12,
                  color: _isFinished && !_isSuccess
                      ? CyberColors.crimsonAlert
                      : CyberColors.mutedText,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 20),

              // Status Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: CyberColors.elevatedSurface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _isFinished
                        ? (_isSuccess ? CyberColors.electricMint : CyberColors.crimsonAlert)
                        : primaryColor,
                    width: 1.2,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!_isFinished) ...[
                      SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.0,
                          valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isConnecting ? 'TRANSMITTING...' : 'DISCONNECTING...',
                        style: CyberTypography.monoBadge.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                    ] else ...[
                      Icon(
                        _isSuccess ? Icons.check_circle_rounded : Icons.error_rounded,
                        size: 14,
                        color: _isSuccess ? CyberColors.electricMint : CyberColors.crimsonAlert,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _isSuccess ? 'CONFIRMED' : 'FAILED',
                        style: CyberTypography.monoBadge.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _isSuccess ? CyberColors.electricMint : CyberColors.crimsonAlert,
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
