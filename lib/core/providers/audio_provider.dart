import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

AudioHandler? _audioHandler;
AudioHandler? get audioHandler => _audioHandler;
set audioHandler(AudioHandler? h) => _audioHandler = h;

final audioHandlerProvider = Provider<AudioHandler?>((ref) => _audioHandler);

