import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';

/// Checks if today is the user's birthday and shows a celebration modal.
/// Also records the wish so we don't repeat on the same day.
class BirthdayService {
  static Future<void> checkAndShow(BuildContext context, WidgetRef ref) async {
    final profile = ref.read(profileProvider).value;
    if (profile == null || !profile.isBirthdayToday) return;

    // Don't show if already shown today
    try {
      final existing = await Supabase.instance.client
          .from('birthday_wishes')
          .select('id')
          .eq('user_id', profile.id)
          .eq('wish_date', DateTime.now().toIso8601String().substring(0, 10))
          .maybeSingle();
      if (existing != null) return;
    } catch (_) {
      // Table might not exist yet, continue
    }

    if (!context.mounted) return;

    // Record the wish
    try {
      await Supabase.instance.client.from('birthday_wishes').insert({
        'user_id': profile.id,
        'wish_date': DateTime.now().toIso8601String().substring(0, 10),
        'age': profile.age,
      });
    } catch (e) {
      debugPrint('Error recording birthday wish: $e');
    }

    if (!context.mounted) return;

    // Show celebration modal
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _BirthdayModal(name: profile.name, age: profile.age),
    );
  }

  /// Send birthday email via Supabase Edge Function.
  static Future<void> sendBirthdayEmail({
    required String userId,
    required String email,
    required String name,
    required int age,
  }) async {
    try {
      await Supabase.instance.client.functions.invoke('send-birthday-email', body: {
        'user_id': userId,
        'email': email,
        'name': name,
        'age': age,
      });
    } catch (e) {
      debugPrint('BirthdayService sendEmail error: $e');
    }
  }
}

class _BirthdayModal extends StatelessWidget {
  final String name;
  final int age;

  const _BirthdayModal({required this.name, this.age = 0});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ageText = age > 0 ? ' (Turning $age!)' : '';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      backgroundColor: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Happy Birthday! 🎂', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            Text(
              'Happy Birthday$name$ageText!',
              style: TextStyle(fontSize: 16, color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'From all of us at Church On App — may God bless your new year with joy, health, and purpose.',
              style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primaryColor,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('Thank You!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
