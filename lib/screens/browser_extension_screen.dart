import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/device_identity_service.dart';
import '../services/drive_service.dart';
import '../services/vault_security_service.dart';
import '../widgets/totp_qr_scanner_dialog.dart';
import '../widgets/tether_sync_dialog.dart';

class BrowserExtensionScreen extends StatefulWidget {
  const BrowserExtensionScreen({super.key});

  @override
  State<BrowserExtensionScreen> createState() => _BrowserExtensionScreenState();
}

class _BrowserExtensionScreenState extends State<BrowserExtensionScreen> {
  List<Map<String, dynamic>> _devices = [];
  String _currentDeviceId = '';
  String _currentDeviceName = '';
  List<Map<String, dynamic>> _desktopSessions = [];
  Timer? _sessionsRefreshTimer;

  @override
  void initState() {
    super.initState();
    _loadDeviceIdentityAndDevices();
    _fetchSessions();
    _sessionsRefreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) {
        _fetchSessions();
      }
    });
  }

  @override
  void dispose() {
    _sessionsRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchSessions() async {
    final drive = context.read<DriveService>();
    if (!drive.isSignedIn) return;
    final sessions = await drive.getActiveDesktopSessions();
    if (mounted) {
      setState(() {
        _desktopSessions = sessions;
      });
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Terminate Desktop Session?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text('Are you sure you want to terminate the active session on "$deviceName"? The browser extension on that computer will be locked immediately.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Terminate Session'),
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
      }
    }
  }

  Future<void> _extendSession(String sessionId, String deviceName, int minutes) async {
    final drive = context.read<DriveService>();
    final ok = await drive.extendDesktopSession(sessionId, additionalMinutes: minutes);
    if (ok && mounted) {
      await _fetchSessions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Session on "$deviceName" extended by $minutes mins.'),
            backgroundColor: Colors.blue.shade700,
          ),
        );
      }
    }
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid Desktop Pairing QR code.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    final targetDevice = deviceName ?? 'Desktop Browser Extension';

    // Request confirmation
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.qr_code_scanner_rounded, color: Color(0xFFFF6F00)),
            SizedBox(width: 10),
            Text('Pair & Unlock Desktop?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        content: Text(
          'Allow "$targetDevice" to connect to your vault and unlock for 30 minutes?',
          style: const TextStyle(fontSize: 14, color: Color(0xFF334155)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Deny')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6F00),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Approve & Unlock'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final sec = context.read<VaultSecurityService>();
    final drive = context.read<DriveService>();
    final masterPwd = await sec.getMasterPassword();

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
    }
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

  Future<void> _fetchDevices() async {
    final drive = context.read<DriveService>();
    if (!drive.isSignedIn) return;
    final list = await drive.getRegisteredDevices();
    if (mounted) {
      setState(() {
        _devices = list;
      });
    }
  }

  Future<void> _renameDevice(String deviceId, String currentName) async {
    final ctrl = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Rename Device', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Device Name',
            hintText: 'e.g. My Primary Phone',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6F00)),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Device renamed to "$newName"')),
          );
        }
      }
    }
  }

  Future<void> _removeDevice(String deviceId, String deviceName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove Device?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text('Remove "$deviceName" from your registered devices? It will no longer receive extension confirmation pop-ups.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final drive = context.read<DriveService>();
      final ok = await drive.removeRegisteredDevice(deviceId);
      if (ok && mounted) {
        await _fetchDevices();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Removed "$deviceName"')),
          );
        }
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final drive = context.watch<DriveService>();
    final activeSessions = _desktopSessions.where((s) => s['isCurrentlyActive'] == true).toList();
    final isAuthorized = activeSessions.isNotEmpty;
    final int? minMinsLeft = activeSessions.isNotEmpty
        ? activeSessions.map((s) => (s['minutesRemaining'] as num?)?.toInt() ?? 0).reduce((a, b) => a < b ? a : b)
        : null;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Browser Extension (Windows)', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Hero Banner ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isAuthorized
                      ? [const Color(0xFF14532D), const Color(0xFF15803D)]
                      : [const Color(0xFF1E293B), const Color(0xFF0F172A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          isAuthorized ? Icons.laptop_windows_rounded : Icons.lock_outline_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isAuthorized ? Colors.greenAccent.withValues(alpha: 0.25) : const Color(0xFF64748B).withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isAuthorized ? '● DESKTOP CONNECTED' : '🔒 DESKTOP LOCKED',
                                style: TextStyle(
                                  color: isAuthorized ? Colors.greenAccent : const Color(0xFFCBD5E1),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isAuthorized ? '${activeSessions.length} Active Desktop Session${activeSessions.length > 1 ? "s" : ""}' : 'Awaiting Mobile Push Approval',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (isAuthorized && minMinsLeft != null) ...[
                    const Divider(color: Colors.white24, height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Next Session Expiry:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        Text(
                          '$minMinsLeft minutes remaining',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ── Instant QR Pairing Card ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFF6F00).withValues(alpha: 0.3)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF6F00).withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF6F00).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.qr_code_scanner_rounded, color: Color(0xFFFF6F00), size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Instant QR Desktop Pairing',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
                            ),
                            Text(
                              'Scan the QR code on your PC screen to unlock immediately',
                              style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _scanDesktopQrCode,
                      icon: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 18),
                      label: const Text(
                        'Scan Desktop Extension QR',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6F00),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ── Source Google Account on Phone ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.cloud_done_rounded, color: Color(0xFF2563EB), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'SOURCE GOOGLE ACCOUNT (PHONE)',
                          style: TextStyle(color: Color(0xFF64748B), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                        ),
                        Text(
                          drive.userEmail ?? 'Not Signed In',
                          style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ── Active Desktop Sessions ──
            _buildActiveSessionsSection(drive),

            const SizedBox(height: 16),

            // ── Linked Mobile Phones Management ──
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.devices_rounded, color: Color(0xFFFF6F00), size: 20),
                      SizedBox(width: 8),
                      Text(
                        'LINKED MOBILE PHONES',
                        style: TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Phones registered to receive biometric autofill approval pop-ups from your Windows browser extension.',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 11, height: 1.35),
                  ),
                  const SizedBox(height: 14),

                  // Current Device Card
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF86EFAC)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.phone_android_rounded, color: Color(0xFF15803D), size: 20),
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
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF16A34A),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text('THIS PHONE', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'ID: ${_currentDeviceId.isNotEmpty ? _currentDeviceId : "Initializing..."}',
                                style: const TextStyle(color: Color(0xFF64748B), fontSize: 10, fontFamily: 'monospace'),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_rounded, size: 18, color: Color(0xFF15803D)),
                          tooltip: 'Rename this phone',
                          onPressed: () => _renameDevice(_currentDeviceId, _currentDeviceName),
                        ),
                      ],
                    ),
                  ),

                  // Other Registered Devices
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
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE2E8F0),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.smartphone_rounded, color: Color(0xFF475569), size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '$platform • ID: $id',
                                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_rounded, size: 18, color: Color(0xFF64748B)),
                              tooltip: 'Rename',
                              onPressed: () => _renameDevice(id, name),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                              tooltip: 'Remove',
                              onPressed: () => _removeDevice(id, name),
                            ),
                          ],
                        ),
                      );
                    }),
                  ] else if (!drive.isSignedIn) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.info_outline_rounded, color: Color(0xFFD97706), size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Sign in to Google Drive in Settings to sync and manage multiple phones.',
                              style: TextStyle(color: Color(0xFF92400E), fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveSessionsSection(DriveService drive) {
    final activeList = _desktopSessions.where((s) => s['isCurrentlyActive'] == true).toList();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: activeList.isNotEmpty ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.laptop_chromebook_rounded,
                  color: activeList.isNotEmpty ? const Color(0xFF16A34A) : const Color(0xFF64748B),
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'DESKTOP SESSIONS (${activeList.length})',
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Browser extensions currently unlocked on Windows. Terminating a session locks the extension immediately.',
            style: TextStyle(color: Color(0xFF64748B), fontSize: 11, height: 1.35),
          ),
          const SizedBox(height: 14),

          if (!drive.isSignedIn) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Row(
                children: const [
                  Icon(Icons.info_outline_rounded, color: Color(0xFFD97706), size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Sign in to Google Drive in Settings to view and terminate live desktop sessions.',
                      style: TextStyle(color: Color(0xFF92400E), fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (activeList.isEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: const [
                  Icon(Icons.phonelink_off_rounded, size: 32, color: Color(0xFF94A3B8)),
                  SizedBox(height: 8),
                  Text(
                    'No Active Desktop Sessions',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF334155)),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'When you unlock the extension on Windows, its active session and time remaining will appear here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
          ] else ...[
            ...activeList.map((s) => _buildSessionTile(s, isActive: true)),
          ],
        ],
      ),
    );
  }

  Widget _buildSessionTile(Map<String, dynamic> s, {required bool isActive}) {
    final sessionId = (s['sessionId'] as String?) ?? '';
    final deviceName = (s['deviceName'] as String?) ?? 'Windows Browser Extension';
    final minsLeft = (s['minutesRemaining'] as num?)?.toInt() ?? 0;
    final createdAt = (s['createdAt'] as num?)?.toInt() ?? 0;
    final status = (s['status'] as String?) ?? (isActive ? 'ACTIVE' : 'EXPIRED');

    final borderColor = isActive ? const Color(0xFF3B82F6) : const Color(0xFFE2E8F0);
    final bannerBg = isActive ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC);
    final bannerBorderBottom = isActive ? const Color(0xFFDBEAFE) : const Color(0xFFE2E8F0);
    final iconColor = isActive ? const Color(0xFF2563EB) : const Color(0xFF64748B);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isActive ? Colors.white : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: borderColor,
          width: isActive ? 2.0 : 1.0,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: Colors.blue.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Device Name Header Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: bannerBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(
                bottom: BorderSide(color: bannerBorderBottom),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.touch_app_rounded,
                  color: iconColor,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    deviceName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isActive ? const Color(0xFF0F172A) : const Color(0xFF475569),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // Session Details & Actions Body
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (isActive) ...[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF16A34A),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Active • $minsLeft min${minsLeft == 1 ? "" : "s"} left',
                            style: const TextStyle(
                              color: Color(0xFF15803D),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      Text(
                        status == 'TERMINATED' || status == 'LOCKED' ? '● Locked' : '○ Expired',
                        style: TextStyle(
                          color: status == 'TERMINATED' || status == 'LOCKED' ? Colors.red.shade700 : const Color(0xFF94A3B8),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                    if (createdAt > 0) ...[
                      Text(
                        '• Started ${_formatSessionTime(createdAt)}',
                        style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                      ),
                    ],
                  ],
                ),
                if (isActive) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF2563EB),
                          side: const BorderSide(color: Color(0xFF93C5FD)),
                          backgroundColor: const Color(0xFFEFF6FF),
                          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.more_time_rounded, size: 15),
                        label: const Text(
                          '+15m Extend',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                        onPressed: () => _extendSession(sessionId, deviceName, 15),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFDC2626),
                          side: const BorderSide(color: Color(0xFFFCA5A5)),
                          backgroundColor: const Color(0xFFFEF2F2),
                          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.stop_circle_outlined, size: 15),
                        label: const Text(
                          'Terminate Session',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                        onPressed: () => _terminateSession(sessionId, deviceName),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
