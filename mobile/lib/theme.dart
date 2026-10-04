import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens lifted from the MidMen mockups: near-black/navy backgrounds,
/// warm off-white cards, a single gold accent, generous rounding.
class MidManColors {
  static const ink = Color(0xFF12141C); // near-black background
  static const navy = Color(0xFF1B2233); // secondary dark surface
  static const cream = Color(0xFFF7F3EC); // card / light surface
  static const gold = Color(0xFFC9A24B); // accent
  static const goldDark = Color(0xFFA6822F);
  static const textDark = Color(0xFF1E1E1E);
  static const textMuted = Color(0xFF7A7A7A);
  static const success = Color(0xFF3FA76B);
  static const warning = Color(0xFFD9A441);
  static const danger = Color(0xFFC0392B);
}

ThemeData buildMidManTheme() {
  final base = ThemeData(brightness: Brightness.light, useMaterial3: true);
  final displayFont = GoogleFonts.playfairDisplayTextTheme();
  final bodyFont = GoogleFonts.interTextTheme();

  return base.copyWith(
    scaffoldBackgroundColor: MidManColors.cream,
    colorScheme: base.colorScheme.copyWith(
      primary: MidManColors.gold,
      onPrimary: Colors.black,
      secondary: MidManColors.navy,
      surface: MidManColors.cream,
      error: MidManColors.danger,
    ),
    textTheme: bodyFont.copyWith(
      displayLarge: displayFont.displayLarge,
      displayMedium: displayFont.displayMedium,
      displaySmall: displayFont.displaySmall,
      headlineMedium: displayFont.headlineMedium,
      headlineSmall: displayFont.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: MidManColors.cream,
      foregroundColor: MidManColors.textDark,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: EdgeInsets.zero,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: MidManColors.gold,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF1EEE7),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: MidManColors.textDark,
      unselectedItemColor: MidManColors.textMuted,
      type: BottomNavigationBarType.fixed,
      showUnselectedLabels: true,
    ),
  );
}

/// Status -> color, used for chips across Requests screens.
Color statusColor(String status) {
  switch (status) {
    case 'requested':
      return MidManColors.warning;
    case 'arranging':
    case 'approval_required':
    case 'payment_pending':
      return MidManColors.warning;
    case 'in_progress':
      return MidManColors.gold;
    case 'completed':
    case 'verified':
    case 'closed':
      return MidManColors.success;
    case 'rejected':
    case 'cancelled':
      return MidManColors.danger;
    default:
      return MidManColors.textMuted;
  }
}

String customerStageLabel(String status) {
  const stageMap = {
    'requested': 'Received',
    'arranging': 'Arranging',
    'approval_required': 'Arranging',
    'payment_pending': 'Arranging',
    'in_progress': 'In Progress',
    'completed': 'Completed',
    'verified': 'Completed',
    'closed': 'Completed',
    'rejected': 'Declined',
    'cancelled': 'Cancelled',
  };
  return stageMap[status] ?? status;
}
