import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

class MyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final _player = AudioPlayer();

  MyAudioHandler() {
    // Notify the system about the current state of the player
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);
    
    // Stop playing when the stream ends (not really applicable for radio but good practice)
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) stop();
    });
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  /// The underlying engine — lets callers read position/duration directly
  /// when they need finer control than [playbackState].
  AudioPlayer get player => _player;

  /// Convenience for on-screen players (duration + live position).
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<bool> get playingStream => _player.playingStream;

  @override
  Future<void> playFromUri(Uri uri, [Map<String, dynamic>? extras]) async {
    final mediaItem = MediaItem(
      id: uri.toString(),
      album: extras?['album'] ?? "Radio",
      title: extras?['title'] ?? "Live Stream",
      artist: extras?['artist'] ?? "Church On App",
      artUri: Uri.parse(extras?['artUri'] ?? "https://media.churchonapp.com/radio_cover.png"),
      // Carry through so the mini-player can deep-link back to the source
      // (e.g. `route: /sermon/<id>`).
      extras: extras,
    );
    this.mediaItem.add(mediaItem);

    try {
      await _player.setAudioSource(AudioSource.uri(uri));
      play();
    } catch (e) {
      debugPrint("Error loading audio: $e");
      rethrow;
    }
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.stop,
        if (_player.playing) MediaControl.pause else MediaControl.play,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    );
  }
}

