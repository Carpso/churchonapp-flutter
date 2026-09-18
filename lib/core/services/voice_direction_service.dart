import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Lightweight wrapper around flutter_tts for spoken turn-by-turn directions
/// in Carpso Ride and the church-locator map. Uses device TTS engine (no API
/// key required). All methods are fire-and-forget — TTS failure is never fatal.
class VoiceDirectionService {
  static final FlutterTts _tts = FlutterTts();
  static bool _initialised = false;

  /// User-facing mute toggle (persisted in SharedPreferences by the UI layer).
  static bool _muted = false;
  static bool get isMuted => _muted;
  static void setMuted(bool value) {
    _muted = value;
    if (value) stop();
  }

  /// Announcement queue — prevents maneuvers from stacking on top of each
  /// other when position updates arrive faster than speech completes.
  static final List<String> _queue = [];
  static bool _draining = false;

  /// Dedupe bookkeeping: the same instruction for the same step is never
  /// repeated within [_dedupeWindow].
  static const Duration _dedupeWindow = Duration(seconds: 10);
  static const Duration _minGap = Duration(milliseconds: 1800);
  static String? _lastText;
  static DateTime? _lastTextAt;
  static String? _lastStepKey;

  /// Configure TTS once per app lifecycle. Safe to call multiple times.
  static Future<void> _ensureInit() async {
    if (_initialised) return;
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.48); // slightly slower for clarity
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      // Let `speak` resolve when the utterance finishes so the queue can pace
      // itself (ignored on platforms that don't support it).
      try {
        await _tts.awaitSpeakCompletion(true);
      } catch (_) {}
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

  /// Queue a maneuver announcement. Dedupes repeat instructions for the same
  /// [stepKey] within ~10 s and paces utterances so they never stack.
  static Future<void> announceManeuver(
    String text, {
    String urgency = 'normal',
    String? stepKey,
  }) async {
    if (text.isEmpty || _muted) return;
    final now = DateTime.now();

    final sameStep =
        stepKey != null && stepKey == _lastStepKey && _lastText == text;
    final recent = _lastTextAt != null && now.difference(_lastTextAt!) < _dedupeWindow;
    if (sameStep && recent) return;
    if (_lastText == text && recent) return;

    _lastStepKey = stepKey;
    _lastText = text;
    _lastTextAt = now;

    // Keep the queue short — only the two most recent pending announcements
    // matter; older ones are stale by the time they would play.
    if (_queue.length >= 2) _queue.removeAt(0);
    _queue.add(text);
    await _drain();
  }

  static Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      await _ensureInit();
      while (_queue.isNotEmpty) {
        if (_muted) {
          _queue.clear();
          break;
        }
        final text = _queue.removeAt(0);
        final started = DateTime.now();
        try {
          await _tts.speak(text);
        } catch (e) {
          debugPrint('VoiceDirection announce failed: $e');
        }
        final elapsed = DateTime.now().difference(started);
        if (elapsed < _minGap) await Future.delayed(_minGap - elapsed);
      }
    } finally {
      _draining = false;
    }
  }

  /// Stop any ongoing speech and clear the pending queue.
  static Future<void> stop() async {
    _queue.clear();
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
