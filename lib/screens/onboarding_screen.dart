import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/database_service.dart';
import '../services/drive_service.dart';
import '../services/secure_backup_export_service.dart';
import '../services/vault_security_service.dart';

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
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
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
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1E293B)),
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
                        height: 8,
                        decoration: BoxDecoration(
                          color: _currentPage == index
                              ? const Color(0xFFFF6F00) // Orange accent
                              : const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(4),
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
    );
  }

  // ─── Step 1: Welcome & Restore ─────────────────────────────────────────────

  Widget _buildStep1Welcome() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFF6F00).withValues(alpha: 0.1),
              border: Border.all(color: const Color(0xFFFF6F00).withValues(alpha: 0.3), width: 2),
            ),
            child: const Icon(
              Icons.shield_rounded,
              size: 72,
              color: Color(0xFFFF6F00),
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'CardVault',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 32,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Zero-Knowledge Bank & Card Manager\nProtected by Hardware AES-256 and Biometrics',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF64748B), fontSize: 14, height: 1.5),
          ),
          const Spacer(),

          // Google Drive & Local Restore Option
          OutlinedButton.icon(
            onPressed: () => _showRestoreDialog(),
            icon: const Icon(Icons.cloud_download_rounded, color: Color(0xFF0F172A)),
            label: const Text('Restore via Google Drive or File', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
              backgroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFFCBD5E1)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 12),

          // Primary: Create New Vault
          ElevatedButton(
            onPressed: _nextPage,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6F00),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 54),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 3,
            ),
            child: const Text(
              'Create New Vault',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
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
          const Text(
            'Set Master Password',
            style: TextStyle(color: Color(0xFF0F172A), fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'This password encrypts your entire vault locally. It is never stored or sent to any server.',
            style: TextStyle(color: Color(0xFF64748B), fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 24),

          // Password Field
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            style: const TextStyle(color: Color(0xFF0F172A)),
            decoration: InputDecoration(
              labelText: 'Master Password (min 4 characters)',
              prefixIcon: const Icon(Icons.lock_outline_rounded, color: Color(0xFFFF6F00)),
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: const Color(0xFF64748B)),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Confirm Password Field
          TextField(
            controller: _confirmController,
            obscureText: _obscureConfirm,
            style: const TextStyle(color: Color(0xFF0F172A)),
            decoration: InputDecoration(
              labelText: 'Confirm Master Password',
              prefixIcon: const Icon(Icons.lock_rounded, color: Color(0xFFFF6F00)),
              suffixIcon: IconButton(
                icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility, color: const Color(0xFF64748B)),
                onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
              ),
            ),
          ),

          if (_step2Error != null) ...[
            const SizedBox(height: 8),
            Text(_step2Error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w600)),
          ],

          const SizedBox(height: 24),

          // Recovery Key Container
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.key_rounded, color: Color(0xFFFF6F00), size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Your 16-Character Recovery Key',
                      style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'If you forget your master password, this key is the ONLY way to recover your vault.',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED), // Warm light orange
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFFEDD5)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _generatedRecoveryKey,
                        style: const TextStyle(
                          color: Color(0xFFC2410C),
                          fontFamily: 'Courier',
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          _copiedRecoveryKey ? Icons.check_circle_rounded : Icons.copy_rounded,
                          color: _copiedRecoveryKey ? Colors.green : const Color(0xFFC2410C),
                          size: 20,
                        ),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _generatedRecoveryKey));
                          setState(() => _copiedRecoveryKey = true);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Recovery Key copied to clipboard!')),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          ElevatedButton(
            onPressed: () {
              final pwd = _passwordController.text.trim();
              final conf = _confirmController.text.trim();

              if (pwd.length < 4) {
                setState(() => _step2Error = 'Password must be at least 4 characters.');
                return;
              }
              if (pwd != conf) {
                setState(() => _step2Error = 'Passwords do not match.');
                return;
              }

              setState(() => _step2Error = null);
              _nextPage();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6F00),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 54),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Continue to Biometrics', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
              color: Colors.blue.withValues(alpha: 0.1),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.3), width: 2),
            ),
            child: const Icon(
              Icons.fingerprint_rounded,
              size: 80,
              color: Colors.blueAccent,
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'Biometric Unlock',
            style: TextStyle(color: Color(0xFF0F172A), fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Use your fingerprint or face recognition to unlock your vault quickly without entering your Master Password every time.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF64748B), fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 32),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
              ],
            ),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enable Biometrics', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold)),
              subtitle: const Text('Fingerprint / Face Recognition', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
              activeThumbColor: const Color(0xFFFF6F00),
              value: _biometricEnabled,
              onChanged: (val) => setState(() => _biometricEnabled = val),
            ),
          ),

          const Spacer(),

          ElevatedButton(
            onPressed: _isSettingUp ? null : _completeSetup,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6F00),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 54),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: _isSettingUp
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text('Finish & Open Vault', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _showRestoreDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Restore Vault', style: TextStyle(color: Color(0xFF0F172A), fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Choose where to restore your encrypted backup from:', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
            const SizedBox(height: 20),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFFF6F00).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.cloud_download_rounded, color: Color(0xFFFF6F00)),
              ),
              title: const Text('Google Drive Backup', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold)),
              subtitle: const Text('Restores from hidden Google Drive AppData folder', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              tileColor: const Color(0xFFF8F9FA),
              onTap: () async {
                Navigator.pop(ctx);
                await _restoreFromDriveInOnboarding();
              },
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.file_open_rounded, color: Colors.blueAccent),
              ),
              title: const Text('Import Backup File (.json)', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold)),
              subtitle: const Text('Select CardVault JSON backup and decrypt with Master Password', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              tileColor: const Color(0xFFF8F9FA),
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Restore error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _showMasterPasswordPromptForDrive(String payload) async {
    final passwordCtrl = TextEditingController();
    String? errorText;

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
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This Google Drive backup is encrypted with a Master Password.\n\nEnter the password to decrypt and restore your vault:',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordCtrl,
                obscureText: true,
                style: const TextStyle(color: Color(0xFF0F172A)),
                decoration: InputDecoration(
                  labelText: 'Master Password',
                  hintText: 'Enter your Master Password',
                  errorText: errorText,
                  prefixIcon: const Icon(Icons.lock_rounded, color: Color(0xFFFF6F00)),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
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
                  setDlgState(() => errorText = 'Please enter password');
                  return;
                }

                try {
                  final items = SecureBackupExportService.importVaultWithPassword(
                    backupPayload: payload,
                    userPassword: pwd,
                  );

                  final db = context.read<DatabaseService>();
                  final sec = context.read<VaultSecurityService>();
                  for (final item in items) {
                    await db.insertItem(item);
                  }

                  // Automatically configure vault with this verified Master Password
                  await sec.setupVault(masterPassword: pwd, biometricEnabled: true);

                  if (mounted) {
                    Navigator.pop(dlgCtx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('✓ Successfully restored ${items.length} items from Google Drive!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
                  }
                } catch (e) {
                  setDlgState(() => errorText = 'Incorrect password. Please verify and try again.');
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
        dialogTitle: 'Select CardVault Encrypted Backup (.json)',
      );

      if (result == null || result.files.isEmpty || result.files.single.path == null) {
        return;
      }

      final file = File(result.files.single.path!);
      final fileContent = await file.readAsString();
      final fileName = result.files.single.name;

      if (!mounted) return;

      final passwordCtrl = TextEditingController();
      String? errorText;

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
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Selected: $fileName\n\nEnter the Master Password used when this backup file was created:',
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordCtrl,
                  obscureText: true,
                  style: const TextStyle(color: Color(0xFF0F172A)),
                  decoration: InputDecoration(
                    labelText: 'Master Password',
                    hintText: 'Enter your Master Password',
                    errorText: errorText,
                    prefixIcon: const Icon(Icons.key_rounded, color: Color(0xFFFF6F00)),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
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
                    setDlgState(() => errorText = 'Please enter password');
                    return;
                  }

                  try {
                    final items = SecureBackupExportService.importVaultWithPassword(
                      backupPayload: fileContent,
                      userPassword: pwd,
                    );

                    final db = context.read<DatabaseService>();
                    final sec = context.read<VaultSecurityService>();
                    for (final item in items) {
                      await db.insertItem(item);
                    }

                    // Automatically setup vault with this verified Master Password
                    await sec.setupVault(masterPassword: pwd, biometricEnabled: true);

                    if (mounted) {
                      Navigator.pop(dlgCtx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('✓ Successfully restored ${items.length} items from $fileName!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                      Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
                    }
                  } catch (e) {
                    setDlgState(() => errorText = 'Incorrect password or incompatible backup file.');
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
