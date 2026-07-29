import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Smart in-app rating prompt that fires at high-satisfaction moments.
/// Cooldown: won't ask again within 7 days. Max 3 prompts per install lifetime.
class RatingService {
  static const _kLastPromptKey = 'rating_last_prompt';
  static const _kPromptCountKey = 'rating_prompt_count';
  static const _kCooldownDays = 7;
  static const _kMaxPrompts = 3;

  /// Call after a high-satisfaction moment (quiz perfect score, payment success,
  /// streak milestone, etc). Returns true if the prompt was shown.
  static Future<bool> promptIfNeeded(BuildContext context, {String reason = ''}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastStr = prefs.getString(_kLastPromptKey);
      final count = prefs.getInt(_kPromptCountKey) ?? 0;

      if (count >= _kMaxPrompts) return false;

      if (lastStr != null) {
        final last = DateTime.tryParse(lastStr);
        if (last != null && DateTime.now().difference(last).inDays < _kCooldownDays) {
          return false;
        }
      }

      final inAppReview = InAppReview.instance;
      if (!await inAppReview.isAvailable()) return false;

      // Small delay so the user sees the success screen first
      await Future.delayed(const Duration(seconds: 2));
      if (!context.mounted) return false;

      await inAppReview.requestReview();

      await prefs.setString(_kLastPromptKey, DateTime.now().toIso8601String());
      await prefs.setInt(_kPromptCountKey, count + 1);
      return true;
    } catch (e) {
      debugPrint('RatingService prompt error: $e');
      return false;
    }
  }

  /// Force open the store listing (e.g., from a "Rate Us" button).
  static Future<void> openStoreListing() async {
    try {
      final inAppReview = InAppReview.instance;
      if (await inAppReview.isAvailable()) {
        await inAppReview.openStoreListing();
      }
    } catch (e) {
      debugPrint('RatingService openStore error: $e');
    }
  }
}
