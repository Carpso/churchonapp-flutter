import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/utils/connectivity_util.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import '../data/kids_service.dart';
import 'activity_details_page.dart';

class KidsZoneScreen extends ConsumerStatefulWidget {
  const KidsZoneScreen({super.key});

  @override
  ConsumerState<KidsZoneScreen> createState() => _KidsZoneScreenState();
}

class _KidsZoneScreenState extends ConsumerState<KidsZoneScreen> {
  int _completedCount = 0;
  final int _weeklyGoal = 5;

  @override
  void initState() {
    super.initState();
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      final res = await Supabase.instance.client
          .from('kids_progress')
          .select('completed_resource_ids, weekly_activity_count')
          .eq('user_id', user.id)
          .maybeSingle();
      if (res != null && mounted) {
        setState(() {
          _completedCount = res['weekly_activity_count'] ?? 0;
        });
      }
    } catch (_) {}
  }

  Future<void> _markCompleted() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      await Supabase.instance.client.rpc('kids_upsert_progress', params: {
        'p_user_id': user.id,
        'p_activity_count': _completedCount + 1,
      });
      setState(() => _completedCount++);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resources = ref.watch(kidsResourcesProvider);
    final profile = ref.watch(profileProvider).value;

    final stories = resources.value?.where((r) => r.category == 'bible_story' || r.category == 'story').toList() ?? [];
    final activities = resources.value?.where((r) => r.category != 'bible_story' && r.category != 'story').toList() ?? [];

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F0),
      appBar: AppBar(
        title: const Text("Kids Zone", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
      ),
      body: OfflineAwareWrapper(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _buildHeaderBanner(theme, profile?.coins ?? 0),
            const SizedBox(height: 24),
            _buildSectionTitle("Activities"),
            const SizedBox(height: 12),
            _buildActivityGrid(context, activities),
            const SizedBox(height: 24),
            _buildSectionTitle("Bible Stories"),
            const SizedBox(height: 12),
            _buildStoryList(stories),
            const SizedBox(height: 24),
            _buildSectionTitle("Progress"),
            const SizedBox(height: 12),
            _buildProgressCard(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderBanner(ThemeData theme, int coins) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Colors.orange, Colors.deepOrange]),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [BoxShadow(color: Colors.orange.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Junior", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text("Earn coins by learning verses & completing activities!", style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.coins, color: Colors.amber, size: 16),
                      const SizedBox(width: 6),
                      Text("$coins CC", style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.15)),
            child: const Icon(LucideIcons.smile, color: Colors.white, size: 44),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF2D1810)));
  }

  Widget _buildActivityGrid(BuildContext context, List<KidsZoneResource> activities) {
    if (activities.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
        child: const Center(child: Text("Activities loading...", style: TextStyle(color: Colors.grey))),
      );
    }
    final display = activities.take(4).toList();
    while (display.length < 4) {
      display.add(KidsZoneResource(id: '', title: 'Coming Soon', description: 'New activities added weekly', category: 'activity', isFree: true));
    }
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _activityCard(context, display[0].title, display[0].categoryIcon, _categoryColor(display[0].category), display[0].description ?? '', display[0])),
            const SizedBox(width: 12),
            Expanded(child: _activityCard(context, display[1].title, display[1].categoryIcon, _categoryColor(display[1].category), display[1].description ?? '', display[1])),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _activityCard(context, display[2].title, display[2].categoryIcon, _categoryColor(display[2].category), display[2].description ?? '', display[2])),
            const SizedBox(width: 12),
            Expanded(child: _activityCard(context, display[3].title, display[3].categoryIcon, _categoryColor(display[3].category), display[3].description ?? '', display[3])),
          ],
        ),
      ],
    );
  }

  Color _categoryColor(String cat) {
    switch (cat) {
      case 'game': case 'activity': return Colors.purple;
      case 'verse': case 'memory': return Colors.blue;
      case 'coloring': return Colors.pink;
      case 'lesson': case 'video': return Colors.teal;
      case 'song': return Colors.deepPurple;
      default: return Colors.orange;
    }
  }

  Widget _activityCard(BuildContext context, String title, IconData? icon, Color color, String subtitle, KidsZoneResource res) {
    return GestureDetector(
      onTap: res.id.isNotEmpty ? () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => ActivityDetailsPage(title: title, icon: icon ?? LucideIcons.star, color: color)));
        _markCompleted();
      } : null,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10)]),
        child: Column(
          children: [
            Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(18)), child: Icon(icon ?? LucideIcons.star, color: color, size: 32)),
            const SizedBox(height: 12),
            Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 11), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _buildStoryList(List<KidsZoneResource> stories) {
    final list = stories.isNotEmpty ? stories : _defaultStories;
    return SizedBox(
      height: 120,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: list.length,
        itemBuilder: (context, index) {
          final s = list[index];
          return GestureDetector(
            onTap: s.id.isNotEmpty ? () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => ActivityDetailsPage(title: s.title, icon: LucideIcons.bookOpen, color: _categoryColor(s.category))));
              _markCompleted();
            } : null,
            child: Container(
              width: 160,
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: _categoryColor(s.category).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(18)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.title, style: TextStyle(color: _categoryColor(s.category), fontWeight: FontWeight.bold, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                if (s.description?.isNotEmpty == true) Text(s.description!, style: const TextStyle(color: Colors.grey, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
              ]),
            ),
          );
        },
      ),
    );
  }

  List<KidsZoneResource> get _defaultStories => [
    KidsZoneResource(id: '', title: 'David and Goliath', description: '1 Samuel 17', category: 'bible_story', isFree: true),
    KidsZoneResource(id: '', title: 'Jonah and the Whale', description: 'Jonah 1-3', category: 'bible_story', isFree: true),
    KidsZoneResource(id: '', title: "Noah's Ark", description: 'Genesis 6-9', category: 'bible_story', isFree: true),
    KidsZoneResource(id: '', title: 'The Birth of Jesus', description: 'Luke 2', category: 'bible_story', isFree: true),
  ];

  Widget _buildProgressCard(ThemeData theme) {
    final pct = _weeklyGoal > 0 ? (_completedCount / _weeklyGoal).clamp(0.0, 1.0) : 0.0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10)]),
      child: Column(
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text("Weekly Progress", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            Text("$_completedCount of $_weeklyGoal done", style: TextStyle(color: theme.primaryColor, fontWeight: FontWeight.bold, fontSize: 13)),
          ]),
          const SizedBox(height: 14),
          ClipRRect(borderRadius: BorderRadius.circular(10), child: LinearProgressIndicator(value: pct, backgroundColor: Colors.grey.withValues(alpha: 0.1), valueColor: AlwaysStoppedAnimation(theme.primaryColor), minHeight: 8)),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: List.generate(7, (i) => _dayChip(_dayLabels[i], i < _completedCount, theme))),
        ],
      ),
    );
  }

  static const _dayLabels = ['M', 'T', 'W', 'Th', 'F', 'Sa', 'Su'];

  Widget _dayChip(String day, bool done, ThemeData theme) {
    return Container(
      width: 34, height: 34,
      decoration: BoxDecoration(shape: BoxShape.circle, color: done ? theme.primaryColor : Colors.grey.withValues(alpha: 0.1)),
      child: Center(child: Text(day, style: TextStyle(color: done ? Colors.white : Colors.grey, fontSize: 11, fontWeight: FontWeight.bold))),
    );
  }
}
