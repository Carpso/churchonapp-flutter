import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../providers/audio_provider.dart';

/// Persistent "now playing" strip shown above the bottom navigation.
///
/// Background audio could be started (radio, audio sermons, kids stories) but
/// there was no way to see or control it once you left the screen. This bar
/// appears whenever the shared audio handler has a track, with play/pause,
/// stop, and tap-to-reopen the source screen.
class MiniPlayerBar extends ConsumerWidget {
  const MiniPlayerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.watch(audioHandlerProvider);
    if (handler == null) return const SizedBox.shrink();

    return StreamBuilder<MediaItem?>(
      stream: handler.mediaItem,
      builder: (context, mediaSnap) {
        final item = mediaSnap.data;
        if (item == null) return const SizedBox.shrink();

        return StreamBuilder<PlaybackState>(
          stream: handler.playbackState,
          builder: (context, stateSnap) {
            final state = stateSnap.data;
            final playing = state?.playing ?? false;
            final processing = state?.processingState;
            // Nothing loaded / already finished → hide the bar.
            if (processing == AudioProcessingState.idle ||
                processing == AudioProcessingState.completed) {
              return const SizedBox.shrink();
            }

            final theme = Theme.of(context);
            final art = item.artUri?.toString() ?? '';

            return Material(
              color: theme.colorScheme.surface,
              elevation: 8,
              child: InkWell(
                onTap: () {
                  final route = item.extras?['route']?.toString();
                  if (route != null && route.isNotEmpty) {
                    context.push(route);
                  } else if (item.album == 'Radio') {
                    context.push('/radio');
                  }
                },
                child: Container(
                  height: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: theme.dividerColor.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: art.isNotEmpty
                              ? Image.network(
                                  art,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      _artFallback(theme),
                                )
                              : _artFallback(theme),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w700),
                            ),
                            if (item.artist != null)
                              Text(
                                item.artist!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.6)),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          playing ? LucideIcons.pause : LucideIcons.play,
                          size: 20,
                        ),
                        onPressed: () =>
                            playing ? handler.pause() : handler.play(),
                        tooltip: playing ? 'Pause' : 'Play',
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.x, size: 18),
                        onPressed: () => handler.stop(),
                        tooltip: 'Stop',
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _artFallback(ThemeData theme) {
    return Container(
      color: theme.primaryColor.withValues(alpha: 0.15),
      child: Icon(LucideIcons.music, size: 18, color: theme.primaryColor),
    );
  }
}
