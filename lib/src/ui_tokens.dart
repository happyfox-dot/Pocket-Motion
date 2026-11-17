// Keep the upstream Flutter 3.47 API while also building on newer SDKs.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

/// Unified design tokens across all pages, panels, and dialogs.
abstract final class UiTokens {
  static const Color canvas = Color(0xFFF4F6F9);
  static const Color sidebarBg = Color(0xFFF8FAFC);
  static const Color surface = Colors.white;
  static const Color subtleBg = Color(0xFFF8FAFC);
  static const Color mutedBg = Color(0xFFF1F5F9);

  static const Color border = Color(0xFFE2E8F0);
  static const Color borderStrong = Color(0xFFCBD5E1);

  static const Color primary = Color(0xFF0D9488);
  static const Color primaryDark = Color(0xFF0F766E);
  static const Color primaryTint = Color(0xFFF0FDFA);
  static const Color primarySoft = Color(0xFFE6FFFA);
  static const Color primaryBorder = Color(0xFF99F6E4);

  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF334155);
  static const Color textMuted = Color(0xFF64748B);
  static const Color textSubtle = Color(0xFF94A3B8);

  static const Color success = Color(0xFF059669);
  static const Color successTint = Color(0xFFECFDF5);
  static const Color successBorder = Color(0xFFA7F3D0);

  static const Color warning = Color(0xFFB45309);
  static const Color warningTint = Color(0xFFFFFBEB);
  static const Color warningBorder = Color(0xFFFDE68A);

  static const Color danger = Color(0xFFDC2626);
  static const Color dangerTint = Color(0xFFFEF2F2);
  static const Color dangerBorder = Color(0xFFFECACA);

  static const Color darkStage = Color(0xFF0B0F17);
  static const Color consoleBg = Color(0xFF0F172A);

  static const double cardRadius = 12;
  static const double controlRadius = 8;
  static const double badgeRadius = 5;
  static const double compactFieldHeight = 30;
}
