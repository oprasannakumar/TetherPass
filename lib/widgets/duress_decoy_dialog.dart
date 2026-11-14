import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/vault_security_service.dart';

/// Shows the stealth Duress Decoy Vault setup dialog.
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
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, color: Color(0xFFFF6F00)),
            SizedBox(width: 8),
            Text(
              'Duress Decoy Vault',
              style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 17),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'If coerced into unlocking TetherPass, entering this alternate Duress PIN will open a Decoy Vault with harmless dummy items.',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFFEDD5)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: Color(0xFFC2410C), size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Your real passwords, cards, and accounts remain completely hidden and locked. Cloud sync is permanently disabled in Decoy mode.',
                        style: TextStyle(color: Color(0xFFC2410C), fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: pinCtrl,
                obscureText: true,
                style: const TextStyle(color: Color(0xFF0F172A)),
                decoration: InputDecoration(
                  labelText: isEnabled ? 'New Duress PIN / Password' : 'Set Duress PIN / Password',
                  hintText: 'Must differ from Master Password',
                  prefixIcon: const Icon(Icons.password_rounded, color: Color(0xFFFF6F00)),
                  errorText: errorText,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmCtrl,
                obscureText: true,
                style: const TextStyle(color: Color(0xFF0F172A)),
                decoration: InputDecoration(
                  labelText: 'Confirm Duress PIN / Password',
                  prefixIcon: const Icon(Icons.check_circle_outline_rounded, color: Color(0xFFFF6F00)),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
                  const SnackBar(content: Text('Duress Decoy Vault disabled.')),
                );
              },
              child: const Text('Disable Duress', style: TextStyle(color: Colors.redAccent)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6F00)),
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
                const SnackBar(
                  content: Text('✓ Duress Decoy PIN activated successfully!'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Text('Save PIN'),
          ),
        ],
      ),
    ),
  );
}
