import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Brand Colors
  static const Color primarySapphire = Color(0xFF0A192F);
  static const Color secondaryNavy = Color(0xFF112240);
  static const Color accentNeonCyan = Color(0xFF64FFDA);
  static const Color accentNeonPurple = Color(0xFFBC13FE);
  static const Color textLight = Color(0xFFCCD6F6);
  static const Color textDim = Color(0xFF8892B0);
  static const Color alertRed = Color(0xFFFF4D4D);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: primarySapphire,
      primaryColor: accentNeonCyan,
      colorScheme: const ColorScheme.dark(
        primary: accentNeonCyan,
        secondary: accentNeonPurple,
        surface: secondaryNavy,
        onSurface: textLight,
        error: alertRed,
      ),
      textTheme: GoogleFonts.outfitTextTheme(
        const TextTheme(
          displayLarge: TextStyle(color: textLight, fontWeight: FontWeight.bold),
          displayMedium: TextStyle(color: textLight, fontWeight: FontWeight.bold),
          bodyLarge: TextStyle(color: textLight),
          bodyMedium: TextStyle(color: textDim),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: accentNeonCyan,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentNeonCyan,
          foregroundColor: primarySapphire,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          textStyle: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      cardTheme: CardThemeData(
        color: secondaryNavy,
        elevation: 10,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: accentNeonCyan.withOpacity(0.1), width: 1),
        ),
      ),
    );
  }
}

// Glassmorphic Decoration Utility
BoxDecoration glassDecoration({double opacity = 0.1}) {
  return BoxDecoration(
    color: AppTheme.secondaryNavy.withOpacity(opacity),
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: Colors.white.withOpacity(0.05), width: 1),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.2),
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
    ],
  );
}
