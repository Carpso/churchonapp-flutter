import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/audio_handler.dart';

AudioHandler? _audioHandler;
AudioHandler? get audioHandler => _audioHandler;
set audioHandler(AudioHandler? h) => _audioHandler = h;

/// The app-wide background audio engine.
///
/// Typed as [MyAudioHandler] (not the base [AudioHandler]) so on-screen players
/// can also read the live position/duration/playing streams — this is what lets
/// audio sermons, Bible audio and radio survive the screen being closed and the
/// app being backgrounded, with lock-screen / notification controls.
final audioHandlerProvider = Provider<MyAudioHandler?>((ref) {
  final h = _audioHandler;
  return h is MyAudioHandler ? h : null;
});
