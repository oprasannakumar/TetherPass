import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/totp_service.dart';

/// Result obtained from scanning a 2FA QR code
class TotpQrScanResult {
  final String secret;
  final String? issuer;
  final String? account;
  final String raw;

  const TotpQrScanResult({
    required this.secret,
    this.issuer,
    this.account,
    required this.raw,
  });
}

/// Target of the QR code scanner
enum QrScannerTarget {
  totp2FA,
  desktopPairing,
  any,
}

/// A modal dialog that opens the camera to scan a 2FA setup or Desktop Pairing QR code.
class TotpQrScannerDialog extends StatefulWidget {
  final QrScannerTarget target;

  const TotpQrScannerDialog({
    super.key,
    this.target = QrScannerTarget.totp2FA,
  });

  /// Opens the scanner and returns the [TotpQrScanResult] if successful.
  static Future<TotpQrScanResult?> scan(
    BuildContext context, {
    QrScannerTarget target = QrScannerTarget.totp2FA,
  }) {
    return showModalBottomSheet<TotpQrScanResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: false,
      builder: (ctx) => TotpQrScannerDialog(target: target),
    );
  }

  @override
  State<TotpQrScannerDialog> createState() => _TotpQrScannerDialogState();
}

class _TotpQrScannerDialogState extends State<TotpQrScannerDialog>
    with SingleTickerProviderStateMixin {
  late final MobileScannerController _controller;
  late final AnimationController _animController;
  late final Animation<double> _scanLineAnimation;

  bool _isProcessing = false;
  String? _errorMessage;
  TotpQrScanResult? _detectedResult;
  Timer? _countdownTimer;
  int _remainingSeconds = 30;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      formats: const [BarcodeFormat.qrCode],
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _scanLineAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _animController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing || _detectedResult != null) return;

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && raw.trim().isNotEmpty) {
        _processScannedRaw(raw.trim());
        break;
      }
    }
  }

  void _processScannedRaw(String raw) {
    final isDesktopPair = raw.startsWith('tetherpass://pair') ||
        raw.startsWith('http://tetherpass.app/pair') ||
        raw.contains('req=') ||
        raw.contains('"action":"pair"') ||
        raw.contains('"requestId"');

    // Handle desktop pairing QR code
    if (widget.target == QrScannerTarget.desktopPairing || isDesktopPair) {
      if (isDesktopPair) {
        HapticFeedback.heavyImpact();
        Navigator.of(context).pop(TotpQrScanResult(secret: '', raw: raw));
        return;
      }
      if (widget.target == QrScannerTarget.desktopPairing) {
        if (mounted) {
          setState(() {
            _errorMessage = 'Scanned QR is not a valid Desktop Pairing code';
          });
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) setState(() => _errorMessage = null);
          });
        }
        return;
      }
    }

    // 1. Try URI parsing
    final uriInfo = TotpService.parseTotpUri(raw);
    if (uriInfo != null && uriInfo.secret.isNotEmpty) {
      _handleSuccess(
        TotpQrScanResult(
          secret: uriInfo.secret,
          issuer: uriInfo.issuer,
          account: uriInfo.account,
          raw: raw,
        ),
      );
      return;
    }

    // 2. Try direct Base32 secret key
    final clean = TotpService.cleanKey(raw);
    if (TotpService.isValidSecret(clean)) {
      _handleSuccess(
        TotpQrScanResult(
          secret: clean,
          raw: raw,
        ),
      );
      return;
    }

    // Invalid QR code
    if (mounted) {
      setState(() {
        _errorMessage = widget.target == QrScannerTarget.desktopPairing
            ? 'Scanned QR is not a valid Desktop Pairing code'
            : 'Scanned QR is not a valid 2FA setup code';
      });
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _errorMessage = null;
          });
        }
      });
    }
  }

  void _handleSuccess(TotpQrScanResult result) {
    setState(() {
      _isProcessing = true;
      _detectedResult = result;
      _remainingSeconds = TotpService.getRemainingSeconds();
    });

    HapticFeedback.heavyImpact();

    // Start live countdown to show rolling code
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _remainingSeconds = TotpService.getRemainingSeconds();
      });
    });
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;

      final capture = await _controller.analyzeImage(image.path);
      if (capture != null && capture.barcodes.isNotEmpty) {
        for (final barcode in capture.barcodes) {
          final raw = barcode.rawValue;
          if (raw != null && raw.trim().isNotEmpty) {
            _processScannedRaw(raw.trim());
            return;
          }
        }
      }

      if (mounted) {
        setState(() {
          _errorMessage = 'No 2FA QR code found in the selected image';
        });
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _errorMessage = null);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to analyze gallery image: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;

    return Container(
      height: size.height * 0.85,
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6F00).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.qr_code_scanner_rounded,
                    color: Color(0xFFFF6F00),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.target == QrScannerTarget.desktopPairing
                            ? 'Scan Desktop Extension QR'
                            : 'Scan 2FA Setup QR Code',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        widget.target == QrScannerTarget.desktopPairing
                            ? 'Point at the pairing QR code on your computer'
                            : 'Point at the 2FA QR code on your computer screen',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Error / Status bar
          if (_errorMessage != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFEF4444)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: Color(0xFFEF4444), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: Color(0xFFFCA5A5),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Main View (Scanner or Verification Card)
          Expanded(
            child: _detectedResult != null
                ? _buildVerificationView()
                : _buildCameraScannerView(),
          ),

          // Bottom Control Dock
          if (_detectedResult == null) _buildBottomControls(),
        ],
      ),
    );
  }

  Widget _buildCameraScannerView() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Live Mobile Scanner
            MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
            ),

            // Translucent dark vignette around scan box
            ColorFiltered(
              colorFilter: ColorFilter.mode(
                Colors.black.withValues(alpha: 0.55),
                BlendMode.srcOut,
              ),
              child: Stack(
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.transparent,
                    ),
                  ),
                  Align(
                    alignment: Alignment.center,
                    child: Container(
                      width: 250,
                      height: 250,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Corner brackets overlay
            const SizedBox(
              width: 250,
              height: 250,
              child: CustomPaint(
                painter: _CornerBracketPainter(
                  color: Color(0xFFFF6F00),
                  bracketLength: 28,
                  strokeWidth: 4,
                ),
              ),
            ),

            // Animated Laser scanning beam
            SizedBox(
              width: 234,
              height: 250,
              child: AnimatedBuilder(
                animation: _scanLineAnimation,
                builder: (context, child) {
                  return Align(
                    alignment: Alignment(0.0, _scanLineAnimation.value * 2 - 1),
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFFFF6F00).withValues(alpha: 0.0),
                            const Color(0xFFFF6F00),
                            const Color(0xFFFFB300),
                            const Color(0xFFFF6F00),
                            const Color(0xFFFF6F00).withValues(alpha: 0.0),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF6F00).withValues(alpha: 0.8),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // Helper text
            Positioned(
              bottom: 24,
              child: Text(
                widget.target == QrScannerTarget.desktopPairing
                    ? 'Align Desktop QR code inside frame'
                    : 'Align 2FA QR code inside frame',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  shadows: [
                    Shadow(color: Colors.black, blurRadius: 4),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Torch toggle
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (context, state, child) {
              final isTorchOn = state.torchState == TorchState.on;
              return _buildActionButton(
                icon: isTorchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                label: isTorchOn ? 'Flash On' : 'Flash Off',
                isActive: isTorchOn,
                onTap: () => _controller.toggleTorch(),
              );
            },
          ),

          // Flip Camera
          _buildActionButton(
            icon: Icons.flip_camera_ios_rounded,
            label: 'Flip',
            onTap: () => _controller.switchCamera(),
          ),

          // Gallery Pick
          _buildActionButton(
            icon: Icons.photo_library_rounded,
            label: 'Gallery',
            onTap: _pickImageFromGallery,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFFFF6F00).withValues(alpha: 0.25)
              : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? const Color(0xFFFF6F00) : Colors.white12,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isActive ? const Color(0xFFFF6F00) : Colors.white70,
              size: 22,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isActive ? const Color(0xFFFF6F00) : Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerificationView() {
    final result = _detectedResult!;
    final code = TotpService.generateCode(result.secret);
    final formattedCode = code.length == 6
        ? '${code.substring(0, 3)} ${code.substring(3)}'
        : code;
    final progress = TotpService.getProgress();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Success badge
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF10B981), width: 2),
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: Color(0xFF10B981),
              size: 48,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '2FA QR Code Verified!',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'The authenticator key was successfully captured.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 20),

          // Live verification card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
            ),
            child: Column(
              children: [
                if (result.issuer != null || result.account != null) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.account_circle_rounded,
                          color: Color(0xFFFF6F00), size: 18),
                      const SizedBox(width: 8),
                      Text(
                        [
                          if (result.issuer != null) result.issuer,
                          if (result.account != null) result.account,
                        ].join(' : '),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(color: Colors.white12, height: 1),
                  const SizedBox(height: 12),
                ],

                const Text(
                  'CURRENT 6-DIGIT VERIFICATION CODE',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF94A3B8),
                  ),
                ),
                const SizedBox(height: 8),

                // Formatted rolling code
                Text(
                  formattedCode,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                    color: Color(0xFF34D399),
                  ),
                ),
                const SizedBox(height: 10),

                // Progress ring & countdown
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 2.5,
                        backgroundColor: Colors.white12,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _remainingSeconds <= 5
                              ? Colors.redAccent
                              : const Color(0xFF10B981),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Refreshes in ${_remainingSeconds}s',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _remainingSeconds <= 5
                            ? Colors.redAccent
                            : const Color(0xFF10B981),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Action Buttons: Confirm & Retake
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _detectedResult = null;
                      _isProcessing = false;
                      _countdownTimer?.cancel();
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Rescan'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop(result);
                  },
                  icon: const Icon(Icons.check_rounded, color: Colors.white),
                  label: const Text(
                    'Apply & Use Key',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6F00),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Custom painter for camera viewfinder corner brackets
class _CornerBracketPainter extends CustomPainter {
  final Color color;
  final double bracketLength;
  final double strokeWidth;

  const _CornerBracketPainter({
    required this.color,
    required this.bracketLength,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;
    final len = bracketLength;

    // Top-Left
    canvas.drawLine(const Offset(0, 0), Offset(len, 0), paint);
    canvas.drawLine(const Offset(0, 0), Offset(0, len), paint);

    // Top-Right
    canvas.drawLine(Offset(w, 0), Offset(w - len, 0), paint);
    canvas.drawLine(Offset(w, 0), Offset(w, len), paint);

    // Bottom-Left
    canvas.drawLine(Offset(0, h), Offset(len, h), paint);
    canvas.drawLine(Offset(0, h), Offset(0, h - len), paint);

    // Bottom-Right
    canvas.drawLine(Offset(w, h), Offset(w - len, h), paint);
    canvas.drawLine(Offset(w, h), Offset(w, h - len), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
