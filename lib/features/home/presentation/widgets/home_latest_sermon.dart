import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/core/widgets/app_image.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import 'package:church_on_app/core/widgets/error_retry_widget.dart';
import 'package:church_on_app/features/home/data/sermon_service.dart';
import 'package:church_on_app/features/home/presentation/sermon_player_screen.dart';

class HomeLatestSermon extends ConsumerWidget {
  const HomeLatestSermon({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sermonsAsync = ref.watch(latestSermonsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, "Latest Sermon"),
        sermonsAsync.when(
          data: (sermons) {
            if (sermons.isEmpty) return const Text("No sermons available.");
            final sermon = sermons.first;
            return GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => SermonPlayerScreen(sermon: sermon))),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        AppImage(sermon.thumbnailUrl, height: 180, width: double.infinity, fit: BoxFit.cover),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Theme.of(context).primaryColor, shape: BoxShape.circle),
                          child: Icon(LucideIcons.play, color: Theme.of(context).colorScheme.secondary, size: 24),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.all(15.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(sermon.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 5),
                          Text("${sermon.preacher} • Latest Sunday", style: const TextStyle(color: Colors.grey, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
          loading: () => Card(
            child: Column(
              children: [
                const ShimmerLoader.rectangular(height: 180),
                Padding(
                  padding: const EdgeInsets.all(15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShimmerLoader.rectangular(width: 200, height: 18),
                      const SizedBox(height: 8),
                      ShimmerLoader.rectangular(width: 140, height: 14),
                    ],
                  ),
                ),
              ],
            ),
          ),
          error: (err, stack) => ErrorRetryWidget(
            message: "Failed to load sermons",
            onRetry: () => ref.invalidate(latestSermonsProvider),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15.0),
      child: Row(
        children: [
          Container(width: 4, height: 18, decoration: BoxDecoration(color: Theme.of(context).primaryColor, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 10),
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
