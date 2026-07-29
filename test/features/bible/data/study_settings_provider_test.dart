import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:church_on_app/features/bible/data/study_settings_provider.dart';

void main() {
  group('StudySettings', () {
    test('default settings are correct', () {
      const settings = StudySettings();
      expect(settings.preferredTranslation, 'kjv');
      expect(settings.dailyMemoryVerseGoal, 3);
      expect(settings.darkMode, false);
      expect(settings.dailyReminders, true);
      expect(settings.reminderTime.hour, 7);
      expect(settings.reminderTime.minute, 0);
    });

    test('copyWith updates fields correctly', () {
      const settings = StudySettings();
      final updated = settings.copyWith(
        preferredTranslation: 'NIV',
        dailyMemoryVerseGoal: 5,
        darkMode: true,
      );
      expect(updated.preferredTranslation, 'NIV');
      expect(updated.dailyMemoryVerseGoal, 5);
      expect(updated.darkMode, true);
      expect(updated.dailyReminders, true);
    });
  });

  group('StudySettingsNotifier', () {
    test('initial state has default settings', () {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          studySettingsProvider.overrideWith(() => StudySettingsNotifier()),
        ],
      );
      final settings = container.read(studySettingsProvider);
      expect(settings.preferredTranslation, 'kjv');
      expect(settings.dailyMemoryVerseGoal, 3);
      expect(settings.darkMode, false);
      container.dispose();
    });

    test('updateTranslation saves selection', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          studySettingsProvider.overrideWith(() => StudySettingsNotifier()),
        ],
      );
      final notifier = container.read(studySettingsProvider.notifier);
      await notifier.setTranslation('NIV');
      final settings = container.read(studySettingsProvider);
      expect(settings.preferredTranslation, 'NIV');
      container.dispose();
    });

    test('updateMemoryVerseGoal saves goal', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          studySettingsProvider.overrideWith(() => StudySettingsNotifier()),
        ],
      );
      final notifier = container.read(studySettingsProvider.notifier);
      await notifier.setDailyMemoryVerseGoal(5);
      final settings = container.read(studySettingsProvider);
      expect(settings.dailyMemoryVerseGoal, 5);
      container.dispose();
    });

    test('toggleDarkMode toggles correctly', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          studySettingsProvider.overrideWith(() => StudySettingsNotifier()),
        ],
      );
      final notifier = container.read(studySettingsProvider.notifier);
      await notifier.setDarkMode(true);
      expect(container.read(studySettingsProvider).darkMode, true);
      await notifier.setDarkMode(false);
      expect(container.read(studySettingsProvider).darkMode, false);
      container.dispose();
    });

    test('memory verse goal is clamped between 1 and 5', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          studySettingsProvider.overrideWith(() => StudySettingsNotifier()),
        ],
      );
      final notifier = container.read(studySettingsProvider.notifier);
      await notifier.setDailyMemoryVerseGoal(10);
      expect(container.read(studySettingsProvider).dailyMemoryVerseGoal, 5);
      await notifier.setDailyMemoryVerseGoal(0);
      expect(container.read(studySettingsProvider).dailyMemoryVerseGoal, 1);
      container.dispose();
    });
  });
}
