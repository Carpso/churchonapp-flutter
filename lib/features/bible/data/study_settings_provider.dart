import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StudySettings {
  final String preferredTranslation;
  final int dailyMemoryVerseGoal;
  final TimeOfDayPreference reminderTime;
  final bool darkMode;
  final bool dailyReminders;

  const StudySettings({
    this.preferredTranslation = 'kjv',
    this.dailyMemoryVerseGoal = 3,
    this.reminderTime = const TimeOfDayPreference(hour: 7, minute: 0),
    this.darkMode = false,
    this.dailyReminders = true,
  });

  StudySettings copyWith({
    String? preferredTranslation,
    int? dailyMemoryVerseGoal,
    TimeOfDayPreference? reminderTime,
    bool? darkMode,
    bool? dailyReminders,
  }) {
    return StudySettings(
      preferredTranslation: preferredTranslation ?? this.preferredTranslation,
      dailyMemoryVerseGoal: dailyMemoryVerseGoal ?? this.dailyMemoryVerseGoal,
      reminderTime: reminderTime ?? this.reminderTime,
      darkMode: darkMode ?? this.darkMode,
      dailyReminders: dailyReminders ?? this.dailyReminders,
    );
  }

  Map<String, dynamic> toJson() => {
    'preferredTranslation': preferredTranslation,
    'dailyMemoryVerseGoal': dailyMemoryVerseGoal,
    'reminderHour': reminderTime.hour,
    'reminderMinute': reminderTime.minute,
    'darkMode': darkMode,
    'dailyReminders': dailyReminders,
  };

  factory StudySettings.fromJson(Map<String, dynamic> json) {
    return StudySettings(
      preferredTranslation: json['preferredTranslation'] as String? ?? 'kjv',
      dailyMemoryVerseGoal: json['dailyMemoryVerseGoal'] as int? ?? 3,
      reminderTime: TimeOfDayPreference(
        hour: json['reminderHour'] as int? ?? 7,
        minute: json['reminderMinute'] as int? ?? 0,
      ),
      darkMode: json['darkMode'] as bool? ?? false,
      dailyReminders: json['dailyReminders'] as bool? ?? true,
    );
  }
}

class TimeOfDayPreference {
  final int hour;
  final int minute;

  const TimeOfDayPreference({required this.hour, required this.minute});

  String get formatted => '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimeOfDayPreference &&
          hour == other.hour &&
          minute == other.minute;

  @override
  int get hashCode => hour.hashCode ^ minute.hashCode;
}

class StudySettingsNotifier extends Notifier<StudySettings> {
  static const _key = 'deep_study_settings';

  @override
  StudySettings build() {
    _loadSettings();
    return const StudySettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString(_key);
      if (data != null) {
        final decoded = jsonDecode(data) as Map<String, dynamic>;
        state = StudySettings.fromJson(decoded);
      }
    } catch (e) {
      debugPrint('Error loading study settings: $e');
    }
  }

  Future<void> saveSettings(StudySettings settings) async {
    state = settings;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(settings.toJson()));
  }

  Future<void> setTranslation(String translation) async {
    final updated = state.copyWith(preferredTranslation: translation);
    await saveSettings(updated);
  }

  Future<void> setDailyMemoryVerseGoal(int goal) async {
    final updated = state.copyWith(dailyMemoryVerseGoal: goal.clamp(1, 5));
    await saveSettings(updated);
  }

  Future<void> setReminderTime(TimeOfDayPreference time) async {
    final updated = state.copyWith(reminderTime: time);
    await saveSettings(updated);
  }

  Future<void> setDarkMode(bool value) async {
    final updated = state.copyWith(darkMode: value);
    await saveSettings(updated);
  }

  Future<void> setDailyReminders(bool value) async {
    final updated = state.copyWith(dailyReminders: value);
    await saveSettings(updated);
  }
}

final studySettingsProvider = NotifierProvider<StudySettingsNotifier, StudySettings>(StudySettingsNotifier.new);
