import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

late AudioHandler audioHandler;
final audioHandlerProvider = Provider<AudioHandler>((ref) => audioHandler);
