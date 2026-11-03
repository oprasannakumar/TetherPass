import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/autofill_bridge_service.dart';
import '../services/auto_lock_service.dart';
import '../services/vault_security_service.dart';

class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key});

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isAuthenticating = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    AutofillBridgeService.syncVaultState(isUnlocked: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAutoBiometric();
    });
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _checkAutoBiometric() async {
    final sec = context.read<VaultSecurityService>();
    final auth = context.read<AuthService>();

    final enabled = await sec.isBiometricEnabled();
    final canAuth = await auth.canAuthenticate();

    if (enabled && canAuth && mounted) {
      _triggerBiometric();
    }
  }

  Future<void> _triggerBiometric() async {
    AutoLockService.isAuthenticating = true;
    setState(() => _isAuthenticating = true);
    final auth = context.read<AuthService>();

    final success = await auth.authenticate(
      reason: 'Scan your fingerprint or face to unlock TetherPass',
    );

    AutoLockService.isAuthenticating = false;
    if (mounted) {
      setState(() => _isAuthenticating = false);
      if (success) {
        AutoLockService.markUnlocked();
        Navigator.of(context).pushReplacementNamed('/home');
      }
    }
  }

  Future<void> _unlockWithPassword() async {
    final pwd = _passwordController.text.trim();
    if (pwd.isEmpty) {
      setState(() => _errorMessage = 'Please enter your Master Password');
      return;
    }

    setState(() {
      _isAuthenticating = true;
      _errorMessage = null;
    });

    final sec = context.read<VaultSecurityService>();
    final valid = await sec.verifyMasterPassword(pwd);

    if (mounted) {
      setState(() => _isAuthenticating = false);
      if (valid) {
        AutoLockService.markUnlocked();
        Navigator.of(context).pushReplacementNamed('/home');
      } else {
        setState(() => _errorMessage = 'Incorrect Master Password');
      }
    }
  }

  void _showForgotPasswordDialog() {
    final keyController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    String? dialogError;
    bool isKeyVerified = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Row(
              children: const [
                Icon(Icons.lock_reset_rounded, color: Color(0xFFFF6F00)),
                SizedBox(width: 8),
                Text('Reset Master Password', style: TextStyle(color: Color(0xFF0F172A), fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isKeyVerified) ...[
                    const Text(
                      'Enter your 16-character Recovery Key (e.g. XXXX-XXXX-XXXX-XXXX):',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: keyController,
                      textCapitalization: TextCapitalization.characters,
                      style: const TextStyle(
                        color: Color(0xFFC2410C),
                        fontFamily: 'Courier',
                        letterSpacing: 2,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'XXXX-XXXX-XXXX-XXXX',
                      ),
                    ),
                  ] else ...[
                    const Text(
                      'Recovery Key Verified! Set your new Master Password:',
                      style: TextStyle(color: Colors.green, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: newPasswordController,
                      obscureText: true,
                      style: const TextStyle(color: Color(0xFF0F172A)),
                      decoration: const InputDecoration(
                        labelText: 'New Master Password',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmPasswordController,
                      obscureText: true,
                      style: const TextStyle(color: Color(0xFF0F172A)),
                      decoration: const InputDecoration(
                        labelText: 'Confirm New Password',
                      ),
                    ),
                  ],
                  if (dialogError != null) ...[
                    const SizedBox(height: 8),
                    Text(dialogError!, style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
                onPressed: () => Navigator.pop(ctx),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6F00),
                  foregroundColor: Colors.white,
                ),
                child: Text(isKeyVerified ? 'Save & Unlock' : 'Verify Key'),
                onPressed: () async {
                  final sec = context.read<VaultSecurityService>();
                  if (!isKeyVerified) {
                    final key = keyController.text.trim();
                    final ok = await sec.verifyRecoveryKey(key);
                    if (ok) {
                      setDialogState(() {
                        isKeyVerified = true;
                        dialogError = null;
                      });
                    } else {
                      setDialogState(() => dialogError = 'Invalid recovery key. Please check again.');
                    }
                  } else {
                    final p1 = newPasswordController.text.trim();
                    final p2 = confirmPasswordController.text.trim();
                    if (p1.length < 4) {
                      setDialogState(() => dialogError = 'Password must be at least 4 chars.');
                      return;
                    }
                    if (p1 != p2) {
                      setDialogState(() => dialogError = 'Passwords do not match.');
                      return;
                    }
                    await sec.resetMasterPassword(p1);
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      const SnackBar(content: Text('Password reset successfully!')),
                    );
                    Navigator.of(this.context).pushReplacementNamed('/home');
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Centered App Icon & Vault Door
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: const Color(0xFFFF6F00).withValues(alpha: 0.3), width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF6F00).withValues(alpha: 0.2),
                        blurRadius: 28,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/icons/vault_logo.png',
                      width: 88,
                      height: 88,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'TetherPass',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Vault is Locked',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
                ),
                const SizedBox(height: 36),

                // Master Password Input with Eye Toggle
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  style: const TextStyle(color: Color(0xFF0F172A)),
                  onSubmitted: (_) => _unlockWithPassword(),
                  decoration: InputDecoration(
                    labelText: 'Master Password',
                    prefixIcon: const Icon(Icons.lock_outline_rounded, color: Color(0xFFFF6F00)),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: const Color(0xFF64748B)),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                ),

                if (_errorMessage != null) ...[
                  const SizedBox(height: 10),
                  Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.w600)),
                ],

                const SizedBox(height: 20),

                // Unlock Button
                ElevatedButton(
                  onPressed: _isAuthenticating ? null : _unlockWithPassword,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6F00),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 54),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 3,
                  ),
                  child: _isAuthenticating
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Unlock Vault', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),

                const SizedBox(height: 24),

                // Biometric Fingerprint Button
                InkWell(
                  onTap: _triggerBiometric,
                  borderRadius: BorderRadius.circular(32),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: const [
                        BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.fingerprint_rounded, color: Colors.blueAccent, size: 28),
                        SizedBox(width: 10),
                        Text('Unlock with Biometrics', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w600, fontSize: 13)),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Forgot Password Link
                TextButton(
                  onPressed: _showForgotPasswordDialog,
                  child: const Text(
                    'Forgot Password?',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 13, decoration: TextDecoration.underline),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
