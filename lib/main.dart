import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'services/auth_service.dart';
import 'services/auto_lock_service.dart';
import 'services/bin_database_service.dart';
import 'services/crypto_service.dart';
import 'services/database_service.dart';
import 'services/drive_service.dart';
import 'services/vault_security_service.dart';
import 'screens/onboarding_screen.dart';
import 'screens/unlock_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/add_edit_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Force portrait orientation
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system navigation & status bar style for light theme
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  // Initialise zero-knowledge encryption & local DB
  final cryptoService = CryptoService();
  await cryptoService.init();

  final dbService = DatabaseService(cryptoService: cryptoService);
  await dbService.init();

  final securityService = VaultSecurityService(cryptoService: cryptoService);
  final authService = AuthService();
  final driveService = DriveService(
    cryptoService: cryptoService,
    databaseService: dbService,
    vaultSecurityService: securityService,
  );

  // Pre-load offline BIN database in background
  unawaited(BinDatabaseService.init());

  await AutoLockService.init(appNavigatorKey);

  final isOnboarded = await securityService.isOnboarded();
  final autoLockSec = await AutoLockService.getAutoLockSeconds();
  final startAtHome = isOnboarded && autoLockSec < 0;
  if (startAtHome) {
    AutoLockService.markUnlocked();
  }

  runApp(
    MultiProvider(
      providers: [
        Provider<CryptoService>.value(value: cryptoService),
        Provider<DatabaseService>.value(value: dbService),
        Provider<VaultSecurityService>.value(value: securityService),
        Provider<AuthService>.value(value: authService),
        ChangeNotifierProvider<DriveService>.value(value: driveService),
      ],
      child: TetherPassApp(
        initialRoute: !isOnboarded ? '/onboarding' : (startAtHome ? '/home' : '/unlock'),
      ),
    ),
  );
}

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class TetherPassApp extends StatefulWidget {
  final String initialRoute;

  const TetherPassApp({super.key, required this.initialRoute});

  @override
  State<TetherPassApp> createState() => _TetherPassAppState();
}

class _TetherPassAppState extends State<TetherPassApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      if (AutoLockService.isNeverLock) return;
      AutoLockService.markPaused();
    } else if (state == AppLifecycleState.resumed) {
      if (AutoLockService.isNeverLock) {
        AutoLockService.clearPaused();
        return;
      }
      final shouldLock = AutoLockService.shouldLockOnResume();
      AutoLockService.clearPaused();
      if (shouldLock) {
        AutoLockService.lockVault();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFFFF6F00); // Warm vibrant orange
    const backgroundColor = Color(0xFFF8F9FA); // Crisp clean light background
    const surfaceColor = Colors.white;
    const textPrimary = Color(0xFF1E293B); // Dark slate
    const textSecondary = Color(0xFF64748B); // Muted slate

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => AutoLockService.recordUserActivity(),
      onPointerMove: (_) => AutoLockService.recordUserActivity(),
      onPointerUp: (_) => AutoLockService.recordUserActivity(),
      child: MaterialApp(
        navigatorKey: appNavigatorKey,
        title: 'TetherPass',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: backgroundColor,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryColor,
          brightness: Brightness.light,
          primary: primaryColor,
          surface: surfaceColor,
          onSurface: textPrimary,
          background: backgroundColor,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: surfaceColor,
          elevation: 0,
          scrolledUnderElevation: 1,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
          iconTheme: IconThemeData(color: textPrimary),
        ),
        cardTheme: CardThemeData(
          color: surfaceColor,
          elevation: 1,
          shadowColor: Colors.black12,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          floatingLabelBehavior: FloatingLabelBehavior.always,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: primaryColor, width: 1.8),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.redAccent, width: 1.2),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.redAccent, width: 1.8),
          ),
          labelStyle: const TextStyle(color: textSecondary, fontWeight: FontWeight.w600, fontSize: 13),
          floatingLabelStyle: const TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 13),
          hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontStyle: FontStyle.italic),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
      initialRoute: widget.initialRoute,
      routes: {
        '/onboarding': (_) => const OnboardingScreen(),
        '/unlock': (_) => const UnlockScreen(),
        '/home': (_) => const HomeScreen(),
        '/settings': (_) => const SettingsScreen(),
        '/add': (_) => const AddEditScreen(),
      },
    ),
  );
}
}
