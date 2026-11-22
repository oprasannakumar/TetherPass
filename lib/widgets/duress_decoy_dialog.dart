import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/vault_security_service.dart';
import '../theme/cyber_theme.dart';

/// Shows the stealth Duress Decoy Vault setup dialog in Cyber-Vault styling.
Future<void> showDuressDecoySetupDialog(BuildContext context, {VoidCallback? onStateChanged}) async {
  final sec = context.read<VaultSecurityService>();
  final isEnabled = await sec.isDuressEnabled();

  final pinCtrl = TextEditingController();
  final confirmCtrl = TextEditingController();
  String? errorText;

  if (!context.mounted) return;

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setDlgState) => AlertDialog(
        backgroundColor: CyberColors.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: CyberColors.crimsonAlert.withValues(alpha: 0.4), width: 1.2),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: CyberColors.crimsonAlert.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.shield_outlined, color: CyberColors.crimsonAlert, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'DURESS DECOY ENCLAVE',
                style: CyberTypography.cyberHeader.copyWith(
                  color: CyberColors.crimsonAlert,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Under coercion, entering this alternate duress PIN disarms the alarm by mounting a dummy decoy enclave with synthesized credentials.',
                style: CyberTypography.bodySmall.copyWith(color: CyberColors.mutedText, height: 1.4),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: CyberColors.obsidianBg.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: CyberColors.plasmaAmber.withValues(alpha: 0.4)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: CyberColors.plasmaAmber, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Genuine cards, accounts, and passkeys remain physically encrypted in hardware. Remote sync channels are severed immediately.',
                        style: CyberTypography.monoData.copyWith(color: CyberColors.plasmaAmber, fontSize: 11, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: pinCtrl,
                obscureText: true,
                style: CyberTypography.monoData.copyWith(color: Colors.white, letterSpacing: 2.0),
                decoration: InputDecoration(
                  labelText: isEnabled ? 'New Duress PIN / Password' : 'Set Duress PIN / Password',
                  labelStyle: GoogleFonts.rajdhani(color: CyberColors.mutedText, fontWeight: FontWeight.w600, fontSize: 13),
                  hintText: 'Must differ from Master Password',
                  hintStyle: CyberTypography.monoData.copyWith(color: CyberColors.mutedText.withValues(alpha: 0.4), fontSize: 12),
                  prefixIcon: const Icon(Icons.password_rounded, color: CyberColors.crimsonAlert),
                  errorText: errorText,
                  errorStyle: const TextStyle(color: CyberColors.crimsonAlert, fontSize: 11, fontWeight: FontWeight.bold),
                  filled: true,
                  fillColor: CyberColors.obsidianBg.withValues(alpha: 0.6),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: CyberColors.crimsonAlert, width: 1.5)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmCtrl,
                obscureText: true,
                style: CyberTypography.monoData.copyWith(color: Colors.white, letterSpacing: 2.0),
                decoration: InputDecoration(
                  labelText: 'Confirm Duress PIN / Password',
                  labelStyle: GoogleFonts.rajdhani(color: CyberColors.mutedText, fontWeight: FontWeight.w600, fontSize: 13),
                  prefixIcon: const Icon(Icons.check_circle_outline_rounded, color: CyberColors.crimsonAlert),
                  filled: true,
                  fillColor: CyberColors.obsidianBg.withValues(alpha: 0.6),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: CyberColors.crimsonAlert, width: 1.5)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (isEnabled)
            TextButton(
              onPressed: () async {
                final scaffold = ScaffoldMessenger.of(context);
                await sec.disableDuress();
                onStateChanged?.call();
                if (ctx.mounted) Navigator.pop(ctx);
                scaffold.showSnackBar(
                  SnackBar(
                    backgroundColor: CyberColors.cardSurface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    content: const Text('Duress Decoy Vault deactivated.'),
                  ),
                );
              },
              child: Text('PURGE DURESS', style: CyberTypography.monoBadge.copyWith(color: CyberColors.crimsonAlert)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('ABORT', style: CyberTypography.monoBadge.copyWith(color: CyberColors.mutedText)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: CyberColors.crimsonAlert,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              final p = pinCtrl.text.trim();
              final c = confirmCtrl.text.trim();
              if (p.length < 4) {
                setDlgState(() => errorText = 'PIN must be at least 4 characters');
                return;
              }
              if (p != c) {
                setDlgState(() => errorText = 'PINs do not match');
                return;
              }

              // Verify it is not identical to real Master Password
              final isSameAsMaster = await sec.verifyMasterPassword(p);
              if (isSameAsMaster) {
                setDlgState(() => errorText = 'Duress PIN cannot be identical to Master Password!');
                return;
              }

              final scaffold = ScaffoldMessenger.of(context);
              await sec.setDuressPassword(p);
              onStateChanged?.call();
              if (ctx.mounted) Navigator.pop(ctx);
              scaffold.showSnackBar(
                SnackBar(
                  content: Text('✓ Duress Decoy PIN activated successfully!', style: CyberTypography.monoData.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
                  backgroundColor: CyberColors.cardSurface,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: CyberColors.electricMint.withValues(alpha: 0.5))),
                ),
              );
            },
            child: Text('ARM DURESS PIN', style: GoogleFonts.rajdhani(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ),
  );
}
