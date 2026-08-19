import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:church_on_app/features/modules/live_streaming/data/live_stream_service.dart';

class LiveStreamingScreen extends ConsumerWidget {
  const LiveStreamingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeStreamsAsync = ref.watch(activeStreamsProvider);
    final upcomingStreamsAsync = ref.watch(upcomingStreamsProvider);
    final profile = ref.watch(profileProvider).value;
    final isLeader = profile?.isPastor == true || profile?.isBishop == true || profile?.isAdminOrHigher == true;

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
                if (streams.isEmpty) return const Padding(padding: EdgeInsets.all(20), child: Center(child: Text("No live streams")));
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('LIVE NOW', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.red)),
                    const SizedBox(height: 12),
                    ...streams.map((stream) => Card(
                      child: ListTile(
                        title: Text(
                          stream['title'] ?? 'Live Stream',
                          style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text("${stream['viewer_count'] ?? 0} watching", style: const TextStyle(color: Colors.black54)),
                      ),
                    )),
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
                if (streams.isEmpty) return const Padding(padding: EdgeInsets.all(20), child: Center(child: Text("No upcoming streams")));
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('UPCOMING', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    ...streams.map((stream) => Card(
                      child: ListTile(
                        title: Text(
                          stream['title'] ?? 'Scheduled Stream',
                          style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
                        ),
                      ),
                    )),
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
          ],
        ),
      ),
    );
  }
}
