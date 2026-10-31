import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/device_identity_service.dart';
import '../services/drive_service.dart';
import '../services/extension_auth_service.dart';
import '../services/vault_security_service.dart';

class BrowserExtensionScreen extends StatefulWidget {
  const BrowserExtensionScreen({super.key});

  @override
  State<BrowserExtensionScreen> createState() => _BrowserExtensionScreenState();
}

class _BrowserExtensionScreenState extends State<BrowserExtensionScreen> {
  static const String extensionFolderPath =
      r'C:\Users\bhask\.gemini\antigravity\scratch\card_vault_extension';

  List<Map<String, dynamic>> _devices = [];
  String _currentDeviceId = '';
  String _currentDeviceName = '';
  bool _loadingDevices = false;

  List<Map<String, dynamic>> _desktopSessions = [];
  bool _loadingSessions = false;
  Timer? _sessionsRefreshTimer;

  @override
  void initState() {
    super.initState();
    _loadDeviceIdentityAndDevices();
    _fetchSessions();
    _sessionsRefreshTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (mounted) _fetchSessions();
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
      final ok = await drive.terminateDesktopSession(sessionId);
      if (ok && mounted) {
        await _fetchSessions();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Session on "$deviceName" terminated and locked.'),
              backgroundColor: Colors.red.shade700,
            ),
          );
        }
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
    setState(() => _loadingDevices = true);
    final list = await drive.getRegisteredDevices();
    if (mounted) {
      setState(() {
        _devices = list;
        _loadingDevices = false;
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

  Future<void> _handleAuthorize() async {
    final sec = context.read<VaultSecurityService>();
    final auth = context.read<AuthService>();
    final authService = context.read<ExtensionAuthService>();

    // 1. Optional Google Drive sync
    // If signed in, the session token is synced to Drive as well.
    // If not signed in, local PIN authorization remains fully active.

    // 2. Security Check: Authenticate via Biometrics or Master Password
    final isBiometricEnabled = await sec.isBiometricEnabled();
    final canAuth = await auth.canAuthenticate();

    bool authenticated = false;
    String? masterPwd;

    if (isBiometricEnabled && canAuth) {
      authenticated = await auth.authenticate(
        reason: 'Authorize TetherPass Browser Extension on Windows PC',
      );
      if (authenticated) {
        masterPwd = await sec.getMasterPassword();
      }
    }

    if (!authenticated || masterPwd == null || masterPwd.isEmpty) {
      if (!mounted) return;
      // Prompt for Master Password if biometric fails, isn't enabled, or password not yet cached
      masterPwd = await _promptMasterPasswordDialog();
      authenticated = masterPwd != null && masterPwd.isNotEmpty;
    }

    if (!authenticated || masterPwd == null || masterPwd.isEmpty) {
      // User cancelled password prompt
      return;
    }

    if (mounted) {
      final success = await authService.authorizeExtension(
        durationMinutes: 30,
        masterPassword: masterPwd,
      );
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Browser extension approved for 30 mins',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.green.shade700,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to update authorization in Google Drive.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<String?> _promptMasterPasswordDialog() async {
    final sec = context.read<VaultSecurityService>();
    final ctrl = TextEditingController();
    String? errorText;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Verify Master Password', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter your Master Password to authorize desktop autofill.', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                obscureText: true,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Master Password',
                  errorText: errorText,
                  prefixIcon: const Icon(Icons.lock_rounded, color: Color(0xFFFF6F00)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6F00)),
              onPressed: () async {
                final text = ctrl.text.trim();
                final ok = await sec.verifyMasterPassword(text);
                if (ok) {
                  await sec.saveMasterPassword(text);
                  if (ctx.mounted) {
                    Navigator.pop(ctx, text);
                  }
                } else {
                  setDlgState(() => errorText = 'Incorrect Master Password');
                }
              },
              child: const Text('Verify & Authorize'),
            ),
          ],
        ),
      ),
    );
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<ExtensionAuthService>();
    final drive = context.watch<DriveService>();
    final isAuthorized = authService.isAuthorized;

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
                                color: isAuthorized ? Colors.greenAccent.withValues(alpha: 0.25) : const Color(0xFFFF6F00).withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isAuthorized ? '● DESKTOP AUTHORIZED' : '🔒 DESKTOP LOCKED',
                                style: TextStyle(
                                  color: isAuthorized ? Colors.greenAccent : const Color(0xFFFFB74D),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isAuthorized ? 'Autofill Active on Windows PC' : 'Awaiting Mobile Authorization',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (isAuthorized && authService.expiresAt != null) ...[
                    const Divider(color: Colors.white24, height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Session Expiry:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        Text(
                          '${authService.expiresAt!.difference(DateTime.now()).inMinutes} minutes remaining',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
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

            const SizedBox(height: 14),

            // ── 6-Digit One-Time Pairing PIN Section ──
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'DESKTOP PAIRING PIN',
                        style: TextStyle(color: Color(0xFFFF6F00), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                      ),
                      InkWell(
                        onTap: () {
                          authService.regeneratePin();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Generated fresh 6-digit PIN'), duration: Duration(seconds: 1)),
                          );
                        },
                        child: Row(
                          children: const [
                            Icon(Icons.refresh_rounded, size: 14, color: Color(0xFF64748B)),
                            SizedBox(width: 4),
                            Text('Regenerate', style: TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // PIN Display
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: authService.currentPin));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('PIN copied to clipboard!'), duration: Duration(seconds: 1)),
                      );
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            authService.currentPin,
                            style: const TextStyle(
                              color: Color(0xFF0F172A),
                              fontFamily: 'Courier',
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 10,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.copy_rounded, color: Color(0xFF94A3B8), size: 18),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Enter this 6-digit code in the TetherPass extension popup on your Windows browser along with your Master Password.',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 11, height: 1.4),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Authorization Button Actions ──
            if (!isAuthorized) ...[
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6F00),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 2,
                ),
                icon: const Icon(Icons.verified_user_rounded),
                label: authService.isLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Authorize Desktop Extension', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                onPressed: authService.isLoading ? null : _handleAuthorize,
              ),
            ] else ...[
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.lock_reset_rounded),
                label: const Text('Revoke Desktop Authorization Now', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                onPressed: authService.isLoading ? null : () async {
                  await authService.revokeExtension();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Desktop authorization revoked and extension locked',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                        backgroundColor: Colors.red.shade700,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    );
                  }
                },
              ),
            ],

            const SizedBox(height: 20),

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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                      if (drive.isSignedIn)
                        InkWell(
                          onTap: _loadingDevices ? null : _fetchDevices,
                          child: Row(
                            children: [
                              _loadingDevices
                                  ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.refresh_rounded, size: 16, color: Color(0xFF64748B)),
                              const SizedBox(width: 4),
                              const Text('Refresh', style: TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
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

            const SizedBox(height: 24),

            // ── Setup Guide: How to Load in Windows Chrome/Edge ──
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
                      Icon(Icons.help_outline_rounded, color: Color(0xFFFF6F00), size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Windows Chrome / Edge Setup Guide',
                        style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _buildStepRow('1', 'Open Google Chrome or Microsoft Edge on Windows and navigate to: chrome://extensions or edge://extensions'),
                  _buildStepRow('2', 'Turn on "Developer mode" toggle switch in top-right corner.'),
                  _buildStepRow('3', 'Click "Load unpacked" button on the top-left toolbar.'),
                  _buildStepRow('4', 'Select the extension directory on your PC:'),
                  Container(
                    margin: const EdgeInsets.only(left: 28, top: 4, bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            extensionFolderPath,
                            style: TextStyle(fontFamily: 'Courier', fontSize: 10, color: Color(0xFF0F172A), fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            Clipboard.setData(const ClipboardData(text: extensionFolderPath));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Folder path copied!'), duration: Duration(seconds: 1)),
                            );
                          },
                          child: const Icon(Icons.copy_rounded, size: 16, color: Color(0xFFFF6F00)),
                        ),
                      ],
                    ),
                  ),
                  _buildStepRow('5', 'TetherPass icon appears in your toolbar! Enter your 6-digit PIN and Master Password to unlock autofill across all websites.'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepRow(String num, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              color: Color(0xFFFFF7ED),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(num, style: const TextStyle(color: Color(0xFFFF6F00), fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(color: Color(0xFF475569), fontSize: 12, height: 1.35)),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveSessionsSection(DriveService drive) {
    final activeList = _desktopSessions.where((s) => s['isCurrentlyActive'] == true).toList();
    final inactiveList = _desktopSessions.where((s) => s['isCurrentlyActive'] != true).toList();

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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
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
                    Flexible(
                      child: Text(
                        'DESKTOP SESSIONS (${activeList.length})',
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: _loadingSessions ? null : _fetchSessions,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _loadingSessions
                              ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.refresh_rounded, size: 16, color: Color(0xFF64748B)),
                          const SizedBox(width: 3),
                          const Text('Refresh', style: TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ],
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
          ] else if (activeList.isEmpty && inactiveList.isEmpty) ...[
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
            // Active Sessions
            if (activeList.isNotEmpty) ...[
              ...activeList.map((s) => _buildSessionTile(s, isActive: true)),
            ] else ...[
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle_outline_rounded, size: 16, color: Color(0xFF64748B)),
                    SizedBox(width: 8),
                    Text(
                      'No desktop extensions are currently active.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
            ],

            // Inactive / Terminated Sessions (if any)
            if (inactiveList.isNotEmpty) ...[
              const SizedBox(height: 10),
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    'Recent / Past Sessions (${inactiveList.length})',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.bold),
                  ),
                  children: inactiveList.map((s) => _buildSessionTile(s, isActive: false)).toList(),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildSessionTile(Map<String, dynamic> s, {required bool isActive}) {
    final sessionId = (s['sessionId'] as String?) ?? '';
    final deviceName = (s['deviceName'] as String?) ?? 'Windows Browser Extension';
    final authMode = (s['authMode'] as String?) ?? 'PUSH';
    final minsLeft = (s['minutesRemaining'] as num?)?.toInt() ?? 0;
    final createdAt = (s['createdAt'] as num?)?.toInt() ?? 0;
    final status = (s['status'] as String?) ?? (isActive ? 'ACTIVE' : 'EXPIRED');

    final isPush = authMode.toUpperCase() == 'PUSH';

    final borderColor = isActive
        ? (isPush ? const Color(0xFF3B82F6) : const Color(0xFFF97316))
        : (isPush ? const Color(0xFFBFDBFE) : const Color(0xFFFFEDD5));
    final bannerBg = isActive
        ? (isPush ? const Color(0xFFEFF6FF) : const Color(0xFFFFF7ED))
        : const Color(0xFFF8FAFC);
    final bannerBorderBottom = isActive
        ? (isPush ? const Color(0xFFDBEAFE) : const Color(0xFFFFEDD5))
        : const Color(0xFFE2E8F0);
    final iconColor = isActive
        ? (isPush ? const Color(0xFF2563EB) : const Color(0xFFEA580C))
        : const Color(0xFF64748B);

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
                  color: (isPush ? Colors.blue : Colors.orange).withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Device Name Header Banner (Distinguished by color, labels removed)
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
                  isPush ? Icons.touch_app_rounded : Icons.dialpad_rounded,
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
                        status == 'TERMINATED' ? '● Terminated' : '○ Expired',
                        style: TextStyle(
                          color: status == 'TERMINATED' ? Colors.red.shade700 : const Color(0xFF94A3B8),
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
