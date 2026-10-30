import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
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

  Future<void> _handleAuthorize() async {
    final sec = context.read<VaultSecurityService>();
    final auth = context.read<AuthService>();
    final authService = context.read<ExtensionAuthService>();
    final drive = context.read<DriveService>();

    // 1. Optional Google Drive sync
    // If signed in, the session token is synced to Drive as well.
    // If not signed in, local PIN authorization remains fully active.

    // 2. Security Check: Authenticate via Biometrics or Master Password
    final isBiometricEnabled = await sec.isBiometricEnabled();
    final canAuth = await auth.canAuthenticate();

    bool authenticated = false;
    if (isBiometricEnabled && canAuth) {
      authenticated = await auth.authenticate(
        reason: 'Authorize CardVault Browser Extension on Windows PC',
      );
    }

    if (!authenticated && mounted) {
      // Prompt for Master Password if biometric fails or isn't enabled
      authenticated = await _promptMasterPasswordDialog();
    }

    if (authenticated && mounted) {
      final success = await authService.authorizeExtension(durationMinutes: 30);
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: Colors.white),
                  SizedBox(width: 8),
                  Text('✓ Desktop Extension authorized for 30 minutes!'),
                ],
              ),
              backgroundColor: Colors.green.shade700,
              behavior: SnackBarBehavior.floating,
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

  Future<bool> _promptMasterPasswordDialog() async {
    final sec = context.read<VaultSecurityService>();
    final ctrl = TextEditingController();
    String? errorText;

    final result = await showDialog<bool>(
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
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6F00)),
              onPressed: () async {
                final ok = await sec.verifyMasterPassword(ctrl.text.trim());
                if (ok) {
                  Navigator.pop(ctx, true);
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
    return result ?? false;
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
                    'Enter this 6-digit code in the CardVault extension popup on your Windows browser along with your Master Password.',
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
                onPressed: authService.isLoading ? null : () => authService.revokeExtension(),
              ),
            ],

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
                  _buildStepRow('5', 'CardVault icon appears in your toolbar! Enter your 6-digit PIN and Master Password to unlock autofill across all websites.'),
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
}
