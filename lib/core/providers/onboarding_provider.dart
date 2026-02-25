import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';


class OnboardingNotifier extends Notifier<AsyncValue<bool>> {
  @override
  AsyncValue<bool> build() {
    _init();
    return const AsyncValue.loading();
  }


  Future<void> _init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = AsyncValue.data(prefs.getBool('seen_onboarding') ?? false);
    } catch (e) {
      debugPrint("Onboarding init error: $e");
      state = const AsyncValue.data(true); // Fallback to seen or skip
    }
  }


  Future<void> completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('seen_onboarding', true);
    state = const AsyncValue.data(true);
  }
}

final onboardingProvider = NotifierProvider<OnboardingNotifier, AsyncValue<bool>>(() {
  return OnboardingNotifier();
});

