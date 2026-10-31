import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/vault_item.dart';
import '../services/auth_service.dart';
import '../services/autofill_bridge_service.dart';
import '../services/database_service.dart';
import '../services/drive_service.dart';
import '../services/extension_auth_service.dart';
import '../services/vault_security_service.dart';
import '../widgets/app_tour_dialog.dart';
import '../widgets/spotlight_tour.dart';
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
  int _selectedFilter = 0; // 0 = All, 1 = Credit, 2 = Debit, 3 = Bank

  // GlobalKeys to point directly to each button in the spotlight tour
  final GlobalKey _profileKey = GlobalKey();
  final GlobalKey _driveSyncKey = GlobalKey();
  final GlobalKey _tourHelpKey = GlobalKey();
  final GlobalKey _lockKey = GlobalKey();
  final GlobalKey _searchFilterKey = GlobalKey();
  final GlobalKey _fabKey = GlobalKey();

  Timer? _accessRequestPollTimer;
  bool _isShowingApprovalDialog = false;

  @override
  void initState() {
    super.initState();
    _loadItems();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final drive = context.read<DriveService>();
      if (!drive.isSignedIn) {
        await drive.trySilentSignIn();
      }
      _checkFirstTimeTour();
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
    _accessRequestPollTimer?.cancel();
    super.dispose();
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
            'This mobile phone was removed from your CardVault account. All credentials and local vault data on this device have been wiped clean.',
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
                  'Desktop Sign-In',
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
                'A Windows computer is requesting access to your CardVault cards, bank accounts, and passwords.',
                style: TextStyle(fontSize: 13, color: Color(0xFF475569), height: 1.4),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.devices_rounded, size: 16, color: Color(0xFF64748B)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(deviceName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A))),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.access_time_rounded, size: 16, color: Color(0xFF64748B)),
                        const SizedBox(width: 8),
                        const Text('Just now', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                      ],
                    ),
                  ],
                ),
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
          reason: 'Authorize CardVault Browser Extension on Windows PC',
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
        await drive.respondToAccessRequest(
          requestId: requestId,
          approved: true,
          deviceName: deviceName,
          masterPassword: masterPwd,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Browser extension approved for 30 mins',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.green.shade700,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
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

  Future<void> _checkFirstTimeTour() async {
    final sec = context.read<VaultSecurityService>();
    final seen = await sec.hasSeenTour();
    if (!seen && mounted) {
      // Small delay to ensure widgets are laid out with accurate coordinates
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) _startSpotlightTour();
      });
    }
  }

  void _startSpotlightTour() {
    final steps = <SpotlightTourStep>[
      SpotlightTourStep(
        targetKey: _profileKey,
        icon: Icons.person_rounded,
        title: 'Profile & Settings',
        description: 'Tap here to change your Master Password, toggle Biometrics, view your 16-character Recovery Key, or Link Google Drive.',
        isCircle: true,
      ),
      SpotlightTourStep(
        targetKey: _driveSyncKey,
        icon: Icons.cloud_sync_rounded,
        title: 'Google Drive Cloud Sync',
        description: 'Tap to manually back up your encrypted vault or restore saved cards from your Google Drive anytime.',
        isCircle: true,
      ),
      SpotlightTourStep(
        targetKey: _tourHelpKey,
        icon: Icons.help_outline_rounded,
        title: 'Interactive App Tour',
        description: 'Tap this Help icon anytime to replay this button pointer tour or view the full feature guide.',
        isCircle: true,
      ),
      SpotlightTourStep(
        targetKey: _lockKey,
        icon: Icons.lock_rounded,
        title: 'Instant Vault Lock',
        description: 'Tap here to immediately lock the app and secure all credentials behind Master Password & Biometrics.',
        isCircle: true,
      ),
      SpotlightTourStep(
        targetKey: _searchFilterKey,
        icon: Icons.search_rounded,
        title: 'Search & Quick Filters',
        description: 'Search cards by nickname or bank name, or toggle between All, Credit Cards, Debit Cards, and Bank accounts.',
        isCircle: false,
        borderRadius: 16,
      ),
      SpotlightTourStep(
        targetKey: _fabKey,
        icon: Icons.add_rounded,
        title: 'Add New Card or Account (+)',
        description: 'Tap this orange button to add a new Credit Card, Debit Card, or Bank account to your vault.',
        isCircle: true,
      ),
    ];

    SpotlightTourOverlay.show(
      context: context,
      steps: steps,
      onFinish: () {
        final sec = context.read<VaultSecurityService>();
        sec.setTourSeen(true);
      },
    );
  }

  void _showTourOptionsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6F00).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.school_rounded, color: Color(0xFFFF6F00), size: 22),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CardVault Interactive Tour',
                      style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(
                      'Choose how you would like to explore features',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Option 1: 7-Chapter Illustrated Guide
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6F00).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.auto_stories_rounded, color: Color(0xFFFF6F00)),
              ),
              title: const Text('Complete Illustrated Guide', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold)),
              subtitle: const Text('7 illustrated chapters covering cards, bank accounts, keyboard autofill, and security', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFFE2E8F0))),
              tileColor: const Color(0xFFF8FAFC),
              onTap: () {
                Navigator.pop(ctx);
                AppTourDialog.show(context);
              },
            ),
            const SizedBox(height: 10),

            // Option 2: Screen Pointer Tour
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.touch_app_rounded, color: Colors.blueAccent),
              ),
              title: const Text('Interactive Screen Tour', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold)),
              subtitle: const Text('Spotlight walk through every button and icon on the main screen', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFFE2E8F0))),
              tileColor: const Color(0xFFF8FAFC),
              onTap: () {
                Navigator.pop(ctx);
                _startSpotlightTour();
              },
            ),
          ],
        ),
      ),
    );
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

      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchNick = item.nickname.toLowerCase().contains(q);
        final matchBank = item.bankName.toLowerCase().contains(q);
        final matchHolder = item.cardHolder.toLowerCase().contains(q);
        final matchAcc = item.allAccounts.any((a) => a.accountNumber.toLowerCase().contains(q) || a.ifscCode.toLowerCase().contains(q));
        final matchType = item.isCard ? (item.isDebit ? 'debit' : 'credit') : 'bank';
        return matchNick || matchBank || matchHolder || matchAcc || matchType.contains(q);
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
    AutofillBridgeService.syncVaultState(isUnlocked: false);
    context.read<ExtensionAuthService>().onMobileVaultLocked();
    Navigator.of(context).pushNamedAndRemoveUntil('/unlock', (route) => false);
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
    final passwordCtrl = TextEditingController();
    String? errorText;

    await showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.cloud_download_rounded, color: Color(0xFFFF6F00)),
              SizedBox(width: 8),
              Text('Cloud Backup Password', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This Google Drive backup is encrypted with a Master Password.\n\nEnter the password to decrypt:',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordCtrl,
                obscureText: true,
                style: const TextStyle(color: Color(0xFF0F172A)),
                decoration: InputDecoration(
                  labelText: 'Master Password',
                  hintText: 'Enter backup password',
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
              child: const Text('Decrypt & Restore'),
              onPressed: () async {
                final pwd = passwordCtrl.text.trim();
                if (pwd.isEmpty) {
                  setDlgState(() => errorText = 'Please enter password');
                  return;
                }

                try {
                  final count = await drive.restore(masterPassword: pwd);
                  await _loadItems();
                  if (mounted) {
                    Navigator.pop(dlgCtx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('✓ Restored $count items from Google Drive!'),
                        backgroundColor: Colors.green.shade800,
                      ),
                    );
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

  void _showDriveMenu() {
    final drive = context.read<DriveService>();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.add_to_drive_rounded, color: Color(0xFFFF6F00), size: 24),
                const SizedBox(width: 10),
                const Text(
                  'Google Drive Cloud Sync',
                  style: TextStyle(color: Color(0xFF0F172A), fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              drive.isSignedIn
                  ? 'Connected as ${drive.userEmail}'
                  : 'Sync your encrypted vault to your private Google Drive',
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
            ),
            const SizedBox(height: 18),

            // Backup Button
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFFF6F00).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.cloud_upload_rounded, color: Color(0xFFFF6F00)),
              ),
              title: const Text('Backup to Google Drive', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold)),
              subtitle: Text('Upload encrypted backup (${_items.length} items)', style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFE2E8F0))),
              tileColor: const Color(0xFFF8F9FA),
              onTap: () {
                Navigator.pop(ctx);
                _backupToGoogleDrive();
              },
            ),
            const SizedBox(height: 10),

            // Restore Button
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.cloud_download_rounded, color: Colors.blueAccent),
              ),
              title: const Text('Restore from Google Drive', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold)),
              subtitle: const Text('Download & merge latest backup', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFE2E8F0))),
              tileColor: const Color(0xFFF8F9FA),
              onTap: () {
                Navigator.pop(ctx);
                _restoreFromGoogleDrive();
              },
            ),
            const SizedBox(height: 10),

            if (drive.isSignedIn)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 16),
                  label: const Text('Disconnect Google Drive', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                  onPressed: () async {
                    await drive.signOut();
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
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
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
              _checkFirstTimeTour();
            },
            child: CircleAvatar(
              backgroundColor: const Color(0xFFFF6F00).withValues(alpha: 0.15),
              backgroundImage: drive.userPhotoUrl != null ? NetworkImage(drive.userPhotoUrl!) : null,
              child: drive.userPhotoUrl == null
                  ? const Icon(Icons.person_rounded, color: Color(0xFFFF6F00), size: 20)
                  : null,
            ),
          ),
        ),
        // Centered Title
        title: const Text(
          'My Vault',
          style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: 0.5),
        ),
        centerTitle: true,
        // Actions: Google Drive Sync & Lock Icon
        actions: [
          // Google Drive Sync Icon
          IconButton(
            key: _driveSyncKey,
            icon: _isSyncing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Color(0xFFFF6F00), strokeWidth: 2))
                : Stack(
                    children: [
                      const Icon(Icons.cloud_sync_rounded, color: Color(0xFF0F172A)),
                      if (drive.isSignedIn)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.green,
                            ),
                          ),
                        ),
                    ],
                  ),
            tooltip: 'Google Drive Sync',
            onPressed: _showDriveMenu,
          ),
          // App Tour & Guide
          IconButton(
            key: _tourHelpKey,
            icon: const Icon(Icons.help_outline_rounded, color: Color(0xFF64748B)),
            tooltip: 'App Tour & Guide',
            onPressed: _showTourOptionsSheet,
          ),
          // Lock Icon
          IconButton(
            key: _lockKey,
            icon: const Icon(Icons.lock_rounded, color: Color(0xFF64748B)),
            tooltip: 'Lock Vault',
            onPressed: _lockVault,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search & Filter Header
          Padding(
            key: _searchFilterKey,
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
            child: Column(
              children: [
                TextField(
                  onChanged: (val) => setState(() => _searchQuery = val),
                  style: const TextStyle(color: Color(0xFF0F172A), fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search by bank or nickname...',
                    prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF94A3B8), size: 20),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                  ),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('All (${_items.length})', 0),
                      const SizedBox(width: 8),
                      _buildFilterChip('Credit Cards (${_items.where((i) => i.isCard && i.isCredit).length})', 1),
                      const SizedBox(width: 8),
                      _buildFilterChip('Debit Cards (${_items.where((i) => i.isCard && i.isDebit).length})', 2),
                      const SizedBox(width: 8),
                      _buildFilterChip('Bank (${_items.where((i) => i.isNetBanking).length})', 3),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Main List grouped alphabetically by Bank Name
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF6F00)))
                : _filteredItems.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        color: const Color(0xFFFF6F00),
                        backgroundColor: Colors.white,
                        onRefresh: _loadItems,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 80),
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

      // Fixed Orange "+" Floating Action Button at Bottom Right
      floatingActionButton: FloatingActionButton(
        key: _fabKey,
        backgroundColor: const Color(0xFFFF6F00),
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.add, size: 28),
        onPressed: () async {
          final added = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const AddEditScreen()),
          );
          if (added == true) _loadItems();
        },
      ),
    );
  }

  Widget _buildFilterChip(String label, int index) {
    final isSelected = _selectedFilter == index;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => setState(() => _selectedFilter = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFF6F00) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? const Color(0xFFFF6F00) : const Color(0xFFE2E8F0)),
          boxShadow: isSelected
              ? [BoxShadow(color: const Color(0xFFFF6F00).withValues(alpha: 0.25), blurRadius: 4, offset: const Offset(0, 2))]
              : const [BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF64748B),
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
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
              const Icon(Icons.account_balance_rounded, color: Color(0xFFFF6F00), size: 16),
              const SizedBox(width: 8),
              Text(
                bankName,
                style: const TextStyle(
                  color: Color(0xFFFF6F00),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${items.length} ${items.length == 1 ? "item" : "items"}',
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.w600),
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

    Color tileBgColor = Colors.white;
    Color tileBorderColor = const Color(0xFFE2E8F0);
    double borderWidth = 1.0;
    List<BoxShadow> tileShadow = const [
      BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1)),
    ];

    Color iconBg;
    Color iconColor;

    if (isExpired) {
      // Red colour for already expired card
      tileBgColor = const Color(0xFFFEF2F2);
      tileBorderColor = const Color(0xFFEF4444);
      borderWidth = 1.8;
      tileShadow = [
        BoxShadow(color: Colors.red.withValues(alpha: 0.18), blurRadius: 6, offset: const Offset(0, 2)),
      ];
      iconBg = Colors.red.shade100;
      iconColor = Colors.red.shade700;
    } else if (isExpiringSoon) {
      // Yellow colour for card which is going to expire in 2 to 3 months
      tileBgColor = const Color(0xFFFEFCE8);
      tileBorderColor = const Color(0xFFEAB308);
      borderWidth = 1.8;
      tileShadow = [
        BoxShadow(color: const Color(0xFFEAB308).withValues(alpha: 0.22), blurRadius: 6, offset: const Offset(0, 2)),
      ];
      iconBg = const Color(0xFFFEF08A);
      iconColor = const Color(0xFFB45309);
    } else {
      iconBg = item.isCard
          ? (item.isDebit
              ? const Color(0xFF10B981).withValues(alpha: 0.12)
              : const Color(0xFFFF6F00).withValues(alpha: 0.12))
          : Colors.blueAccent.withValues(alpha: 0.12);
      iconColor = item.isCard
          ? (item.isDebit ? const Color(0xFF10B981) : const Color(0xFFFF6F00))
          : Colors.blueAccent;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: tileBgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tileBorderColor, width: borderWidth),
        boxShadow: tileShadow,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ItemDetailScreen(item: item)),
          );
          _loadItems();
        },
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            item.isCard
                ? (item.isDebit ? Icons.account_balance_wallet_rounded : Icons.credit_card_rounded)
                : Icons.account_balance_rounded,
            color: iconColor,
            size: 22,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                item.nickname,
                style: TextStyle(
                  color: isExpired
                      ? const Color(0xFF991B1B)
                      : (isExpiringSoon ? const Color(0xFF854D0E) : const Color(0xFF0F172A)),
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (item.isCard) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: item.isDebit ? const Color(0xFFECFDF5) : const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: item.isDebit ? const Color(0xFFA7F3D0) : const Color(0xFFC7D2FE),
                  ),
                ),
                child: Text(
                  item.isDebit ? 'DEBIT' : 'CREDIT',
                  style: TextStyle(
                    color: item.isDebit ? const Color(0xFF047857) : const Color(0xFF4338CA),
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isExpired
                      ? Colors.red.shade100
                      : (isExpiringSoon ? const Color(0xFFFEF08A) : const Color(0xFFF1F5F9)),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isExpired
                        ? Colors.red.shade300
                        : (isExpiringSoon ? const Color(0xFFFACC15) : const Color(0xFFE2E8F0)),
                  ),
                ),
                child: Text(
                  item.cardTier.displayName.toUpperCase(),
                  style: TextStyle(
                    color: isExpired
                        ? Colors.red.shade900
                        : (isExpiringSoon ? const Color(0xFF854D0E) : const Color(0xFF475569)),
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),


            ] else ...[
              if (item.isAnyPasswordExpired)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline_rounded, color: Colors.red, size: 10),
                      SizedBox(width: 3),
                      Text(
                        'PASSWORD EXPIRED',
                        style: TextStyle(color: Colors.red, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                )
              else if (item.isAnyPasswordExpiringSoon)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 10),
                      SizedBox(width: 3),
                      Text(
                        'EXPIRING SOON',
                        style: TextStyle(color: Color(0xFFD97706), fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            item.isCard
                ? '${item.isDebit ? "Debit" : "Credit"}  •  ${item.cardNetwork}  •  ${item.maskedCardNumber}'
                : (item.allAccounts.isNotEmpty
                    ? (item.allAccounts.length > 1
                        ? '${item.allAccounts.length} Accounts  •  Primary: ${item.allAccounts.first.maskedAccountNumber}'
                        : 'A/C: ${item.allAccounts.first.maskedAccountNumber}${item.allAccounts.first.ifscCode.isNotEmpty ? "  •  ${item.allAccounts.first.ifscCode}" : ""}')
                    : 'User ID: ${item.userId.isEmpty ? "—" : item.userId}'),
            style: TextStyle(
              color: isExpired
                  ? Colors.red.shade800
                  : (isExpiringSoon ? const Color(0xFF854D0E) : const Color(0xFF64748B)),
              fontSize: 12,
            ),
          ),
        ),
        trailing: Icon(
          Icons.arrow_forward_ios_rounded,
          color: isExpired
              ? Colors.red.shade400
              : (isExpiringSoon ? const Color(0xFFCA8A04) : const Color(0xFFCBD5E1)),
          size: 14,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shield_outlined, size: 64, color: const Color(0xFFCBD5E1)),
          const SizedBox(height: 16),
          const Text(
            'Your Vault is Empty',
            style: TextStyle(color: Color(0xFF0F172A), fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tap the orange + button below to add your\nfirst credit card or Bank account.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF64748B), fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 24),
          // Actions in empty state: Interactive Button Tour + Quick Restore
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.touch_app_rounded, size: 16),
                label: const Text('Button Tour (Pointing Tour)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6F00),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                onPressed: _startSpotlightTour,
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.cloud_download_rounded, color: Colors.blueAccent, size: 16),
                label: const Text('Restore from Drive', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.blueAccent),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                onPressed: _restoreFromGoogleDrive,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
