import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/core/widgets/app_image.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
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

class _SermonLibraryScreenState extends ConsumerState<SermonLibraryScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  String _selectedCategory = "All";
  List<String> _categories = const ["All"];
  static const List<String> _fallbackCategories = [
    "All", "Worship", "Faith", "Prayer", "Grace", "Bible Study", "Hope",
  ];
  List<Sermon> _sermons = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _offset = 0;
  static const int _limit = 10;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadSermons();
  }

  Future<void> _loadCategories() async {
    final service = ref.read(sermonServiceProvider);
    final dbCategories = await service.fetchCategories();
    if (mounted) {
      setState(() {
        _categories = dbCategories.isEmpty
            ? _fallbackCategories
            : ["All", ...dbCategories];
      });
    }
  }

  Future<void> _loadSermons() async {
    final service = ref.read(sermonServiceProvider);
    final batch = await service.fetchLatestSermons(
      category: _selectedCategory == "All" ? null : _selectedCategory,
    );
    if (mounted) {
      setState(() {
        _sermons = batch;
        _hasMore = batch.length >= _limit;
        _isLoading = false;
      });
    }
  }

  void _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final service = ref.read(sermonServiceProvider);
      final more = await service.fetchLatestSermons(
        offset: _offset + _limit,
        limit: _limit,
        category: _selectedCategory == "All" ? null : _selectedCategory,
      );
      if (mounted) {
        setState(() {
          _offset += _limit;
          _sermons = [..._sermons, ...more];
          _hasMore = more.length >= _limit;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final tenant = ref.watch(currentTenantProvider);
    final liveStatus = tenant != null
        ? ref.watch(liveStatusProvider(tenant.id)).value
        : null;
    final isLive = liveStatus?.isLive ?? false;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Sermons", style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const DeepStudySuiteScreen()));
            },
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).primaryColor), 
            child: const Text("Deep Study", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
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
                setState(() {
                  _sermons = [];
                  _offset = 0;
                  _hasMore = true;
                });
                await Future.wait([_loadSermons(), _loadCategories()]);
              },
              child: _isLoading
              ? ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: 5,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.only(bottom: 15),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const ShimmerLoader.rectangular(width: 90, height: 90),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              ShimmerLoader.rectangular(width: double.infinity, height: 16),
                              SizedBox(height: 10),
                              ShimmerLoader.rectangular(width: 150, height: 12),
                              SizedBox(height: 10),
                              ShimmerLoader.rectangular(width: 90, height: 12),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : _sermons.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(LucideIcons.mic2, size: 64, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.15)),
                      const SizedBox(height: 16),
                      Text('No sermons yet', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Text('Check back later for new messages', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4), fontSize: 13)),
                    ],
                  ),
                )
                  : ListView.builder(
                    padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).padding.bottom + 90),
                    itemCount: _sermons.length +
                        (_selectedCategory == "All" && _sermons.isNotEmpty ? 1 : 0) +
                        (_hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      var listIndex = index;
                      if (_selectedCategory == "All" && _sermons.isNotEmpty) {
                        if (index == 0) {
                          return _buildHeroCard(_sermons.first);
                        }
                        listIndex = index - 1;
                      }
                      if (listIndex == _sermons.length) {
                        return _isLoadingMore
                            ? const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: ShimmerLoader.rectangular(height: 48),
                              )
                            : GestureDetector(
                                onTap: _loadMore,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  margin: const EdgeInsets.only(top: 8),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.surface,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Theme.of(context).primaryColor.withValues(alpha: 0.3)),
                                  ),
                                  child: Center(
                                    child: Text("Load More", style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              );
                      }
                      return _buildSermonCard(_sermons[listIndex]);
                    },
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
              child: const Text("LIVE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
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
            onTap: () {
              setState(() => _selectedCategory = _categories[index]);
              _loadSermons();
            },
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: isSelected ? Theme.of(context).colorScheme.secondary : Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: isSelected ? [BoxShadow(color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.3), blurRadius: 10)] : [],
              ),
              child: Center(
                child: Text(
                  _categories[index],
                  style: TextStyle(
                    color: isSelected ? Colors.white : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
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

  void _openSermon(Sermon sermon) {
    if (sermon.isLive && sermon.videoUrl.isNotEmpty) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => LiveStreamScreen(
        streamUrl: sermon.videoUrl,
        title: sermon.title,
      )));
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (context) => SermonPlayerScreen(sermon: sermon)));
    }
  }

  Widget _buildHeroCard(Sermon sermon) {
    return GestureDetector(
      onTap: () => _openSermon(sermon),
      child: Container(
        height: 240,
        margin: const EdgeInsets.fromLTRB(0, 4, 0, 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AppImage(sermon.thumbnailUrl, fit: BoxFit.cover),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                  stops: [0.3, 1.0],
                ),
              ),
            ),
            Positioned(
              top: 14,
              left: 14,
              child: sermon.isLive
                  ? const _LiveBadge()
                  : Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.amber,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        "LATEST SERMON",
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w900,
                          fontSize: 10,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: const BoxDecoration(
                    color: Colors.amber,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Colors.black45, blurRadius: 12),
                    ],
                  ),
                  child: const Icon(LucideIcons.play, color: Colors.black, size: 26),
                ),
              ),
            ),
            Positioned(
              left: 18,
              right: 18,
              bottom: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (sermon.category.isNotEmpty)
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              sermon.category.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.8),
                            ),
                          ),
                        ),
                      const Spacer(),
                      if (sermon.durationMinutes != null) ...[
                        const Icon(LucideIcons.clock, color: Colors.white70, size: 12),
                        const SizedBox(width: 4),
                        Text(
                          '${sermon.durationMinutes} min',
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    sermon.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${sermon.preacher}  •  ${_formatDuration(DateTime.now().difference(sermon.createdAt))}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSermonCard(Sermon sermon) {
    final isLiveSermon = sermon.isLive;
    return GestureDetector(
      onTap: () => _openSermon(sermon),
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [BoxShadow(color: Theme.of(context).shadowColor.withValues(alpha: 0.02), blurRadius: 10)],
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
                if (isLiveSermon)
                  const Positioned(top: 12, left: 12, child: _LiveBadge())
                else if (sermon.createdAt.isAfter(DateTime.now().subtract(const Duration(days: 7))))
                  Container(
                    margin: const EdgeInsets.all(12),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(8)),
                    child: const Text("NEW", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                if (isLiveSermon && sermon.viewerCount > 0)
                  Positioned(
                    bottom: 15,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(LucideIcons.eye, color: Colors.white, size: 12),
                          const SizedBox(width: 4),
                          Text(
                            '${sermon.viewerCount} watching',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
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
                      CircleAvatar(
                        radius: 10,
                        backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.2),
                        child: Text(
                          sermon.preacher.isNotEmpty ? sermon.preacher[0].toUpperCase() : '?',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          sermon.preacher,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                            fontSize: 12,
                          ),
                        ),
                      ),
                      if (sermon.durationMinutes != null) ...[
                        Icon(LucideIcons.clock, size: 14, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)),
                        const SizedBox(width: 5),
                        Text(
                          '${sermon.durationMinutes} min',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4), fontSize: 12),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Text(
                        isLiveSermon ? 'LIVE' : _formatDuration(DateTime.now().difference(sermon.createdAt)),
                        style: TextStyle(
                          color: isLiveSermon
                              ? const Color(0xFFDC2626)
                              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                          fontSize: 12,
                          fontWeight: isLiveSermon ? FontWeight.w900 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                  if (sermon.category.isNotEmpty && sermon.category != 'General') ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Theme.of(context).primaryColor.withValues(alpha: 0.2)),
                        ),
                        child: Text(
                          sermon.category,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveBadge extends StatefulWidget {
  const _LiveBadge();

  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.55, end: 1.0).animate(_controller),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFDC2626),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [BoxShadow(color: Colors.red.withValues(alpha: 0.4), blurRadius: 8)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            const Text(
              "LIVE",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 10,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

