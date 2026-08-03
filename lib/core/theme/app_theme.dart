import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/tenant_service.dart';
import '../config/app_constants.dart';

/// The official Church On App brand color — Sunflower Yellow.
const Color kSunflowerYellow = AppConstants.sunflowerYellow;

final Map<String, TextTheme Function()> _fontFactories = {
  'Plus Jakarta Sans': () => GoogleFonts.plusJakartaSansTextTheme(),
  'Inter': () => GoogleFonts.interTextTheme(),
  'Roboto': () => GoogleFonts.robotoTextTheme(),
  'Montserrat': () => GoogleFonts.montserratTextTheme(),
  'Playfair Display': () => GoogleFonts.playfairDisplayTextTheme(),
  'Lato': () => GoogleFonts.latoTextTheme(),
  'Poppins': () => GoogleFonts.poppinsTextTheme(),
  'Merriweather': () => GoogleFonts.merriweatherTextTheme(),
  'Open Sans': () => GoogleFonts.openSansTextTheme(),
  'Raleway': () => GoogleFonts.ralewayTextTheme(),
  'Nunito': () => GoogleFonts.nunitoTextTheme(),
  'Source Sans 3': () => GoogleFonts.sourceSans3TextTheme(),
  'Oswald': () => GoogleFonts.oswaldTextTheme(),
  'PT Serif': () => GoogleFonts.ptSerifTextTheme(),
  'Work Sans': () => GoogleFonts.workSansTextTheme(),
  'DM Sans': () => GoogleFonts.dmSansTextTheme(),
  'Noto Sans': () => GoogleFonts.notoSansTextTheme(),
  'Libre Baskerville': () => GoogleFonts.libreBaskervilleTextTheme(),
  'Cabin': () => GoogleFonts.cabinTextTheme(),
  'Figtree': () => GoogleFonts.figtreeTextTheme(),
  'Urbanist': () => GoogleFonts.urbanistTextTheme(),
  'Sora': () => GoogleFonts.soraTextTheme(),
  'Karla': () => GoogleFonts.karlaTextTheme(),
  'Manrope': () => GoogleFonts.manropeTextTheme(),
  'Outfit': () => GoogleFonts.outfitTextTheme(),
  'Barlow': () => GoogleFonts.barlowTextTheme(),
  'Commissioner': () => GoogleFonts.commissionerTextTheme(),
  'Epilogue': () => GoogleFonts.epilogueTextTheme(),
  'Lexend': () => GoogleFonts.lexendTextTheme(),
  'Public Sans': () => GoogleFonts.publicSansTextTheme(),
  'Space Grotesk': () => GoogleFonts.spaceGroteskTextTheme(),
  'Syne': () => GoogleFonts.syneTextTheme(),
  'Zilla Slab': () => GoogleFonts.zillaSlabTextTheme(),
};

TextTheme _buildTextTheme(String fontFamily) {
  final factory = _fontFactories[fontFamily];
  if (factory != null) return factory();
  return GoogleFonts.plusJakartaSansTextTheme();
}

class AppTheme {
  static ThemeData getTheme(Tenant? tenant) {
    final primary = tenant?.primaryColor ?? kSunflowerYellow;
    final secondary = tenant?.accentColor ?? AppConstants.primaryDark;
    final surface = tenant?.surfaceColor ?? AppConstants.surfaceWarm;
    const surfaceWhite = Colors.white;
    final fontFamily = tenant?.fontFamily ?? 'Plus Jakarta Sans';
    final baseTextTheme = _buildTextTheme(fontFamily);

    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: surface,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        secondary: secondary,
        surface: surfaceWhite,
        brightness: Brightness.light,
      ),
      textTheme: baseTextTheme.copyWith(
        displayLarge: baseTextTheme.displayLarge?.copyWith(
          color: secondary,
          fontWeight: FontWeight.bold,
          fontSize: 32,
        ),
        titleLarge: baseTextTheme.titleLarge?.copyWith(
          color: secondary,
          fontWeight: FontWeight.bold,
          fontSize: 22,
        ),
        bodyLarge: baseTextTheme.bodyLarge?.copyWith(
          color: secondary,
          fontSize: 16,
        ),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(
          color: secondary.withValues(alpha: 0.8),
          fontSize: 14,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: secondary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: secondary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      cardTheme: CardThemeData(
        color: surfaceWhite,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }

  static ThemeData getDarkTheme(Tenant? tenant) {
    final primary = tenant?.primaryColor ?? kSunflowerYellow;
    final surface = const Color(0xFF121212);
    final cardColor = const Color(0xFF1E1E1E);
    final fontFamily = tenant?.fontFamily ?? 'Plus Jakarta Sans';
    final baseTextTheme = _buildTextTheme(fontFamily);

    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: surface,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        secondary: tenant?.accentColor ?? Colors.amberAccent,
        surface: cardColor,
        brightness: Brightness.dark,
      ),
      textTheme: baseTextTheme.copyWith(
        displayLarge: baseTextTheme.displayLarge?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 32,
        ),
        titleLarge: baseTextTheme.titleLarge?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 22,
        ),
        bodyLarge: baseTextTheme.bodyLarge?.copyWith(
          color: Colors.white70,
          fontSize: 16,
        ),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(
          color: Colors.white60,
          fontSize: 14,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.black,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }

  static LinearGradient getGradient(Tenant? tenant) {
    final primary = tenant?.primaryColor ?? kSunflowerYellow;
    return LinearGradient(
      colors: [primary, primary.withValues(alpha: 0.8)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }
}

class AppThemeData {
  final ThemeData light;
  final ThemeData dark;
  final ThemeMode mode;
  const AppThemeData({required this.light, required this.dark, required this.mode});
}

final appThemeProvider = Provider<AppThemeData>((ref) {
  final tenant = ref.watch(currentTenantProvider);
  return AppThemeData(
    light: AppTheme.getTheme(tenant),
    dark: AppTheme.getDarkTheme(tenant),
    mode: tenant?.themeMode ?? ThemeMode.light,
  );
});

final themeProvider = Provider<ThemeData>((ref) => ref.watch(appThemeProvider).light);
final darkThemeProvider = Provider<ThemeData>((ref) => ref.watch(appThemeProvider).dark);
final themeModeProvider = Provider<ThemeMode>((ref) => ref.watch(appThemeProvider).mode);
