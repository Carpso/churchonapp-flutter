import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/core/widgets/app_image.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/features/home/data/sermon_service.dart';
import 'package:church_on_app/features/home/presentation/sermon_player_screen.dart';
import 'package:church_on_app/features/home/presentation/sermon_search_screen.dart';
import 'package:church_on_app/features/home/presentation/live_stream_screen.dart';
import 'package:church_on_app/features/home/data/live_streaming_service.dart';
import 'package:church_on_app/features/bible/presentation/deep_study_suite_screen.dart';

class SermonLibraryScreen extends ConsumerStatefulWidget {
  const SermonLibraryScreen({super.key});

  @override
  ConsumerState<SermonLibraryScreen> createState() => _SermonLibraryScreenState();
}

class _SermonLibraryScreenState extends ConsumerState<SermonLibraryScreen> {
  String _selectedCategory = "All";
  final List<String> _categories = ["All", "Bible", "Miracles", "Faith", "Prosperity", "Healing", "Worship"];

  @override
  Widget build(BuildContext context) {
    final sermonsAsync = ref.watch(latestSermonsProvider);
    final tenant = ref.watch(currentTenantProvider);
    final liveStatus = tenant != null
        ? ref.watch(liveStatusProvider(tenant.id)).value
        : null;
    final isLive = liveStatus?.isLive ?? false;

    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text("Sermons", style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const DeepStudySuiteScreen()));
            },
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).primaryColor), 
            child: const Text("Deep Study", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          IconButton(
            icon: const Icon(LucideIcons.search), 
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SermonSearchScreen())),
          ),
        ],
      ),
      body: Column(
        children: [
          if (isLive && liveStatus?.streamUrl != null)
            _buildLiveBanner(context, liveStatus!),
          _buildCategoryFilter(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(latestSermonsProvider);
                await Future.delayed(const Duration(seconds: 1));
              },
              child: sermonsAsync.when(
                data: (sermons) {
                  if (sermons.isEmpty) {
                    return ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        const SizedBox(height: 60),
                        const Icon(LucideIcons.mic2, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        const Center(
                          child: Text('No sermons yet',
                              style: TextStyle(color: Colors.grey, fontSize: 16)),
                        ),
                        const SizedBox(height: 8),
                        const Center(
                          child: Text('Check back later for new messages',
                              style: TextStyle(color: Colors.grey, fontSize: 13)),
                        ),
                      ],
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: sermons.length,
                    itemBuilder: (context, index) {
                      return _buildSermonCard(sermons[index]);
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Text('Could not load sermons',
                      style: const TextStyle(color: Colors.grey, fontSize: 14)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveBanner(BuildContext context, LiveStreamStatus liveStatus) {
    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (context) => LiveStreamScreen(
          streamUrl: liveStatus.streamUrl!,
          title: liveStatus.title ?? "Live Service",
        )));
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFDC2626), Color(0xFF991B1B)]),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.red.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
              child: const Text("LIVE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(liveStatus.title ?? "Live Stream", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
            ),
            const Icon(LucideIcons.chevronRight, color: Colors.white70, size: 18),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    if (d.inDays > 0) return '${d.inDays}d ago';
    if (d.inHours > 0) return '${d.inHours}h ago';
    return '${d.inMinutes}m ago';
  }

  Widget _buildCategoryFilter() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final bool isSelected = _selectedCategory == _categories[index];
          return GestureDetector(
            onTap: () => setState(() => _selectedCategory = _categories[index]),
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: isSelected ? Theme.of(context).colorScheme.secondary : Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: isSelected ? [BoxShadow(color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.3), blurRadius: 10)] : [],
              ),
              child: Center(
                child: Text(
                  _categories[index],
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSermonCard(Sermon sermon) {
    return GestureDetector(
      onTap: () {
        if (sermon.isLive && sermon.videoUrl.isNotEmpty) {
          Navigator.push(context, MaterialPageRoute(builder: (context) => LiveStreamScreen(
            streamUrl: sermon.videoUrl,
            title: sermon.title,
          )));
        } else {
          Navigator.push(context, MaterialPageRoute(builder: (context) => SermonPlayerScreen(sermon: sermon)));
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  height: 180,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: AppImage(
                    sermon.thumbnailUrl,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  bottom: 15,
                  right: 15,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                    child: const Icon(LucideIcons.play, color: Colors.white, size: 20),
                  ),
                ),
                if (sermon.createdAt.isAfter(DateTime.now().subtract(const Duration(days: 7))))
                  Container(
                    margin: const EdgeInsets.all(12),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(8)),
                    child: const Text("NEW", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 8)),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 5),
                  Text(sermon.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      ClipOval(
                        child: AppImage(sermon.thumbnailUrl, width: 20, height: 20, fit: BoxFit.cover),
                      ),
                      const SizedBox(width: 10),
                      Text(sermon.preacher, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                      const Spacer(),
                      Icon(LucideIcons.clock, size: 14, color: Colors.grey),
                      const SizedBox(width: 5),
                      Text(
                        sermon.isLive ? 'LIVE' : _formatDuration(DateTime.now().difference(sermon.createdAt)),
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

