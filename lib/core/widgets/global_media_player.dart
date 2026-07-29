import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:audio_service/audio_service.dart';
import 'package:church_on_app/core/providers/audio_provider.dart';

class GlobalMediaState {
  final bool isPlaying;
  final String title;
  final String subtitle;
  final String audioUrl;
  final Duration position;
  final Duration duration;

  const GlobalMediaState({
    this.isPlaying = false,
    this.title = '',
    this.subtitle = '',
    this.audioUrl = '',
    this.position = Duration.zero,
    this.duration = Duration.zero,
  });

  GlobalMediaState copyWith({
    bool? isPlaying,
    String? title,
    String? subtitle,
    String? audioUrl,
    Duration? position,
    Duration? duration,
  }) {
    return GlobalMediaState(
      isPlaying: isPlaying ?? this.isPlaying,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      audioUrl: audioUrl ?? this.audioUrl,
      position: position ?? this.position,
      duration: duration ?? this.duration,
    );
  }
}

class GlobalMediaPlayerController {
  GlobalMediaPlayerController._();
  static final GlobalMediaPlayerController instance = GlobalMediaPlayerController._();

  final ValueNotifier<GlobalMediaState> state = ValueNotifier(const GlobalMediaState());

  AudioHandler? _handler;
  StreamSubscription<PlaybackState>? _playbackSub;
  StreamSubscription<MediaItem?>? _mediaItemSub;
  Timer? _positionTimer;

  void init() {
    _handler = audioHandler;
    if (_handler == null) return;

    _playbackSub?.cancel();
    _mediaItemSub?.cancel();
    _positionTimer?.cancel();

    _playbackSub = _handler!.playbackState.listen((playback) {
      final current = state.value;
      final mediaDur = _handler!.mediaItem.value?.duration ?? Duration.zero;
      state.value = current.copyWith(
        isPlaying: playback.playing,
        position: playback.position,
        duration: mediaDur,
      );
    });

    _mediaItemSub = _handler!.mediaItem.listen((item) {
      if (item == null) return;
      final current = state.value;
      state.value = current.copyWith(
        title: item.title,
        subtitle: item.artist ?? '',
        audioUrl: item.id,
        duration: item.duration ?? Duration.zero,
      );
    });

    _positionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_handler != null && _handler!.playbackState.value.playing) {
        final current = state.value;
        final mediaDur = _handler!.mediaItem.value?.duration ?? Duration.zero;
        state.value = current.copyWith(
          position: _handler!.playbackState.value.position,
          duration: mediaDur,
        );
      }
    });
  }

  void playEpisode({
    required String title,
    required String subtitle,
    required String audioUrl,
  }) async {
    state.value = GlobalMediaState(
      isPlaying: true,
      title: title,
      subtitle: subtitle,
      audioUrl: audioUrl,
    );

    if (_handler == null) {
      _handler = audioHandler;
      init();
    }

    if (_handler != null) {
      await _handler!.playFromUri(
        Uri.parse(audioUrl),
        {'title': title, 'artist': subtitle, 'album': 'Church On App'},
      );
    }
  }

  void togglePlayPause() {
    if (_handler == null) return;
    if (_handler!.playbackState.value.playing) {
      _handler!.pause();
    } else {
      _handler!.play();
    }
  }

  void skipForward() {
    if (_handler == null) return;
    final pos = _handler!.playbackState.value.position;
    final dur = _handler!.mediaItem.value?.duration ?? Duration.zero;
    _handler!.seek(Duration(seconds: (pos.inSeconds + 15).clamp(0, dur.inSeconds)));
  }

  void skipBackward() {
    if (_handler == null) return;
    final pos = _handler!.playbackState.value.position;
    final dur = _handler!.mediaItem.value?.duration ?? Duration.zero;
    _handler!.seek(Duration(seconds: (pos.inSeconds - 15).clamp(0, dur.inSeconds)));
  }

  void stop() {
    _handler?.stop();
    state.value = const GlobalMediaState();
  }

  void dispose() {
    _playbackSub?.cancel();
    _mediaItemSub?.cancel();
    _positionTimer?.cancel();
    state.dispose();
  }
}

final GlobalMediaPlayerController globalMediaPlayerController = GlobalMediaPlayerController.instance;

class GlobalMediaPlayer extends StatefulWidget {
  const GlobalMediaPlayer({super.key});

  @override
  State<GlobalMediaPlayer> createState() => _GlobalMediaPlayerState();
}

class _GlobalMediaPlayerState extends State<GlobalMediaPlayer> {
  @override
  void initState() {
    super.initState();
    globalMediaPlayerController.init();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<GlobalMediaState>(
      valueListenable: globalMediaPlayerController.state,
      builder: (context, mediaState, _) {
        if (!mediaState.isPlaying && mediaState.title.isEmpty) {
          return const SizedBox.shrink();
        }

        final progress = mediaState.duration.inSeconds > 0
            ? mediaState.position.inSeconds / mediaState.duration.inSeconds
            : 0.0;

        return Container(
          padding: const EdgeInsets.fromLTRB(20, 8, 16, 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, -2)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.amber),
                  minHeight: 2,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          mediaState.title,
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          mediaState.subtitle,
                          style: const TextStyle(color: Colors.white54, fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.skipBack, color: Colors.white, size: 20),
                    onPressed: globalMediaPlayerController.skipBackward,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                  GestureDetector(
                    onTap: globalMediaPlayerController.togglePlayPause,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(color: Colors.amber, shape: BoxShape.circle),
                      child: Icon(
                        mediaState.isPlaying ? LucideIcons.pause : LucideIcons.play,
                        color: Colors.black,
                        size: 18,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.skipForward, color: Colors.white, size: 20),
                    onPressed: globalMediaPlayerController.skipForward,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x, color: Colors.white38, size: 18),
                    onPressed: globalMediaPlayerController.stop,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
