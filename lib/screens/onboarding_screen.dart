import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/database_service.dart';
import '../services/drive_service.dart';
import '../services/secure_backup_export_service.dart';
import '../services/vault_security_service.dart';
import '../theme/cyber_theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // Step 2 controllers
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String _generatedRecoveryKey = '';
  bool _copiedRecoveryKey = false;
  String? _step2Error;

  // Step 3
  bool _biometricEnabled = true;
  bool _isSettingUp = false;

  @override
  void initState() {
    super.initState();
    final sec = context.read<VaultSecurityService>();
    _generatedRecoveryKey = sec.generateRecoveryKey();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _nextPage() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _previousPage() {
    _pageController.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _completeSetup() async {
    setState(() => _isSettingUp = true);
    final sec = context.read<VaultSecurityService>();

    try {
      await sec.setupVault(
        masterPassword: _passwordController.text.trim(),
        biometricEnabled: _biometricEnabled,
        customRecoveryKey: _generatedRecoveryKey,
      );

      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Setup failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSettingUp = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CyberColors.obsidianBg,
      body: CyberBackground(
        showGrid: true,
        child: SafeArea(
          child: Column(
            children: [
              // Top Indicator
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (_currentPage > 0)
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: CyberColors.laserCyan),
                        onPressed: _previousPage,
                      )
                    else
                      const SizedBox(width: 48),
                    Row(
                      children: List.generate(
                        3,
                        (index) => Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: _currentPage == index ? 24 : 8,
                          height: 6,
                          decoration: BoxDecoration(
                            color: _currentPage == index
                                ? CyberColors.laserCyan
                                : CyberColors.glassBorderMuted,
                            borderRadius: BorderRadius.circular(3),
                            boxShadow: _currentPage == index
                                ? [
                                    BoxShadow(
                                      color: CyberColors.laserCyan.withValues(alpha: 0.5),
                                      blurRadius: 6,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),

              // Page View
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (page) => setState(() => _currentPage = page),
                  children: [
                    _buildStep1Welcome(),
                    _buildStep2MasterPassword(),
                    _buildStep3Biometric(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Step 1: Welcome & Genesis ─────────────────────────────────────────────

  Widget _buildStep1Welcome() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF0F172A),
              border: Border.all(color: CyberColors.laserCyan.withValues(alpha: 0.5), width: 1.8),
              boxShadow: [
                BoxShadow(
                  color: CyberColors.laserCyan.withValues(alpha: 0.25),
                  blurRadius: 28,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/icons/vault_logo.png',
                width: 96,
                height: 96,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.shield_rounded,
                  color: CyberColors.laserCyan,
                  size: 48,
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'TETHERPASS',
            style: CyberTypography.hudTitle(
              color: CyberColors.textWhite,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: 3.0,
            ),
          ),
          const SizedBox(height: 8),
          const CyberBadge(
            text: 'ZERO-KNOWLEDGE // HARDWARE ENCLAVE',
            color: CyberColors.laserCyan,
            hasGlow: true,
          ),
          const SizedBox(height: 12),
          Text(
            'Air-Gapped Sovereign Credential & Bank Manager\nProtected by Hardware AES-256 and Biometric Nodes',
            textAlign: TextAlign.center,
            style: CyberTypography.body(
              color: CyberColors.textMuted,
              fontSize: 13,
            ),
          ),
          const Spacer(),

          // Google Drive & Local Restore Option
          CyberNeonButton(
            onPressed: () => _showRestoreDialog(),
            isOutlined: true,
            label: 'RESTORE FROM DRIVE // FILE',
            icon: const Icon(Icons.cloud_download_rounded, color: CyberColors.laserCyan, size: 18),
            primaryColor: CyberColors.laserCyan,
          ),
          const SizedBox(height: 14),

          // Primary: Create New Vault
          CyberNeonButton(
            onPressed: _nextPage,
            label: 'INITIALIZE NEW VAULT',
            icon: const Icon(Icons.add_moderator_rounded, color: Colors.black, size: 18),
            primaryColor: CyberColors.electricMint,
            textColor: Colors.black,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ─── Step 2: Set Master Password & Recovery Key ────────────────────────────

  Widget _buildStep2MasterPassword() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ARM MASTER PASSKEY',
            style: CyberTypography.hudTitle(
              color: CyberColors.textWhite,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'This sovereign passkey locally seals your hardware vault. It is zero-knowledge and never leaves this device.',
            style: CyberTypography.body(color: CyberColors.textMuted, fontSize: 12.5),
          ),
          const SizedBox(height: 22),

          // Password Field
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            style: CyberTypography.mono(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              labelText: 'MASTER PASSKEY (MIN 4 CHARS)',
              prefixIcon: const Icon(Icons.lock_outline_rounded, color: CyberColors.laserCyan),
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: CyberColors.textMuted),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Confirm Password Field
          TextField(
            controller: _confirmController,
            obscureText: _obscureConfirm,
            style: CyberTypography.mono(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              labelText: 'CONFIRM MASTER PASSKEY',
              prefixIcon: const Icon(Icons.lock_rounded, color: CyberColors.laserCyan),
              suffixIcon: IconButton(
                icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility, color: CyberColors.textMuted),
                onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
              ),
            ),
          ),

          if (_step2Error != null) ...[
            const SizedBox(height: 8),
            Text(
              _step2Error!,
              style: CyberTypography.mono(color: CyberColors.crimsonAlert, fontSize: 11),
            ),
          ],

          const SizedBox(height: 22),

          // Recovery Key Glassmorphic Container
          CyberGlassCard(
            padding: const EdgeInsets.all(18),
            borderRadius: 16,
            borderColor: CyberColors.glassBorder,
            showCornerBrackets: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.key_rounded, color: CyberColors.laserCyan, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '16-CHARACTER RECOVERY KEY',
                      style: CyberTypography.hudTitle(
                        color: CyberColors.textWhite,
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'If you forget your master passkey, this hardware key is the ONLY sovereign method to recover your vault.',
                  style: CyberTypography.body(color: CyberColors.textMuted, fontSize: 11),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    color: CyberColors.cardSurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: CyberColors.laserCyan.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _generatedRecoveryKey,
                            style: CyberTypography.mono(
                              color: CyberColors.laserCyan,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2.0,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          _copiedRecoveryKey ? Icons.check_circle_rounded : Icons.copy_rounded,
                          color: _copiedRecoveryKey ? CyberColors.electricMint : CyberColors.laserCyan,
                          size: 20,
                        ),
                        tooltip: 'Copy Recovery Key',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _generatedRecoveryKey));
                          setState(() => _copiedRecoveryKey = true);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Recovery Key copied to secure clipboard!'),
                              backgroundColor: CyberColors.cardSurface,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          CyberNeonButton(
            onPressed: () {
              final pwd = _passwordController.text.trim();
              final conf = _confirmController.text.trim();

              if (pwd.length < 4) {
                setState(() => _step2Error = 'Passkey must be at least 4 characters.');
                return;
              }
              if (pwd != conf) {
                setState(() => _step2Error = 'Passkeys do not match.');
                return;
              }

              setState(() => _step2Error = null);
              _nextPage();
            },
            primaryColor: CyberColors.laserCyan,
            label: 'PROCEED TO BIOMETRICS',
            icon: const Icon(Icons.arrow_forward_rounded, color: Colors.black, size: 18),
          ),
        ],
      ),
    );
  }

  // ─── Step 3: Biometric Authentication Prompt ───────────────────────────────

  Widget _buildStep3Biometric() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: CyberColors.glassFill,
              border: Border.all(color: CyberColors.laserCyan.withValues(alpha: 0.5), width: 2),
              boxShadow: [
                BoxShadow(
                  color: CyberColors.laserCyan.withValues(alpha: 0.25),
                  blurRadius: 24,
                ),
              ],
            ),
            child: const Icon(
              Icons.fingerprint_rounded,
              size: 80,
              color: CyberColors.laserCyan,
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'BIOMETRIC PROTOCOL',
            style: CyberTypography.hudTitle(
              color: CyberColors.textWhite,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Arm hardware fingerprint or facial recognition to disarm your vault quickly without entering your Master Passkey every cycle.',
            textAlign: TextAlign.center,
            style: CyberTypography.body(color: CyberColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 28),

          CyberGlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            borderRadius: 16,
            borderColor: CyberColors.glassBorder,
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'ENABLE BIOMETRICS',
                style: CyberTypography.hudTitle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              subtitle: Text(
                'Fingerprint / Touch / Face ID',
                style: CyberTypography.mono(color: CyberColors.laserCyan, fontSize: 11),
              ),
              activeThumbColor: CyberColors.laserCyan,
              value: _biometricEnabled,
              onChanged: (val) => setState(() => _biometricEnabled = val),
            ),
          ),

          const Spacer(),

          CyberNeonButton(
            onPressed: _isSettingUp ? null : _completeSetup,
            isLoading: _isSettingUp,
            label: 'SEAL VAULT & INITIALIZE',
            icon: const Icon(Icons.lock_rounded, color: Colors.black, size: 18),
            primaryColor: CyberColors.electricMint,
            textColor: Colors.black,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _showRestoreDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: CyberColors.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        side: BorderSide(color: CyberColors.glassBorder, width: 1.2),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'RESTORE VAULT PAYLOAD',
              style: CyberTypography.hudTitle(
                color: CyberColors.textWhite,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Select source to reconstruct encrypted enclave payload:',
              style: CyberTypography.mono(color: CyberColors.textMuted, fontSize: 11),
            ),
            const SizedBox(height: 18),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: CyberColors.laserCyan.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: CyberColors.laserCyan.withValues(alpha: 0.3)),
                ),
                child: const Icon(Icons.cloud_download_rounded, color: CyberColors.laserCyan),
              ),
              title: Text('Google Drive Cloud Backup', style: CyberTypography.hudTitle(color: Colors.white, fontSize: 13)),
              subtitle: Text('Reconstruct from hidden AppData enclave payload', style: CyberTypography.mono(color: CyberColors.textMuted, fontSize: 10)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: CyberColors.glassBorderMuted),
              ),
              tileColor: CyberColors.glassFill,
              onTap: () async {
                Navigator.pop(ctx);
                await _restoreFromDriveInOnboarding();
              },
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: CyberColors.electricMint.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: CyberColors.electricMint.withValues(alpha: 0.3)),
                ),
                child: const Icon(Icons.file_open_rounded, color: CyberColors.electricMint),
              ),
              title: Text('Import Encrypted File (.json)', style: CyberTypography.hudTitle(color: Colors.white, fontSize: 13)),
              subtitle: Text('Load local ciphertext payload and decrypt with passkey', style: CyberTypography.mono(color: CyberColors.textMuted, fontSize: 10)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: CyberColors.glassBorderMuted),
              ),
              tileColor: CyberColors.glassFill,
              onTap: () {
                Navigator.pop(ctx);
                _importBackupFileInOnboarding();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _restoreFromDriveInOnboarding() async {
    final drive = context.read<DriveService>();
    final ok = await drive.signIn();
    if (!ok || !mounted) return;

    try {
      final count = await drive.restore();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restored $count items! Proceeding to setup...'), backgroundColor: Colors.green),
        );
        _nextPage();
      }
    } on MasterPasswordRequiredException catch (req) {
      if (!mounted) return;
      await _showMasterPasswordPromptForDrive(req.payload);
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('master password') ||
          msg.contains('password') ||
          msg.contains('key mismatch') ||
          msg.contains('decryption failed')) {
        if (!mounted) return;
        final payload = await drive.downloadRawBackupPayload().catchError((_) => '');
        if (!mounted) return;
        await _showMasterPasswordPromptForDrive(payload);
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Restore error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _showMasterPasswordPromptForDrive(String payload) async {
    final sec = context.read<VaultSecurityService>();
    final db = context.read<DatabaseService>();
    final passwordCtrl = TextEditingController();
    String? errorText;
    bool isUsingRecoveryKey = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.cloud_download_rounded, color: Color(0xFFFF6F00)),
              SizedBox(width: 8),
              Text('Cloud Backup Detected', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isUsingRecoveryKey
                      ? 'Enter your 16-character Emergency Recovery Key (XXXX-XXXX-XXXX-XXXX):'
                      : 'This Google Drive backup is encrypted with a Master Password.\n\nEnter password to decrypt and restore:',
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordCtrl,
                  obscureText: !isUsingRecoveryKey,
                  style: const TextStyle(color: Color(0xFF0F172A)),
                  decoration: InputDecoration(
                    labelText: isUsingRecoveryKey ? 'Recovery Key' : 'Master Password',
                    hintText: isUsingRecoveryKey ? 'XXXX-XXXX-XXXX-XXXX' : 'Enter your Master Password',
                    errorText: errorText,
                    prefixIcon: Icon(isUsingRecoveryKey ? Icons.vpn_key_rounded : Icons.lock_rounded, color: const Color(0xFFFF6F00)),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    child: Text(
                      isUsingRecoveryKey ? 'Use Master Password instead' : 'Forgot Password? Use 16-char Recovery Key',
                      style: const TextStyle(color: Color(0xFF0284C7), fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    onPressed: () {
                      setDlgState(() {
                        isUsingRecoveryKey = !isUsingRecoveryKey;
                        errorText = null;
                        passwordCtrl.clear();
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
              onPressed: () => Navigator.pop(dlgCtx),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6F00)),
              child: const Text('Decrypt & Finish Setup'),
              onPressed: () async {
                final pwd = passwordCtrl.text.trim();
                if (pwd.isEmpty) {
                  setDlgState(() => errorText = isUsingRecoveryKey ? 'Please enter recovery key' : 'Please enter password');
                  return;
                }

                try {
                  int count = 0;
                  if (payload.contains('TETHERPASS_SECURE_BACKUP') || payload.contains('CARDVAULT_SECURE_BACKUP')) {
                    final items = SecureBackupExportService.importVaultWithPassword(
                      backupPayload: payload,
                      userPassword: pwd,
                    );
                    for (final item in items) {
                      await db.insertItem(item);
                    }
                    count = items.length;
                  } else {
                    count = await db.importEncryptedBackup(payload, masterPassword: pwd);
                  }

                  if (isUsingRecoveryKey) {
                    // Decrypted using recovery key! Let user choose their new master password
                    if (context.mounted) {
                      Navigator.pop(dlgCtx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('✓ Verified with Recovery Key! Restored $count items. Please create your Master Password:'),
                          backgroundColor: Colors.green,
                        ),
                      );
                      _pageController.animateToPage(1, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                    }
                  } else {
                    // Automatically configure vault with this verified Master Password
                    await sec.setupVault(masterPassword: pwd, biometricEnabled: true);
                    if (context.mounted) {
                      Navigator.pop(dlgCtx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('✓ Successfully restored $count items from Google Drive!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                      Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
                    }
                  }
                } catch (e) {
                  setDlgState(() => errorText = isUsingRecoveryKey
                      ? 'Invalid Recovery Key. Please check the 16 characters.'
                      : 'Incorrect password. Please verify or use your Recovery Key.');
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _importBackupFileInOnboarding() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: 'Select TetherPass Encrypted Backup (.json)',
      );

      if (result == null || result.files.isEmpty || result.files.single.path == null) {
        return;
      }

      final file = File(result.files.single.path!);
      final fileContent = await file.readAsString();
      final fileName = result.files.single.name;

      if (!mounted) return;

      final sec = context.read<VaultSecurityService>();
      final db = context.read<DatabaseService>();
      final passwordCtrl = TextEditingController();
      String? errorText;
      bool isUsingRecoveryKey = false;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dlgCtx) => StatefulBuilder(
          builder: (context, setDlgState) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.file_open_rounded, color: Color(0xFFFF6F00)),
                SizedBox(width: 8),
                Text('Decrypt Backup File', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Selected: $fileName\n\n${isUsingRecoveryKey ? 'Enter your 16-character Emergency Recovery Key:' : 'Enter the Master Password used when this backup was created:'}',
                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordCtrl,
                    obscureText: !isUsingRecoveryKey,
                    style: const TextStyle(color: Color(0xFF0F172A)),
                    decoration: InputDecoration(
                      labelText: isUsingRecoveryKey ? 'Recovery Key' : 'Master Password',
                      hintText: isUsingRecoveryKey ? 'XXXX-XXXX-XXXX-XXXX' : 'Enter your Master Password',
                      errorText: errorText,
                      prefixIcon: Icon(isUsingRecoveryKey ? Icons.vpn_key_rounded : Icons.key_rounded, color: const Color(0xFFFF6F00)),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      child: Text(
                        isUsingRecoveryKey ? 'Use Master Password instead' : 'Forgot Password? Use 16-char Recovery Key',
                        style: const TextStyle(color: Color(0xFF0284C7), fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      onPressed: () {
                        setDlgState(() {
                          isUsingRecoveryKey = !isUsingRecoveryKey;
                          errorText = null;
                          passwordCtrl.clear();
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
                onPressed: () => Navigator.pop(dlgCtx),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6F00)),
                child: const Text('Decrypt & Finish Setup'),
                onPressed: () async {
                  final pwd = passwordCtrl.text.trim();
                  if (pwd.isEmpty) {
                    setDlgState(() => errorText = isUsingRecoveryKey ? 'Please enter recovery key' : 'Please enter password');
                    return;
                  }

                  try {
                    final items = SecureBackupExportService.importVaultWithPassword(
                      backupPayload: fileContent,
                      userPassword: pwd,
                    );

                    for (final item in items) {
                      await db.insertItem(item);
                    }

                    if (isUsingRecoveryKey) {
                      if (context.mounted) {
                        Navigator.pop(dlgCtx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('✓ Verified with Recovery Key! Restored ${items.length} items. Please create your Master Password:'),
                            backgroundColor: Colors.green,
                          ),
                        );
                        _pageController.animateToPage(1, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                      }
                    } else {
                      await sec.setupVault(masterPassword: pwd, biometricEnabled: true);
                      if (context.mounted) {
                        Navigator.pop(dlgCtx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('✓ Successfully restored ${items.length} items from $fileName!'),
                            backgroundColor: Colors.green,
                          ),
                        );
                        Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
                      }
                    }
                  } catch (e) {
                    setDlgState(() => errorText = isUsingRecoveryKey
                        ? 'Invalid Recovery Key. Please check the 16 characters.'
                        : 'Incorrect password or incompatible backup file.');
                  }
                },
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
