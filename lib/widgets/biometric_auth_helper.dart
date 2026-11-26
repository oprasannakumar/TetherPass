import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/vault_security_service.dart';
import '../theme/cyber_theme.dart';

/// Centralized security helper for biometric and master password authorizations across TetherPass.
class BiometricAuthHelper {
  /// Authenticates the user using Biometrics if available and enabled.
  /// If biometric fails or is cancelled, provides a Master Password fallback dialog.
  /// Returns `true` if authorized, `false` otherwise.
  static Future<bool> authenticate(
    BuildContext context, {
    required String reason,
    String title = 'Scanner Biometric Authorization',
  }) async {
    try {
      final auth = context.read<AuthService>();
      final sec = context.read<VaultSecurityService>();
      final isBio = await sec.isBiometricEnabled();
      final canAuth = await auth.canAuthenticate();

      if (isBio && canAuth) {
        final success = await auth.authenticate(
          reason: reason,
          title: title,
        );
        if (success) return true;
      }
    } catch (_) {}

    if (!context.mounted) return false;

    // Fallback: Master Password verification prompt
    return await promptMasterPassword(context, reason: reason);
  }

  /// Prompts for Master Password verification dialog in a futuristic cyber theme.
  static Future<bool> promptMasterPassword(
    BuildContext context, {
    required String reason,
  }) async {
    final sec = context.read<VaultSecurityService>();
    final ctrl = TextEditingController();
    String? errorText;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: CyberColors.cardSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF1E293B), width: 1.2),
          ),
          title: Text(
            'SECURITY VERIFICATION',
            style: CyberTypography.hudTitle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                reason,
                style: CyberTypography.body(fontSize: 12, color: CyberColors.textMuted),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                obscureText: true,
                autofocus: true,
                style: CyberTypography.body(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Master Password',
                  labelStyle: CyberTypography.mono(color: CyberColors.electricMint, fontSize: 12),
                  errorText: errorText,
                  errorStyle: CyberTypography.mono(color: CyberColors.crimsonAlert, fontSize: 11),
                  filled: true,
                  fillColor: CyberColors.elevatedSurface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: CyberColors.electricMint, width: 1.2),
                  ),
                ),
                onSubmitted: (_) async {
                  final pwd = ctrl.text.trim();
                  if (pwd.isEmpty) {
                    setDlgState(() => errorText = 'Password cannot be empty');
                    return;
                  }
                  final valid = await sec.verifyMasterPassword(pwd);
                  if (valid && context.mounted) {
                    Navigator.of(context).pop(true);
                  } else if (context.mounted) {
                    setDlgState(() => errorText = 'Incorrect master password');
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'CANCEL',
                style: CyberTypography.mono(color: CyberColors.textDim, fontSize: 12),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                final pwd = ctrl.text.trim();
                if (pwd.isEmpty) {
                  setDlgState(() => errorText = 'Password cannot be empty');
                  return;
                }
                final valid = await sec.verifyMasterPassword(pwd);
                if (valid && context.mounted) {
                  Navigator.of(context).pop(true);
                } else if (context.mounted) {
                  setDlgState(() => errorText = 'Incorrect master password');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: CyberColors.electricMint,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(
                'VERIFY',
                style: CyberTypography.mono(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );

    return result ?? false;
  }
}
