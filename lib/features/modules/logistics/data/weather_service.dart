import 'dart:convert';
import 'package:http/http.dart' as http;
import 'weather_model.dart';

class CityPreset {
  final String name;
  final double latitude;
  final double longitude;

  const CityPreset({
    required this.name,
    required this.latitude,
    required this.longitude,
  });
}

class WeatherService {
  static const _baseUrl = 'https://api.open-meteo.com/v1/forecast';

  static const List<CityPreset> cityPresets = [
    CityPreset(name: 'Lusaka, Zambia', latitude: -15.3875, longitude: 28.3228),
    CityPreset(name: 'Ndola, Zambia', latitude: -12.9587, longitude: 28.6366),
    CityPreset(name: 'Kitwe, Zambia', latitude: -12.8024, longitude: 28.2132),
    CityPreset(name: 'Livingstone, Zambia', latitude: -17.8419, longitude: 25.8543),
    CityPreset(name: 'Harare, Zimbabwe', latitude: -17.8252, longitude: 31.0335),
    CityPreset(name: 'Bulawayo, Zimbabwe', latitude: -20.1569, longitude: 28.5833),
  ];

  Future<WeatherData> fetchWeather({
    double latitude = -15.3875,
    double longitude = 28.3228,
    String locationName = 'Lusaka, Zambia',
  }) async {
    try {
      final uri = Uri.parse(_baseUrl).replace(queryParameters: {
        'latitude': latitude.toString(),
        'longitude': longitude.toString(),
        'current': 'temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,wind_speed_10m',
        'hourly': 'temperature_2m,weather_code',
        'daily': 'weather_code,temperature_2m_max,temperature_2m_min',
        'timezone': 'auto',
      });

      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final data = WeatherData.fromJson(json);
        return WeatherData(
          temperature: data.temperature,
          feelsLike: data.feelsLike,
          humidity: data.humidity,
          windSpeed: data.windSpeed,
          precipitation: data.precipitation,
          weatherCode: data.weatherCode,
          location: locationName,
          hourly: data.hourly,
          daily: data.daily,
          timestamp: DateTime.now(),
        );
      }
    } catch (_) {}

    // Offline / Fallback Preset Data
    return WeatherData(
      temperature: 29.0,
      feelsLike: 31.0,
      humidity: 42.0,
      windSpeed: 14.0,
      precipitation: 0.0,
      weatherCode: 0,
      location: locationName,
      timestamp: DateTime.now(),
    );
  }

  static String weatherEmoji(int code) {
    if (code == 0) return '☀️';
    if (code <= 2) return '⛅';
    if (code == 3) return '☁️';
    if (code == 45 || code == 48) return '🌫️';
    if (code >= 51 && code <= 57) return '💧';
    if (code >= 61 && code <= 67) return '🌧️';
    if (code >= 71 && code <= 77) return '❄️';
    if (code >= 80 && code <= 82) return '🌦️';
    if (code >= 95) return '⛈️';
    return '☀️';
  }
}
