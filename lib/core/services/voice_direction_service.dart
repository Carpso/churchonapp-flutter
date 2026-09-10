import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Lightweight wrapper around flutter_tts for spoken turn-by-turn directions
/// in Carpso Ride and the church-locator map. Uses device TTS engine (no API
/// key required). All methods are fire-and-forget — TTS failure is never fatal.
class VoiceDirectionService {
  static final FlutterTts _tts = FlutterTts();
  static bool _initialised = false;

  /// Configure TTS once per app lifecycle. Safe to call multiple times.
  static Future<void> _ensureInit() async {
    if (_initialised) return;
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.48); // slightly slower for clarity
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      _initialised = true;
    } catch (e) {
      debugPrint('VoiceDirectionService init failed: $e');
    }
  }

  /// Speak a direction string. Cancels any in-progress utterance first.
  static Future<void> speak(String text) async {
    if (text.isEmpty) return;
    try {
      await _ensureInit();
      await _tts.stop();
      await _tts.speak(text);
    } catch (e) {
      debugPrint('VoiceDirection speak failed: $e');
    }
  }

  /// Stop any ongoing speech.
  static Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  /// Convert a distance in metres + a street name into a spoken direction.
  static String buildDirection({
    required double distanceMetres,
    String? streetName,
    bool approaching = false,
  }) {
    final km = distanceMetres / 1000;
    final metres = distanceMetres.round();
    String distText;
    if (km >= 1.0) {
      distText = '${km.toStringAsFixed(1)} kilometres';
    } else {
      distText = '$metres metres';
    }
    final street = (streetName != null && streetName.isNotEmpty) ? ' on $streetName' : '';
    if (approaching) return 'You are approaching your destination, $distText away$street.';
    if (metres < 100) return 'Turn now$street. Your destination is $distText ahead.';
    if (metres < 500) return 'In $distText, turn$street.';
    return 'Continue for $distText$street.';
  }
}
