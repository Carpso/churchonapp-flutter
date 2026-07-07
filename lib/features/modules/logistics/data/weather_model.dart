class WeatherData {
  final double temperature;
  final double feelsLike;
  final double humidity;
  final double windSpeed;
  final double precipitation;
  final int weatherCode;
  final String location;
  final DateTime timestamp;

  WeatherData({
    required this.temperature,
    required this.feelsLike,
    required this.humidity,
    required this.windSpeed,
    required this.precipitation,
    required this.weatherCode,
    this.location = 'Lusaka, Zambia',
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  String get condition {
    if (weatherCode == 0) return 'Clear Sky';
    if (weatherCode <= 3) return ['Mainly Clear', 'Partly Cloudy', 'Overcast'][weatherCode - 1];
    if (weatherCode == 45 || weatherCode == 48) return 'Foggy';
    if (weatherCode >= 51 && weatherCode <= 57) return 'Drizzle';
    if (weatherCode >= 61 && weatherCode <= 67) return 'Rain';
    if (weatherCode >= 71 && weatherCode <= 77) return 'Snow';
    if (weatherCode >= 80 && weatherCode <= 82) return 'Rain Showers';
    if (weatherCode >= 95) return 'Thunderstorm';
    return 'Unknown';
  }

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    final current = json['current'] as Map<String, dynamic>? ?? {};
    return WeatherData(
      temperature: (current['temperature_2m'] as num?)?.toDouble() ?? 28.0,
      feelsLike: (current['apparent_temperature'] as num?)?.toDouble() ?? 30.0,
      humidity: (current['relative_humidity_2m'] as num?)?.toDouble() ?? 45.0,
      windSpeed: (current['wind_speed_10m'] as num?)?.toDouble() ?? 12.0,
      precipitation: (current['precipitation'] as num?)?.toDouble() ?? 5.0,
      weatherCode: (current['weather_code'] as int?) ?? 0,
      timestamp: DateTime.now(),
    );
  }
}
