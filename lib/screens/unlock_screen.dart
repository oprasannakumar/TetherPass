import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/autofill_bridge_service.dart';
import '../services/auto_lock_service.dart';
import '../services/database_service.dart';
import '../services/vault_security_service.dart';
import '../theme/cyber_theme.dart';

/// Cyber-Vault Robotic Unlock Screen
/// Displays an armored biometric enclave with frosted glassmorphic credential cards,
/// pulsing quantum security indicators, and high-tech biometric authorization.
class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key});

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> with SingleTickerProviderStateMixin {
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isAuthenticating = false;
  String? _errorMessage;
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    AutofillBridgeService.syncVaultState(isUnlocked: false);

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _glowAnimation = Tween<double>(begin: 8.0, end: 24.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAutoBiometric();
    });
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _glowController.dispose();
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
      reason: 'Scan your biometric passkey to disarm TetherPass Cyber-Vault',
    );

    AutoLockService.isAuthenticating = false;
    if (mounted) {
      setState(() => _isAuthenticating = false);
      if (success) {
        HapticFeedback.mediumImpact();
        AutoLockService.markUnlocked();
        Navigator.of(context).pushReplacementNamed('/home');
      }
    }
  }

  Future<void> _unlockWithPassword() async {
    final pwd = _passwordController.text.trim();
    if (pwd.isEmpty) {
      setState(() => _errorMessage = 'PLEASE INPUT MASTER VAULT PASSKEY');
      return;
    }

    setState(() {
      _isAuthenticating = true;
      _errorMessage = null;
    });

    final sec = context.read<VaultSecurityService>();
    final db = context.read<DatabaseService>();

    // Check if Duress (Decoy Vault) PIN was entered under coercion
    final isDuress = await sec.isDuressEnabled();
    if (isDuress && await sec.verifyDuressPassword(pwd)) {
      db.isDecoyMode = true;
      if (mounted) {
        setState(() => _isAuthenticating = false);
        HapticFeedback.heavyImpact();
        AutoLockService.markUnlocked();
        Navigator.of(context).pushReplacementNamed('/home');
      }
      return;
    }

    final valid = await sec.verifyMasterPassword(pwd);

    if (mounted) {
      setState(() => _isAuthenticating = false);
      if (valid) {
        db.isDecoyMode = false;
        HapticFeedback.mediumImpact();
        AutoLockService.markUnlocked();
        Navigator.of(context).pushReplacementNamed('/home');
      } else {
        HapticFeedback.vibrate();
        setState(() => _errorMessage = 'AUTHENTICATION FAILED: INVALID PASSKEY');
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
            backgroundColor: CyberColors.cardSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: CyberColors.glassBorder, width: 1.2),
            ),
            title: Row(
              children: [
                const Icon(Icons.lock_reset_rounded, color: CyberColors.laserCyan, size: 22),
                const SizedBox(width: 8),
                Text(
                  'RECOVER VAULT ACCESS',
                  style: CyberTypography.hudTitle(
                    fontSize: 15,
                    color: CyberColors.textWhite,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isKeyVerified) ...[
                    Text(
                      'Input your 16-character hardware Recovery Key to authenticate emergency override:',
                      style: CyberTypography.body(fontSize: 12, color: CyberColors.textMuted),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: keyController,
                      textCapitalization: TextCapitalization.characters,
                      style: CyberTypography.mono(
                        color: CyberColors.laserCyan,
                        fontSize: 14,
                        letterSpacing: 2.0,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'XXXX-XXXX-XXXX-XXXX',
                        prefixIcon: Icon(Icons.vpn_key_rounded, color: CyberColors.laserCyan, size: 20),
                      ),
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: CyberColors.electricMint.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: CyberColors.electricMint.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.verified_user_rounded, color: CyberColors.electricMint, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            'RECOVERY KEY VERIFIED',
                            style: CyberTypography.mono(
                              color: CyberColors.electricMint,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: newPasswordController,
                      obscureText: true,
                      style: CyberTypography.mono(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'NEW MASTER PASSKEY',
                        prefixIcon: Icon(Icons.password_rounded, color: CyberColors.laserCyan, size: 20),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmPasswordController,
                      obscureText: true,
                      style: CyberTypography.mono(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'CONFIRM PASSKEY',
                        prefixIcon: Icon(Icons.check_circle_outline_rounded, color: CyberColors.laserCyan, size: 20),
                      ),
                    ),
                  ],
                  if (dialogError != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      dialogError!,
                      style: CyberTypography.mono(color: CyberColors.crimsonAlert, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                child: Text('ABORT', style: CyberTypography.mono(color: CyberColors.textMuted, fontSize: 12)),
                onPressed: () => Navigator.pop(ctx),
              ),
              CyberNeonButton(
                height: 42,
                primaryColor: CyberColors.laserCyan,
                label: isKeyVerified ? 'RESEAL & UNLOCK' : 'VERIFY KEY',
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
                      setDialogState(() => dialogError = 'INVALID RECOVERY KEY CHECKSUM');
                    }
                  } else {
                    final p1 = newPasswordController.text.trim();
                    final p2 = confirmPasswordController.text.trim();
                    if (p1.length < 4) {
                      setDialogState(() => dialogError = 'PASSKEY MUST BE >= 4 CHARACTERS');
                      return;
                    }
                    if (p1 != p2) {
                      setDialogState(() => dialogError = 'PASSKEYS DO NOT MATCH');
                      return;
                    }
                    final messenger = ScaffoldMessenger.of(context);
                    final navigator = Navigator.of(context);
                    await sec.resetMasterPassword(p1);
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Master Passkey updated successfully!'),
                        backgroundColor: CyberColors.cardSurface,
                      ),
                    );
                    navigator.pushReplacementNamed('/home');
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
      backgroundColor: CyberColors.obsidianBg,
      body: CyberBackground(
        showGrid: true,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Robotic Vault Lock Core with Dynamic Breathing Glow
                  AnimatedBuilder(
                    animation: _glowController,
                    builder: (context, child) {
                      return Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF0D1526),
                          border: Border.all(
                            color: CyberColors.laserCyan.withValues(alpha: 0.5),
                            width: 1.8,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: CyberColors.laserCyan.withValues(alpha: 0.28),
                              blurRadius: _glowAnimation.value,
                              spreadRadius: _glowAnimation.value * 0.25,
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: Image.asset(
                            'assets/icons/vault_logo.png',
                            width: 86,
                            height: 86,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.security_rounded,
                              size: 48,
                              color: CyberColors.laserCyan,
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 20),

                  // Brand & Status Telemetry
                  Text(
                    'TETHERPASS',
                    style: CyberTypography.hudTitle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.8,
                      color: CyberColors.textWhite,
                    ),
                  ),
                  const SizedBox(height: 8),

                  const CyberBadge(
                    text: 'VAULT ENCLAVE: ARMED // ZERO-KNOWLEDGE',
                    icon: Icons.shield_rounded,
                    color: CyberColors.laserCyan,
                    hasGlow: true,
                  ),

                  const SizedBox(height: 28),

                  // Glassmorphic Credential Input Chassis
                  CyberGlassCard(
                    padding: const EdgeInsets.all(22),
                    borderRadius: 18,
                    borderColor: CyberColors.glassBorder,
                    showCornerBrackets: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'HARDWARE PASSKEY',
                              style: CyberTypography.mono(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: CyberColors.textMuted,
                                letterSpacing: 1.0,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: CyberColors.electricMint.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'AES-256',
                                style: CyberTypography.mono(
                                  fontSize: 9.5,
                                  color: CyberColors.electricMint,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Monospace Password Field with Cyan Refraction
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          style: CyberTypography.mono(
                            color: Colors.white,
                            fontSize: 15,
                            letterSpacing: _obscurePassword ? 4.0 : 1.5,
                          ),
                          onSubmitted: (_) => _unlockWithPassword(),
                          decoration: InputDecoration(
                            hintText: 'Enter Master Passkey',
                            prefixIcon: const Icon(
                              Icons.vpn_key_rounded,
                              color: CyberColors.laserCyan,
                              size: 20,
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                color: CyberColors.textMuted,
                                size: 20,
                              ),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                        ),

                        if (_errorMessage != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: CyberColors.crimsonAlert.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: CyberColors.crimsonAlert.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.warning_amber_rounded, color: CyberColors.crimsonAlert, size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: CyberTypography.mono(
                                      color: CyberColors.crimsonAlert,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 20),

                        // High-Contrast Primary Electric Mint Unlock Button
                        CyberNeonButton(
                          onPressed: _isAuthenticating ? null : _unlockWithPassword,
                          label: 'DISARM VAULT',
                          icon: const Icon(Icons.lock_open_rounded, color: Colors.black, size: 18),
                          primaryColor: CyberColors.electricMint,
                          textColor: Colors.black,
                          isLoading: _isAuthenticating,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 22),

                  // Glassmorphic Biometric Sensor Trigger
                  CyberGlassCard(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    borderRadius: 30,
                    borderColor: CyberColors.laserCyan.withValues(alpha: 0.3),
                    glowColor: CyberColors.laserCyan,
                    onTap: _triggerBiometric,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: CyberColors.laserCyan.withValues(alpha: 0.15),
                          ),
                          child: const Icon(
                            Icons.fingerprint_rounded,
                            color: CyberColors.laserCyan,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'BIOMETRIC SCAN',
                              style: CyberTypography.hudTitle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: CyberColors.textWhite,
                                letterSpacing: 0.8,
                              ),
                            ),
                            Text(
                              'Tap for Touch / Face ID',
                              style: CyberTypography.mono(
                                fontSize: 10,
                                color: CyberColors.laserCyan,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),

                  const SizedBox(height: 26),

                  // Forgot Password Recovery Button
                  TextButton.icon(
                    onPressed: _showForgotPasswordDialog,
                    icon: const Icon(Icons.help_outline_rounded, color: CyberColors.textMuted, size: 15),
                    label: Text(
                      'LOST MASTER PASSKEY? RECOVER ACCESS',
                      style: CyberTypography.mono(
                        color: CyberColors.textMuted,
                        fontSize: 11,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
