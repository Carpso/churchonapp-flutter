import 'package:flutter/material.dart';

/// Centralized application constants for Church On App
class AppConstants {
  // Brand & Platform Identifiers
  static const String appName = 'Church On App';
  static const String brandPrefix = 'COA';
  static const String defaultCountry = 'Zambia';
  static const String defaultCountryIso = 'ZM';

  // Brand Palette
  static const Color sunflowerYellow = Color(0xFFFFDA03);
  static const Color primaryDark = Color(0xFF1A1A1A);
  static const Color surfaceWarm = Color(0xFFFFFAEB);
  static const Color accentGreen = Color(0xFF10B981);
  static const Color accentRed = Color(0xFFEF4444);

  // Timeouts & Retry Limits
  static const Duration apiTimeout = Duration(seconds: 30);
  static const Duration lipilaPollInterval = Duration(seconds: 4);
  static const int lipilaMaxAttempts = 30;
  static const int offlineSyncRetryLimit = 3;

  // Pagination & Display Limits
  static const int defaultPageSize = 20;
  static const int maxRecentHistoryItems = 50;

  // Church Coin Reward Scale
  static const int coinsDailyOpenReward = 15;
  static const int coinsFastCompleteReward = 50;
  static const int coinsReferralReward = 100;
  static const int coinsAttendanceReward = 20;
}
