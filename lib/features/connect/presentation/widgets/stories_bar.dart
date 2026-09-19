import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:video_player/video_player.dart';

import 'package:church_on_app/core/services/supabase_service.dart';
import 'package:church_on_app/features/connect/data/story_service.dart';
import 'package:church_on_app/features/connect/presentation/story_archive_screen.dart';

/// Plays a video story inline (looping, muted-safe) instead of showing a
/// placeholder icon. Disposed as soon as the story changes.
class _StoryVideo extends StatefulWidget {
  final String url;
  const _StoryVideo({required this.url});

  @override
  State<_StoryVideo> createState() => _StoryVideoState();
}

class _StoryVideoState extends State<_StoryVideo> {
  VideoPlayerController? _ctrl;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      _ctrl = c;
      await c.initialize();
      await c.setLooping(true);
      await c.play();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('story video init failed: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _ctrl;
    if (_failed || c == null || !c.value.isInitialized) {
      return const Center(
        child: Icon(LucideIcons.video, color: Colors.white54, size: 48),
      );
    }
    return Center(
      child: AspectRatio(
        aspectRatio: c.value.aspectRatio,
        child: VideoPlayer(c),
      ),
    );
  }
}

/// Instagram-style stories for Church Social.
///
/// A story is a 24h post shown as an avatar with a coloured ring: the brand
/// yellow when unseen, grey once you have watched it. Stories are tenant-scoped
/// with an optional public flag. Tapping opens the full-screen viewer.
class StoryGroup {
  final String userId;
  final String name;
  final String avatarUrl;
  final List<Map<String, dynamic>> stories;
  final bool seen;

  StoryGroup({
    required this.userId,
    required this.name,
    required this.avatarUrl,
    required this.stories,
    required this.seen,
  });
}

/// Active stories (not expired) for my church + public ones, grouped by author.
final storiesProvider = FutureProvider<List<StoryGroup>>((ref) async {
  try {
    final client = ref.watch(supabaseServiceProvider).client;
    final rows = await client
        .from('social_stories')
        .select('id, user_id, tenant_id, media_url, media_type, caption, '
            'thumbnail_url, view_count, created_at, expires_at')
        .gt('expires_at', DateTime.now().toIso8601String())
        // Newest first: with ascending order + limit(100) a just-posted story
        // was pushed off the end once >100 active platform-wide stories existed
        // (RLS also returns other churches' public stories).
        .order('created_at', ascending: false)
        .limit(100);

    final list = (rows as List).cast<Map<String, dynamic>>();
    if (list.isEmpty) return [];

    final me = client.auth.currentUser?.id;
    final ids = list.map((s) => s['user_id'].toString()).toSet().toList();

    // Two-step profile lookup (no FK-name dependency).
    final profs = await client
        .from('profiles')
        .select('id, full_name, avatar_url')
        .inFilter('id', ids);
    final byId = {
      for (final p in (profs as List)) p['id'].toString(): p,
    };

    // Which have I already seen?
    final viewed = await client
        .from('social_story_views')
        .select('story_id')
        .eq('viewer_id', me ?? '');
    final viewedIds =
        (viewed as List).map((v) => v['story_id'].toString()).toSet();

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final s in list) {
      grouped.putIfAbsent(s['user_id'].toString(), () => []).add(s);
    }

    final groups = grouped.entries.map((e) {
      final p = byId[e.key];
      final stories = e.value;
      final allSeen = stories.every((s) => viewedIds.contains(s['id'].toString()));
      return StoryGroup(
        userId: e.key,
        name: (p?['full_name'] ?? 'Member').toString(),
        avatarUrl: (p?['avatar_url'] ?? '').toString(),
        stories: stories,
        seen: allSeen,
      );
    }).toList();

    // Unseen first, then most recent.
    groups.sort((a, b) => (a.seen ? 1 : 0).compareTo(b.seen ? 1 : 0));
    return groups;
  } catch (e) {
    debugPrint('stories load failed (non-fatal): $e');
    return [];
  }
});

class StoriesBar extends ConsumerWidget {
  const StoriesBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(storiesProvider);
    final theme = Theme.of(context);
    final uid = ref.watch(supabaseServiceProvider).client.auth.currentUser?.id;

    return SizedBox(
      height: 104,
      child: async.when(
        loading: () => const SizedBox.shrink(),
        error: (_, __) => const SizedBox.shrink(),
        data: (groups) {
          final hasArchiveTile = uid != null;
          if (groups.isEmpty && !hasArchiveTile) return const SizedBox.shrink();
          final itemCount = groups.length + (hasArchiveTile ? 1 : 0);
          return ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: itemCount,
            itemBuilder: (context, i) {
              if (hasArchiveTile && i == 0) {
                return _ArchiveTile(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const StoryArchiveScreen(),
                  )),
                );
              }
              final gi = hasArchiveTile ? i - 1 : i;
              final g = groups[gi];
              final ring = g.seen ? Colors.grey.shade400 : theme.primaryColor;
              return GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      StoryViewerScreen(groups: groups, initial: gi),
                )),
                child: Container(
                  width: 76,
                  margin: const EdgeInsets.only(right: 10),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: ring, width: 2.5),
                        ),
                        child: CircleAvatar(
                          radius: 26,
                          backgroundColor: Colors.grey.shade200,
                          backgroundImage: g.avatarUrl.isNotEmpty
                              ? NetworkImage(g.avatarUrl)
                              : null,
                          child: g.avatarUrl.isEmpty
                              ? const Icon(LucideIcons.user, size: 20)
                              : null,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        g.name.split(' ').first,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Leading tile that opens the poster's own story archive.
class _ArchiveTile extends StatelessWidget {
  final VoidCallback onTap;
  const _ArchiveTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 76,
        margin: const EdgeInsets.only(right: 10),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                    width: 2.5),
              ),
              child: CircleAvatar(
                radius: 26,
                backgroundColor:
                    theme.colorScheme.onSurface.withValues(alpha: 0.08),
                child: Icon(LucideIcons.archive,
                    size: 20,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              'Archive',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen story viewer: progress bars, tap right/left to move, 5s per
/// story, records a view (deduped server-side) as each story shows.
class StoryViewerScreen extends ConsumerStatefulWidget {
  final List<StoryGroup> groups;
  final int initial;
  const StoryViewerScreen({
    super.key,
    required this.groups,
    required this.initial,
  });

  @override
  ConsumerState<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends ConsumerState<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  late PageController _pages;
  late AnimationController _progress;
  int _group = 0;
  int _story = 0;

  List<Map<String, dynamic>> get _current => widget.groups[_group].stories;

  @override
  void initState() {
    super.initState();
    _group = widget.initial;
    _pages = PageController(initialPage: _group);
    _progress = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed) _next();
      });
    _startStory();
  }

  @override
  void dispose() {
    _progress.dispose();
    _pages.dispose();
    super.dispose();
  }

  void _startStory() {
    final story = _current[_story];
    _progress.forward(from: 0);
    // Record the view (fire-and-forget).
    try {
      ref.read(supabaseServiceProvider).client.rpc('record_story_view', params: {
        'p_story_id': story['id'],
      });
    } catch (e) {
      debugPrint('record_story_view failed: $e');
    }
  }

  void _next() {
    if (_story + 1 < _current.length) {
      setState(() => _story++);
      _startStory();
      return;
    }
    if (_group + 1 < widget.groups.length) {
      setState(() {
        _group++;
        _story = 0;
      });
      _pages.jumpToPage(_group);
      _startStory();
      return;
    }
    if (mounted) Navigator.of(context).maybePop();
  }

  void _prev() {
    if (_story > 0) {
      setState(() => _story--);
      _startStory();
      return;
    }
    if (_group > 0) {
      setState(() {
        _group--;
        _story = 0;
      });
      _pages.jumpToPage(_group);
      _startStory();
      return;
    }
    _progress.forward(from: 0);
  }

  /// Owner-only: who has watched this story.
  Future<void> _showViewers() async {
    final client = ref.read(supabaseServiceProvider).client;
    final story = _current[_story];
    List<Map<String, dynamic>> viewers = [];
    try {
      final rows = await client
          .from('social_story_views')
          .select('viewer_id, viewed_at')
          .eq('story_id', story['id'])
          .order('viewed_at', ascending: false)
          .limit(200);
      final ids = (rows as List).map((r) => r['viewer_id'].toString()).toList();
      if (ids.isNotEmpty) {
        final profs = await client
            .from('profiles')
            .select('id, full_name, avatar_url')
            .inFilter('id', ids);
        viewers = (profs as List).cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('story viewer list failed: $e');
    }
    if (!mounted) return;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.black87,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '${viewers.length} viewer${viewers.length == 1 ? '' : 's'}',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14),
              ),
            ),
            if (viewers.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 24),
                child: Text('No views yet',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: viewers.length,
                  itemBuilder: (c, i) {
                    final v = viewers[i];
                    final av = (v['avatar_url'] ?? '').toString();
                    return ListTile(
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: Colors.white24,
                        backgroundImage:
                            av.isNotEmpty ? NetworkImage(av) : null,
                        child: av.isEmpty
                            ? const Icon(LucideIcons.user,
                                size: 16, color: Colors.white)
                            : null,
                      ),
                      title: Text(
                        (v['full_name'] ?? 'Member').toString(),
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final story = _current[_story];
    final meId =
        ref.read(supabaseServiceProvider).client.auth.currentUser?.id;
    final media = (story['media_url'] ?? '').toString();
    final caption = (story['caption'] ?? '').toString();
    final isVideo = (story['media_type'] ?? 'image') == 'video';
    final author = widget.groups[_group];

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapUp: (d) {
          final w = MediaQuery.of(context).size.width;
          if (d.globalPosition.dx < w / 2) {
            _prev();
          } else {
            _next();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (isVideo)
              _StoryVideo(url: media)
            else if (media.isNotEmpty)
              Image.network(
                media,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(LucideIcons.imageOff,
                      color: Colors.white38, size: 48),
                ),
              ),
            // Progress bars
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: 10,
              right: 10,
              child: Row(
                children: List.generate(_current.length, (i) {
                  return Expanded(
                    child: Container(
                      height: 3,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: i < _story
                          ? Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            )
                          : i == _story
                              ? AnimatedBuilder(
                                  animation: _progress,
                                  builder: (c, _) => FractionallySizedBox(
                                    alignment: Alignment.centerLeft,
                                    widthFactor: _progress.value,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius:
                                            BorderRadius.circular(2),
                                      ),
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                    ),
                  );
                }),
              ),
            ),
            // Author row
            Positioned(
              top: MediaQuery.of(context).padding.top + 26,
              left: 14,
              right: 14,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.white24,
                    backgroundImage: author.avatarUrl.isNotEmpty
                        ? NetworkImage(author.avatarUrl)
                        : null,
                    child: author.avatarUrl.isEmpty
                        ? const Icon(LucideIcons.user,
                            size: 14, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      author.name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x,
                        color: Colors.white, size: 20),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
            if (caption.isNotEmpty)
              Positioned(
                left: 20,
                right: 20,
                bottom: 78,
                child: Text(
                  caption,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
                  ),
                ),
              ),
            // Quick reaction bar (❤️ 🙏 🔥 😂 👏). Counts are visible to all,
            // and the owner also sees the aggregate on the bar below.
            Positioned(
              left: 0,
              right: 0,
              bottom: author.userId == meId ? 58 : 18,
              child: _StoryReactionBar(
                key: ValueKey('story-reactions-${story['id']}'),
                storyId: story['id'].toString(),
              ),
            ),
            // Owner-only: view count + who watched.
            if (author.userId == meId)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: InkWell(
                    onTap: _showViewers,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      color: Colors.black54,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(LucideIcons.eye,
                              color: Colors.white, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            '${story['view_count'] ?? 0} views · tap to see who',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Quick reactions for the currently shown story.
class _StoryReactionBar extends ConsumerStatefulWidget {
  final String storyId;
  const _StoryReactionBar({super.key, required this.storyId});

  @override
  ConsumerState<_StoryReactionBar> createState() => _StoryReactionBarState();
}

class _StoryReactionBarState extends ConsumerState<_StoryReactionBar> {
  String? _mine;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadMine();
  }

  Future<void> _loadMine() async {
    final r = await ref.read(storyServiceProvider).myReaction(widget.storyId);
    if (mounted) setState(() => _mine = r);
  }

  Future<void> _react(String emoji) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(storyServiceProvider)
          .reactToStory(widget.storyId, emoji);
      ref.invalidate(storyReactionSummaryProvider(widget.storyId));
      await _loadMine();
    } catch (e) {
      debugPrint('react to story failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary =
        ref.watch(storyReactionSummaryProvider(widget.storyId)).asData?.value ??
            const <String, int>{};
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final emoji in kStoryReactions)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: _busy ? null : () => _react(emoji),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _mine == emoji
                      ? Theme.of(context).primaryColor
                      : Colors.black38,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Text(emoji, style: const TextStyle(fontSize: 16)),
                    if ((summary[emoji] ?? 0) > 0) ...[
                      const SizedBox(width: 4),
                      Text(
                        '${summary[emoji]}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
