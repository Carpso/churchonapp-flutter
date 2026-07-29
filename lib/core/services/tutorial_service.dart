import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TutorialService {
  static const _keyHomeTutorial = 'has_seen_home_tutorial';

  Future<bool> hasSeenHomeTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyHomeTutorial) ?? false;
  }

  Future<void> markHomeTutorialSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHomeTutorial, true);
  }
}

final tutorialServiceProvider = Provider((ref) => TutorialService());
