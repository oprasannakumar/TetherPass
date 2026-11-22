import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Cyber-Vault & Robotic Glassmorphism Color Palette
class CyberColors {
  CyberColors._();

  // Backgrounds & Canvas
  static const Color obsidianBg = Color(0xFF070A12);
  static const Color obsidianDeep = Color(0xFF04060A);
  static const Color cardSurface = Color(0xFF0F1728);
  static const Color elevatedSurface = Color(0xFF141E34);

  // Glassmorphic Surface Tints
  static const Color glassFill = Color(0x1A142038); // 10% translucent
  static const Color glassFillLight = Color(0x281B2B4C); // 16% translucent
  static const Color glassBorder = Color(0xFF1E293B); // sleek dark graphite border
  static const Color glassBorderMuted = Color(0x24FFFFFF); // crisp subtle border

  // Robotic Neon Accents
  static const Color laserCyan = Color(0xFF00E5FF);
  static const Color cyanGlow = Color(0x6600E5FF);
  static const Color electricMint = Color(0xFF00F5A0);
  static const Color mintGlow = Color(0x5500F5A0);
  static const Color quantumViolet = Color(0xFFA855F7);
  static const Color violetGlow = Color(0x55A855F7);
  static const Color plasmaAmber = Color(0xFFF59E0B);
  static const Color crimsonAlert = Color(0xFFFF3366);
  static const Color skyBlue = Color(0xFF38BDF8);

  // Text & Telemetry
  static const Color textWhite = Color(0xFFF8FAFC);
  static const Color textMuted = Color(0xFF8892B0);
  static const Color mutedText = Color(0xFF8892B0);
  static const Color textDim = Color(0xFF475569);
  static const Color textCyan = Color(0xFF38BDF8);
  static const Color borderSubtle = Color(0x1FFFFFFF);
}

/// Cyber-Vault Typography
class CyberTypography {
  CyberTypography._();

  static TextStyle get cyberHeader => hudTitle(fontSize: 16);
  static TextStyle get cyberDisplay => hudTitle(fontSize: 22);
  static TextStyle get bodySmall => body(fontSize: 12, color: CyberColors.textMuted);
  static TextStyle get bodyLarge => body(fontSize: 16);
  static TextStyle get monoBadge => mono(fontSize: 11);
  static TextStyle get monoData => mono(fontSize: 13, color: CyberColors.textWhite);

  // Robotic HUD & Header Fonts (Orbitron / Rajdhani)
  static TextStyle hudTitle({
    double fontSize = 20,
    FontWeight fontWeight = FontWeight.w800,
    Color color = CyberColors.textWhite,
    double letterSpacing = 1.2,
  }) {
    return GoogleFonts.orbitron(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
    );
  }

  static TextStyle hudSubtitle({
    double fontSize = 12,
    FontWeight fontWeight = FontWeight.w600,
    Color color = CyberColors.laserCyan,
    double letterSpacing = 1.0,
  }) {
    return GoogleFonts.rajdhani(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
    );
  }

  // General Clean Body UI Font (Plus Jakarta Sans)
  static TextStyle body({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.normal,
    Color color = CyberColors.textWhite,
  }) {
    return GoogleFonts.plusJakartaSans(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
    );
  }

  // Technical Monospace Telemetry Font (JetBrains Mono)
  static TextStyle mono({
    double fontSize = 12,
    FontWeight fontWeight = FontWeight.w600,
    Color color = CyberColors.laserCyan,
    double letterSpacing = 0.8,
  }) {
    return GoogleFonts.jetBrainsMono(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
    );
  }
}

/// Reusable Glassmorphism Card with Robotic Corner Accents
class CyberGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final Color? borderColor;
  final Color? glowColor;
  final double blurAmount;
  final VoidCallback? onTap;
  final bool showCornerBrackets;
  final Gradient? customGradient;

  const CyberGlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 16,
    this.borderColor,
    this.glowColor,
    this.blurAmount = 14,
    this.onTap,
    this.showCornerBrackets = false,
    this.customGradient,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveBorderColor = borderColor ?? CyberColors.glassBorderMuted;
    final content = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurAmount, sigmaY: blurAmount),
        child: Container(
          padding: padding ?? const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            gradient: customGradient ??
                const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    CyberColors.glassFillLight,
                    CyberColors.glassFill,
                  ],
                ),
            border: Border.all(
              color: effectiveBorderColor,
              width: 1.2,
            ),
            boxShadow: glowColor != null
                ? [
                    BoxShadow(
                      color: glowColor!.withValues(alpha: 0.15),
                      blurRadius: 16,
                      spreadRadius: -2,
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: child,
        ),
      ),
    );

    if (onTap != null) {
      return Container(
        margin: margin,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(borderRadius),
            splashColor: CyberColors.laserCyan.withValues(alpha: 0.12),
            highlightColor: CyberColors.laserCyan.withValues(alpha: 0.06),
            child: content,
          ),
        ),
      );
    }

    return Container(
      margin: margin,
      child: content,
    );
  }
}

/// Cybernetic Background with subtle glowing radial ambient orbs and scanlines
class CyberBackground extends StatelessWidget {
  final Widget child;
  final bool showGrid;

  const CyberBackground({
    super.key,
    required this.child,
    this.showGrid = true,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Deep obsidian base
        Container(
          color: CyberColors.obsidianBg,
        ),

        // Ambient Glowing Neon Light Orbs
        Positioned(
          top: -120,
          right: -80,
          child: Container(
            width: 340,
            height: 340,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  CyberColors.laserCyan.withValues(alpha: 0.16),
                  CyberColors.laserCyan.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 100,
          left: -100,
          child: Container(
            width: 380,
            height: 380,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  CyberColors.electricMint.withValues(alpha: 0.12),
                  CyberColors.electricMint.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: 320,
          right: -120,
          child: Container(
            width: 320,
            height: 320,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  CyberColors.quantumViolet.withValues(alpha: 0.10),
                  CyberColors.quantumViolet.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ),

        // Cyber Grid Overlay (Optional Subtle Matrix Wireframe)
        if (showGrid)
          Positioned.fill(
            child: CustomPaint(
              painter: _CyberGridPainter(),
            ),
          ),

        // Main Page Content
        child,
      ],
    );
  }
}

class _CyberGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x0600E5FF)
      ..strokeWidth = 1.0;

    const step = 42.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Robotic Cybernetic Neon Button
class CyberNeonButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget? icon;
  final String label;
  final Color primaryColor;
  final Color textColor;
  final double height;
  final bool isLoading;
  final bool isOutlined;
  final double borderRadius;

  const CyberNeonButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.primaryColor = CyberColors.laserCyan,
    this.textColor = Colors.black,
    this.height = 52,
    this.isLoading = false,
    this.isOutlined = false,
    this.borderRadius = 14,
  });

  @override
  Widget build(BuildContext context) {
    if (isOutlined) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(color: primaryColor, width: 1.4),
          color: primaryColor.withValues(alpha: 0.08),
          boxShadow: [
            BoxShadow(
              color: primaryColor.withValues(alpha: 0.15),
              blurRadius: 10,
              spreadRadius: -2,
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(borderRadius),
            onTap: isLoading ? null : onPressed,
            child: Center(
              child: isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: primaryColor, strokeWidth: 2),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[
                          icon!,
                          const SizedBox(width: 8),
                        ],
                        Text(
                          label,
                          style: CyberTypography.hudTitle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: primaryColor,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: LinearGradient(
          colors: [
            primaryColor,
            primaryColor.withValues(alpha: 0.85),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withValues(alpha: 0.45),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(borderRadius),
          onTap: isLoading ? null : onPressed,
          child: Center(
            child: isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: textColor, strokeWidth: 2),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        icon!,
                        const SizedBox(width: 8),
                      ],
                      Text(
                        label,
                        style: CyberTypography.hudTitle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: textColor,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Robotic HUD Telemetry Badge
class CyberBadge extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color color;
  final bool hasGlow;

  const CyberBadge({
    super.key,
    required this.text,
    this.icon,
    this.color = CyberColors.laserCyan,
    this.hasGlow = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
        boxShadow: hasGlow
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.25),
                  blurRadius: 8,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            text,
            style: CyberTypography.mono(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}
