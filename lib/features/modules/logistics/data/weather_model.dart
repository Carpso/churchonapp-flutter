import 'package:flutter/material.dart';

class HourlyForecast {
  final String time;
  final double temperature;
  final int weatherCode;

  HourlyForecast({
    required this.time,
    required this.temperature,
    required this.weatherCode,
  });
}

class DailyForecast {
  final String dayName;
  final double maxTemp;
  final double minTemp;
  final int weatherCode;

  DailyForecast({
    required this.dayName,
    required this.maxTemp,
    required this.minTemp,
    required this.weatherCode,
  });
}

class WeatherThemeData {
  final LinearGradient backgroundGradient;
  final LinearGradient cardGradient;
  final LinearGradient chipGradient;
  final Color primaryTextColor;
  final Color subtextColor;
  final String statusBadge;
  final IconData statusIcon;

  WeatherThemeData({
    required this.backgroundGradient,
    required this.cardGradient,
    required this.chipGradient,
    required this.primaryTextColor,
    required this.subtextColor,
    required this.statusBadge,
    required this.statusIcon,
  });
}

class WeatherData {
  final double temperature;
  final double feelsLike;
  final double humidity;
  final double windSpeed;
  final double precipitation;
  final int weatherCode;
  final String location;
  final DateTime timestamp;
  final List<HourlyForecast> hourly;
  final List<DailyForecast> daily;

  WeatherData({
    required this.temperature,
    required this.feelsLike,
    required this.humidity,
    required this.windSpeed,
    required this.precipitation,
    required this.weatherCode,
    this.location = 'Lusaka, Zambia',
    DateTime? timestamp,
    List<HourlyForecast>? hourly,
    List<DailyForecast>? daily,
  })  : timestamp = timestamp ?? DateTime.now(),
        hourly = hourly ?? _defaultHourly(),
        daily = daily ?? _defaultDaily();

  String get condition {
    if (weatherCode == 0) return 'Clear Sky';
    if (weatherCode == 1) return 'Mainly Clear';
    if (weatherCode == 2) return 'Partly Cloudy';
    if (weatherCode == 3) return 'Overcast';
    if (weatherCode == 45 || weatherCode == 48) return 'Foggy';
    if (weatherCode >= 51 && weatherCode <= 57) return 'Drizzle';
    if (weatherCode >= 61 && weatherCode <= 67) return 'Rain';
    if (weatherCode >= 71 && weatherCode <= 77) return 'Snow';
    if (weatherCode >= 80 && weatherCode <= 82) return 'Rain Showers';
    if (weatherCode >= 95) return 'Thunderstorm';
    return 'Clear Sky';
  }

  bool get isHot => temperature >= 28.0;
  bool get isRainy => weatherCode >= 51;
  bool get isNight {
    final hour = DateTime.now().hour;
    return hour < 6 || hour >= 19;
  }

  WeatherThemeData get theme {
    if (isNight) {
      return WeatherThemeData(
        backgroundGradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF0F172A)],
        ),
        cardGradient: const LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF334155)],
        ),
        chipGradient: const LinearGradient(
          colors: [Color(0xFF1E1B4B), Color(0xFF312E81)],
        ),
        primaryTextColor: Colors.white,
        subtextColor: Colors.white70,
        statusBadge: 'Night Sky',
        statusIcon: Icons.nights_stay,
      );
    }

    if (isRainy) {
      return WeatherThemeData(
        backgroundGradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1E293B), Color(0xFF334155), Color(0xFF475569)],
        ),
        cardGradient: const LinearGradient(
          colors: [Color(0xFF334155), Color(0xFF475569)],
        ),
        chipGradient: const LinearGradient(
          colors: [Color(0xFF2C3E50), Color(0xFF4A6572)],
        ),
        primaryTextColor: Colors.white,
        subtextColor: Colors.white70,
        statusBadge: 'Rainy',
        statusIcon: Icons.water_drop,
      );
    }

    if (isHot) {
      return WeatherThemeData(
        backgroundGradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF7C2D12), Color(0xFFC2410C), Color(0xFFEA580C)],
        ),
        cardGradient: const LinearGradient(
          colors: [Color(0xFFEA580C), Color(0xFFF97316)],
        ),
        chipGradient: const LinearGradient(
          colors: [Color(0xFFDC2626), Color(0xFFDC2626)],
        ),
        primaryTextColor: Colors.white,
        subtextColor: Colors.white70,
        statusBadge: 'Scorching Hot',
        statusIcon: Icons.wb_sunny,
      );
    }

    if (weatherCode == 3) {
      return WeatherThemeData(
        backgroundGradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF374151), Color(0xFF4B5563), Color(0xFF6B7280)],
        ),
        cardGradient: const LinearGradient(
          colors: [Color(0xFF4B5563), Color(0xFF6B7280)],
        ),
        chipGradient: const LinearGradient(
          colors: [Color(0xFF475569), Color(0xFF475569)],
        ),
        primaryTextColor: Colors.white,
        subtextColor: Colors.white70,
        statusBadge: 'Overcast Cloud',
        statusIcon: Icons.cloud,
      );
    }

    // Default Clear / Sunny Sky — single clear-blue chip
    return WeatherThemeData(
      backgroundGradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF0284C7), Color(0xFF0369A1), Color(0xFF075985)],
      ),
      cardGradient: const LinearGradient(
        colors: [Color(0xFF0284C7), Color(0xFF38BDF8)],
      ),
      chipGradient: const LinearGradient(
        colors: [Color(0xFF0369A1), Color(0xFF0369A1)],
      ),
      primaryTextColor: Colors.white,
      subtextColor: Colors.white70,
      statusBadge: 'Clear Sky',
      statusIcon: Icons.sunny,
    );
  }

  String get scriptureVerse {
    if (isRainy) {
      return '“He covers the sky with clouds; he supplies the earth with rain and makes grass grow on the hills.” — Psalm 147:8';
    }
    if (isHot) {
      return '“The LORD is your keeper; the LORD is your shade on your right hand. The sun shall not strike you by day.” — Psalm 121:5-6';
    }
    if (isNight) {
      return '“When I consider your heavens, the work of your fingers, the moon and the stars, which you have set in place...” — Psalm 8:3';
    }
    return '“The heavens declare the glory of God; the skies proclaim the work of his hands.” — Psalm 19:1';
  }

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    final current = json['current'] as Map<String, dynamic>? ?? {};
    final hourlyJson = json['hourly'] as Map<String, dynamic>? ?? {};
    final dailyJson = json['daily'] as Map<String, dynamic>? ?? {};

    final temp = (current['temperature_2m'] as num?)?.toDouble() ?? 28.0;
    final feels = (current['apparent_temperature'] as num?)?.toDouble() ?? 30.0;
    final hum = (current['relative_humidity_2m'] as num?)?.toDouble() ?? 45.0;
    final wind = (current['wind_speed_10m'] as num?)?.toDouble() ?? 12.0;
    final precip = (current['precipitation'] as num?)?.toDouble() ?? 0.0;
    final code = (current['weather_code'] as int?) ?? 0;

    // Parse hourly forecast
    final parsedHourly = <HourlyForecast>[];
    try {
      final times = hourlyJson['time'] as List? ?? [];
      final temps = hourlyJson['temperature_2m'] as List? ?? [];
      final codes = hourlyJson['weather_code'] as List? ?? [];

      for (int i = 0; i < times.length && i < 24; i++) {
        final rawTime = times[i].toString();
        final hourStr = rawTime.contains('T') ? rawTime.split('T')[1] : rawTime;
        parsedHourly.add(
          HourlyForecast(
            time: hourStr,
            temperature: (temps[i] as num).toDouble(),
            weatherCode: (codes[i] as num).toInt(),
          ),
        );
      }
    } catch (e) {
      debugPrint('WeatherModel: Error parsing hourly forecast: $e');
    }

    // Parse 5-day daily forecast
    final parsedDaily = <DailyForecast>[];
    try {
      final days = dailyJson['time'] as List? ?? [];
      final maxs = dailyJson['temperature_2m_max'] as List? ?? [];
      final mins = dailyJson['temperature_2m_min'] as List? ?? [];
      final dCodes = dailyJson['weather_code'] as List? ?? [];

      for (int i = 0; i < days.length && i < 5; i++) {
        parsedDaily.add(
          DailyForecast(
            dayName: _formatDayName(days[i].toString()),
            maxTemp: (maxs[i] as num).toDouble(),
            minTemp: (mins[i] as num).toDouble(),
            weatherCode: (dCodes[i] as num).toInt(),
          ),
        );
      }
    } catch (e) {
      debugPrint('WeatherModel: Error parsing daily forecast: $e');
    }

    return WeatherData(
      temperature: temp,
      feelsLike: feels,
      humidity: hum,
      windSpeed: wind,
      precipitation: precip,
      weatherCode: code,
      hourly: parsedHourly.isNotEmpty ? parsedHourly : _defaultHourly(),
      daily: parsedDaily.isNotEmpty ? parsedDaily : _defaultDaily(),
      timestamp: DateTime.now(),
    );
  }

  static String _formatDayName(String raw) {
    try {
      final dt = DateTime.parse(raw);
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[dt.weekday - 1];
    } catch (_) {
      return 'Day';
    }
  }

  static List<HourlyForecast> _defaultHourly() {
    return [
      HourlyForecast(time: '08:00', temperature: 22, weatherCode: 0),
      HourlyForecast(time: '12:00', temperature: 29, weatherCode: 0),
      HourlyForecast(time: '16:00', temperature: 31, weatherCode: 1),
      HourlyForecast(time: '20:00', temperature: 24, weatherCode: 2),
      HourlyForecast(time: '00:00', temperature: 19, weatherCode: 0),
    ];
  }

  static List<DailyForecast> _defaultDaily() {
    return [
      DailyForecast(dayName: 'Today', maxTemp: 31, minTemp: 19, weatherCode: 0),
      DailyForecast(dayName: 'Tomorrow', maxTemp: 29, minTemp: 18, weatherCode: 2),
      DailyForecast(dayName: 'Thu', maxTemp: 28, minTemp: 17, weatherCode: 61),
      DailyForecast(dayName: 'Fri', maxTemp: 30, minTemp: 19, weatherCode: 0),
      DailyForecast(dayName: 'Sat', maxTemp: 32, minTemp: 20, weatherCode: 0),
    ];
  }
}
