import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/drive_service.dart';
import '../services/vault_security_service.dart';
import '../widgets/totp_qr_scanner_dialog.dart';
import '../widgets/tether_sync_dialog.dart';

// ─── Cyber-Vault Luxury Palette ─────────────────────────────────────────────
class CyberPalette {
  CyberPalette._();

  static const Color obsidianBg = Color(0xFF0A0E17);
  static const Color surfaceCard = Color(0xFF121622);
  static const Color surfaceElevated = Color(0xFF181B25);
  static const Color borderSubtle = Color(0x14FFFFFF); // rgba(255, 255, 255, 0.08)
  static const Color borderHighlight = Color(0x2800E5FF);

  static const Color electricMint = Color(0xFF00F5A0);
  static const Color laserCyan = Color(0xFF00E5FF);
  static const Color skyBlue = Color(0xFF38BDF8);
  static const Color amberWarning = Color(0xFFF59E0B);
  static const Color coralRed = Color(0xFFEF4444);
  static const Color mutedText = Color(0xFF8892B0);
  static const Color darkDivider = Color(0xFF1F2433);
}

/// Desktop Tether Relay Screen matching the "Cyber-Vault Luxury" dark cybersecurity design.
class BrowserExtensionScreen extends StatefulWidget {
  const BrowserExtensionScreen({super.key});

  @override
  State<BrowserExtensionScreen> createState() => _BrowserExtensionScreenState();
}

class _BrowserExtensionScreenState extends State<BrowserExtensionScreen>
    with TickerProviderStateMixin {
  // Controllers
  late AnimationController _pulseController;
  late AnimationController _waveformController;
  late AnimationController _holdController;

  // Timers
  Timer? _countdownTimer;
  Timer? _pollTimer;

  // Live State
  int _ttlSecondsRemaining = 869; // 14 mins 29 secs initial countdown
  int _selectedDeviceIndex = 0; // 0: Pixel 8 Pro, 1: Galaxy S23, 2: Broadcast
  bool _hasPendingRequest = true;
  int _pendingSecondsAgo = 12;
  bool _isHolding = false;

  // Audit Ledger Items
  final List<Map<String, dynamic>> _auditEvents = [
    {
      'title': 'GitHub Account SSH Token',
      'detail': 'Autofilled • Chrome 124 (Workstation)',
      'time': '2m ago',
      'icon': Icons.check_circle_rounded,
      'color': CyberPalette.electricMint,
    },
    {
      'title': 'NetBanking IFSC / Secret',
      'detail': 'Ephemeral Streamed • Edge Browser',
      'time': '1h ago',
      'icon': Icons.key_rounded,
      'color': CyberPalette.laserCyan,
    },
    {
      'title': 'Volatile RAM Purged',
      'detail': 'Timeout auto-triggered • 0 leaks detected',
      'time': '3h ago',
      'icon': Icons.delete_sweep_rounded,
      'color': CyberPalette.coralRed,
    },
  ];

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _waveformController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _holdController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _holdController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _streamKeyWithBiometrics();
      }
    });

    // Countdown ticker
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          if (_ttlSecondsRemaining > 0) _ttlSecondsRemaining--;
          _pendingSecondsAgo++;
        });
      }
    });

    // Check Drive background sessions
    _pollDriveSessions();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) _pollDriveSessions();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _waveformController.dispose();
    _holdController.dispose();
    _countdownTimer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _pollDriveSessions() async {
    final drive = context.read<DriveService>();
    if (!drive.isSignedIn) return;
    try {
      final sessions = await drive.getActiveDesktopSessions();
      if (mounted && sessions.isNotEmpty) {
        final active = sessions.firstWhere(
          (s) => s['isCurrentlyActive'] == true,
          orElse: () => sessions.first,
        );
        final expiresAt = (active['expiresAt'] as num?)?.toInt() ?? 0;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (expiresAt > now) {
          final remSec = ((expiresAt - now) / 1000).clamp(0, 1800).toInt();
          setState(() {
            _ttlSecondsRemaining = remSec;
          });
        }
      }
    } catch (_) {}
  }

  String _formatTtl(int totalSeconds) {
    final mins = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  Future<void> _scanDesktopQrCode() async {
    final result = await TotpQrScannerDialog.scan(
      context,
      target: QrScannerTarget.desktopPairing,
    );
    if (result == null || !mounted) return;

    final raw = result.raw.trim();
    String? requestId;
    String? deviceName;

    if (raw.startsWith('tetherpass://pair') || raw.startsWith('http://tetherpass.app/pair')) {
      final uri = Uri.tryParse(raw);
      if (uri != null) {
        requestId = uri.queryParameters['req'] ?? uri.queryParameters['requestId'];
        deviceName = uri.queryParameters['dev'] ?? uri.queryParameters['device'] ?? uri.queryParameters['deviceName'];
      }
    } else {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        if (map['action'] == 'pair' || map.containsKey('requestId') || map.containsKey('req')) {
          requestId = (map['requestId'] ?? map['req']) as String?;
          deviceName = (map['deviceName'] ?? map['device'] ?? map['dev']) as String?;
        }
      } catch (_) {}
    }

    if (requestId == null || requestId.isEmpty) {
      if (mounted) {
        _showCyberToast('Invalid Desktop Pairing QR code', isSuccess: false);
      }
      return;
    }

    final targetDevice = deviceName ?? 'Workstation Desktop (Windows MV3)';
    final drive = context.read<DriveService>();
    final sec = context.read<VaultSecurityService>();
    final masterPwd = await sec.getMasterPassword();
    if (!mounted) return;

    final ok = await TetherSyncDialog.run<bool>(
      context: context,
      mode: TetherSyncMode.connecting,
      deviceName: targetDevice,
      task: () => drive.respondToAccessRequest(
        requestId: requestId!,
        approved: true,
        deviceName: targetDevice,
        masterPassword: masterPwd,
      ),
    );

    if (ok == true && mounted) {
      setState(() {
        _ttlSecondsRemaining = 1800;
        _auditEvents.insert(0, {
          'title': 'MV3 Companion Authenticated',
          'detail': 'Paired via Direct QR • $targetDevice',
          'time': 'Just now',
          'icon': Icons.verified_user_rounded,
          'color': CyberPalette.electricMint,
        });
      });
      _showCyberToast('Relay Pipe Established with $targetDevice', isSuccess: true);
    }
  }

  Future<void> _streamKeyWithBiometrics() async {
    HapticFeedback.heavyImpact();
    final auth = AuthService();
    final isAuthed = await auth.authenticate(reason: 'Stream zero-knowledge card key to Amazon.com checkout');

    if (isAuthed) {
      HapticFeedback.vibrate();
      if (mounted) {
        setState(() {
          _hasPendingRequest = false;
          _auditEvents.insert(0, {
            'title': 'HDFC Infinia (Visa Infinite)',
            'detail': 'Passkey Streamed • Amazon.com (Checkout)',
            'time': 'Just now',
            'icon': Icons.bolt_rounded,
            'color': CyberPalette.electricMint,
          });
        });
        _showCyberToast('✓ Ephemeral Passkey Streamed to Active MV3!', isSuccess: true);
      }
    } else {
      HapticFeedback.mediumImpact();
      if (mounted) {
        _showCyberToast('Biometric authorization cancelled', isSuccess: false);
      }
    }
    _holdController.reset();
    setState(() => _isHolding = false);
  }

  void _rejectPendingRequest() {
    HapticFeedback.lightImpact();
    setState(() {
      _hasPendingRequest = false;
      _auditEvents.insert(0, {
        'title': 'Blocked Authorization Request',
        'detail': 'Rejected manually • Amazon.com',
        'time': 'Just now',
        'icon': Icons.block_rounded,
        'color': CyberPalette.coralRed,
      });
    });
    _showCyberToast('Request rejected and blocked on Active MV3.', isSuccess: false);
  }

  void _purgeAllAuditLogs() {
    HapticFeedback.mediumImpact();
    setState(() {
      _auditEvents.clear();
      _auditEvents.add({
        'title': 'Volatile RAM Purged',
        'detail': 'Manual purge executed • 0 residual hashes',
        'time': 'Just now',
        'icon': Icons.delete_sweep_rounded,
        'color': CyberPalette.coralRed,
      });
    });
    _showCyberToast('All relay audit logs purged from RAM cache.', isSuccess: true);
  }

  void _showCyberToast(String msg, {bool isSuccess = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF121622),
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isSuccess ? CyberPalette.electricMint : CyberPalette.coralRed,
            width: 1,
          ),
        ),
        content: Row(
          children: [
            Icon(
              isSuccess ? Icons.verified_rounded : Icons.info_outline_rounded,
              color: isSuccess ? CyberPalette.electricMint : CyberPalette.coralRed,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                msg,
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final drive = context.watch<DriveService>();

    return Scaffold(
      backgroundColor: CyberPalette.obsidianBg,
      body: SafeArea(
        child: Column(
          children: [
            // ── 1. Top App Bar ──────────────────────────────────────────
            _buildTopAppBar(drive),

            // ── Scrollable Body ─────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── 2. Companion Connection Status Card ───────────────
                    _buildCompanionStatusCard(),
                    const SizedBox(height: 16),

                    // ── 3. Pending Request Section (Actionable) ───────────
                    if (_hasPendingRequest) ...[
                      _buildPendingRequestCard(),
                      const SizedBox(height: 16),
                    ],

                    // ── 4. Target Device Dispatch ─────────────────────────
                    _buildTargetDeviceDispatch(),
                    const SizedBox(height: 16),

                    // ── 5. Relay Audit Ledger ─────────────────────────────
                    _buildRelayAuditLedger(),
                    const SizedBox(height: 16),

                    // ── 6. Bottom Channel Badge ───────────────────────────
                    _buildBottomChannelBadge(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

            // ── 7. Fixed Bottom Navigation Bar ────────────────────────────
            _buildFixedBottomNavBar(),
          ],
        ),
      ),
    );
  }

  // ─── Section 1: Top App Bar ───────────────────────────────────────────────
  Widget _buildTopAppBar(DriveService drive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: CyberPalette.obsidianBg,
        border: Border(bottom: BorderSide(color: CyberPalette.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Left: Shield logo mark + Title & Subtitle
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: CyberPalette.surfaceElevated,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: CyberPalette.borderHighlight),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1A00E5FF),
                      blurRadius: 10,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(Icons.shield_outlined, color: CyberPalette.laserCyan, size: 22),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TetherPass',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  Text(
                    'Tether Relay',
                    style: GoogleFonts.plusJakartaSans(
                      color: CyberPalette.mutedText,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const Spacer(),

              // Right: QR Scan Pair Button
              IconButton(
                icon: const Icon(Icons.qr_code_scanner_rounded, color: CyberPalette.laserCyan, size: 21),
                tooltip: 'Scan Desktop QR Code',
                style: IconButton.styleFrom(
                  backgroundColor: CyberPalette.surfaceElevated,
                  side: const BorderSide(color: CyberPalette.borderSubtle),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _scanDesktopQrCode,
              ),
              const SizedBox(width: 8),

              // Right: Biometric trigger chip button
              IconButton(
                icon: const Icon(Icons.fingerprint_rounded, color: CyberPalette.electricMint, size: 21),
                tooltip: 'Authenticate Biometrics',
                style: IconButton.styleFrom(
                  backgroundColor: CyberPalette.surfaceElevated,
                  side: const BorderSide(color: CyberPalette.borderSubtle),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  final auth = AuthService();
                  final ok = await auth.authenticate(reason: 'Test Sovereign Hardware Biometrics');
                  if (ok && mounted) {
                    _showCyberToast('✓ Biometric Sensor Hardware Verified!', isSuccess: true);
                  }
                },
              ),
              const SizedBox(width: 8),

              // Right: Profile Avatar chip
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: CyberPalette.surfaceElevated,
                  shape: BoxShape.circle,
                  border: Border.all(color: CyberPalette.borderHighlight),
                ),
                clipBehavior: Clip.antiAlias,
                child: drive.userPhotoUrl != null
                    ? Image.network(
                        drive.userPhotoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.person_outline_rounded, color: Colors.white70, size: 18),
                      )
                    : const Center(
                        child: Icon(Icons.person_outline_rounded, color: Colors.white70, size: 18),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Sub-badge: Glowing pulsing cyan dot with status
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0x1400E5FF),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0x3300E5FF)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, _) => Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: CyberPalette.laserCyan,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: CyberPalette.laserCyan.withValues(alpha: 0.4 + (_pulseController.value * 0.6)),
                          blurRadius: 6 + (_pulseController.value * 4),
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'TETHER ACTIVE: WINDOWS MV3',
                  style: GoogleFonts.jetBrainsMono(
                    color: CyberPalette.laserCyan,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Section 2: Companion Connection Status Card ──────────────────────────
  Widget _buildCompanionStatusCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: CyberPalette.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CyberPalette.borderSubtle),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row with glowing dot + RAM ONLY chip badge
          Row(
            children: [
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, _) => Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: CyberPalette.laserCyan,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: CyberPalette.laserCyan.withValues(alpha: 0.5 + (_pulseController.value * 0.5)),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'MV3 RELAY ESTABLISHED',
                style: GoogleFonts.jetBrainsMono(
                  color: CyberPalette.laserCyan,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: CyberPalette.surfaceElevated,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: CyberPalette.borderSubtle),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.memory_rounded, color: CyberPalette.electricMint, size: 13),
                    const SizedBox(width: 5),
                    Text(
                      'RAM ONLY',
                      style: GoogleFonts.jetBrainsMono(
                        color: CyberPalette.electricMint,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Title & Subtitle with Desktop Icon
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: CyberPalette.surfaceElevated,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: CyberPalette.borderSubtle),
                ),
                child: const Center(
                  child: Icon(Icons.desktop_windows_rounded, color: Colors.white, size: 24),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Chrome MV3 Companion',
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Workstation Desktop (Windows 11 Pro • v124.0)',
                      style: GoogleFonts.plusJakartaSans(
                        color: CyberPalette.mutedText,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Two metadata pills
          Row(
            children: [
              // Ephemeral Key TTL countdown timer
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: CyberPalette.surfaceElevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: CyberPalette.borderSubtle),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.timer_outlined, color: CyberPalette.amberWarning, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '⏱ ${_formatTtl(_ttlSecondsRemaining)}',
                          style: GoogleFonts.jetBrainsMono(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Volatile Memory Pill
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: CyberPalette.surfaceElevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: CyberPalette.borderSubtle),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.security_rounded, color: CyberPalette.skyBlue, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Wipe on Disconnect',
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          const Divider(color: CyberPalette.darkDivider, height: 1),
          const SizedBox(height: 12),

          // Bottom status line: Animated waveform pipe icon
          Row(
            children: [
              _buildAnimatedWaveform(),
              const SizedBox(width: 10),
              Text(
                'Sync Pipe: AES-GCM-256',
                style: GoogleFonts.jetBrainsMono(
                  color: CyberPalette.mutedText,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() => _ttlSecondsRemaining += 900); // +15 mins
                  _showCyberToast('+15m Added to Volatile Session TTL');
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text(
                    '+15m Extend',
                    style: GoogleFonts.plusJakartaSans(
                      color: CyberPalette.laserCyan,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
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

  // ── Animated Waveform Bars ──
  Widget _buildAnimatedWaveform() {
    return AnimatedBuilder(
      animation: _waveformController,
      builder: (context, _) {
        final val = _waveformController.value;
        return SizedBox(
          width: 24,
          height: 16,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildBar(6 + (val * 8)),
              _buildBar(14 - (val * 8)),
              _buildBar(8 + (val * 6)),
              _buildBar(16 - (val * 6)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBar(double height) {
    return Container(
      width: 2.5,
      height: height.clamp(4.0, 16.0),
      decoration: BoxDecoration(
        color: CyberPalette.laserCyan,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  // ─── Section 3: Pending Request Section (Actionable Card) ─────────────────
  Widget _buildPendingRequestCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: CyberPalette.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CyberPalette.amberWarning.withValues(alpha: 0.6), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33F59E0B),
            blurRadius: 20,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Amber pulsing ring icon + Waiting for Passkey badge
          Row(
            children: [
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, _) => Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: CyberPalette.amberWarning,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: CyberPalette.amberWarning.withValues(alpha: 0.4 + (_pulseController.value * 0.6)),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'PENDING REQUEST',
                style: GoogleFonts.jetBrainsMono(
                  color: CyberPalette.amberWarning,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0x28F59E0B),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0x4DF59E0B)),
                ),
                child: Text(
                  'Waiting for Passkey',
                  style: GoogleFonts.plusJakartaSans(
                    color: CyberPalette.amberWarning,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Origin Header: Amazon.com logo, TLS Encrypted, and red URGENT badge
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: CyberPalette.surfaceElevated,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: CyberPalette.borderSubtle),
                ),
                child: const Center(
                  child: Icon(Icons.shopping_cart_outlined, color: Colors.white, size: 22),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Amazon.com',
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: CyberPalette.surfaceElevated,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: CyberPalette.borderSubtle),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.lock_rounded, color: CyberPalette.electricMint, size: 10),
                              const SizedBox(width: 4),
                              Text(
                                'TLS Encrypted',
                                style: GoogleFonts.jetBrainsMono(
                                  color: Colors.white70,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$_pendingSecondsAgo seconds ago • Initiated from Active MV3',
                      style: GoogleFonts.plusJakartaSans(
                        color: CyberPalette.mutedText,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0x33EF4444),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: CyberPalette.coralRed),
                ),
                child: Text(
                  'URGENT',
                  style: GoogleFonts.jetBrainsMono(
                    color: CyberPalette.coralRed,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Details Key-Value Table
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: CyberPalette.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: CyberPalette.borderSubtle),
            ),
            child: Column(
              children: [
                _buildKeyValueRow('Requested Item', 'HDFC Infinia (Visa Infinite)', isBold: true),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(color: CyberPalette.darkDivider, height: 1),
                ),
                _buildKeyValueRow('Vault Card ID', '•••• •••• •••• 8842', isMono: true),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(color: CyberPalette.darkDivider, height: 1),
                ),
                _buildKeyValueRow('Destination URL', 'https://amazon.com/gp/buy...', isMono: true, color: CyberPalette.laserCyan),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Notice: Ready for zero-knowledge biometric authorization
          Row(
            children: [
              const Icon(Icons.verified_user_outlined, color: CyberPalette.electricMint, size: 15),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Ready for zero-knowledge biometric authorization',
                  style: GoogleFonts.plusJakartaSans(
                    color: CyberPalette.mutedText,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Action Buttons (Horizontal layout)
          Row(
            children: [
              // Reject button
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: CyberPalette.coralRed,
                  side: BorderSide(color: CyberPalette.coralRed.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.close_rounded, size: 18),
                label: Text(
                  'Reject',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                onPressed: _rejectPendingRequest,
              ),
              const SizedBox(width: 12),

              // Hold to Stream Key (High-contrast primary button)
              Expanded(
                child: GestureDetector(
                  onTapDown: (_) {
                    setState(() => _isHolding = true);
                    _holdController.forward();
                    HapticFeedback.lightImpact();
                  },
                  onTapUp: (_) {
                    if (_holdController.status != AnimationStatus.completed) {
                      _holdController.reverse();
                      setState(() => _isHolding = false);
                    }
                  },
                  onTapCancel: () {
                    _holdController.reverse();
                    setState(() => _isHolding = false);
                  },
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Background container with animated hold progress fill
                      Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: CyberPalette.electricMint,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x4D00F5A0),
                              blurRadius: 16,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: AnimatedBuilder(
                          animation: _holdController,
                          builder: (context, _) => FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: _holdController.value,
                            child: Container(
                              color: Colors.white.withValues(alpha: 0.35),
                            ),
                          ),
                        ),
                      ),
                      // Button label with Fingerprint icon
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.fingerprint_rounded, color: Colors.black, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            _isHolding ? 'Holding to Stream...' : 'Hold to Stream Key',
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.black,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKeyValueRow(String key, String value, {bool isBold = false, bool isMono = false, Color? color}) {
    return Row(
      children: [
        Text(
          key,
          style: GoogleFonts.plusJakartaSans(
            color: CyberPalette.mutedText,
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: isMono
              ? GoogleFonts.jetBrainsMono(
                  color: color ?? Colors.white,
                  fontSize: 12,
                  fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
                )
              : GoogleFonts.plusJakartaSans(
                  color: color ?? Colors.white,
                  fontSize: 12.5,
                  fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
                ),
        ),
      ],
    );
  }

  // ─── Section 4: Target Device Dispatch ────────────────────────────────────
  Widget _buildTargetDeviceDispatch() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: CyberPalette.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CyberPalette.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.screen_share_outlined, color: CyberPalette.laserCyan, size: 20),
              const SizedBox(width: 8),
              Text(
                'Target Device Dispatch',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0x1400E5FF),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0x3300E5FF)),
                ),
                child: Text(
                  'Live Broadcast',
                  style: GoogleFonts.jetBrainsMono(
                    color: CyberPalette.laserCyan,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Select which active sovereign hardware authenticators receive real-time push payloads.',
            style: GoogleFonts.plusJakartaSans(
              color: CyberPalette.mutedText,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),

          // 3-column selector row
          Row(
            children: [
              _buildDeviceCard(
                index: 0,
                icon: Icons.phone_android_rounded,
                title: 'Pixel 8 Pro',
                subtitle: '(This Device)',
              ),
              const SizedBox(width: 10),
              _buildDeviceCard(
                index: 1,
                icon: Icons.phone_android_rounded,
                title: 'Galaxy S23',
                subtitle: 'Standby',
              ),
              const SizedBox(width: 10),
              _buildDeviceCard(
                index: 2,
                icon: Icons.cell_tower_rounded,
                title: 'Broadcast',
                subtitle: 'All Vaults',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceCard({
    required int index,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final isSelected = _selectedDeviceIndex == index;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          HapticFeedback.lightImpact();
          setState(() => _selectedDeviceIndex = index);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0x1A00E5FF) : CyberPalette.surfaceElevated,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? CyberPalette.laserCyan : CyberPalette.borderSubtle,
              width: isSelected ? 1.5 : 1,
            ),
            boxShadow: isSelected
                ? const [
                    BoxShadow(
                      color: Color(0x3300E5FF),
                      blurRadius: 12,
                      offset: Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? CyberPalette.laserCyan : CyberPalette.mutedText,
                size: 24,
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: GoogleFonts.plusJakartaSans(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: GoogleFonts.jetBrainsMono(
                  color: isSelected ? CyberPalette.laserCyan : CyberPalette.mutedText,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Section 5: Relay Audit Ledger ────────────────────────────────────────
  Widget _buildRelayAuditLedger() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: CyberPalette.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CyberPalette.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.terminal_rounded, color: CyberPalette.laserCyan, size: 20),
              const SizedBox(width: 8),
              Text(
                'Relay Audit Ledger',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: CyberPalette.coralRed,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
                onPressed: _purgeAllAuditLogs,
                child: Text(
                  'Purge All Logs',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // List of past sync events
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _auditEvents.length,
            separatorBuilder: (_, __) => const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(color: CyberPalette.darkDivider, height: 1),
            ),
            itemBuilder: (context, idx) {
              final item = _auditEvents[idx];
              return Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: CyberPalette.surfaceElevated,
                      shape: BoxShape.circle,
                      border: Border.all(color: CyberPalette.borderSubtle),
                    ),
                    child: Center(
                      child: Icon(item['icon'] as IconData, color: item['color'] as Color, size: 16),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['title'] as String,
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item['detail'] as String,
                          style: GoogleFonts.plusJakartaSans(
                            color: CyberPalette.mutedText,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    item['time'] as String,
                    style: GoogleFonts.jetBrainsMono(
                      color: CyberPalette.mutedText,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // ─── Section 6: Bottom Channel Badge ──────────────────────────────────────
  Widget _buildBottomChannelBadge() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: CyberPalette.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CyberPalette.borderSubtle),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_sync_outlined, color: CyberPalette.laserCyan, size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Google Drive Isolated AppData Channel • card_vault_access_request.json • E2EE',
              style: GoogleFonts.jetBrainsMono(
                color: CyberPalette.mutedText,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Section 7: Fixed Bottom Navigation Bar ───────────────────────────────
  Widget _buildFixedBottomNavBar() {
    return Container(
      decoration: const BoxDecoration(
        color: CyberPalette.surfaceCard,
        border: Border(top: BorderSide(color: CyberPalette.borderSubtle)),
      ),
      child: Row(
        children: [
          _buildNavItem(0, Icons.lock_outline_rounded, 'Vault', onTap: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              Navigator.pushReplacementNamed(context, '/home');
            }
          }),
          _buildNavItem(1, Icons.cell_tower_rounded, 'Tether Relay', isActive: true),
          _buildNavItem(2, Icons.nfc_rounded, 'Scan & NFC', onTap: _scanDesktopQrCode),
          _buildNavItem(3, Icons.security_rounded, 'Security', onTap: () {
            Navigator.pop(context);
          }),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label, {bool isActive = false, VoidCallback? onTap}) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isActive ? CyberPalette.laserCyan : CyberPalette.mutedText,
                size: 22,
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.plusJakartaSans(
                      color: isActive ? Colors.white : CyberPalette.mutedText,
                      fontSize: 11,
                      fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                  if (isActive) ...[
                    const SizedBox(width: 4),
                    Container(
                      width: 4,
                      height: 4,
                      decoration: const BoxDecoration(
                        color: CyberPalette.laserCyan,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
