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
  const LiveStreamingScreen({super.key, this.initialChurchId});

  /// When set (a shared `?tenant=<id>` link), the screen goes straight to that
  /// church's broadcast instead of showing the platform-wide list.
  final String? initialChurchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final initial = initialChurchId;
    if (initial != null && initial.isNotEmpty) {
      // A per-church share link must land on that church's service, not on a
      // list the member then has to search.
      return _ChurchLiveGate(churchId: initial);
    }
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

/// Resolves ONE church's current broadcast for a shared per-church link
/// (`/live-streaming?tenant=<id>` or `/church/<id>/live`).
///
/// Why this exists: a church's own share link used to drop the member on the
/// platform-wide list, where their own service was one row among every other
/// church's. This gate does the lookup and hands off straight to the player —
/// the tenant's members land on their own tenant's service, which is the whole
/// point of the link.
class _ChurchLiveGate extends ConsumerStatefulWidget {
  const _ChurchLiveGate({required this.churchId});

  final String churchId;

  @override
  ConsumerState<_ChurchLiveGate> createState() => _ChurchLiveGateState();
}

class _ChurchLiveGateState extends ConsumerState<_ChurchLiveGate> {
  bool _redirecting = false;

  Future<void> _resolve() async {
    if (_redirecting) return;
    _redirecting = true;
    final service = ref.read(liveStreamServiceProvider);
    try {
      final row = await service.getActiveStreamForChurch(widget.churchId);
      if (!mounted) return;

      if (row != null) {
        final id = row['id']?.toString() ?? '';
        context.pushReplacement('/live-player', extra: {
          'streamUrl': row['hls_url']?.toString() ?? '',
          'streamId': id.isEmpty ? null : id,
          'churchId': widget.churchId,
          'title': row['title']?.toString() ?? 'Live Service',
          'isAudioOnly': row['is_audio_only'] == true,
          'thumbnailUrl': row['thumbnail_url']?.toString(),
        });
        return;
      }

      // Not live right now — fall back to the most recent recording so the link
      // still leads somewhere useful instead of a dead end.
      final replays = await service.getRecentRecordings();
      if (!mounted) return;
      final mine = replays
          .where((r) => r['church_id']?.toString() == widget.churchId)
          .toList();
      if (mine.isNotEmpty) {
        final r = mine.first;
        final archive = r['archive_url']?.toString() ?? '';
        final rec = r['recording_hls_url']?.toString() ?? '';
        final url = archive.isNotEmpty ? archive : rec;
        if (url.isNotEmpty) {
          context.pushReplacement('/live-player', extra: {
            'streamUrl': url,
            'streamId': r['id']?.toString(),
            'churchId': widget.churchId,
            'title': r['title']?.toString() ?? 'Recent Service',
            'thumbnailUrl': r['thumbnail_url']?.toString(),
          });
          return;
        }
      }
    } catch (e) {
      debugPrint('[LiveStreaming] per-church link failed: $e');
    }

    if (!mounted) return;
    setState(() => _redirecting = false);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolve());
  }

  @override
  Widget build(BuildContext context) {
    final brand = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.circle, size: 10, color: Colors.red),
            SizedBox(width: 8),
            Text('Live Service'),
          ],
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_redirecting) ...[
                CircularProgressIndicator(color: brand),
                const SizedBox(height: 16),
                const Text('Finding the service...', textAlign: TextAlign.center),
              ] else ...[
                Icon(Icons.wifi_off, size: 48, color: Colors.grey.withValues(alpha: 0.4)),
                const SizedBox(height: 12),
                const Text(
                  'This church is not streaming right now',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'You will get a notification the moment the service starts.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: _resolve,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('CHECK AGAIN'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => context.go('/live-streaming'),
                  child: const Text('Browse all churches'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}