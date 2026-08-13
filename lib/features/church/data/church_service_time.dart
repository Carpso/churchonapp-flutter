import 'package:flutter/material.dart';

/// A recurring weekly church service entry stored in `churches.service_times`.
class ChurchServiceTime {
  final int dayOfWeek; // 1 = Monday ... 7 = Sunday
  final String title;
  final TimeOfDay startTime;
  final TimeOfDay? endTime;
  final String? description;
  final bool enableCarpso;

  const ChurchServiceTime({
    required this.dayOfWeek,
    required this.title,
    required this.startTime,
    this.endTime,
    this.description,
    this.enableCarpso = true,
  });

  factory ChurchServiceTime.fromMap(Map<String, dynamic> map) {
    TimeOfDay parseTime(dynamic v) {
      if (v == null) return const TimeOfDay(hour: 9, minute: 0);
      final parts = v.toString().split(':');
      return TimeOfDay(
        hour: int.tryParse(parts[0]) ?? 9,
        minute: int.tryParse(parts[1]) ?? 0,
      );
    }

    return ChurchServiceTime(
      dayOfWeek: (map['day_of_week'] ?? map['day'] ?? 7) as int,
      title: (map['title'] ?? 'Service').toString(),
      startTime: parseTime(map['start_time'] ?? map['start']),
      endTime: map['end_time'] != null || map['end'] != null
          ? parseTime(map['end_time'] ?? map['end'])
          : null,
      description: map['description']?.toString(),
      enableCarpso: map['enable_carpso'] != false,
    );
  }

  Map<String, dynamic> toMap() {
    String fmt(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return {
      'day_of_week': dayOfWeek,
      'title': title,
      'start_time': fmt(startTime),
      if (endTime != null) 'end_time': fmt(endTime!),
      if (description != null && description!.isNotEmpty) 'description': description,
      'enable_carpso': enableCarpso,
    };
  }

  String get formattedTime {
    final s = _formatTimeOfDay(startTime);
    if (endTime == null) return s;
    return '$s - ${_formatTimeOfDay(endTime!)}';
  }

  static String _formatTimeOfDay(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final period = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $period';
  }
}

/// Parses `churches.service_times` (JSONB array or map) into a list.
List<ChurchServiceTime> parseServiceTimes(dynamic raw) {
  if (raw == null) return [];
  if (raw is List) {
    return raw
        .whereType<Map<String, dynamic>>()
        .map(ChurchServiceTime.fromMap)
        .toList();
  }
  if (raw is Map) {
    // Legacy map shape { "Sunday": "09:00 - 11:30", ... } — best-effort.
    final List<ChurchServiceTime> out = [];
    final dayMap = {
      'Monday': 1, 'Tuesday': 2, 'Wednesday': 3, 'Thursday': 4,
      'Friday': 5, 'Saturday': 6, 'Sunday': 7,
    };
    raw.forEach((k, v) {
      final day = dayMap[k.toString()];
      if (day == null) return;
      final text = v.toString();
      final parts = text.split('-').map((s) => s.trim()).toList();
      out.add(ChurchServiceTime(
        dayOfWeek: day,
        title: '$k Service',
        startTime: _parseTimeString(parts.first),
        endTime: parts.length > 1 ? _parseTimeString(parts.last) : null,
      ));
    });
    return out;
  }
  return [];
}

TimeOfDay _parseTimeString(String s) {
  try {
    final parts = s.split(':');
    return TimeOfDay(
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1].split(' ').first),
    );
  } catch (_) {
    return const TimeOfDay(hour: 9, minute: 0);
  }
}
