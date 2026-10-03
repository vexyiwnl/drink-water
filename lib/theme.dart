import 'package:flutter/material.dart';

const navy = Color(0xFF0A1628);
const card = Color(0xFF12223B);
const cardHigh = Color(0xFF1A3052);
const aqua = Color(0xFF22D3EE);
const aquaDeep = Color(0xFF0EA5E9);
const textMain = Color(0xFFE6EEF8);
const textMuted = Color(0xFF8DA2C0);

final _radius = BorderRadius.circular(16);

final appTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: navy,
  colorScheme: const ColorScheme.dark(
    primary: aqua,
    onPrimary: navy,
    secondary: aquaDeep,
    onSecondary: navy,
    surface: navy,
    onSurface: textMain,
    onSurfaceVariant: textMuted,
    surfaceContainerLow: card,
    surfaceContainer: card,
    surfaceContainerHigh: cardHigh,
    surfaceContainerHighest: cardHigh,
    outline: Color(0xFF2A4470),
    outlineVariant: Color(0xFF203858),
    error: Color(0xFFF87171),
  ),
  cardTheme: CardThemeData(
    color: card,
    elevation: 8,
    shadowColor: Colors.black.withValues(alpha: 0.5),
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      shape: RoundedRectangleBorder(borderRadius: _radius),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      shape: RoundedRectangleBorder(borderRadius: _radius),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      side: const BorderSide(color: Color(0xFF2A4470)),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: cardHigh,
    border: OutlineInputBorder(borderRadius: _radius, borderSide: BorderSide.none),
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: card,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
  ),
  snackBarTheme: SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    backgroundColor: cardHigh,
    contentTextStyle: const TextStyle(color: textMain),
    actionTextColor: aqua,
    shape: RoundedRectangleBorder(borderRadius: _radius),
  ),
  navigationBarTheme: NavigationBarThemeData(
    backgroundColor: card,
    indicatorColor: aqua.withValues(alpha: 0.18),
  ),
  navigationRailTheme: NavigationRailThemeData(
    backgroundColor: card,
    indicatorColor: aqua.withValues(alpha: 0.18),
  ),
);
