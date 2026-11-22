import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/vault_item.dart';
import '../services/auth_service.dart';
import '../services/autofill_bridge_service.dart';
import '../services/auto_lock_service.dart';
import '../services/database_service.dart';
import '../services/device_identity_service.dart';
import '../services/drive_service.dart';
import '../services/vault_security_service.dart';
import '../widgets/duress_decoy_dialog.dart';
import '../widgets/tether_sync_dialog.dart';
import '../theme/cyber_theme.dart';
import 'add_edit_screen.dart';
import 'item_detail_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<VaultItem> _items = [];
  bool _isLoading = true;
  bool _isSyncing = false;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();
  int _selectedFilter = 0; // 0 = All, 1 = Credit, 2 = Debit, 3 = Bank

  // GlobalKeys for home screen elements
  final GlobalKey _profileKey = GlobalKey();
  final GlobalKey _driveSyncKey = GlobalKey();
  final GlobalKey _lockKey = GlobalKey();
  final GlobalKey _searchFilterKey = GlobalKey();
  final GlobalKey _fabKey = GlobalKey();

  Timer? _accessRequestPollTimer;
  bool _isShowingApprovalDialog = false;

  @override
  void initState() {
    super.initState();
    AutoLockService.markUnlocked();
    _loadItems();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final drive = context.read<DriveService>();
      if (!drive.isSignedIn) {
        await drive.trySilentSignIn();
      }
      _startApprovalPolling();

      final isRemoved = await drive.isCurrentDeviceRemoved();
      if (isRemoved && mounted) {
        await _executeRemoteWipe();
        return;
      }

      drive.registerDeviceOnDrive();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _accessRequestPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleSearchInput(String val) async {
    final sec = context.read<VaultSecurityService>();
    final isTrigger = await sec.isDecoyTriggerMatch(val);
    if (isTrigger) {
      _searchCtrl.clear();
      HapticFeedback.heavyImpact();
      setState(() {
        _searchQuery = '';
      });
      VaultSecurityService.isDecoySetupRevealed = true;
      if (mounted) {
        await showDuressDecoySetupDialog(context, onStateChanged: () {
          if (mounted) setState(() {});
        });
        if (mounted) setState(() {});
      }
      return;
    }
    setState(() => _searchQuery = val);
  }

  void _startApprovalPolling() {
    _accessRequestPollTimer?.cancel();
    _accessRequestPollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted || _isShowingApprovalDialog) return;
      final drive = context.read<DriveService>();
      if (!drive.isSignedIn) return;

      // Check if device was remotely removed from another device or extension
      final isRemoved = await drive.isCurrentDeviceRemoved();
      if (isRemoved && mounted) {
        await _executeRemoteWipe();
        return;
      }

      final req = await drive.checkForPendingAccessRequest();
      if (req != null && mounted && !_isShowingApprovalDialog) {
        _showDesktopApprovalDialog(req);
      }
    });
  }

  Future<void> _executeRemoteWipe() async {
    _accessRequestPollTimer?.cancel();
    if (!mounted) return;

    final db = context.read<DatabaseService>();
    final sec = context.read<VaultSecurityService>();
    final drive = context.read<DriveService>();

    await db.clearAllData();
    await sec.wipeAllData();
    await AutofillBridgeService.syncVaultState(isUnlocked: false, items: []);
    
    // Acknowledge wipe on Drive so device is not blocked if user chooses to sign back in
    await drive.acknowledgeAndClearDeviceWipe();
    await DeviceIdentityService.updateSessionRegistrationTime(DateTime.now().millisecondsSinceEpoch);
    await drive.signOut();

    if (mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
              SizedBox(width: 8),
              Text('Device Removed', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: const Text(
            'This mobile phone was removed from your TetherPass account. All credentials and local vault data on this device have been wiped clean.',
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                Navigator.of(ctx).pushNamedAndRemoveUntil('/onboarding', (route) => false);
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _showDesktopApprovalDialog(Map<String, dynamic> req) async {
    _isShowingApprovalDialog = true;
    final requestId = req['requestId'] as String? ?? '';
    final deviceName = req['device'] as String? ?? 'Windows PC';
    final drive = context.read<DriveService>();
    final auth = context.read<AuthService>();
    final sec = context.read<VaultSecurityService>();

    HapticFeedback.vibrate();

    // Multi-mobile sync check: dismiss if already approved by another device
    Timer? multiDeviceSyncTimer;

    final approved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        multiDeviceSyncTimer?.cancel();
        multiDeviceSyncTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) async {
          if (!mounted) return;
          final status = await drive.getAccessRequestStatus(requestId);
          if (status != null && status != 'PENDING' && ctx.mounted) {
            multiDeviceSyncTimer?.cancel();
            Navigator.of(ctx).pop(null); // Auto-dismiss
          }
        });

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.laptop_windows_rounded, color: Color(0xFFFF6F00), size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Desktop Authorization',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'A desktop computer is requesting access to decrypt your TetherPass credentials.',
                style: TextStyle(fontSize: 13, color: Color(0xFF475569), height: 1.4),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFFD8A8), width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.computer_rounded, size: 16, color: Color(0xFFFF6F00)),
                        SizedBox(width: 6),
                        Text(
                          'REQUESTING DEVICE:',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: Color(0xFFFF6F00),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      deviceName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.shield_outlined, size: 13, color: Color(0xFFD97706)),
                          SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'Verify this matches your browser screen',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF92400E)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'If you did not initiate this request, tap Deny to protect your account.',
                style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          actions: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Centered Horizontally: Approve with Biometrics
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6F00),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 2,
                  ),
                  onPressed: () {
                    multiDeviceSyncTimer?.cancel();
                    Navigator.of(ctx).pop(true);
                  },
                  icon: const Icon(Icons.fingerprint_rounded, size: 22),
                  label: const Text(
                    'Approve with Biometrics',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                const SizedBox(height: 8),
                // 2. Deny Button placed below Approve Button
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onPressed: () {
                    multiDeviceSyncTimer?.cancel();
                    Navigator.of(ctx).pop(false);
                  },
                  child: const Text(
                    'Deny',
                    style: TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );

    multiDeviceSyncTimer?.cancel();

    if (approved == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Desktop request was resolved by another linked device.'),
          backgroundColor: Color(0xFF475569),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    if (approved == true && mounted) {
      bool authenticated = false;
      final isBio = await sec.isBiometricEnabled();
      final canAuth = await auth.canAuthenticate();

      if (isBio && canAuth) {
        authenticated = await auth.authenticate(
          reason: 'Authorize TetherPass Browser Extension on Windows PC',
        );
      }

      if (!authenticated && mounted) {
        // Fallback to Master Password verification if biometric fails
        authenticated = await _promptPasswordVerification();
      }

      if (authenticated && mounted) {
        final sec = context.read<VaultSecurityService>();
        var masterPwd = await sec.getMasterPassword();
        if ((masterPwd == null || masterPwd.isEmpty) && mounted) {
          final verified = await _promptPasswordVerification();
          if (verified) {
            masterPwd = await sec.getMasterPassword();
          }
        }
        if (!mounted) return;
        await TetherSyncDialog.run<bool>(
          context: context,
          mode: TetherSyncMode.connecting,
          deviceName: deviceName,
          task: () => drive.respondToAccessRequest(
            requestId: requestId,
            approved: true,
            deviceName: deviceName,
            masterPassword: masterPwd,
          ),
        );
      } else if (mounted) {
        await drive.respondToAccessRequest(requestId: requestId, approved: false);
      }
    } else if (mounted) {
      await drive.respondToAccessRequest(requestId: requestId, approved: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Desktop access request denied.'),
            backgroundColor: Color(0xFF475569),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }

    _isShowingApprovalDialog = false;
  }

  Future<bool> _promptPasswordVerification() async {
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
              const Text('Enter Master Password to confirm desktop access.', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                obscureText: true,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Master Password',
                  errorText: errorText,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final valid = await sec.verifyMasterPassword(ctrl.text.trim());
                if (!ctx.mounted) return;
                if (valid) {
                  Navigator.of(ctx).pop(true);
                } else {
                  setDlgState(() => errorText = 'Incorrect Master Password');
                }
              },
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
    return result ?? false;
  }

  Future<void> _loadItems() async {
    setState(() => _isLoading = true);
    final db = context.read<DatabaseService>();
    final items = await db.getAllItems();
    if (mounted) {
      setState(() {
        _items = items;
        _isLoading = false;
      });
      // Synchronize cards with Android Autofill Service in RAM
      AutofillBridgeService.syncVaultState(isUnlocked: true, items: items);
    }
  }

  List<VaultItem> get _filteredItems {
    return _items.where((item) {
      if (_selectedFilter == 1 && (!item.isCard || !item.isCredit)) return false;
      if (_selectedFilter == 2 && (!item.isCard || !item.isDebit)) return false;
      if (_selectedFilter == 3 && !item.isNetBanking) return false;
      if (_selectedFilter == 4 && !item.isPassword) return false;

      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchNick = item.nickname.toLowerCase().contains(q);
        final matchBank = item.bankName.toLowerCase().contains(q);
        final matchHolder = item.cardHolder.toLowerCase().contains(q);
        final matchAcc = item.allAccounts.any((a) => a.accountNumber.toLowerCase().contains(q) || a.ifscCode.toLowerCase().contains(q));
        final matchUser = item.userId.toLowerCase().contains(q);
        final matchWeb = item.website.toLowerCase().contains(q);
        final matchType = item.isCard
            ? (item.isDebit ? 'debit' : 'credit')
            : (item.isPassword ? 'password' : 'bank');
        return matchNick || matchBank || matchHolder || matchAcc || matchUser || matchWeb || matchType.contains(q);
      }
      return true;
    }).toList();
  }

  // Groups items alphabetically by Bank Name
  Map<String, List<VaultItem>> get _groupedItems {
    final map = <String, List<VaultItem>>{};
    for (final item in _filteredItems) {
      final key = item.bankName.toUpperCase().trim();
      final groupKey = key.isEmpty ? 'OTHER' : key;
      map.putIfAbsent(groupKey, () => []).add(item);
    }

    final sortedKeys = map.keys.toList()..sort();
    final sortedMap = <String, List<VaultItem>>{};
    for (final k in sortedKeys) {
      sortedMap[k] = map[k]!;
    }
    return sortedMap;
  }

  void _lockVault() {
    AutoLockService.lockVault();
  }

  // ─── Google Drive Actions ───────────────────────────────────────────────────

  Future<void> _backupToGoogleDrive() async {
    final drive = context.read<DriveService>();
    if (!drive.isSignedIn) {
      final ok = await drive.signIn();
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(drive.lastError ?? 'Google Sign-In cancelled.')),
          );
        }
        return;
      }
    }

    // ANTI-DATA LOSS PROTECTION:
    // If local vault is empty, check if cloud backup exists and intercept accidental overwrite!
    if (_items.isEmpty) {
      final hasBackup = await drive.hasExistingBackup();
      if (hasBackup) {
        if (!mounted) return;
        final shouldRestore = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: CyberColors.cardSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: CyberColors.plasmaAmber, width: 1.2),
            ),
            title: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: CyberColors.plasmaAmber, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'EMPTY VAULT WARNING',
                    style: CyberTypography.hudTitle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ],
            ),
            content: Text(
              'Your phone currently has 0 saved items, but Google Drive already contains your saved vault backup!\n\n'
              'Backing up now would overwrite your cloud data. Did you mean to Restore your vault instead?',
              style: CyberTypography.body(color: CyberColors.textMuted, fontSize: 13),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('CANCEL', style: CyberTypography.mono(color: CyberColors.textMuted, fontSize: 12)),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.cloud_download_rounded, size: 16, color: Colors.black),
                label: Text('RESTORE FROM DRIVE', style: CyberTypography.mono(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: CyberColors.electricMint,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ],
          ),
        );
        if (shouldRestore == true) {
          await _restoreFromGoogleDrive();
        }
        return;
      }
    }

    setState(() => _isSyncing = true);
    try {
      await drive.backup();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ ${_items.length} items securely backed up to Google Drive!'),
            backgroundColor: const Color(0xFF1E293B),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _restoreFromGoogleDrive() async {
    final drive = context.read<DriveService>();
    if (!drive.isSignedIn) {
      final ok = await drive.signIn();
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(drive.lastError ?? 'Google Sign-In cancelled.')),
          );
        }
        return;
      }
    }

    setState(() => _isSyncing = true);
    try {
      final count = await drive.restore();
      await _loadItems();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Restored $count items from Google Drive!'),
            backgroundColor: Colors.green.shade800,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on MasterPasswordRequiredException catch (req) {
      if (mounted) {
        await _promptDriveMasterPassword(req.payload);
      }
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('master password') ||
          msg.contains('password') ||
          msg.contains('key mismatch') ||
          msg.contains('decryption failed')) {
        if (mounted) {
          final payload = await drive.downloadRawBackupPayload().catchError((_) => '');
          if (mounted) {
            await _promptDriveMasterPassword(payload);
          }
        }
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restore failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _promptDriveMasterPassword(String payload) async {
    final drive = context.read<DriveService>();
    final sec = context.read<VaultSecurityService>();
    final passwordCtrl = TextEditingController();
    String? errorText;
    bool isUsingRecoveryKey = false;

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: CyberColors.cardSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: CyberColors.laserCyan, width: 1.2),
          ),
          title: Row(
            children: [
              const Icon(Icons.cloud_download_rounded, color: CyberColors.laserCyan, size: 22),
              const SizedBox(width: 8),
              Text(
                'RESTORE CLOUD BACKUP',
                style: CyberTypography.hudTitle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
              ),
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
                      : 'Enter your Master Password to decrypt your cloud backup:',
                  style: CyberTypography.body(color: CyberColors.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordCtrl,
                  obscureText: !isUsingRecoveryKey,
                  style: CyberTypography.body(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: isUsingRecoveryKey ? 'Recovery Key' : 'Master Password',
                    labelStyle: CyberTypography.mono(color: CyberColors.laserCyan, fontSize: 12),
                    hintText: isUsingRecoveryKey ? 'XXXX-XXXX-XXXX-XXXX' : 'Enter backup password',
                    hintStyle: CyberTypography.mono(color: CyberColors.textDim, fontSize: 11),
                    errorText: errorText,
                    errorStyle: CyberTypography.mono(color: CyberColors.crimsonAlert, fontSize: 10),
                    prefixIcon: Icon(isUsingRecoveryKey ? Icons.vpn_key_rounded : Icons.key_rounded, color: CyberColors.laserCyan, size: 18),
                    filled: true,
                    fillColor: CyberColors.elevatedSurface,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: CyberColors.glassBorderMuted)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: CyberColors.glassBorderMuted)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: CyberColors.laserCyan, width: 1.4)),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    child: Text(
                      isUsingRecoveryKey ? 'Use Master Password instead' : 'Forgot password? Use Recovery Key',
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
              onPressed: () => Navigator.pop(dlgCtx),
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
                  final count = await drive.restore(masterPassword: pwd, rawPayload: payload.isNotEmpty ? payload : null);
                  try {
                    if (!isUsingRecoveryKey) {
                      await sec.saveMasterPassword(pwd);
                    }
                  } catch (_) {}
                  await _loadItems();
                  if (context.mounted) {
                    Navigator.pop(dlgCtx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('✓ Restored $count items from Google Drive!'),
                        backgroundColor: CyberColors.cardSurface,
                      ),
                    );
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

  void _showDriveMenu() {
    final drive = context.read<DriveService>();

    showModalBottomSheet(
      context: context,
      backgroundColor: CyberColors.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: CyberColors.laserCyan, width: 1.2),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(22),
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
                  child: const Icon(Icons.add_to_drive_rounded, color: CyberColors.laserCyan, size: 22),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'GOOGLE DRIVE CLOUD SYNC',
                      style: CyberTypography.hudTitle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      drive.isSignedIn
                          ? 'Connected as ${drive.userEmail}'
                          : 'Zero-Knowledge E2EE Google Drive Channel',
                      style: CyberTypography.mono(color: CyberColors.textMuted, fontSize: 10),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Backup Button
            ListTile(
              enabled: _items.isNotEmpty,
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _items.isEmpty
                      ? CyberColors.elevatedSurface
                      : CyberColors.laserCyan.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _items.isEmpty
                        ? CyberColors.glassBorderMuted
                        : CyberColors.laserCyan.withValues(alpha: 0.4),
                  ),
                ),
                child: Icon(
                  Icons.cloud_upload_rounded,
                  color: _items.isEmpty ? CyberColors.textDim : CyberColors.laserCyan,
                  size: 20,
                ),
              ),
              title: Text(
                'BACKUP TO GOOGLE DRIVE',
                style: CyberTypography.hudTitle(
                  color: _items.isEmpty ? CyberColors.textDim : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              subtitle: Text(
                _items.isEmpty ? 'Disabled: Vault is empty (Add items first)' : 'Upload encrypted backup (${_items.length} items)',
                style: CyberTypography.mono(
                  color: _items.isEmpty ? CyberColors.crimsonAlert : CyberColors.textMuted,
                  fontSize: 10.5,
                ),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: CyberColors.glassBorderMuted),
              ),
              tileColor: CyberColors.elevatedSurface,
              onTap: _items.isEmpty ? () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Cannot backup an empty vault. Did you mean to Restore?'),
                    backgroundColor: CyberColors.cardSurface,
                  ),
                );
              } : () {
                Navigator.pop(ctx);
                _backupToGoogleDrive();
              },
            ),
            const SizedBox(height: 10),

            // Restore Button
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: CyberColors.electricMint.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: CyberColors.electricMint.withValues(alpha: 0.4)),
                ),
                child: const Icon(Icons.cloud_download_rounded, color: CyberColors.electricMint, size: 20),
              ),
              title: Text(
                'RESTORE FROM GOOGLE DRIVE',
                style: CyberTypography.hudTitle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
              subtitle: Text(
                'Download & merge latest zero-knowledge backup',
                style: CyberTypography.mono(color: CyberColors.textMuted, fontSize: 10.5),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: CyberColors.glassBorderMuted),
              ),
              tileColor: CyberColors.elevatedSurface,
              onTap: () {
                Navigator.pop(ctx);
                _restoreFromGoogleDrive();
              },
            ),
            const SizedBox(height: 12),

            if (drive.isSignedIn)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.logout_rounded, color: CyberColors.crimsonAlert, size: 16),
                  label: Text('DISCONNECT DRIVE', style: CyberTypography.mono(color: CyberColors.crimsonAlert, fontSize: 11)),
                  onPressed: () async {
                    await drive.signOut();
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    setState(() {});
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final drive = context.watch<DriveService>();
    final grouped = _groupedItems;

    return Scaffold(
      backgroundColor: CyberColors.obsidianBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        // Profile Avatar (Left)
        leading: Padding(
          key: _profileKey,
          padding: const EdgeInsets.all(8.0),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
              _loadItems();
            },
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: CyberColors.laserCyan.withValues(alpha: 0.5), width: 1.2),
                boxShadow: [
                  BoxShadow(color: CyberColors.laserCyan.withValues(alpha: 0.2), blurRadius: 6),
                ],
              ),
              child: CircleAvatar(
                backgroundColor: CyberColors.cardSurface,
                backgroundImage: drive.userPhotoUrl != null ? NetworkImage(drive.userPhotoUrl!) : null,
                child: drive.userPhotoUrl == null
                    ? const Icon(Icons.person_rounded, color: CyberColors.laserCyan, size: 20)
                    : null,
              ),
            ),
          ),
        ),
        // Centered Cyber Robotic Title
        title: Column(
          children: [
            Text(
              'TETHERPASS VAULT',
              style: CyberTypography.hudTitle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: CyberColors.textWhite,
                letterSpacing: 2.0,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'ENCLAVE // HARDWARE AIR-GAP',
              style: CyberTypography.mono(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: CyberColors.laserCyan,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
        centerTitle: true,
        // Actions: Google Drive Sync & Lock Icon
        actions: [
          // Google Drive Sync Icon
          IconButton(
            key: _driveSyncKey,
            icon: _isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: CyberColors.laserCyan, strokeWidth: 2),
                  )
                : Stack(
                    children: [
                      const Icon(Icons.cloud_sync_rounded, color: CyberColors.laserCyan, size: 22),
                      if (drive.isSignedIn)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: CyberColors.electricMint,
                              boxShadow: [
                                BoxShadow(color: CyberColors.electricMint, blurRadius: 4),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
            tooltip: 'Google Drive Sync',
            onPressed: _showDriveMenu,
          ),
          // Lock Icon
          IconButton(
            key: _lockKey,
            icon: const Icon(Icons.lock_rounded, color: CyberColors.crimsonAlert, size: 22),
            tooltip: 'Arm Vault Lock',
            onPressed: _lockVault,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: CyberBackground(
        showGrid: true,
        child: Column(
          children: [
            // Search & Filter Header
            Padding(
              key: _searchFilterKey,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: Column(
                children: [
                  // Glassmorphic Search Input with Neon Laser Border
                  CyberGlassCard(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    borderRadius: 14,
                    borderColor: CyberColors.glassBorder,
                    showCornerBrackets: true,
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: _handleSearchInput,
                      style: CyberTypography.mono(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'SEARCH VAULT // BANK / CORE ID...',
                        hintStyle: CyberTypography.mono(color: CyberColors.textDim, fontSize: 11),
                        prefixIcon: const Icon(Icons.search_rounded, color: CyberColors.laserCyan, size: 20),
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        fillColor: Colors.transparent,
                        filled: false,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Robotic Filter Pills
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('ALL (${_items.length})', 0),
                        const SizedBox(width: 8),
                        _buildFilterChip('CREDIT (${_items.where((i) => i.isCard && i.isCredit).length})', 1),
                        const SizedBox(width: 8),
                        _buildFilterChip('DEBIT (${_items.where((i) => i.isCard && i.isDebit).length})', 2),
                        const SizedBox(width: 8),
                        _buildFilterChip('BANK (${_items.where((i) => i.isNetBanking).length})', 3),
                        const SizedBox(width: 8),
                        _buildFilterChip('PASSWORDS (${_items.where((i) => i.isPassword).length})', 4),
                      ],
                    ),
                  ),
                  if (VaultSecurityService.isDecoySetupRevealed) ...[
                    const SizedBox(height: 10),
                    CyberGlassCard(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      borderRadius: 12,
                      borderColor: CyberColors.plasmaAmber.withValues(alpha: 0.5),
                      glowColor: CyberColors.plasmaAmber,
                      child: Row(
                        children: [
                          const Icon(Icons.shield_outlined, color: CyberColors.plasmaAmber, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'DURESS DECOY VAULT (STEALTH UNLOCKED)',
                                  style: CyberTypography.hudTitle(
                                    color: CyberColors.plasmaAmber,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                FutureBuilder<bool>(
                                  future: context.read<VaultSecurityService>().isDuressEnabled(),
                                  builder: (ctx, snap) {
                                    final active = snap.data == true;
                                    return Text(
                                      active ? 'STATUS: ARMED • Alternate PIN Linked' : 'STATUS: UNCONFIGURED • Set PIN',
                                      style: CyberTypography.mono(
                                        color: active ? CyberColors.electricMint : CyberColors.plasmaAmber,
                                        fontSize: 9.5,
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              await showDuressDecoySetupDialog(context, onStateChanged: () {
                                if (mounted) setState(() {});
                              });
                            },
                            child: Text(
                              'CONFIGURE',
                              style: CyberTypography.mono(
                                color: CyberColors.laserCyan,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.visibility_off_outlined, color: CyberColors.textMuted, size: 16),
                            tooltip: 'Hide Decoy Setup',
                            onPressed: () {
                              setState(() {
                                VaultSecurityService.isDecoySetupRevealed = false;
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Decoy Vault setup is hidden again.'),
                                  backgroundColor: CyberColors.cardSurface,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Main List grouped by Bank Name
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: CyberColors.laserCyan))
                  : _filteredItems.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          color: CyberColors.laserCyan,
                          backgroundColor: CyberColors.cardSurface,
                          onRefresh: _loadItems,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                            itemCount: grouped.keys.length,
                            itemBuilder: (context, index) {
                              final bankName = grouped.keys.elementAt(index);
                              final bankItems = grouped[bankName]!;
                              return _buildBankGroup(bankName, bankItems);
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),

      // Fixed Robotic Neon Floating Action Button at Bottom Right
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: CyberColors.laserCyan.withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FloatingActionButton(
          key: _fabKey,
          backgroundColor: CyberColors.laserCyan,
          foregroundColor: Colors.black,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: const Icon(Icons.add_rounded, size: 30, color: Colors.black),
          onPressed: () async {
            final added = await Navigator.push<bool>(
              context,
              MaterialPageRoute(builder: (_) => const AddEditScreen()),
            );
            if (added == true) _loadItems();
          },
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, int index) {
    final isSelected = _selectedFilter == index;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => setState(() => _selectedFilter = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? CyberColors.laserCyan.withValues(alpha: 0.2) : CyberColors.glassFill,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? CyberColors.laserCyan : CyberColors.glassBorderMuted,
            width: isSelected ? 1.4 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: CyberColors.laserCyan.withValues(alpha: 0.3),
                    blurRadius: 8,
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: CyberTypography.mono(
            color: isSelected ? CyberColors.laserCyan : CyberColors.textMuted,
            fontSize: 10.5,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }

  Widget _buildBankGroup(String bankName, List<VaultItem> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: CyberColors.laserCyan,
                  boxShadow: [
                    BoxShadow(color: CyberColors.laserCyan, blurRadius: 4),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                bankName.toUpperCase(),
                style: CyberTypography.hudTitle(
                  color: CyberColors.laserCyan,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: CyberColors.glassFillLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: CyberColors.glassBorderMuted, width: 0.8),
                ),
                child: Text(
                  '${items.length} ${items.length == 1 ? "CORE" : "CORES"}',
                  style: CyberTypography.mono(
                    color: CyberColors.textMuted,
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        ...items.map((item) => _buildItemTile(item)),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _buildItemTile(VaultItem item) {
    final isExpired = item.isCard && item.isCardExpired;
    final isExpiringSoon = item.isCard && item.isCardExpiringSoon;

    Color tileBorderColor = CyberColors.glassBorderMuted;
    Color? glowColor;

    Color iconBg;
    Color iconColor;

    if (isExpired) {
      tileBorderColor = CyberColors.crimsonAlert;
      glowColor = CyberColors.crimsonAlert;
      iconBg = CyberColors.crimsonAlert.withValues(alpha: 0.16);
      iconColor = CyberColors.crimsonAlert;
    } else if (isExpiringSoon) {
      tileBorderColor = CyberColors.plasmaAmber;
      glowColor = CyberColors.plasmaAmber;
      iconBg = CyberColors.plasmaAmber.withValues(alpha: 0.16);
      iconColor = CyberColors.plasmaAmber;
    } else if (item.isPassword) {
      iconBg = CyberColors.quantumViolet.withValues(alpha: 0.16);
      iconColor = CyberColors.quantumViolet;
    } else {
      iconBg = item.isCard
          ? (item.isDebit
              ? CyberColors.electricMint.withValues(alpha: 0.16)
              : CyberColors.laserCyan.withValues(alpha: 0.16))
          : CyberColors.skyBlue.withValues(alpha: 0.16);
      iconColor = item.isCard
          ? (item.isDebit ? CyberColors.electricMint : CyberColors.laserCyan)
          : CyberColors.skyBlue;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: CyberGlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        borderRadius: 16,
        borderColor: tileBorderColor,
        glowColor: glowColor,
        showCornerBrackets: isExpired || isExpiringSoon,
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ItemDetailScreen(item: item)),
          );
          _loadItems();
        },
        child: Row(
          children: [
            // Glowing Cyber Icon Node
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: iconColor.withValues(alpha: 0.4), width: 1),
                boxShadow: [
                  BoxShadow(color: iconColor.withValues(alpha: 0.25), blurRadius: 8),
                ],
              ),
              child: Icon(
                item.isPassword
                    ? Icons.vpn_key_rounded
                    : (item.isCard
                        ? (item.isDebit ? Icons.account_balance_wallet_rounded : Icons.credit_card_rounded)
                        : Icons.account_balance_rounded),
                color: iconColor,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
          children: [
            Expanded(
              child: Text(
                item.nickname,
                style: CyberTypography.hudTitle(
                  color: isExpired
                      ? CyberColors.crimsonAlert
                      : (isExpiringSoon ? CyberColors.plasmaAmber : Colors.white),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            if (item.isPassword) ...[
              const CyberBadge(
                text: 'PASSKEY',
                color: CyberColors.quantumViolet,
              ),
            ] else if (item.isCard) ...[
              CyberBadge(
                text: item.isDebit ? 'DEBIT' : 'CREDIT',
                color: item.isDebit ? CyberColors.electricMint : CyberColors.laserCyan,
              ),
              const SizedBox(width: 4),
              CyberBadge(
                text: item.cardTier.displayName.toUpperCase(),
                color: isExpired
                    ? CyberColors.crimsonAlert
                    : (isExpiringSoon ? CyberColors.plasmaAmber : CyberColors.textMuted),
              ),
            ],
          ],
        ),
        const SizedBox(height: 5),
        Text(
          item.isPassword
              ? '${item.website.isNotEmpty ? "${item.website}  •  " : ""}${item.userId.isNotEmpty ? item.userId : "Password Encrypted"}'
              : (item.isCard
                  ? '${item.isDebit ? "Debit" : "Credit"}  •  ${item.cardNetwork}  •  ${item.maskedCardNumber}'
                  : (item.allAccounts.isNotEmpty
                      ? (item.allAccounts.length > 1
                          ? '${item.allAccounts.length} Accounts  •  Primary: ${item.allAccounts.first.maskedAccountNumber}'
                          : 'A/C: ${item.allAccounts.first.maskedAccountNumber}${item.allAccounts.first.ifscCode.isNotEmpty ? "  •  ${item.allAccounts.first.ifscCode}" : ""}')
                      : 'User ID: ${item.userId.isEmpty ? "—" : item.userId}')),
          style: CyberTypography.mono(
            color: isExpired
                ? CyberColors.crimsonAlert
                : (isExpiringSoon ? CyberColors.plasmaAmber : CyberColors.textMuted),
            fontSize: 11,
            letterSpacing: 0.4,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    ),
  ),
  const SizedBox(width: 6),
  Icon(
    Icons.chevron_right_rounded,
    color: isExpired
        ? CyberColors.crimsonAlert
        : (isExpiringSoon ? CyberColors.plasmaAmber : CyberColors.textMuted),
    size: 20,
  ),
],
),
),
);
}

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: CyberColors.glassFill,
                border: Border.all(color: CyberColors.laserCyan.withValues(alpha: 0.3)),
                boxShadow: [
                  BoxShadow(
                    color: CyberColors.laserCyan.withValues(alpha: 0.2),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: const Icon(Icons.shield_outlined, size: 54, color: CyberColors.laserCyan),
            ),
            const SizedBox(height: 20),
            Text(
              'ENCLAVE IS EMPTY',
              style: CyberTypography.hudTitle(
                color: CyberColors.textWhite,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Initialize your sovereign vault cores by tapping the "+" button below or restore an encrypted cloud payload.',
              textAlign: TextAlign.center,
              style: CyberTypography.body(
                color: CyberColors.textMuted,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 24),
            CyberNeonButton(
              height: 44,
              primaryColor: CyberColors.laserCyan,
              isOutlined: true,
              label: 'RESTORE FROM DRIVE',
              icon: const Icon(Icons.cloud_download_rounded, color: CyberColors.laserCyan, size: 18),
              onPressed: _restoreFromGoogleDrive,
            ),
          ],
        ),
      ),
    );
  }
}
