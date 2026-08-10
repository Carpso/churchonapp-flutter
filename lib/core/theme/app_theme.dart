import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/tenant_service.dart';
import '../config/app_constants.dart';

/// The official Church On App brand color — Sunflower Yellow.
const Color kSunflowerYellow = AppConstants.sunflowerYellow;

/// Semantic status colors (wire into ColorScheme so dark mode & tenant
/// theming work automatically). Exposed as an extension on ColorScheme.
extension AppColorScheme on ColorScheme {
  Color get success => brightness == Brightness.dark
      ? const Color(0xFF10B981) // Emerald 500
      : const Color(0xFF059669); // Emerald 600
  Color get warning => brightness == Brightness.dark
      ? const Color(0xFFF59E0B) // Amber 500
      : const Color(0xFFD97706); // Amber 600
  Color get info => brightness == Brightness.dark
      ? const Color(0xFF3B82F6) // Blue 500
      : const Color(0xFF2563EB); // Blue 600
  Color get neutral => brightness == Brightness.dark
      ? const Color(0xFF9CA3AF)
      : const Color(0xFF6B7280);
}

/// Helper to get status colors based on a status string.
class StatusColor {
  static Color fromString(BuildContext context, String status) {
    final scheme = Theme.of(context).colorScheme;
    final s = status.toLowerCase();
    if (s.contains('success') || s.contains('settled') || s.contains('active') || s.contains('verified') || s.contains('completed') || s.contains('paid')) {
      return scheme.success;
    }
    if (s.contains('fail') || s.contains('error') || s.contains('declined') || s.contains('cancel') || s.contains('rejected') || s.contains('expired')) {
      return scheme.error;
    }
    if (s.contains('pending') || s.contains('processing') || s.contains('waiting') || s.contains('open') || s.contains('warn')) {
      return scheme.warning;
    }
    return scheme.info;
  }
}

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

/// Bundled fonts served without network fetch (avoid offline font flash).
const Set<String> kBundledFonts = {
  'Plus Jakarta Sans',
  'Inter',
  'Roboto',
  'Playfair Display',
};

TextTheme _buildTextTheme(String fontFamily) {
  final factory = _fontFactories[fontFamily];
  if (factory != null) return factory();
  return GoogleFonts.plusJakartaSansTextTheme();
}

/// Minimum allowed UI font size — below this we fail the Google Play
/// accessibility review. Use this for tiny badges & helper text.
const double kMinUIFontSize = 11;

class AppTheme {
  static ThemeData getTheme(Tenant? tenant) {
    final primary = tenant?.primaryColor ?? kSunflowerYellow;
    final secondary = tenant?.accentColor ?? AppConstants.primaryDark;
    final surface = tenant?.surfaceColor ?? AppConstants.surfaceWarm;
    const surfaceWhite = Colors.white;
    final fontFamily = tenant?.fontFamily ?? 'Plus Jakarta Sans';
    // Guard runtime font load: if the tenant chose a font we don't bundle,
    // still allow it (google_fonts will fetch it) — but bundle the top 3.
    final baseTextTheme = _buildTextTheme(fontFamily);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      secondary: secondary,
      surface: surfaceWhite,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: surface,
      colorScheme: colorScheme,
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
        labelSmall: baseTextTheme.labelSmall?.copyWith(
          fontSize: kMinUIFontSize,
        ),
        labelMedium: baseTextTheme.labelMedium?.copyWith(fontSize: 12),
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
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: secondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: secondary,
          side: BorderSide(color: secondary.withValues(alpha: 0.3)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceWhite,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        labelStyle: const TextStyle(color: Colors.grey, fontSize: 14),
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.error, width: 2),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: secondary,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 4,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: TextStyle(
          color: secondary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        contentTextStyle: TextStyle(
          color: secondary.withValues(alpha: 0.8),
          fontSize: 14,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surfaceWhite,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        showDragHandle: true,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceWhite,
        selectedColor: primary.withValues(alpha: 0.15),
        labelStyle: TextStyle(
          color: secondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        side: BorderSide(color: secondary.withValues(alpha: 0.15)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? surfaceWhite
              : Colors.grey,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primary
              : Colors.grey.shade300,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? primary : null,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: primary.withValues(alpha: 0.15),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: secondary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: secondary,
        unselectedLabelColor: secondary.withValues(alpha: 0.5),
        indicatorColor: primary,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        unselectedLabelStyle: const TextStyle(fontSize: 13),
      ),
      dividerTheme: DividerThemeData(
        color: secondary.withValues(alpha: 0.1),
        thickness: 1,
      ),
      iconTheme: IconThemeData(color: secondary, size: 22),
      cardTheme: CardThemeData(
        color: surfaceWhite,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  static ThemeData getDarkTheme(Tenant? tenant) {
    final primary = tenant?.primaryColor ?? kSunflowerYellow;
    final surface = const Color(0xFF121212);
    final cardColor = const Color(0xFF1E1E1E);
    final fontFamily = tenant?.fontFamily ?? 'Plus Jakarta Sans';
    final baseTextTheme = _buildTextTheme(fontFamily);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      secondary: tenant?.accentColor ?? Colors.amberAccent,
      surface: cardColor,
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: surface,
      colorScheme: colorScheme,
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
        labelSmall: baseTextTheme.labelSmall?.copyWith(
          fontSize: kMinUIFontSize,
        ),
        labelMedium: baseTextTheme.labelMedium?.copyWith(fontSize: 12),
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
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white70,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1E1E1E),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        labelStyle: const TextStyle(color: Colors.white60, fontSize: 14),
        hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.error, width: 2),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF2C2C2C),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 4,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        contentTextStyle: const TextStyle(color: Colors.white70, fontSize: 14),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        showDragHandle: true,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF2C2C2C),
        selectedColor: primary.withValues(alpha: 0.25),
        labelStyle: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.black
              : Colors.white38,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? primary : Colors.white24,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? primary : null,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: primary.withValues(alpha: 0.15),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white54,
        indicatorColor: primary,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        unselectedLabelStyle: const TextStyle(fontSize: 13),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.white.withValues(alpha: 0.1),
        thickness: 1,
      ),
      iconTheme: const IconThemeData(color: Colors.white, size: 22),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
  const AppThemeData({
    required this.light,
    required this.dark,
    required this.mode,
  });
}

final appThemeProvider = Provider<AppThemeData>((ref) {
  final tenant = ref.watch(currentTenantProvider);
  return AppThemeData(
    light: AppTheme.getTheme(tenant),
    dark: AppTheme.getDarkTheme(tenant),
    mode: tenant?.themeMode ?? ThemeMode.light,
  );
});

final themeProvider = Provider<ThemeData>(
  (ref) => ref.watch(appThemeProvider).light,
);
final darkThemeProvider = Provider<ThemeData>(
  (ref) => ref.watch(appThemeProvider).dark,
);
final themeModeProvider = Provider<ThemeMode>(
  (ref) => ref.watch(appThemeProvider).mode,
);
