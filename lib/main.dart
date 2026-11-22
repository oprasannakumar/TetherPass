import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'services/auth_service.dart';
import 'services/auto_lock_service.dart';
import 'services/crypto_service.dart';
import 'services/database_service.dart';
import 'services/drive_service.dart';
import 'services/vault_security_service.dart';
import 'screens/onboarding_screen.dart';
import 'screens/unlock_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/add_edit_screen.dart';
import 'screens/splash_screen.dart';
import 'theme/cyber_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Force portrait orientation
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system navigation & status bar style for cyber dark theme
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: CyberColors.obsidianBg,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Initialize service singletons for dependency injection
  final cryptoService = CryptoService();
  final dbService = DatabaseService(cryptoService: cryptoService);
  final securityService = VaultSecurityService(cryptoService: cryptoService);
  final authService = AuthService();
  final driveService = DriveService(
    cryptoService: cryptoService,
    databaseService: dbService,
    vaultSecurityService: securityService,
  );

  runApp(
    MultiProvider(
      providers: [
        Provider<CryptoService>.value(value: cryptoService),
        Provider<DatabaseService>.value(value: dbService),
        Provider<VaultSecurityService>.value(value: securityService),
        Provider<AuthService>.value(value: authService),
        ChangeNotifierProvider<DriveService>.value(value: driveService),
      ],
      child: const TetherPassApp(
        initialRoute: '/splash',
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
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => AutoLockService.recordUserActivity(),
      onPointerMove: (_) => AutoLockService.recordUserActivity(),
      onPointerUp: (_) => AutoLockService.recordUserActivity(),
      child: MaterialApp(
        navigatorKey: appNavigatorKey,
        title: 'TetherPass',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: CyberColors.obsidianBg,
          canvasColor: CyberColors.obsidianBg,
          colorScheme: const ColorScheme.dark(
            primary: CyberColors.laserCyan,
            secondary: CyberColors.electricMint,
            tertiary: CyberColors.quantumViolet,
            surface: CyberColors.cardSurface,
            error: CyberColors.crimsonAlert,
            onPrimary: Colors.black,
            onSecondary: Colors.black,
            onSurface: CyberColors.textWhite,
          ),
          appBarTheme: AppBarTheme(
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            centerTitle: true,
            titleTextStyle: CyberTypography.hudTitle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: CyberColors.textWhite,
            ),
            iconTheme: const IconThemeData(color: CyberColors.laserCyan),
          ),
          cardTheme: CardThemeData(
            color: CyberColors.cardSurface.withValues(alpha: 0.65),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: CyberColors.glassBorderMuted, width: 1),
            ),
          ),
          dialogTheme: DialogThemeData(
            backgroundColor: CyberColors.cardSurface,
            elevation: 0,
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xFF1E293B), width: 1.0),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            floatingLabelBehavior: FloatingLabelBehavior.always,
            filled: true,
            fillColor: CyberColors.glassFillLight,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: CyberColors.glassBorderMuted, width: 1.0),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: CyberColors.glassBorderMuted, width: 1.0),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: CyberColors.laserCyan, width: 1.6),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: CyberColors.crimsonAlert, width: 1.2),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: CyberColors.crimsonAlert, width: 1.8),
            ),
            labelStyle: CyberTypography.hudSubtitle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: CyberColors.textMuted,
            ),
            floatingLabelStyle: CyberTypography.hudSubtitle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: CyberColors.laserCyan,
            ),
            hintStyle: CyberTypography.mono(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: CyberColors.textDim,
            ),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: CyberColors.laserCyan,
              foregroundColor: Colors.black,
              elevation: 4,
              shadowColor: CyberColors.cyanGlow,
              textStyle: CyberTypography.hudTitle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Colors.black,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        initialRoute: widget.initialRoute,
      routes: {
        '/splash': (_) => const SplashScreen(),
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
