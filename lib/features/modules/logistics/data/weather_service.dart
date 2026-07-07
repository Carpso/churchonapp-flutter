import 'dart:convert';
import 'package:http/http.dart' as http;
import 'weather_model.dart';

class WeatherService {
  static const _baseUrl = 'https://api.open-meteo.com/v1/forecast';

  Future<WeatherData> fetchWeather({
    double latitude = -15.3875,
    double longitude = 28.3228,
  }) async {
    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      'latitude': latitude.toString(),
      'longitude': longitude.toString(),
      'current': 'temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,wind_speed_10m',
      'timezone': 'auto',
    });

    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Weather API failed: ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return WeatherData.fromJson(json);
  }

  static String weatherEmoji(int code) {
    if (code == 0) return '\u2600\uFE0F';
    if (code <= 2) return '\u26C5';
    if (code == 3) return '\u2601\uFE0F';
    if (code == 45 || code == 48) return '\uD83C\uDF2B\uFE0F';
    if (code >= 51 && code <= 57) return '\uD83D\uDCA7';
    if (code >= 61 && code <= 67) return '\uD83C\uDF27\uFE0F';
    if (code >= 71 && code <= 77) return '\u2744\uFE0F';
    if (code >= 80 && code <= 82) return '\uD83C\uDF26\uFE0F';
    if (code >= 95) return '\u26A1';
    return '\u2753';
  }
}
