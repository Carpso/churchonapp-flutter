import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:universal_io/io.dart';

import '../config/app_constants.dart';
import 'safe_file_paths.dart';

class MyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final _player = AudioPlayer();

  /// Local `file://` URI of the bundled logo, resolved once and reused.
  static Uri? _defaultArtUri;

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
      artUri: _sanitizeArtUri(extras?['artUri']) ?? await _resolveDefaultArt(),
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

  /// Accepts a caller-supplied art URI only when it is well-formed and has a
  /// scheme `audio_service` can actually load. Empty strings, garbage and
  /// `asset:` URIs (which the plugin cannot download) are rejected so the
  /// local logo is used instead — a missing cover can never be passed as a
  /// remote URL that 404s and spams the console.
  Uri? _sanitizeArtUri(Object? raw) {
    if (raw is! String) return null;
    final value = raw.trim();
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    const allowed = {'http', 'https', 'file', 'content'};
    return allowed.contains(uri.scheme) ? uri : null;
  }

  /// Materialises the bundled brand logo to a local `file://` URI so the OS
  /// notification/artwork always resolves — `audio_service` reads `file` URIs
  /// directly and never performs an HTTP request for them, so this cannot 404.
  ///
  /// WEB: `path_provider` has no web implementation, so
  /// `getTemporaryDirectory()` throws
  /// `MissingPluginException(No implementation found for method
  /// getTemporaryDirectory on channel plugins.flutter.io/path_provider)`.
  /// The browser media session does not need a local file, so we skip artwork
  /// entirely on web and never touch `path_provider`.
  Future<Uri?> _resolveDefaultArt() async {
    if (kIsWeb) return null;
    if (_defaultArtUri != null) return _defaultArtUri;
    try {
      final dirPath = await safeTemporaryDirectoryPath();
      if (dirPath == null) return null;
      final file = File('$dirPath/coa_default_art.png');
      if (!await file.exists()) {
        final data = await rootBundle.load(AppConstants.logoAsset);
        await file.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
      }
      return _defaultArtUri = Uri.file(file.path);
    } catch (e) {
      debugPrint('Audio default artwork unavailable (non-fatal): $e');
      return null;
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

