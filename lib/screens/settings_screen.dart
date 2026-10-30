import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/autofill_bridge_service.dart';
import '../services/database_service.dart';
import '../services/drive_service.dart';
import '../services/extension_auth_service.dart';
import '../services/secure_backup_export_service.dart';
import '../services/vault_security_service.dart';
import '../widgets/app_tour_dialog.dart';
import '../widgets/spotlight_tour.dart';
import 'browser_extension_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _biometricEnabled = true;

  // GlobalKeys for pointing directly to each setting in the spotlight tour
  final GlobalKey _accountKey = GlobalKey();
  final GlobalKey _biometricKey = GlobalKey();
  final GlobalKey _changePasswordKey = GlobalKey();
  final GlobalKey _recoveryKeyTileKey = GlobalKey();
  final GlobalKey _autofillKey = GlobalKey();
  final GlobalKey _exportKey = GlobalKey();
  final GlobalKey _importKey = GlobalKey();
  final GlobalKey _lockNowKey = GlobalKey();

  void _startSettingsSpotlightTour() {
    final steps = <SpotlightTourStep>[
      SpotlightTourStep(
        targetKey: _accountKey,
        icon: Icons.account_circle_rounded,
        title: 'Account & Google Drive Linking',
        description: 'Displays your profile and lets you link or disconnect Google Drive. When connected, vault backups happen automatically in the background.',
        isCircle: false,
        borderRadius: 16,
      ),
      SpotlightTourStep(
        targetKey: _biometricKey,
        icon: Icons.fingerprint_rounded,
        title: 'Biometric Unlock Toggle',
        description: 'Enable or disable fingerprint/face recognition. When enabled, the vault unlocks immediately with no password fallback prompt.',
        isCircle: false,
        borderRadius: 16,
      ),
      SpotlightTourStep(
        targetKey: _changePasswordKey,
        icon: Icons.lock_outline_rounded,
        title: 'Change Master Password',
        description: 'Update your Master Password at any time with zero-knowledge verification (only salted SHA-256 is checked).',
        isCircle: false,
        borderRadius: 16,
      ),
      SpotlightTourStep(
        targetKey: _recoveryKeyTileKey,
        icon: Icons.key_rounded,
        title: '16-Character Emergency Recovery Key',
        description: 'View or regenerate your emergency recovery key (XXXX-XXXX-XXXX-XXXX). If you ever forget your Master Password, this key lets you reset it!',
        isCircle: false,
        borderRadius: 16,
      ),
      SpotlightTourStep(
        targetKey: _autofillKey,
        icon: Icons.keyboard_rounded,
        title: 'Keyboard Payment Autofill',
        description: 'Enables card chips above your keyboard in Chrome and shopping apps. Only active when CardVault is unlocked!',
        isCircle: false,
        borderRadius: 16,
      ),
      SpotlightTourStep(
        targetKey: _exportKey,
        icon: Icons.file_upload_outlined,
        title: 'Export Offline Backup',
        description: 'Exports your entire vault locally encrypted with AES-256 so you can save a copy to file or message it securely.',
        isCircle: false,
        borderRadius: 16,
      ),
      SpotlightTourStep(
        targetKey: _importKey,
        icon: Icons.file_download_outlined,
        title: 'Import Offline Backup',
        description: 'Restore your vault credentials by pasting your previously exported encrypted backup code.',
        isCircle: false,
        borderRadius: 16,
      ),
      SpotlightTourStep(
        targetKey: _lockNowKey,
        icon: Icons.lock_clock_rounded,
        title: 'Lock Vault Now',
        description: 'Instantly lock the app and return to the biometric and Master Password authentication screen.',
        isCircle: false,
        borderRadius: 16,
      ),
    ];

    SpotlightTourOverlay.show(
      context: context,
      steps: steps,
    );
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final sec = context.read<VaultSecurityService>();
    final bio = await sec.isBiometricEnabled();
    if (mounted) setState(() => _biometricEnabled = bio);

    // Refresh Google Drive sign-in state silently on opening settings
    if (mounted) {
      final drive = context.read<DriveService>();
      if (!drive.isSignedIn) {
        await drive.trySilentSignIn();
      }
    }
  }

  Future<void> _toggleBiometrics(bool val) async {
    final sec = context.read<VaultSecurityService>();
    await sec.setBiometricEnabled(val);
    setState(() => _biometricEnabled = val);
  }

  void _showChangePasswordDialog() {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? err;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Change Master Password', style: TextStyle(color: Color(0xFF0F172A), fontSize: 18, fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: oldCtrl,
                    obscureText: true,
                    style: const TextStyle(color: Color(0xFF0F172A)),
                    decoration: const InputDecoration(
                      labelText: 'Current Master Password',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: newCtrl,
                    obscureText: true,
                    style: const TextStyle(color: Color(0xFF0F172A)),
                    decoration: const InputDecoration(
                      labelText: 'New Master Password (min 4 chars)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmCtrl,
                    obscureText: true,
                    style: const TextStyle(color: Color(0xFF0F172A)),
                    decoration: const InputDecoration(
                      labelText: 'Confirm New Password',
                    ),
                  ),
                  if (err != null) ...[
                    const SizedBox(height: 10),
                    Text(err!, style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w600)),
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
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6F00)),
                child: const Text('Save'),
                onPressed: () async {
                  final sec = context.read<VaultSecurityService>();
                  final oldP = oldCtrl.text.trim();
                  final newP = newCtrl.text.trim();
                  final confP = confirmCtrl.text.trim();

                  final ok = await sec.verifyMasterPassword(oldP);
                  if (!ok) {
                    setDialogState(() => err = 'Current password is incorrect.');
                    return;
                  }
                  if (newP.length < 4) {
                    setDialogState(() => err = 'New password must be at least 4 characters.');
                    return;
                  }
                  if (newP != confP) {
                    setDialogState(() => err = 'New passwords do not match.');
                    return;
                  }

                  await sec.resetMasterPassword(newP);
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    const SnackBar(content: Text('Master Password changed successfully!')),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _viewOrRegenerateRecoveryKey() async {
    final sec = context.read<VaultSecurityService>();
    final currentKey = await sec.getRecoveryKey() ?? 'XXXX-XXXX-XXXX-XXXX';

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: const [
                Icon(Icons.key_rounded, color: Color(0xFFFF6F00)),
                SizedBox(width: 8),
                Text('Recovery Key', style: TextStyle(color: Color(0xFF0F172A), fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Keep this 16-character key safe. If you forget your Master Password, this key lets you reset it.',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFFEDD5)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        currentKey,
                        style: const TextStyle(
                          color: Color(0xFFC2410C),
                          fontFamily: 'Courier',
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, color: Color(0xFFC2410C), size: 20),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: currentKey));
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
            actions: [
              TextButton(
                child: const Text('Close', style: TextStyle(color: Color(0xFF64748B))),
                onPressed: () => Navigator.pop(ctx),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6F00)),
                child: const Text('Regenerate Key'),
                onPressed: () async {
                  final newK = await sec.regenerateRecoveryKey();
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(content: Text('New Recovery Key generated: $newK')),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _exportBackupFile() async {
    final sec = context.read<VaultSecurityService>();
    final db = context.read<DatabaseService>();
    final masterPwd = await sec.getMasterPassword();

    final passwordCtrl = TextEditingController(text: masterPwd ?? '');
    String? errorText;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.file_upload_outlined, color: Color(0xFFFF6F00)),
              SizedBox(width: 8),
              Text('Export Vault (JSON)', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your vault will be securely encrypted with AES-256 PBKDF2 using your Master Password and saved directly to your device storage in JSON format.',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordCtrl,
                obscureText: true,
                style: const TextStyle(color: Color(0xFF0F172A)),
                decoration: InputDecoration(
                  labelText: 'Encryption Master Password',
                  hintText: 'Enter your Master Password',
                  errorText: errorText,
                  helperText: masterPwd != null ? 'Using your configured Master Password' : null,
                  helperStyle: const TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold),
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
              onPressed: () => Navigator.pop(ctx),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6F00)),
              child: const Text('Export JSON to Device'),
              onPressed: () async {
                final pwd = passwordCtrl.text.trim();
                if (pwd.length < 4) {
                  setDlgState(() => errorText = 'Password must be at least 4 characters');
                  return;
                }
                Navigator.pop(ctx);

                try {
                  final items = await db.getAllItems();
                  if (items.isEmpty) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Your vault is empty. Nothing to export.'), backgroundColor: Colors.orange),
                      );
                    }
                    return;
                  }

                  final encryptedPayload = SecureBackupExportService.exportVaultWithPassword(
                    items: items,
                    userPassword: pwd,
                  );

                  final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
                  final fileName = 'CardVault_Backup_$timestamp.json';

                  // Save exclusively to local device storage (Downloads directory preferred)
                  File? savedFile;
                  final downloadDir = Directory('/storage/emulated/0/Download');
                  if (await downloadDir.exists()) {
                    try {
                      final targetFile = File('${downloadDir.path}/$fileName');
                      await targetFile.writeAsString(encryptedPayload, flush: true);
                      savedFile = targetFile;
                    } catch (_) {}
                  }

                  if (savedFile == null) {
                    try {
                      final extDirs = await getExternalStorageDirectories(type: StorageDirectory.downloads);
                      if (extDirs != null && extDirs.isNotEmpty) {
                        final targetFile = File('${extDirs.first.path}/$fileName');
                        await targetFile.writeAsString(encryptedPayload, flush: true);
                        savedFile = targetFile;
                      }
                    } catch (_) {}
                  }

                  if (savedFile == null) {
                    final appDocs = await getApplicationDocumentsDirectory();
                    final targetFile = File('${appDocs.path}/$fileName');
                    await targetFile.writeAsString(encryptedPayload, flush: true);
                    savedFile = targetFile;
                  }

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Row(
                          children: [
                            const Icon(Icons.check_circle_rounded, color: Colors.white),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '✓ Backup saved locally:\n${savedFile.path}',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                        backgroundColor: const Color(0xFF16A34A),
                        duration: const Duration(seconds: 5),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _importBackupFile() async {
    try {
      // 1. Pick .json file from device storage
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: 'Select CardVault Encrypted Backup (.json)',
      );

      if (result == null || result.files.isEmpty || result.files.single.path == null) {
        return; // User cancelled file selection
      }

      final file = File(result.files.single.path!);
      final fileContent = await file.readAsString();
      final fileName = result.files.single.name;

      final sec = context.read<VaultSecurityService>();
      final db = context.read<DatabaseService>();
      final masterPwd = await sec.getMasterPassword();

      // 2. Try automatic decryption if Master Password is available
      if (masterPwd != null && masterPwd.isNotEmpty) {
        try {
          final items = SecureBackupExportService.importVaultWithPassword(
            backupPayload: fileContent,
            userPassword: masterPwd,
          );

          // Succeeded with user's master password! Show quick confirmation
          if (!mounted) return;
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: Colors.green),
                  SizedBox(width: 8),
                  Text('Restore Backup?', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              content: Text(
                'Decrypted $fileName successfully with your Master Password!\n\nFound ${items.length} credential(s) in this file. Would you like to restore them to your vault?',
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
              ),
              actions: [
                TextButton(
                  child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
                  onPressed: () => Navigator.pop(ctx, false),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6F00)),
                  child: Text('Restore ${items.length} Items'),
                  onPressed: () => Navigator.pop(ctx, true),
                ),
              ],
            ),
          );

          if (confirmed == true && mounted) {
            for (final item in items) {
              await db.insertItem(item);
            }
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Successfully restored ${items.length} vault items from $fileName!'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          }
          return;
        } catch (_) {
          // Decryption with current master password didn't match; fallback to prompt below
        }
      }

      // 3. Fallback prompt for password if different or not cached
      if (!mounted) return;
      final passwordCtrl = TextEditingController();
      String? errorText;

      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setDlgState) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.lock_open_rounded, color: Color(0xFFFF6F00)),
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
                    labelText: 'Decryption Password',
                    hintText: 'Enter Master Password',
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
                onPressed: () => Navigator.pop(ctx),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6F00)),
                child: const Text('Decrypt & Restore'),
                onPressed: () async {
                  final pwd = passwordCtrl.text.trim();
                  if (pwd.isEmpty) {
                    setDlgState(() => errorText = 'Please enter password');
                    return;
                  }

                  try {
                    int restoredCount = 0;
                    if (fileContent.contains('CARDVAULT_SECURE_BACKUP_V1')) {
                      final items = SecureBackupExportService.importVaultWithPassword(
                        backupPayload: fileContent,
                        userPassword: pwd,
                      );
                      for (final item in items) {
                        await db.insertItem(item);
                      }
                      restoredCount = items.length;
                    } else {
                      restoredCount = await db.importEncryptedBackup(fileContent, masterPassword: pwd);
                    }

                    Navigator.pop(ctx);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Successfully restored $restoredCount vault items from $fileName!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } on FormatException catch (fe) {
                    setDlgState(() => errorText = fe.message);
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
          SnackBar(content: Text('File import error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final drive = context.watch<DriveService>();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Settings & Security', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded, color: Color(0xFF64748B)),
            tooltip: 'Settings Tour',
            onPressed: _startSettingsSpotlightTour,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Merged Profile & Google Account Linking Card ──
            Container(
              key: _accountKey,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1)),
                ],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: const Color(0xFFFF6F00).withValues(alpha: 0.12),
                    backgroundImage: drive.userPhotoUrl != null ? NetworkImage(drive.userPhotoUrl!) : null,
                    child: drive.userPhotoUrl == null
                        ? const Icon(Icons.person_rounded, color: Color(0xFFFF6F00), size: 26)
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          drive.isSignedIn ? (drive.userDisplayName ?? 'Google User') : 'Local Vault',
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (drive.isSignedIn) ...[
                              const Icon(Icons.cloud_done_rounded, color: Colors.green, size: 14),
                              const SizedBox(width: 4),
                            ],
                            Expanded(
                              child: Text(
                                drive.isSignedIn
                                    ? (drive.userEmail ?? 'Google Drive Linked')
                                    : 'Link Google Drive to auto-backup',
                                style: TextStyle(
                                  color: drive.isSignedIn ? const Color(0xFF475569) : const Color(0xFF94A3B8),
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (drive.isSignedIn)
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        side: const BorderSide(color: Color(0xFFEF4444)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                      onPressed: () async {
                        await drive.signOut();
                        setState(() {});
                      },
                      child: const Text('Logout', style: TextStyle(color: Color(0xFFEF4444), fontSize: 12, fontWeight: FontWeight.bold)),
                    )
                  else
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add_to_drive_rounded, size: 15),
                      label: const Text('Link Drive', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: const Color(0xFFFF6F00),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      onPressed: () async {
                        final ok = await drive.signIn();
                        if (!ok && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(drive.lastError != null
                                  ? 'Google Sign-In: ${drive.lastError}'
                                  : 'Google Sign-In cancelled.'),
                            ),
                          );
                        }
                        setState(() {});
                      },
                    ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Security Section ──
            const Text(
              'SECURITY & ACCESS',
              style: TextStyle(color: Color(0xFFFF6F00), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2),
            ),
            const SizedBox(height: 10),

            _buildSettingTile(
              key: _biometricKey,
              icon: Icons.fingerprint_rounded,
              title: 'Biometric Unlock',
              subtitle: 'Unlock vault with fingerprint or face',
              trailing: Switch(
                value: _biometricEnabled,
                activeThumbColor: const Color(0xFFFF6F00),
                onChanged: _toggleBiometrics,
              ),
            ),

            _buildSettingTile(
              key: _changePasswordKey,
              icon: Icons.lock_outline_rounded,
              title: 'Change Master Password',
              subtitle: 'Update your main vault password',
              onTap: _showChangePasswordDialog,
            ),

            _buildSettingTile(
              key: _recoveryKeyTileKey,
              icon: Icons.key_rounded,
              title: 'View Recovery Key',
              subtitle: '16-character backup key for emergency reset',
              onTap: _viewOrRegenerateRecoveryKey,
            ),

            const SizedBox(height: 24),

            // ── Keyboard & Autofill Section ──
            const Text(
              'KEYBOARD & AUTOFILL',
              style: TextStyle(color: Color(0xFFFF6F00), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2),
            ),
            const SizedBox(height: 10),

            _buildSettingTile(
              key: _autofillKey,
              icon: Icons.keyboard_rounded,
              title: 'Keyboard Payment Autofill',
              subtitle: 'Show card nicknames above keyboard to fill card, expiry, or CVV',
              trailing: FutureBuilder<bool>(
                future: AutofillBridgeService.isAutofillEnabled(),
                builder: (context, snapshot) {
                  final isEnabled = snapshot.data ?? false;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isEnabled ? Colors.green.shade50 : const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isEnabled ? Colors.green.shade300 : const Color(0xFFFFB74D),
                      ),
                    ),
                    child: Text(
                      isEnabled ? 'Active' : 'Configure',
                      style: TextStyle(
                        color: isEnabled ? Colors.green.shade700 : const Color(0xFFFF6F00),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                },
              ),
              onTap: () async {
                final opened = await AutofillBridgeService.openAutofillSettings();
                if (!opened && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please select CardVault in Android Settings → Passwords & Autofill.'),
                    ),
                  );
                }
              },
            ),

            _buildSettingTile(
              icon: Icons.laptop_windows_rounded,
              title: 'Browser Extension (Windows)',
              subtitle: 'Autofill cards, accounts, IFSC & passwords in Chrome/Edge',
              trailing: Consumer<ExtensionAuthService>(
                builder: (context, auth, _) {
                  final active = auth.isAuthorized;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: active ? Colors.green.shade50 : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: active ? Colors.green.shade300 : const Color(0xFFCBD5E1),
                      ),
                    ),
                    child: Text(
                      active ? 'Authorized' : 'Pair',
                      style: TextStyle(
                        color: active ? Colors.green.shade700 : const Color(0xFF64748B),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                },
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BrowserExtensionScreen()),
                );
              },
            ),

            const SizedBox(height: 24),

            // ── Local File Backup Section ──
            const Text(
              'OFFLINE / LOCAL BACKUP',
              style: TextStyle(color: Color(0xFFFF6F00), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2),
            ),
            const SizedBox(height: 10),

            _buildSettingTile(
              key: _exportKey,
              icon: Icons.file_upload_outlined,
              title: 'Export Backup to File',
              subtitle: 'Share encrypted vault text to file or messaging',
              onTap: _exportBackupFile,
            ),

            _buildSettingTile(
              key: _importKey,
              icon: Icons.file_download_outlined,
              title: 'Import Backup from File',
              subtitle: 'Restore from exported encrypted backup code',
              onTap: _importBackupFile,
            ),

            const SizedBox(height: 24),

            // ── App Tour & Guide ──
            const Text(
              'HELP & APP TOUR',
              style: TextStyle(color: Color(0xFFFF6F00), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2),
            ),
            const SizedBox(height: 10),

            _buildSettingTile(
              icon: Icons.touch_app_rounded,
              title: 'Settings Pointer Tour',
              subtitle: 'Points directly to buttons on this screen & explains each setting',
              onTap: _startSettingsSpotlightTour,
            ),

            _buildSettingTile(
              icon: Icons.home_outlined,
              title: 'Dashboard Pointer Tour',
              subtitle: 'Return to dashboard and point to vault buttons',
              onTap: () async {
                final sec = context.read<VaultSecurityService>();
                await sec.setTourSeen(false);
                if (mounted) Navigator.pop(context); // Returns to Home, which immediately triggers the pointer tour!
              },
            ),

            _buildSettingTile(
              icon: Icons.menu_book_rounded,
              title: 'Feature Overview Guide',
              subtitle: '7-chapter illustrated guide covering cards, banks, autofill & security',
              onTap: () => AppTourDialog.show(context),
            ),

            const SizedBox(height: 24),

            // ── Session ──
            const Text(
              'SESSION',
              style: TextStyle(color: Color(0xFFFF6F00), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2),
            ),
            const SizedBox(height: 10),

            _buildSettingTile(
              key: _lockNowKey,
              icon: Icons.lock_clock_rounded,
              title: 'Lock Vault Now',
              subtitle: 'Return immediately to Master Password screen',
              iconColor: Colors.amber.shade800,
              onTap: () {
                AutofillBridgeService.syncVaultState(isUnlocked: false);
                Navigator.of(context).pushNamedAndRemoveUntil('/unlock', (route) => false);
              },
            ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingTile({
    Key? key,
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    Color? iconColor,
  }) {
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (iconColor ?? const Color(0xFFFF6F00)).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor ?? const Color(0xFFFF6F00), size: 22),
        ),
        title: Text(title, style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(subtitle, style: const TextStyle(color: Color(0xFF64748B), fontSize: 11)),
        trailing: trailing ?? (onTap != null ? const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFFCBD5E1), size: 14) : null),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
