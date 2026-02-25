import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/tenant_service.dart';

class AppTheme {
  static ThemeData getTheme(Tenant? tenant) {
    final primary = tenant?.primaryColor ?? const Color(0xFFFFD700);
    final charcoal = tenant?.accentColor ?? const Color(0xFF1A1A1A);
    const ivory = Color(0xFFFFFAEB);
    const surfaceWhite = Colors.white;

    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: ivory,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        secondary: charcoal,
        surface: surfaceWhite,
      ),
      textTheme: GoogleFonts.plusJakartaSansTextTheme().copyWith(
        displayLarge: GoogleFonts.plusJakartaSans(
          color: charcoal,
          fontWeight: FontWeight.bold,
          fontSize: 32,
        ),
        titleLarge: GoogleFonts.plusJakartaSans(
          color: charcoal,
          fontWeight: FontWeight.bold,
          fontSize: 22,
        ),
        bodyLarge: GoogleFonts.inter(
          color: charcoal,
          fontSize: 16,
        ),
        bodyMedium: GoogleFonts.inter(
          color: charcoal.withOpacity(0.8),
          fontSize: 14,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: charcoal,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: charcoal,
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

  static LinearGradient getGradient(Tenant? tenant) {
    final primary = tenant?.primaryColor ?? const Color(0xFFFFD700);
    return LinearGradient(
      colors: [primary, primary.withOpacity(0.8)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }
}

final themeProvider = Provider<ThemeData>((ref) {
  final tenant = ref.watch(currentTenantProvider);
  return AppTheme.getTheme(tenant);
});

