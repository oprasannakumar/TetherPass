import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/device_identity_service.dart';
import '../services/drive_service.dart';
import '../services/vault_security_service.dart';
import '../theme/cyber_theme.dart';
import '../widgets/totp_qr_scanner_dialog.dart';
import '../widgets/tether_sync_dialog.dart';

/// Desktop Tether Relay Screen matching the "Cyber-Vault" dark cybersecurity glassmorphic design.
/// Communicates with live Google Drive sessions, real paired devices, and instant QR pairing.
class BrowserExtensionScreen extends StatefulWidget {
  const BrowserExtensionScreen({super.key});

  @override
  State<BrowserExtensionScreen> createState() => _BrowserExtensionScreenState();
}

class _BrowserExtensionScreenState extends State<BrowserExtensionScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  List<Map<String, dynamic>> _devices = [];
  String _currentDeviceId = '';
  String _currentDeviceName = '';
  List<Map<String, dynamic>> _desktopSessions = [];
  Timer? _sessionsRefreshTimer;
  Timer? _tickerTimer;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _loadDeviceIdentityAndDevices();
    _fetchSessions();

    // Background polling every 2 seconds
    _sessionsRefreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) {
        _fetchSessions();
      }
    });

    // 1-second countdown ticker for synchronized live seconds display
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _desktopSessions.any((s) => s['isCurrentlyActive'] == true)) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _sessionsRefreshTimer?.cancel();
    _tickerTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDeviceIdentityAndDevices() async {
    final id = await DeviceIdentityService.getDeviceId();
    final name = await DeviceIdentityService.getDeviceName();
    if (mounted) {
      setState(() {
        _currentDeviceId = id;
        _currentDeviceName = name;
      });
      await _fetchDevices();
    }
  }

  Future<void> _fetchSessions() async {
    final drive = context.read<DriveService>();
    if (!drive.isSignedIn) return;
    try {
      final sessions = await drive.getActiveDesktopSessions();
      if (mounted) {
        setState(() {
          _desktopSessions = sessions;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchDevices() async {
    final drive = context.read<DriveService>();
    if (!drive.isSignedIn) return;
    try {
      final list = await drive.getRegisteredDevices();
      if (mounted) {
        setState(() {
          _devices = list;
        });
      }
    } catch (_) {}
  }

  Future<void> _manualRefresh() async {
    HapticFeedback.lightImpact();
    setState(() => _isRefreshing = true);
    await Future.wait([
      _fetchSessions(),
      _fetchDevices(),
    ]);
    if (mounted) {
      setState(() => _isRefreshing = false);
      _showCyberSnackBar('Telemetry synced with Google Drive cloud channel', isSuccess: true);
    }
  }

  String _formatSessionTime(int ms) {
    if (ms <= 0) return 'Just now';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Future<void> _terminateSession(String sessionId, String deviceName) async {
    HapticFeedback.mediumImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: CyberColors.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: CyberColors.crimsonAlert, width: 1.2),
        ),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: CyberColors.crimsonAlert, size: 22),
            const SizedBox(width: 8),
            Text(
              'TERMINATE SESSION?',
              style: CyberTypography.hudTitle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'Terminate the active tethered session on "$deviceName"?\n\nThe browser extension on that computer will be locked immediately and ephemeral cryptographic keys wiped from memory.',
          style: CyberTypography.body(color: CyberColors.textMuted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('CANCEL', style: CyberTypography.mono(color: CyberColors.textMuted, fontSize: 12)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: CyberColors.crimsonAlert,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'TERMINATE',
              style: CyberTypography.mono(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final drive = context.read<DriveService>();
      final ok = await TetherSyncDialog.run<bool>(
        context: context,
        mode: TetherSyncMode.disconnecting,
        deviceName: deviceName,
        task: () => drive.terminateDesktopSession(sessionId),
      );
      if (ok == true && mounted) {
        await _fetchSessions();
        _showCyberSnackBar('Session on "$deviceName" terminated and memory purged.', isSuccess: true);
      }
    }
  }

  Future<void> _extendSession(String sessionId, String deviceName, int minutes) async {
    HapticFeedback.lightImpact();
    final drive = context.read<DriveService>();
    final ok = await drive.extendDesktopSession(sessionId, additionalMinutes: minutes);
    if (ok && mounted) {
      await _fetchSessions();
      _showCyberSnackBar('Session on "$deviceName" extended by +$minutes minutes.', isSuccess: true);
    }
  }

  Future<void> _scanDesktopQrCode() async {
    HapticFeedback.lightImpact();
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
        _showCyberSnackBar('Invalid Desktop Pairing QR code scanned.', isSuccess: false);
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
      await _fetchSessions();
      _showCyberSnackBar('✓ Relay Pipe Established with $targetDevice', isSuccess: true);
    } else if (mounted) {
      _showCyberSnackBar('Pairing expired or rejected. Tap "Refresh" on your PC to try again.', isSuccess: false);
    }
  }

  Future<void> _renameDevice(String deviceId, String currentName) async {
    final ctrl = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: CyberColors.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF1E293B), width: 1.2),
        ),
        title: Text(
          'RENAME DEVICE',
          style: CyberTypography.hudTitle(color: Colors.white, fontSize: 16),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: CyberTypography.body(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Device Name',
            labelStyle: CyberTypography.mono(color: CyberColors.electricMint, fontSize: 12),
            hintText: 'e.g. Workstation or Personal Phone',
            hintStyle: CyberTypography.mono(color: CyberColors.textDim, fontSize: 11),
            filled: true,
            fillColor: CyberColors.elevatedSurface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('CANCEL', style: CyberTypography.mono(color: CyberColors.textMuted, fontSize: 12)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: CyberColors.electricMint,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(
              'SAVE',
              style: CyberTypography.mono(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != currentName) {
      if (!mounted) return;
      final drive = context.read<DriveService>();
      final ok = await drive.renameRegisteredDevice(deviceId, newName);
      if (ok && mounted) {
        if (deviceId == _currentDeviceId) {
          setState(() => _currentDeviceName = newName);
        }
        await _fetchDevices();
        _showCyberSnackBar('Device renamed to "$newName"', isSuccess: true);
      }
    }
  }

  Future<void> _removeDevice(String deviceId, String deviceName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: CyberColors.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: CyberColors.crimsonAlert, width: 1.2),
        ),
        title: Text(
          'REMOVE DEVICE?',
          style: CyberTypography.hudTitle(color: Colors.white, fontSize: 15),
        ),
        content: Text(
          'Remove "$deviceName" from registered devices?\n\nIt will no longer receive extension confirmation pop-ups or passkey relays.',
          style: CyberTypography.body(color: CyberColors.textMuted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('CANCEL', style: CyberTypography.mono(color: CyberColors.textMuted, fontSize: 12)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: CyberColors.crimsonAlert,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'REMOVE',
              style: CyberTypography.mono(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final drive = context.read<DriveService>();
      final ok = await drive.removeRegisteredDevice(deviceId);
      if (ok && mounted) {
        await _fetchDevices();
        _showCyberSnackBar('Removed "$deviceName"', isSuccess: true);
      }
    }
  }

  void _showCyberSnackBar(String msg, {bool isSuccess = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: CyberColors.cardSurface,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isSuccess ? CyberColors.electricMint : CyberColors.crimsonAlert,
            width: 1,
          ),
        ),
        content: Row(
          children: [
            Icon(
              isSuccess ? Icons.verified_rounded : Icons.info_outline_rounded,
              color: isSuccess ? CyberColors.electricMint : CyberColors.crimsonAlert,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                msg,
                style: CyberTypography.body(
                  color: Colors.white,
                  fontSize: 12.5,
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
    final activeSessions = _desktopSessions.where((s) => s['isCurrentlyActive'] == true).toList();
    final isAuthorized = activeSessions.isNotEmpty;

    final int? minMinsLeft = isAuthorized
        ? activeSessions
            .map((s) => (s['minutesRemaining'] as num?)?.toInt() ?? 0)
            .reduce((a, b) => a < b ? a : b)
        : null;

    return Scaffold(
      backgroundColor: CyberColors.obsidianBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: CyberColors.laserCyan),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TETHER RELAY // MV3',
              style: CyberTypography.hudTitle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 15,
                letterSpacing: 1.2,
              ),
            ),
            Text(
              'Zero-Knowledge Workstation Pipe',
              style: CyberTypography.mono(color: CyberColors.laserCyan, fontSize: 10),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: _isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: CyberColors.laserCyan),
                  )
                : const Icon(Icons.refresh_rounded, color: CyberColors.laserCyan),
            tooltip: 'Refresh Sessions',
            onPressed: _isRefreshing ? null : _manualRefresh,
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner_rounded, color: CyberColors.electricMint),
            tooltip: 'Scan Desktop Extension QR',
            onPressed: _scanDesktopQrCode,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: CyberBackground(
        showGrid: true,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 1. Hero Status Card ──────────────────────────────────────
              _buildHeroStatusBanner(isAuthorized, activeSessions.length, minMinsLeft),
              const SizedBox(height: 16),

              // ── 2. Instant QR Pairing Card ──────────────────────────────
              _buildQrPairingCard(),
              const SizedBox(height: 16),

              // ── 3. Source Google Drive Channel ──────────────────────────
              _buildDriveChannelCard(drive),
              const SizedBox(height: 16),

              // ── 4. Live Active Desktop Sessions ─────────────────────────
              _buildActiveSessionsSection(drive, activeSessions),
              const SizedBox(height: 16),

              // ── 5. Linked Sovereign Mobile Devices ──────────────────────
              _buildLinkedMobileDevicesSection(),
              const SizedBox(height: 16),

              // ── 6. Protocol & RAM Security Telemetry ────────────────────
              _buildProtocolTelemetryCard(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ─── 1. Hero Connection Status Banner ─────────────────────────────────────
  Widget _buildHeroStatusBanner(bool isAuthorized, int sessionCount, int? minMinsLeft) {
    return CyberGlassCard(
      padding: const EdgeInsets.all(18),
      borderRadius: 16,
      borderColor: isAuthorized ? CyberColors.electricMint : const Color(0xFF1E293B),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Pulsing icon container
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isAuthorized
                          ? CyberColors.electricMint.withValues(alpha: 0.15 + 0.1 * _pulseController.value)
                          : CyberColors.elevatedSurface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isAuthorized ? CyberColors.electricMint : const Color(0xFF1E293B),
                        width: 1.4,
                      ),
                      boxShadow: isAuthorized
                          ? [
                              BoxShadow(
                                color: CyberColors.electricMint.withValues(alpha: 0.3 * _pulseController.value),
                                blurRadius: 10,
                                spreadRadius: 1,
                              )
                            ]
                          : [],
                    ),
                    child: Icon(
                      isAuthorized ? Icons.laptop_windows_rounded : Icons.phonelink_lock_rounded,
                      color: isAuthorized ? CyberColors.electricMint : CyberColors.textMuted,
                      size: 28,
                    ),
                  );
                },
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isAuthorized
                            ? CyberColors.electricMint.withValues(alpha: 0.15)
                            : CyberColors.crimsonAlert.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isAuthorized ? CyberColors.electricMint : CyberColors.crimsonAlert,
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isAuthorized ? CyberColors.electricMint : CyberColors.crimsonAlert,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            isAuthorized ? 'RELAY PIPE ACTIVE' : 'DESKTOP LOCKED',
                            style: CyberTypography.mono(
                              color: isAuthorized ? CyberColors.electricMint : CyberColors.crimsonAlert,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isAuthorized
                          ? '$sessionCount Active Desktop Session${sessionCount > 1 ? "s" : ""}'
                          : 'Awaiting Direct QR Pair',
                      style: CyberTypography.hudTitle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (isAuthorized && minMinsLeft != null) ...[
            const SizedBox(height: 14),
            Container(height: 1, color: CyberColors.glassBorderMuted),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'PRIMARY SESSION TTL:',
                  style: CyberTypography.mono(color: CyberColors.textMuted, fontSize: 11),
                ),
                Text(
                  '$minMinsLeft min remaining',
                  style: CyberTypography.mono(
                    color: CyberColors.electricMint,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ─── 2. Instant QR Pairing Card ───────────────────────────────────────────
  Widget _buildQrPairingCard() {
    return CyberGlassCard(
      padding: const EdgeInsets.all(16),
      borderRadius: 16,
      borderColor: const Color(0xFF1E293B),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: CyberColors.electricMint.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: CyberColors.electricMint.withValues(alpha: 0.35)),
                ),
                child: const Icon(Icons.qr_code_scanner_rounded, color: CyberColors.electricMint, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'INSTANT QR PAIRING',
                      style: CyberTypography.hudTitle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Scan the QR displayed on Chrome/Edge on your PC to unlock zero-latency relay',
                      style: CyberTypography.body(color: CyberColors.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: CyberNeonButton(
              label: 'SCAN DESKTOP EXTENSION QR',
              icon: const Icon(Icons.qr_code_scanner_rounded, color: Colors.black, size: 18),
              primaryColor: CyberColors.electricMint,
              onPressed: _scanDesktopQrCode,
            ),
          ),
        ],
      ),
    );
  }

  // ─── 3. Source Google Drive Channel ───────────────────────────────────────
  Widget _buildDriveChannelCard(DriveService drive) {
    return CyberGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      borderRadius: 14,
      borderColor: CyberColors.glassBorderMuted,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: CyberColors.elevatedSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: CyberColors.glassBorderMuted),
            ),
            child: Icon(Icons.cloud_sync_rounded, color: drive.isSignedIn ? CyberColors.electricMint : CyberColors.textMuted, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ISOLATED CLOUD RELAY CHANNEL',
                  style: CyberTypography.mono(color: CyberColors.textMuted, fontSize: 9.5),
                ),
                const SizedBox(height: 2),
                Text(
                  drive.isSignedIn ? (drive.userEmail ?? 'Connected') : 'Offline (Sign in in Settings)',
                  style: CyberTypography.mono(
                    color: drive.isSignedIn ? CyberColors.electricMint : CyberColors.crimsonAlert,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (drive.isSignedIn)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: CyberColors.electricMint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: CyberColors.electricMint.withValues(alpha: 0.4)),
              ),
              child: Text(
                'E2EE READY',
                style: CyberTypography.mono(
                  color: CyberColors.electricMint,
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── 4. Live Active Desktop Sessions ──────────────────────────────────────
  Widget _buildActiveSessionsSection(DriveService drive, List<Map<String, dynamic>> activeList) {
    return CyberGlassCard(
      padding: const EdgeInsets.all(16),
      borderRadius: 16,
      borderColor: activeList.isNotEmpty ? CyberColors.electricMint : const Color(0xFF1E293B),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: activeList.isNotEmpty
                      ? CyberColors.electricMint.withValues(alpha: 0.15)
                      : CyberColors.elevatedSurface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: activeList.isNotEmpty ? CyberColors.electricMint : CyberColors.glassBorderMuted,
                  ),
                ),
                child: Icon(
                  Icons.laptop_chromebook_rounded,
                  color: activeList.isNotEmpty ? CyberColors.electricMint : CyberColors.textMuted,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'DESKTOP SESSIONS (${activeList.length})',
                  style: CyberTypography.hudTitle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Browser extensions currently unlocked on Windows. Terminating a session locks the extension immediately and wipes decrypted caches from RAM.',
            style: CyberTypography.body(color: CyberColors.textMuted, fontSize: 11),
          ),
          const SizedBox(height: 14),

          if (!drive.isSignedIn) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: CyberColors.plasmaAmber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: CyberColors.plasmaAmber.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: CyberColors.plasmaAmber, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Sign in to Google Drive in Settings to view and terminate live desktop sessions.',
                      style: CyberTypography.body(color: CyberColors.plasmaAmber, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (activeList.isEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: CyberColors.elevatedSurface.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: CyberColors.glassBorderMuted),
              ),
              child: Column(
                children: [
                  const Icon(Icons.phonelink_off_rounded, size: 36, color: CyberColors.textDim),
                  const SizedBox(height: 10),
                  Text(
                    'NO ACTIVE DESKTOP SESSIONS',
                    style: CyberTypography.hudTitle(
                      color: CyberColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'When you unlock the TetherPass extension on Windows, its active live countdown and session will appear here.',
                    textAlign: TextAlign.center,
                    style: CyberTypography.body(color: CyberColors.textDim, fontSize: 11),
                  ),
                ],
              ),
            ),
          ] else ...[
            ...activeList.map((s) => _buildSessionTile(s)),
          ],
        ],
      ),
    );
  }

  Widget _buildSessionTile(Map<String, dynamic> s) {
    final sessionId = (s['sessionId'] as String?) ?? '';
    final deviceName = (s['deviceName'] as String?) ?? 'Windows Browser Extension';
    final expiresAt = (s['expiresAt'] as num?)?.toInt() ?? 0;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final remainingMs = (expiresAt > nowMs) ? (expiresAt - nowMs) : 0;
    final mins = remainingMs ~/ 60000;
    final secs = (remainingMs % 60000) ~/ 1000;
    final timeStr = mins > 0 ? '$mins m $secs s remaining' : '$secs s remaining';
    final createdAt = (s['createdAt'] as num?)?.toInt() ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: CyberColors.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CyberColors.electricMint, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: CyberColors.electricMint.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: CyberColors.elevatedSurface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
              border: Border(bottom: BorderSide(color: CyberColors.glassBorderMuted)),
            ),
            child: Row(
              children: [
                const Icon(Icons.laptop_windows_rounded, color: CyberColors.electricMint, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    deviceName,
                    style: CyberTypography.hudTitle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: CyberColors.electricMint.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: CyberColors.electricMint.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    'ACTIVE',
                    style: CyberTypography.mono(
                      color: CyberColors.electricMint,
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Details Body
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: CyberColors.electricMint,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      timeStr,
                      style: CyberTypography.mono(
                        color: CyberColors.electricMint,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (createdAt > 0)
                      Text(
                        'Started ${_formatSessionTime(createdAt)}',
                        style: CyberTypography.mono(color: CyberColors.textMuted, fontSize: 10),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: CyberColors.electricMint,
                          side: BorderSide(color: CyberColors.electricMint.withValues(alpha: 0.5)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        icon: const Icon(Icons.more_time_rounded, size: 16),
                        label: Text(
                          '+15m EXTEND',
                          style: CyberTypography.mono(
                            color: CyberColors.electricMint,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                        onPressed: () => _extendSession(sessionId, deviceName, 15),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: CyberColors.crimsonAlert,
                          side: BorderSide(color: CyberColors.crimsonAlert.withValues(alpha: 0.5)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        icon: const Icon(Icons.stop_circle_outlined, size: 16),
                        label: Text(
                          'TERMINATE',
                          style: CyberTypography.mono(
                            color: CyberColors.crimsonAlert,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                        onPressed: () => _terminateSession(sessionId, deviceName),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── 5. Linked Sovereign Mobile Devices ────────────────────────────────────
  Widget _buildLinkedMobileDevicesSection() {
    return CyberGlassCard(
      padding: const EdgeInsets.all(16),
      borderRadius: 16,
      borderColor: const Color(0xFF1E293B),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: CyberColors.electricMint.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.devices_rounded, color: CyberColors.electricMint, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                'LINKED AUTHENTICATOR PHONES',
                style: CyberTypography.hudTitle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Hardware phones registered to receive push approval prompts from your browser extensions.',
            style: CyberTypography.body(color: CyberColors.textMuted, fontSize: 11),
          ),
          const SizedBox(height: 14),

          // Current Phone
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: CyberColors.elevatedSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: CyberColors.electricMint.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: CyberColors.electricMint.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.phone_android_rounded, color: CyberColors.electricMint, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              _currentDeviceName.isNotEmpty ? _currentDeviceName : 'Current Mobile Device',
                              style: CyberTypography.hudTitle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: CyberColors.electricMint.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: CyberColors.electricMint.withValues(alpha: 0.6)),
                            ),
                            child: Text(
                              'THIS PHONE',
                              style: CyberTypography.mono(
                                color: CyberColors.electricMint,
                                fontSize: 8.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'ID: ${_currentDeviceId.isNotEmpty ? _currentDeviceId : "Initializing..."}',
                        style: CyberTypography.mono(color: CyberColors.textDim, fontSize: 9.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_rounded, size: 18, color: CyberColors.laserCyan),
                  tooltip: 'Rename this phone',
                  onPressed: () => _renameDevice(_currentDeviceId, _currentDeviceName),
                ),
              ],
            ),
          ),

          // Other Registered Phones
          if (_devices.where((d) => d['deviceId'] != _currentDeviceId).isNotEmpty) ...[
            const SizedBox(height: 10),
            ..._devices.where((d) => d['deviceId'] != _currentDeviceId).map((d) {
              final name = (d['deviceName'] as String?) ?? 'Mobile Phone';
              final id = (d['deviceId'] as String?) ?? '';
              final platform = (d['platform'] as String?) ?? 'Android';
              return Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: CyberColors.cardSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: CyberColors.glassBorderMuted),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: CyberColors.elevatedSurface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.smartphone_rounded, color: CyberColors.textMuted, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: CyberTypography.hudTitle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$platform • ID: ${id.length > 12 ? "${id.substring(0, 12)}..." : id}',
                            style: CyberTypography.mono(color: CyberColors.textDim, fontSize: 9.5),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_rounded, size: 16, color: CyberColors.textMuted),
                      tooltip: 'Rename',
                      onPressed: () => _renameDevice(id, name),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 16, color: CyberColors.crimsonAlert),
                      tooltip: 'Remove',
                      onPressed: () => _removeDevice(id, name),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  // ─── 6. Protocol & RAM Security Telemetry ─────────────────────────────────
  Widget _buildProtocolTelemetryCard() {
    return CyberGlassCard(
      padding: const EdgeInsets.all(14),
      borderRadius: 14,
      borderColor: CyberColors.glassBorderMuted,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield_outlined, color: CyberColors.laserCyan, size: 16),
              const SizedBox(width: 8),
              Text(
                'ZERO-KNOWLEDGE ARCHITECTURE',
                style: CyberTypography.mono(
                  color: CyberColors.laserCyan,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '• Ephemeral Keys: Decryption keys live exclusively in volatile workstation RAM and are wiped automatically on disconnect or session expiration.\n• No Disk Caches: Passwords, card numbers, and banking credentials are never written to Windows storage.\n• Sovereign Authorization: Only this phone can approve access payloads via biometrics.',
            style: CyberTypography.body(color: CyberColors.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
