import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/widgets/branded_stream_poster.dart';
import 'package:go_router/go_router.dart';
import 'package:church_on_app/features/modules/live_streaming/data/live_stream_service.dart';
import 'package:church_on_app/core/services/unified_stream_service.dart';
import 'package:church_on_app/features/media/presentation/transcript_status_chip.dart';

class LiveStreamingScreen extends ConsumerWidget {
  const LiveStreamingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeStreamsAsync = ref.watch(activeStreamsProvider);
    final upcomingStreamsAsync = ref.watch(upcomingStreamsProvider);
    final recentAsync = ref.watch(recentRecordingsProvider);
    final profile = ref.watch(profileProvider).value;
    final isLeader = profile?.isLeadershipTeam == true || profile?.isSuperadmin == true;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            const Text('Live Streaming'),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(activeStreamsProvider);
          ref.invalidate(upcomingStreamsProvider);
          ref.invalidate(recentRecordingsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (isLeader)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFD32F2F), Color(0xFFFF6D00)]),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.videocam, color: Colors.white, size: 24),
                        SizedBox(width: 10),
                        Text("Leader Studio", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text("Stream live church service directly from your phone.", style: TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(height: 14),
                    ElevatedButton.icon(
                      onPressed: () {
                        final tid = profile?.tenantId ?? '';
                        context.push('/live-studio', extra: {'tenantId': tid, 'streamTitle': "${profile?.name ?? 'Pastor'}'s Live Service"});
                      },
                      icon: const Icon(Icons.camera_front, color: Colors.red, size: 18),
                      label: const Text("START CAMERA STREAM", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.white, minimumSize: const Size(double.infinity, 45), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    ),
                  ],
                ),
              ),
            if (isLeader) const SizedBox(height: 16),
            activeStreamsAsync.when(
              data: (streams) {
                if (streams.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: Text("No live streams right now")),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('LIVE NOW', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.red)),
                    const SizedBox(height: 12),
                    ...streams.map((stream) => _streamTile(context, stream)),
                  ],
                );
              },
              loading: () => Shimmer.fromColors(
                baseColor: Colors.grey.shade300,
                highlightColor: Colors.grey.shade100,
                child: Column(
                  children: [
                    Container(height: 20, width: 100, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                    const SizedBox(height: 12),
                    ...List.generate(2, (_) => Container(height: 80, margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)))),
                  ],
                ),
              ),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
            const SizedBox(height: 24),
            upcomingStreamsAsync.when(
              data: (streams) {
                if (streams.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: Text("No upcoming streams")),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('UPCOMING', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    ...streams.map((stream) => _upcomingTile(context, ref, stream, isLeader)),
                  ],
                );
              },
              loading: () => Shimmer.fromColors(
                baseColor: Colors.grey.shade300,
                highlightColor: Colors.grey.shade100,
                child: Column(
                  children: [
                    Container(height: 20, width: 100, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                    const SizedBox(height: 12),
                    ...List.generate(2, (_) => Container(height: 80, margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)))),
                  ],
                ),
              ),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
            const SizedBox(height: 24),
            recentAsync.when(
              data: (streams) => _replaySection(context, ref, streams, isLeader),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _replaySection(
    BuildContext context,
    WidgetRef ref,
    List<Map<String, dynamic>> streams,
    bool isLeader,
  ) {
    if (streams.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.history, size: 16, color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
            const SizedBox(width: 6),
            const Text('RECENT SERVICES', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Saved replays (archived to Church On storage — playable any time).',
          style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.55)),
        ),
        const SizedBox(height: 12),
        ...streams.map((stream) => _replayTile(context, ref, stream, isLeader)),
      ],
    );
  }

  Widget _audioOnlyBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.mic, size: 10, color: Colors.white),
            SizedBox(width: 3),
            Text('AUDIO',
                style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
          ],
        ),
      );

  Widget _thumb(Map<String, dynamic> stream) {
    final isAudioOnly = stream['is_audio_only'] == true;
    // Branded default poster when a stream has no custom thumbnail (audio-only
    // keeps its mic icon instead — a poster would misrepresent it).
    return SizedBox(
      width: 64,
      height: 44,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: isAudioOnly
                  ? Container(
                      color: Colors.black12,
                      child: const Icon(
                        LucideIcons.mic,
                        size: 18,
                        color: Colors.grey,
                      ),
                    )
                  : SmartStreamPoster(
                      url: stream['thumbnail_url']?.toString(),
                      seed: stream['id'] ?? stream['title'] ?? '',
                      fit: BoxFit.cover,
                    ),
            ),
          ),
          if (isAudioOnly)
            Positioned(left: 3, bottom: 3, child: _audioOnlyBadge()),
        ],
      ),
    );
  }

  Widget _streamTile(BuildContext context, Map<String, dynamic> stream) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        leading: _thumb(stream),
        title: Text(
          stream['title']?.toString() ?? 'Live Stream',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          "${stream['viewer_count'] ?? 0} watching${stream['is_audio_only'] == true ? ' · Audio only' : ''}",
          style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
        ),
        trailing: const Icon(Icons.play_circle_fill, color: Colors.red),
        onTap: () => _openPlayer(context, stream, live: true),
      ),
    );
  }

  Widget _upcomingTile(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> stream,
    bool isLeader,
  ) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        leading: _thumb(stream),
        title: Text(
          stream['title']?.toString() ?? 'Scheduled Stream',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w600),
        ),
        subtitle: stream['scheduled_at'] != null
            ? Text(
                'Starts ${_formatScheduled(stream['scheduled_at'])}',
                style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
              )
            : null,
        trailing: isLeader
            ? TextButton(
                onPressed: () => _startScheduledNow(context, ref, stream),
                child: const Text('Start Now', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              )
            : null,
      ),
    );
  }

  Widget _replayTile(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> stream,
    bool isLeader,
  ) {
    final theme = Theme.of(context);
    final streamId = stream['id']?.toString();
    final status = (stream['archive_status'] ?? 'none').toString();
    final archive = stream['archive_url']?.toString() ?? '';
    final ready = status == 'ready' && archive.isNotEmpty;
    final working =
        status == 'queued' || status == 'processing' || status == 'archiving';
    final failed = status == 'failed';
    final error = (stream['archive_error'] ?? '').toString();

    final subtitle = working
        ? 'Processing recording…'
        : failed
            ? (error.isNotEmpty ? 'Archive failed · $error' : 'Archive failed')
            : 'Recorded ${_formatScheduled(stream['ended_at'] ?? stream['archived_at'])}';

    return Card(
      child: ListTile(
        leading: _thumb(stream),
        title: Text(
          stream['title']?.toString() ?? 'Service Replay',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
            ),
            if (streamId != null && streamId.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TranscriptStatusChip(liveStreamId: streamId),
                ),
              ),
          ],
        ),
        trailing: ready
            ? const Icon(Icons.play_circle_fill, color: Colors.red)
            : working
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : (failed && isLeader && streamId != null
                    ? IconButton(
                        tooltip: 'Retry archive',
                        icon: const Icon(LucideIcons.refreshCw,
                            size: 18, color: Colors.red),
                        onPressed: () => _retryArchive(context, ref, streamId),
                      )
                    : const SizedBox.shrink()),
        onTap: ready ? () => _openPlayer(context, stream, live: false) : null,
      ),
    );
  }

  Future<void> _retryArchive(
    BuildContext context,
    WidgetRef ref,
    String streamId,
  ) async {
    try {
      await ref.read(unifiedStreamServiceProvider).archiveRecording(streamId);
      ref.invalidate(recentRecordingsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Archive retry started…')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Archive retry failed: $e')),
        );
      }
    }
  }

  /// Opens the viewer. Live streams use HLS; replays use the R2 archive URL —
  /// the permanent master copy, so a finished service stays playable in-app
  /// even after Cloudflare Stream expires the recording.
  void _openPlayer(BuildContext context, Map<String, dynamic> stream, {required bool live}) {
    final archive = stream['archive_url']?.toString();
    final hls = stream['hls_url']?.toString();
    final streamId = stream['id']?.toString();
    final url = live ? (hls ?? '') : (archive ?? hls ?? '');
    // A live row may have an empty/stale hls_url (Cloudflare's manifest is not
    // ready until the input connects). Still open the viewer with the streamId
    // so it can resolve/refresh the real playback URL instead of dead-ending.
    final canRepair = live && streamId != null && streamId.isNotEmpty;
    if (url.isEmpty && !canRepair) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This stream is not ready for playback yet.')),
      );
      return;
    }
    context.push('/live-player', extra: {
      'streamUrl': url,
      'streamId': streamId,
      'title': stream['title']?.toString() ?? 'Live Service',
      'isAudioOnly': stream['is_audio_only'] == true,
      'thumbnailUrl': stream['thumbnail_url']?.toString(),
    });
  }

  String _formatScheduled(dynamic scheduledAt) {
    try {
      final dt = DateTime.parse(scheduledAt.toString()).toLocal();
      return '${dt.day}/${dt.month}/${dt.year} at ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return 'Upcoming';
    }
  }

  Future<void> _startScheduledNow(BuildContext context, WidgetRef ref, Map<String, dynamic> stream) async {
    final service = ref.read(liveStreamServiceProvider);
    final streamId = stream['id']?.toString();
    if (streamId == null || streamId.isEmpty) return;

    try {
      await service.startStream(streamId);
      ref.invalidate(activeStreamsProvider);
      ref.invalidate(upcomingStreamsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stream is now live. Connect your encoder to start broadcasting.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start stream: $e')),
        );
      }
    }
  }
}
