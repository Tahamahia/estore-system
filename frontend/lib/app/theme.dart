import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ─── Color Palette ───────────────────────────────────────
  static const Color primary = Color(0xFF6366F1);      // Indigo-500
  static const Color primaryDark = Color(0xFF4F46E5);   // Indigo-600
  static const Color secondary = Color(0xFF06B6D4);     // Cyan-500
  static const Color accent = Color(0xFFF59E0B);        // Amber-500
  static const Color success = Color(0xFF10B981);       // Emerald-500
  static const Color warning = Color(0xFFF97316);       // Orange-500
  static const Color error = Color(0xFFEF4444);         // Red-500

  // Dark theme surface colors
  static const Color darkBg = Color(0xFF0F172A);        // Slate-900
  static const Color darkSurface = Color(0xFF1E293B);   // Slate-800
  static const Color darkCard = Color(0xFF334155);      // Slate-700
  static const Color darkBorder = Color(0xFF475569);    // Slate-600

  // Light theme
  static const Color lightBg = Color(0xFFF8FAFC);
  static const Color lightSurface = Color(0xFFFFFFFF);

  // ─── Dark Theme ──────────────────────────────────────────
  static ThemeData get darkTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: darkBg,
    colorScheme: const ColorScheme.dark(
      primary: primary,
      secondary: secondary,
      surface: darkSurface,
      error: error,
    ),
    textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
    appBarTheme: AppBarTheme(
      backgroundColor: darkSurface,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.inter(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    ),
    cardTheme: CardThemeData(
      color: darkSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: darkBorder, width: 1),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: darkCard,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: darkBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: darkBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    dividerTheme: const DividerThemeData(color: darkBorder, thickness: 1),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: darkSurface,
      selectedIconTheme: const IconThemeData(color: primary),
      unselectedIconTheme: const IconThemeData(color: Colors.white54),
      indicatorColor: primary.withValues(alpha: 0.15),
    ),
  );

  // ─── Light Theme ─────────────────────────────────────────
  static ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: lightBg,
    colorScheme: const ColorScheme.light(
      primary: primary,
      secondary: secondary,
      surface: lightSurface,
      error: error,
    ),
    textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
    appBarTheme: AppBarTheme(
      backgroundColor: lightSurface,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.inter(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: Colors.black87,
      ),
    ),
  );
}
