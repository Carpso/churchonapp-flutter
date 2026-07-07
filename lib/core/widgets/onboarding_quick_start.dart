import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final onboardingDismissedProvider = FutureProvider<bool>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool('onboarding_dismissed') ?? false;
});

class OnboardingQuickStart extends ConsumerStatefulWidget {
  const OnboardingQuickStart({super.key});

  @override
  ConsumerState<OnboardingQuickStart> createState() => _OnboardingQuickStartState();
}

class _OnboardingQuickStartState extends ConsumerState<OnboardingQuickStart> {
  Future<void> _dismiss() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_dismissed', true);
    ref.invalidate(onboardingDismissedProvider);
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);
    final dismissedAsync = ref.watch(onboardingDismissedProvider);

    final profile = profileAsync.asData?.value;
    final dismissed = dismissedAsync.asData?.value ?? false;

    if (dismissed) return const SizedBox.shrink();
    if (profile != null && profile.tenantId != null) return const SizedBox.shrink();

    final items = [
      ('Set up your profile', LucideIcons.user),
      ('Find your church', LucideIcons.church),
      ('Explore sermons', LucideIcons.bookOpen),
      ('Connect with community', LucideIcons.users),
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).primaryColor.withValues(alpha: 0.15),
            Theme.of(context).primaryColor.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).primaryColor.withValues(alpha: 0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Welcome to Church On App!',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 72,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: items.map((item) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(item.$2, size: 12, color: Theme.of(context).primaryColor),
                              const SizedBox(width: 6),
                              Text(
                                item.$1,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: _dismiss,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.05),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.close, size: 16, color: Colors.grey.shade500),
                  ),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: _dismiss,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'GET STARTED',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
