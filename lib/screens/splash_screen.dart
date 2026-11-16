import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auto_lock_service.dart';
import '../services/bin_database_service.dart';
import '../services/crypto_service.dart';
import '../services/database_service.dart';
import '../services/vault_security_service.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';
import 'unlock_screen.dart';
import '../main.dart';

/// Animated Launch Splash Screen
/// Displays the TetherPass icon with a breathing glow and smooth entrance animation
/// while zero-knowledge encryption and local vault services initialize in the background.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _pulseAnimation;
  String _statusText = 'Securing storage...';

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOutBack),
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.4, curve: Curves.easeIn),
      ),
    );

    _pulseAnimation = Tween<double>(begin: 6.0, end: 24.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeInOut,
      ),
    );

    _startAppInitialization();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _startAppInitialization() async {
    final startTime = DateTime.now();

    try {
      if (mounted) {
        setState(() => _statusText = 'Initializing secure enclave...');
      }

      final cryptoService = context.read<CryptoService>();
      final dbService = context.read<DatabaseService>();
      final securityService = context.read<VaultSecurityService>();

      await cryptoService.init();

      if (mounted) {
        setState(() => _statusText = 'Loading encrypted database...');
      }

      await dbService.init();
      await AutoLockService.init(appNavigatorKey);
      AutoLockService.onLockCallback = () {
        dbService.isDecoyMode = false;
      };

      // Pre-load offline BIN database in background without blocking
      unawaited(BinDatabaseService.init());

      if (mounted) {
        setState(() => _statusText = 'Verifying vault integrity...');
      }

      final isOnboarded = await securityService.isOnboarded();
      final autoLockSec = await AutoLockService.getAutoLockSeconds();
      final startAtHome = isOnboarded && autoLockSec < 0;
      if (startAtHome) {
        AutoLockService.markUnlocked();
      }

      // Ensure minimum pleasant display time (~850ms) so animation finishes gracefully
      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      const minDurationMs = 850;
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
          transitionDuration: const Duration(milliseconds: 350),
          pageBuilder: (_, __, ___) => targetScreen,
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    } catch (e) {
      debugPrint('[Splash] Initialization error: $e');
      if (!mounted) return;
      // Fallback navigation if error
      Navigator.pushReplacementNamed(context, '/unlock');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),

              // Animated App Icon with Glowing Breathing Aura
              AnimatedBuilder(
                animation: _animController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _scaleAnimation.value,
                    child: Container(
                      width: 104,
                      height: 104,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF6F00).withValues(alpha: 0.22),
                            blurRadius: _pulseAnimation.value,
                            spreadRadius: _pulseAnimation.value * 0.4,
                            offset: const Offset(0, 4),
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(4),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/icons/vault_logo.png',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: const Color(0xFFFF6F00),
                            child: const Icon(
                              Icons.lock_rounded,
                              size: 52,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 28),

              // Brand Name
              FadeTransition(
                opacity: _fadeAnimation,
                child: const Column(
                  children: [
                    Text(
                      'TetherPass',
                      style: TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Air-Gapped Vault Security',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(flex: 2),

              // Animated Status Indicator
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  children: [
                    SizedBox(
                      width: 140,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: const LinearProgressIndicator(
                          minHeight: 3,
                          backgroundColor: Color(0xFFF1F5F9),
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6F00)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Text(
                        _statusText,
                        key: ValueKey<String>(_statusText),
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 36),
            ],
          ),
        ),
      ),
    );
  }
}
