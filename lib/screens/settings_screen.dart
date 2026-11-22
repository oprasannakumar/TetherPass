import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/bin_database_service.dart';
import '../services/autofill_bridge_service.dart';
import '../services/auto_lock_service.dart';
import '../services/clipboard_service.dart';
import '../services/database_service.dart';
import '../services/drive_service.dart';
import '../services/secure_backup_export_service.dart';
import '../services/vault_security_service.dart';
import '../widgets/duress_decoy_dialog.dart';
import '../theme/cyber_theme.dart';
import 'browser_extension_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  bool _biometricEnabled = true;
  bool _duressEnabled = false;
  bool _isAutofillEnabled = false;
  int _autoLockSeconds = 60;
  int _clipboardPurgeSeconds = 30;

  // GlobalKeys for pointing directly to each setting in the spotlight tour
  final GlobalKey _accountKey = GlobalKey();
  final GlobalKey _biometricKey = GlobalKey();
  final GlobalKey _changePasswordKey = GlobalKey();
  final GlobalKey _recoveryKeyTileKey = GlobalKey();
  final GlobalKey _autofillKey = GlobalKey();
  final GlobalKey _exportKey = GlobalKey();
  final GlobalKey _importKey = GlobalKey();
  final GlobalKey _lockNowKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
    _checkAutofillStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAutofillStatus();
    }
  }

  Future<void> _checkAutofillStatus() async {
    final enabled = await AutofillBridgeService.isAutofillEnabled();
    if (mounted) {
      setState(() => _isAutofillEnabled = enabled);
    }
  }

  Future<void> _loadSettings() async {
    final sec = context.read<VaultSecurityService>();
    final bio = await sec.isBiometricEnabled();
    final duress = await sec.isDuressEnabled();
    final lockSec = await AutoLockService.getAutoLockSeconds();
    final purgeSec = await ClipboardService.getPurgeSeconds();
    if (mounted) {
      setState(() {
        _biometricEnabled = bio;
        _duressEnabled = duress;
        _autoLockSeconds = lockSec;
        _clipboardPurgeSeconds = purgeSec;
      });
    }

    // Refresh Google Drive sign-in state silently on opening settings
    if (mounted) {
      final drive = context.read<DriveService>();
      if (!drive.isSignedIn) {
        await drive.trySilentSignIn();
      }
    }
  }

  String _getAutoLockLabel(int sec) {
    if (sec == 0) return 'Immediately upon exiting';
    if (sec == 30) return 'After 30 seconds';
    if (sec == 60) return 'After 1 minute (Recommended)';
    if (sec == 300) return 'After 5 minutes';
    if (sec == 900) return 'After 15 minutes';
    if (sec < 0) return 'Never (Stay unlocked)';
    return 'After $sec seconds';
  }

  String _getClipboardPurgeLabel(int sec) {
    if (sec == 15) return 'After 15 seconds';
    if (sec == 30) return 'After 30 seconds (Recommended)';
    if (sec == 60) return 'After 1 minute';
    if (sec < 0) return 'Never (Disabled)';
    return 'After $sec seconds';
  }

  InputDecoration _cyberInputDecoration({
    required String labelText,
    String? hintText,
    String? errorText,
    Widget? prefixIcon,
    Widget? suffixIcon,
    String? helperText,
  }) {
    return InputDecoration(
      labelText: labelText,
      labelStyle: CyberTypography.mono(color: CyberColors.laserCyan, fontSize: 12),
      hintText: hintText,
      hintStyle: CyberTypography.mono(color: CyberColors.textDim, fontSize: 11),
      errorText: errorText,
      errorStyle: CyberTypography.mono(color: CyberColors.crimsonAlert, fontSize: 10),
      helperText: helperText,
      helperStyle: CyberTypography.mono(color: CyberColors.electricMint, fontSize: 10),
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: CyberColors.elevatedSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: CyberColors.glassBorderMuted),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: CyberColors.glassBorderMuted),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: CyberColors.laserCyan, width: 1.4),
      ),
    );
  }

  Future<void> _showAutoLockDialog() async {
    final options = <int, String>{
      0: 'Immediately upon switching apps',
      30: 'After 30 seconds',
      60: 'After 1 minute (Recommended)',
      300: 'After 5 minutes',
      900: 'After 15 minutes',
      -1: 'Never (Stay unlocked)',
    };

    final selected = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: CyberColors.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: CyberColors.laserCyan, width: 1.2),
        ),
        title: Row(
          children: [
            const Icon(Icons.timer_outlined, color: CyberColors.laserCyan, size: 22),
            const SizedBox(width: 10),
            Text(
              'AUTO-LOCK VAULT',
              style: CyberTypography.hudTitle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.entries.map((e) {
            final isSelected = _autoLockSeconds == e.key;
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                color: isSelected ? CyberColors.elevatedSurface : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: isSelected ? Border.all(color: CyberColors.laserCyan.withValues(alpha: 0.4)) : null,
              ),
              child: RadioListTile<int>(
                value: e.key,
                groupValue: _autoLockSeconds,
                activeColor: CyberColors.laserCyan,
                title: Text(
                  e.value,
                  style: CyberTypography.body(
                    color: isSelected ? CyberColors.laserCyan : Colors.white,
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
                onChanged: (val) => Navigator.pop(ctx, val),
              ),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('CANCEL', style: CyberTypography.mono(color: CyberColors.textMuted, fontSize: 12)),
          ),
        ],
      ),
    );

    if (selected != null) {
      await AutoLockService.setAutoLockSeconds(selected);
      setState(() => _autoLockSeconds = selected);
    }
  }

  Future<void> _showClipboardPurgeDialog() async {
    final options = <int, String>{
      15: 'After 15 seconds',
      30: 'After 30 seconds (Recommended)',
      60: 'After 1 minute',
      -1: 'Disabled (Do not clear)',
    };

    final selected = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: CyberColors.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: CyberColors.laserCyan, width: 1.2),
        ),
        title: Row(
          children: [
            const Icon(Icons.content_paste_go_rounded, color: CyberColors.laserCyan, size: 22),
            const SizedBox(width: 10),
            Text(
              'AUTO-CLEAR CLIPBOARD',
              style: CyberTypography.hudTitle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.entries.map((e) {
            final isSelected = _clipboardPurgeSeconds == e.key;
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                color: isSelected ? CyberColors.elevatedSurface : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: isSelected ? Border.all(color: CyberColors.laserCyan.withValues(alpha: 0.4)) : null,
              ),
              child: RadioListTile<int>(
                value: e.key,
                groupValue: _clipboardPurgeSeconds,
                activeColor: CyberColors.laserCyan,
                title: Text(
                  e.value,
                  style: CyberTypography.body(
                    color: isSelected ? CyberColors.laserCyan : Colors.white,
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
                onChanged: (val) => Navigator.pop(ctx, val),
              ),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('CANCEL', style: CyberTypography.mono(color: CyberColors.textMuted, fontSize: 12)),
          ),
        ],
      ),
    );

    if (selected != null) {
      await ClipboardService.setPurgeSeconds(selected);
      setState(() => _clipboardPurgeSeconds = selected);
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
            backgroundColor: CyberColors.cardSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: CyberColors.laserCyan, width: 1.2),
            ),
            title: Row(
              children: [
                const Icon(Icons.password_rounded, color: CyberColors.laserCyan, size: 20),
                const SizedBox(width: 8),
                Text(
                  'CHANGE MASTER PASSWORD',
                  style: CyberTypography.hudTitle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: oldCtrl,
                    obscureText: true,
                    style: CyberTypography.body(color: Colors.white),
                    decoration: _cyberInputDecoration(
                      labelText: 'Current Master Password',
                      hintText: 'Enter current password',
                      prefixIcon: const Icon(Icons.lock_outline_rounded, color: CyberColors.laserCyan, size: 18),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: newCtrl,
                    obscureText: true,
                    style: CyberTypography.body(color: Colors.white),
                    decoration: _cyberInputDecoration(
                      labelText: 'New Master Password (min 4 chars)',
                      hintText: 'Enter new password',
                      prefixIcon: const Icon(Icons.lock_rounded, color: CyberColors.laserCyan, size: 18),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmCtrl,
                    obscureText: true,
                    style: CyberTypography.body(color: Colors.white),
                    decoration: _cyberInputDecoration(
                      labelText: 'Confirm New Password',
                      hintText: 'Re-enter new password',
                      prefixIcon: const Icon(Icons.check_circle_outline_rounded, color: CyberColors.laserCyan, size: 18),
                    ),
                  ),
                  if (err != null) ...[
                    const SizedBox(height: 10),
                    Text(err!, style: CyberTypography.mono(color: CyberColors.crimsonAlert, fontSize: 11, fontWeight: FontWeight.w600)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                child: Text('CANCEL', style: CyberTypography.mono(color: CyberColors.textMuted, fontSize: 12)),
                onPressed: () => Navigator.pop(ctx),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: CyberColors.laserCyan,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text('SAVE', style: CyberTypography.mono(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
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
                    SnackBar(
                      content: Text('✓ Master Password updated successfully!'),
                      backgroundColor: CyberColors.cardSurface,
                    ),
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
            backgroundColor: CyberColors.cardSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: CyberColors.laserCyan, width: 1.2),
            ),
            title: Row(
              children: [
                const Icon(Icons.key_rounded, color: CyberColors.laserCyan, size: 20),
                const SizedBox(width: 8),
                Text(
                  'EMERGENCY RECOVERY KEY',
                  style: CyberTypography.hudTitle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Keep this 16-character key safe. If you forget your Master Password, this sovereign key lets you reset your vault.',
                  style: CyberTypography.body(color: CyberColors.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                  decoration: BoxDecoration(
                    color: CyberColors.elevatedSurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: CyberColors.laserCyan.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            currentKey,
                            style: CyberTypography.mono(
                              color: CyberColors.laserCyan,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.copy_rounded, color: CyberColors.laserCyan, size: 20),
                        tooltip: 'Copy Recovery Key',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: currentKey));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Recovery Key copied to clipboard!'),
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
            actions: [
              TextButton(
                child: Text('CLOSE', style: CyberTypography.mono(color: CyberColors.textMuted, fontSize: 12)),
                onPressed: () => Navigator.pop(ctx),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: CyberColors.plasmaAmber,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text('REGENERATE KEY', style: CyberTypography.mono(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11)),
                onPressed: () async {
                  final newK = await sec.regenerateRecoveryKey();
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(
                      content: Text('New Recovery Key generated: $newK'),
                      backgroundColor: CyberColors.cardSurface,
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showDuressPasswordDialog() async {
    await showDuressDecoySetupDialog(context, onStateChanged: () {
      _loadSettings();
      if (mounted) setState(() {});
    });
  }

  Future<void> _showSettingsSearchDialog() async {
    final searchCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: CyberColors.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: CyberColors.laserCyan, width: 1.2),
        ),
        title: Row(
          children: [
            const Icon(Icons.search_rounded, color: CyberColors.laserCyan, size: 20),
            const SizedBox(width: 8),
            Text(
              'SEARCH SETTINGS',
              style: CyberTypography.hudTitle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
        content: TextField(
          controller: searchCtrl,
          autofocus: true,
          style: CyberTypography.body(color: Colors.white),
          decoration: _cyberInputDecoration(
            labelText: 'Search Settings',
            hintText: 'Search or type decoy trigger...',
            prefixIcon: const Icon(Icons.search_rounded, color: CyberColors.laserCyan, size: 18),
          ),
          onChanged: (val) async {
            final sec = context.read<VaultSecurityService>();
            if (await sec.isDecoyTriggerMatch(val)) {
              Navigator.pop(ctx);
              HapticFeedback.heavyImpact();
              VaultSecurityService.isDecoySetupRevealed = true;
              if (mounted) {
                setState(() {});
                await _showDuressPasswordDialog();
              }
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('CLOSE', style: CyberTypography.mono(color: CyberColors.textMuted, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Future<void> _showBinDatabaseDialog() async {
    final stats = await BinDatabaseService.getStats();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: CyberColors.cardSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: CyberColors.laserCyan, width: 1.2),
      ),
      builder: (ctx) {
        bool syncing = false;
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final bundledFmt = NumberFormat.decimalPattern().format(stats['bundled'] ?? 458044);
            final customCount = stats['custom'] ?? 0;

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: CyberColors.laserCyan.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: CyberColors.laserCyan.withValues(alpha: 0.3)),
                          ),
                          child: const Icon(Icons.credit_card_rounded, color: CyberColors.laserCyan, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'CARD BIN REGISTRY',
                                style: CyberTypography.hudTitle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                'Offline Detection & Autonomous Learning',
                                style: CyberTypography.mono(color: CyberColors.textMuted, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: CyberColors.textMuted),
                          onPressed: () => Navigator.pop(modalCtx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'TetherPass includes $bundledFmt pre-packaged offline card issuer prefixes. Whenever you add or customize a card, TetherPass learns the prefix locally on your device for permanent zero-latency recognition.',
                      style: CyberTypography.body(color: CyberColors.textMuted, fontSize: 12.5),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: CyberColors.elevatedSurface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: CyberColors.glassBorderMuted),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                Text(
                                  bundledFmt,
                                  style: CyberTypography.hudTitle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                Text('Bundled Offline', style: CyberTypography.mono(color: CyberColors.textMuted, fontSize: 10)),
                              ],
                            ),
                          ),
                          Container(width: 1, height: 32, color: CyberColors.glassBorderMuted),
                          Expanded(
                            child: Column(
                              children: [
                                Text(
                                  '$customCount',
                                  style: CyberTypography.hudTitle(color: CyberColors.laserCyan, fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                Text('Learned / Synced', style: CyberTypography.mono(color: CyberColors.laserCyan, fontSize: 10)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: CyberColors.laserCyan,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: syncing
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                            : const Icon(Icons.cloud_sync_rounded, size: 20, color: Colors.black),
                        label: Text(
                          syncing ? 'CHECKING UPDATES...' : 'CHECK COMMUNITY UPDATES (OTA)',
                          style: CyberTypography.mono(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black),
                        ),
                        onPressed: syncing
                            ? null
                            : () async {
                                setModalState(() => syncing = true);
                                final count = await BinDatabaseService.syncOnlineDeltas();
                                final updatedStats = await BinDatabaseService.getStats();
                                setModalState(() {
                                  syncing = false;
                                  stats['bundled'] = updatedStats['bundled'] ?? 458044;
                                  stats['custom'] = updatedStats['custom'] ?? 0;
                                });
                                if (!modalCtx.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      count >= 0
                                          ? 'Sync complete! $count new card ranges updated.'
                                          : 'Unable to reach community repository. Offline database is active.',
                                    ),
                                    backgroundColor: count >= 0 ? CyberColors.cardSurface : CyberColors.cardSurface,
                                  ),
                                );
                              },
                      ),
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: TextButton.icon(
                        icon: const Icon(Icons.open_in_new_rounded, size: 14, color: CyberColors.laserCyan),
                        label: Text(
                          'Contribute unlisted card prefix on GitHub',
                          style: CyberTypography.mono(color: CyberColors.laserCyan, fontSize: 11),
                        ),
                        onPressed: () {
                          final url = BinDatabaseService.buildContributeUrl(binPrefix: '', bankName: '');
                          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
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
          backgroundColor: CyberColors.cardSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: CyberColors.laserCyan, width: 1.2),
          ),
          title: Row(
            children: [
              const Icon(Icons.cloud_upload_outlined, color: CyberColors.laserCyan, size: 22),
              const SizedBox(width: 8),
              Text(
                'MULTI-CLOUD & FILE EXPORT',
                style: CyberTypography.hudTitle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your vault will be encrypted with AES-256 PBKDF2 using your Master Password. You can upload to OneDrive, Dropbox, Google Drive, or save to Downloads.',
                style: CyberTypography.body(color: CyberColors.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordCtrl,
                obscureText: true,
                style: CyberTypography.body(color: Colors.white),
                decoration: _cyberInputDecoration(
                  labelText: 'Encryption Master Password',
                  hintText: 'Enter your Master Password',
                  errorText: errorText,
                  helperText: masterPwd != null ? 'Using configured Master Password' : null,
                  prefixIcon: const Icon(Icons.key_rounded, color: CyberColors.laserCyan, size: 18),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              child: Text('CANCEL', style: CyberTypography.mono(color: CyberColors.textMuted, fontSize: 12)),
              onPressed: () => Navigator.pop(ctx),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: CyberColors.laserCyan),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.share_rounded, size: 16, color: CyberColors.laserCyan),
              label: Text('SHARE', style: CyberTypography.mono(color: CyberColors.laserCyan, fontWeight: FontWeight.bold, fontSize: 11)),
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
                        const SnackBar(content: Text('Your vault is empty. Nothing to export.'), backgroundColor: CyberColors.cardSurface),
                      );
                    }
                    return;
                  }

                  final recKey = await sec.getRecoveryKey();
                  final encryptedPayload = SecureBackupExportService.exportVaultWithPassword(
                    items: items,
                    userPassword: pwd,
                    recoveryKey: recKey,
                  );

                  final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
                  final fileName = 'TetherPass_Backup_$timestamp.json';

                  final tempDir = await getTemporaryDirectory();
                  final tempFile = File('${tempDir.path}/$fileName');
                  await tempFile.writeAsString(encryptedPayload, flush: true);

                  await Share.shareXFiles(
                    [XFile(tempFile.path)],
                    text: 'TetherPass Encrypted Vault Backup (AES-256)',
                    subject: 'TetherPass Vault Backup',
                  );
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Cloud share error: $e'), backgroundColor: CyberColors.crimsonAlert),
                    );
                  }
                }
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: CyberColors.laserCyan,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text('SAVE TO DOWNLOADS', style: CyberTypography.mono(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11)),
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
                        const SnackBar(content: Text('Your vault is empty. Nothing to export.'), backgroundColor: CyberColors.cardSurface),
                      );
                    }
                    return;
                  }

                  final recKey = await sec.getRecoveryKey();
                  final encryptedPayload = SecureBackupExportService.exportVaultWithPassword(
                    items: items,
                    userPassword: pwd,
                    recoveryKey: recKey,
                  );

                  final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
                  final fileName = 'TetherPass_Backup_$timestamp.json';

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
                        backgroundColor: CyberColors.cardSurface,
                        content: Row(
                          children: [
                            const Icon(Icons.check_circle_rounded, color: CyberColors.electricMint),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '✓ Backup saved:\n${savedFile.path}',
                                style: CyberTypography.mono(color: Colors.white, fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                        action: SnackBarAction(
                          label: 'Share',
                          textColor: CyberColors.laserCyan,
                          onPressed: () {
                            Share.shareXFiles([XFile(savedFile!.path)], text: 'TetherPass Encrypted Vault Backup');
                          },
                        ),
                        duration: const Duration(seconds: 6),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Export failed: $e'), backgroundColor: CyberColors.crimsonAlert),
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

      final sec = context.read<VaultSecurityService>();
      final db = context.read<DatabaseService>();
      final masterPwd = await sec.getMasterPassword();

      if (masterPwd != null && masterPwd.isNotEmpty) {
        try {
          final items = SecureBackupExportService.importVaultWithPassword(
            backupPayload: fileContent,
            userPassword: masterPwd,
          );

          if (!mounted) return;
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: CyberColors.cardSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: CyberColors.laserCyan, width: 1.2),
              ),
              title: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: CyberColors.electricMint),
                  const SizedBox(width: 8),
                  Text('RESTORE BACKUP?', style: CyberTypography.hudTitle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                ],
              ),
              content: Text(
                'Decrypted $fileName successfully with Master Password!\n\nFound ${items.length} credential(s) in this file. Would you like to restore them to your vault?',
                style: CyberTypography.body(color: CyberColors.textMuted, fontSize: 13),
              ),
              actions: [
                TextButton(
                  child: Text('CANCEL', style: CyberTypography.mono(color: CyberColors.textMuted, fontSize: 12)),
                  onPressed: () => Navigator.pop(ctx, false),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CyberColors.electricMint,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('RESTORE ${items.length} ITEMS', style: CyberTypography.mono(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11)),
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
                  content: Text('✓ Successfully restored ${items.length} vault items from $fileName!'),
                  backgroundColor: CyberColors.cardSurface,
                ),
              );
            }
          }
          return;
        } catch (_) {}
      }

      if (!mounted) return;
      final passwordCtrl = TextEditingController();
      String? errorText;
      bool isUsingRecoveryKey = false;

      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setDlgState) => AlertDialog(
            backgroundColor: CyberColors.cardSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: CyberColors.laserCyan, width: 1.2),
            ),
            title: Row(
              children: [
                const Icon(Icons.lock_open_rounded, color: CyberColors.laserCyan),
                const SizedBox(width: 8),
                Text('DECRYPT BACKUP FILE', style: CyberTypography.hudTitle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Selected: $fileName\n\n${isUsingRecoveryKey ? 'Enter your 16-character Emergency Recovery Key:' : 'Enter the Master Password used when this backup was created:'}',
                    style: CyberTypography.body(color: CyberColors.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordCtrl,
                    obscureText: !isUsingRecoveryKey,
                    style: CyberTypography.body(color: Colors.white),
                    decoration: _cyberInputDecoration(
                      labelText: isUsingRecoveryKey ? 'Recovery Key' : 'Decryption Password',
                      hintText: isUsingRecoveryKey ? 'XXXX-XXXX-XXXX-XXXX' : 'Enter Master Password',
                      errorText: errorText,
                      prefixIcon: Icon(isUsingRecoveryKey ? Icons.vpn_key_rounded : Icons.key_rounded, color: CyberColors.laserCyan, size: 18),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      child: Text(
                        isUsingRecoveryKey ? 'Use Master Password instead' : 'Forgot Password? Use 16-char Recovery Key',
                        style: CyberTypography.mono(color: CyberColors.laserCyan, fontSize: 11, fontWeight: FontWeight.w600),
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
                child: Text('CANCEL', style: CyberTypography.mono(color: CyberColors.textMuted, fontSize: 12)),
                onPressed: () => Navigator.pop(ctx),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: CyberColors.laserCyan,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text('DECRYPT & RESTORE', style: CyberTypography.mono(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11)),
                onPressed: () async {
                  final pwd = passwordCtrl.text.trim();
                  if (pwd.isEmpty) {
                    setDlgState(() => errorText = isUsingRecoveryKey ? 'Please enter recovery key' : 'Please enter password');
                    return;
                  }

                  try {
                    int restoredCount = 0;
                    if (fileContent.contains('TETHERPASS_SECURE_BACKUP') || fileContent.contains('CARDVAULT_SECURE_BACKUP')) {
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

                    if (context.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('✓ Successfully restored $restoredCount vault items from $fileName!'),
                          backgroundColor: CyberColors.cardSurface,
                        ),
                      );
                    }
                  } on FormatException catch (fe) {
                    setDlgState(() => errorText = fe.message);
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
          SnackBar(content: Text('File import error: $e'), backgroundColor: CyberColors.crimsonAlert),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final drive = context.watch<DriveService>();

    return Scaffold(
      backgroundColor: CyberColors.obsidianBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: CyberColors.laserCyan),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'SETTINGS & SECURITY',
          style: CyberTypography.hudTitle(
            color: CyberColors.textWhite,
            fontWeight: FontWeight.w800,
            fontSize: 16,
            letterSpacing: 1.2,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded, color: CyberColors.laserCyan),
            tooltip: 'Search Settings',
            onPressed: _showSettingsSearchDialog,
          ),
        ],
      ),
      body: CyberBackground(
        showGrid: true,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Merged Profile & Google Account Linking Card ──
              CyberGlassCard(
                key: _accountKey,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                borderRadius: 16,
                borderColor: CyberColors.glassBorder,
                showCornerBrackets: true,
                child: Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: CyberColors.laserCyan.withValues(alpha: 0.5), width: 1.4),
                        boxShadow: [
                          BoxShadow(color: CyberColors.laserCyan.withValues(alpha: 0.25), blurRadius: 8),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 24,
                        backgroundColor: CyberColors.cardSurface,
                        backgroundImage: drive.userPhotoUrl != null ? NetworkImage(drive.userPhotoUrl!) : null,
                        child: drive.userPhotoUrl == null
                            ? const Icon(Icons.person_rounded, color: CyberColors.laserCyan, size: 26)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            drive.isSignedIn ? (drive.userDisplayName ?? 'Google Operator') : 'Local Hardware Vault',
                            style: CyberTypography.hudTitle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              if (drive.isSignedIn) ...[
                                const Icon(Icons.cloud_done_rounded, color: CyberColors.electricMint, size: 14),
                                const SizedBox(width: 4),
                              ],
                              Expanded(
                                child: Text(
                                  drive.isSignedIn
                                      ? (drive.userEmail ?? 'Google Drive Cloud E2EE Linked')
                                      : 'Link Google Drive for Zero-Knowledge Backup',
                                  style: CyberTypography.mono(
                                    color: drive.isSignedIn ? CyberColors.electricMint : CyberColors.textMuted,
                                    fontSize: 10.5,
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
                          side: const BorderSide(color: CyberColors.crimsonAlert),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        ),
                        onPressed: () async {
                          await drive.signOut();
                          setState(() {});
                        },
                        child: Text(
                          'UNLINK',
                          style: CyberTypography.mono(
                            color: CyberColors.crimsonAlert,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    else
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add_to_drive_rounded, size: 15, color: Colors.black),
                        label: Text(
                          'LINK DRIVE',
                          style: CyberTypography.mono(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          backgroundColor: CyberColors.laserCyan,
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
                                backgroundColor: CyberColors.cardSurface,
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
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: CyberColors.laserCyan),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'SECURITY & ACCESS PROTOCOLS',
                    style: CyberTypography.mono(
                      color: CyberColors.laserCyan,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
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

            if (VaultSecurityService.isDecoySetupRevealed)
              _buildSettingTile(
                icon: Icons.shield_outlined,
                title: 'Duress Decoy Vault',
                subtitle: _duressEnabled
                    ? 'Active (Alternate PIN opens harmless decoy vault)'
                    : 'Disabled (Tap to set emergency decoy PIN)',
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: _duressEnabled ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _duressEnabled ? 'Active' : 'Configure',
                    style: TextStyle(
                      color: _duressEnabled ? const Color(0xFF15803D) : const Color(0xFF64748B),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                onTap: _showDuressPasswordDialog,
              ),

            _buildSettingTile(
              icon: Icons.timer_outlined,
              title: 'Auto-Lock Vault',
              subtitle: _getAutoLockLabel(_autoLockSeconds),
              onTap: _showAutoLockDialog,
            ),

            _buildSettingTile(
              icon: Icons.content_paste_go_rounded,
              title: 'Clipboard Auto-Clear',
              subtitle: _getClipboardPurgeLabel(_clipboardPurgeSeconds),
              onTap: _showClipboardPurgeDialog,
            ),

            const SizedBox(height: 24),

            // ── Keyboard & Autofill Section ──
            Text(
              'KEYBOARD & AUTOFILL',
              style: CyberTypography.mono(color: CyberColors.laserCyan, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2),
            ),
            const SizedBox(height: 10),

            _buildSettingTile(
              key: _autofillKey,
              icon: Icons.keyboard_rounded,
              title: 'Keyboard Payment Autofill',
              subtitle: 'Show card nicknames above keyboard to fill card, expiry, or CVV',
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _isAutofillEnabled ? CyberColors.electricMint.withValues(alpha: 0.15) : CyberColors.elevatedSurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _isAutofillEnabled ? CyberColors.electricMint : CyberColors.glassBorderMuted,
                  ),
                ),
                child: Text(
                  _isAutofillEnabled ? 'Active' : 'Configure',
                  style: CyberTypography.mono(
                    color: _isAutofillEnabled ? CyberColors.electricMint : CyberColors.laserCyan,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              onTap: () async {
                final opened = await AutofillBridgeService.openAutofillSettings();
                if (!opened && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please select TetherPass in Android Settings → Passwords & Autofill.'),
                    ),
                  );
                }
                _checkAutofillStatus();
              },
            ),

            _buildSettingTile(
              icon: Icons.laptop_windows_rounded,
              title: 'Browser Extension (Windows)',
              subtitle: 'Autofill cards, accounts, IFSC & passwords in Chrome/Edge',
              trailing: const Icon(Icons.chevron_right_rounded, color: CyberColors.laserCyan),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BrowserExtensionScreen()),
                );
              },
            ),

            const SizedBox(height: 24),

            // ── Card Intelligence & Offline BIN Registry ──
            Text(
              'CARD INTELLIGENCE & OFFLINE REGISTRY',
              style: CyberTypography.mono(color: CyberColors.laserCyan, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2),
            ),
            const SizedBox(height: 10),

            _buildSettingTile(
              icon: Icons.credit_card_rounded,
              title: 'Global Card BIN Database',
              subtitle: '458,000+ offline card ranges • Self-learning & OTA updates',
              trailing: const Icon(Icons.sync_rounded, size: 20, color: CyberColors.laserCyan),
              onTap: _showBinDatabaseDialog,
            ),

            const SizedBox(height: 24),

            // ── Multi-Cloud & Offline Backup Section ──
            Text(
              'MULTI-CLOUD & OFFLINE BACKUP',
              style: CyberTypography.mono(color: CyberColors.laserCyan, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2),
            ),
            const SizedBox(height: 10),

            _buildSettingTile(
              key: _exportKey,
              icon: Icons.cloud_upload_outlined,
              title: 'Export to Any Cloud / Storage',
              subtitle: 'Upload encrypted vault to OneDrive, Dropbox, Drive, or Downloads',
              trailing: const Icon(Icons.share_rounded, size: 18, color: CyberColors.laserCyan),
              onTap: _exportBackupFile,
            ),

            _buildSettingTile(
              key: _importKey,
              icon: Icons.cloud_download_outlined,
              title: 'Restore from Cloud or File',
              subtitle: 'Import backup from OneDrive, Dropbox, Drive, or Downloads',
              trailing: const Icon(Icons.folder_open_rounded, size: 18, color: CyberColors.laserCyan),
              onTap: _importBackupFile,
            ),

            const SizedBox(height: 24),

            // ── Session ──
            Text(
              'SESSION',
              style: CyberTypography.mono(color: CyberColors.laserCyan, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2),
            ),
            const SizedBox(height: 10),

            _buildSettingTile(
              key: _lockNowKey,
              icon: Icons.lock_clock_rounded,
              title: 'Lock Vault Now',
              subtitle: 'Return immediately to Master Password screen',
              iconColor: Colors.amber.shade800,
              onTap: () {
                AutoLockService.lockVault();
              },
            ),

            const SizedBox(height: 30),
          ],
        ),
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
    final effectiveColor = iconColor ?? CyberColors.laserCyan;

    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 10),
      child: CyberGlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        borderRadius: 16,
        borderColor: CyberColors.glassBorderMuted,
        onTap: onTap,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: effectiveColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: effectiveColor.withValues(alpha: 0.35), width: 1),
              boxShadow: [
                BoxShadow(color: effectiveColor.withValues(alpha: 0.2), blurRadius: 6),
              ],
            ),
            child: Icon(icon, color: effectiveColor, size: 20),
          ),
          title: Text(
            title,
            style: CyberTypography.hudTitle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
              letterSpacing: 0.6,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              subtitle,
              style: CyberTypography.mono(
                color: CyberColors.textMuted,
                fontSize: 10.5,
              ),
            ),
          ),
          trailing: trailing ?? (onTap != null ? const Icon(Icons.arrow_forward_ios_rounded, color: CyberColors.laserCyan, size: 14) : null),
        ),
      ),
    );
  }
}
