import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auto_lock_service.dart';
import '../services/bin_database_service.dart';
import '../services/crypto_service.dart';
import '../services/database_service.dart';
import '../services/vault_security_service.dart';
import '../theme/cyber_theme.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';
import 'unlock_screen.dart';
import '../main.dart';

/// Cyber-Vault Animated Launch Splash Screen
/// Features a futuristic robotic HUD sequence with glassmorphic depth,
/// rotating neon perimeter rings, and real-time security diagnostics.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _rotationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _glowAnimation;
  String _statusText = 'SYS.INIT: ENCRYPTED STORAGE...';

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    _scaleAnimation = Tween<double>(begin: 0.90, end: 1.05).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: const Interval(0.0, 0.45, curve: Curves.easeIn),
      ),
    );

    _glowAnimation = Tween<double>(begin: 8.0, end: 32.0).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );

    _startAppInitialization();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotationController.dispose();
    super.dispose();
  }

  Future<void> _startAppInitialization() async {
    final startTime = DateTime.now();

    try {
      if (mounted) {
        setState(() => _statusText = 'SYS.ENCLAVE: CALIBRATING HARDWARE VAULT...');
      }

      final cryptoService = context.read<CryptoService>();
      final dbService = context.read<DatabaseService>();
      final securityService = context.read<VaultSecurityService>();

      await cryptoService.init();

      if (mounted) {
        setState(() => _statusText = 'SYS.CRYPTO: MOUNTING AES-256 CORES...');
      }

      await dbService.init();
      await AutoLockService.init(appNavigatorKey);
      AutoLockService.onLockCallback = () {
        dbService.isDecoyMode = false;
      };

      // Pre-load offline BIN database in background without blocking
      unawaited(BinDatabaseService.init());

      if (mounted) {
        setState(() => _statusText = 'SYS.SECURITY: VERIFYING VAULT INTEGRITY...');
      }

      final isOnboarded = await securityService.isOnboarded();
      final autoLockSec = await AutoLockService.getAutoLockSeconds();
      final startAtHome = isOnboarded && autoLockSec < 0;
      if (startAtHome) {
        AutoLockService.markUnlocked();
      }

      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      const minDurationMs = 950;
      if (elapsed < minDurationMs) {
        await Future.delayed(Duration(milliseconds: minDurationMs - elapsed));
      }

      if (!mounted) return;

      final Widget targetScreen = !isOnboarded
          ? const OnboardingScreen()
          : (startAtHome ? const HomeScreen() : const UnlockScreen());

      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 400),
          pageBuilder: (_, __, ___) => targetScreen,
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    } catch (e) {
      debugPrint('[Splash] Initialization error: $e');
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/unlock');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CyberColors.obsidianBg,
      body: CyberBackground(
        showGrid: true,
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),

                // Robotic Central Core with Rotating HUD Ring & Glass Aura
                AnimatedBuilder(
                  animation: Listenable.merge([_pulseController, _rotationController]),
                  builder: (context, child) {
                    return SizedBox(
                      width: 170,
                      height: 170,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Outer Rotating Robotic Ring
                          RotationTransition(
                            turns: _rotationController,
                            child: Container(
                              width: 160,
                              height: 160,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: CyberColors.laserCyan.withValues(alpha: 0.35),
                                  width: 1.5,
                                ),
                              ),
                              child: Stack(
                                children: [
                                  Positioned(
                                    top: 0,
                                    left: 70,
                                    child: Container(
                                      width: 20,
                                      height: 4,
                                      decoration: BoxDecoration(
                                        color: CyberColors.laserCyan,
                                        borderRadius: BorderRadius.circular(2),
                                        boxShadow: [
                                          BoxShadow(
                                            color: CyberColors.laserCyan.withValues(alpha: 0.8),
                                            blurRadius: 8,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 0,
                                    right: 70,
                                    child: Container(
                                      width: 20,
                                      height: 4,
                                      decoration: BoxDecoration(
                                        color: CyberColors.electricMint,
                                        borderRadius: BorderRadius.circular(2),
                                        boxShadow: [
                                          BoxShadow(
                                            color: CyberColors.electricMint.withValues(alpha: 0.8),
                                            blurRadius: 8,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Inner Reverse Rotating Hex Ring
                          RotationTransition(
                            turns: ReverseAnimation(_rotationController),
                            child: Container(
                              width: 136,
                              height: 136,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: CyberColors.quantumViolet.withValues(alpha: 0.25),
                                  width: 1.0,
                                ),
                              ),
                            ),
                          ),

                          // Glassmorphic Glowing Enclave Core
                          Transform.scale(
                            scale: _scaleAnimation.value,
                            child: Container(
                              width: 110,
                              height: 110,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF162544),
                                    Color(0xFF0C1322),
                                  ],
                                ),
                                border: Border.all(
                                  color: CyberColors.laserCyan.withValues(alpha: 0.6),
                                  width: 1.6,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: CyberColors.laserCyan.withValues(alpha: 0.3),
                                    blurRadius: _glowAnimation.value,
                                    spreadRadius: _glowAnimation.value * 0.35,
                                  ),
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.8),
                                    blurRadius: 20,
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.all(8),
                              child: ClipOval(
                                child: Image.asset(
                                  'assets/icons/vault_logo.png',
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Center(
                                    child: Icon(
                                      Icons.shield_rounded,
                                      size: 54,
                                      color: CyberColors.laserCyan,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),

                const SizedBox(height: 32),

                // Futuristic Robotic Branding Title
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: CyberColors.laserCyan,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'TETHERPASS',
                            style: CyberTypography.hudTitle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 3.5,
                              color: CyberColors.textWhite,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: CyberColors.laserCyan,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: CyberColors.laserCyan.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: CyberColors.laserCyan.withValues(alpha: 0.25),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          'AIR-GAPPED CYBER-VAULT PROTOCOL',
                          style: CyberTypography.mono(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: CyberColors.laserCyan,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(flex: 2),

                // Glassmorphic Diagnostic Status Terminal
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 36),
                  child: CyberGlassCard(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    borderRadius: 14,
                    borderColor: CyberColors.glassBorder,
                    showCornerBrackets: true,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'CORE STATUS',
                              style: CyberTypography.mono(
                                fontSize: 9.5,
                                color: CyberColors.textMuted,
                                letterSpacing: 1.0,
                              ),
                            ),
                            Row(
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: CyberColors.electricMint,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'ACTIVE ENCLAVE',
                                  style: CyberTypography.mono(
                                    fontSize: 9.5,
                                    color: CyberColors.electricMint,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // Futuristic Progress Indicator with Cyan / Mint Gradient
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: const SizedBox(
                            height: 3,
                            child: LinearProgressIndicator(
                              backgroundColor: Color(0xFF10192A),
                              valueColor: AlwaysStoppedAnimation<Color>(CyberColors.laserCyan),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: Text(
                            _statusText,
                            key: ValueKey<String>(_statusText),
                            style: CyberTypography.mono(
                              fontSize: 10,
                              color: CyberColors.laserCyan,
                              letterSpacing: 0.6,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
