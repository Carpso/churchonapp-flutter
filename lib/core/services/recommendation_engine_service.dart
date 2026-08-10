import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/tenant_service.dart';

class RecommendationItem {
  final String id;
  final String title;
  final String subtitle;
  final String category;
  final String route;
  final String? imageUrl;
  final IconData icon;
  final int matchPercentage; // e.g. 96
  final Color themeColor;

  RecommendationItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.category,
    required this.route,
    this.imageUrl,
    required this.icon,
    required this.matchPercentage,
    required this.themeColor,
  });
}

class RecommendationEngineService {
  final SupabaseClient _client;
  RecommendationEngineService(this._client);

  Future<List<RecommendationItem>> getRecommendations(String tenantId) async {
    final list = <RecommendationItem>[];

    try {
      // 1. Fetch Sermon audio recommendation
      final sermons = await _client
          .from('sermons')
          .select('id, title, speaker, cover_url')
          .eq('tenant_id', tenantId)
          .limit(2);

      if (sermons.isNotEmpty) {
        for (final s in sermons) {
          list.add(
            RecommendationItem(
              id: s['id'] ?? 's1',
              title: s['title'] ?? 'Walking in Divine Purpose',
              subtitle: s['speaker'] ?? 'Pastor Leonard Kaweme',
              category: 'Audio Message',
              route: '/sermons',
              imageUrl: s['cover_url'],
              icon: LucideIcons.headphones,
              matchPercentage: 98,
              themeColor: const Color(0xFF8B5CF6),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('RecommendationEngine: Error fetching sermon recs: $e');
    }

    // Add high-value fallback recommendations
    if (list.isEmpty) {
      list.add(
        RecommendationItem(
          id: 'rec_s1',
          title: 'Wealth & Stewardship',
          subtitle: 'Series on Financial Breakthrough',
          category: 'Recommended Sermon',
          route: '/sermons',
          icon: LucideIcons.headphones,
          matchPercentage: 97,
          themeColor: const Color(0xFF6366F1),
        ),
      );
    }

    list.add(
      RecommendationItem(
        id: 'rec_b1',
        title: 'The Purpose Driven Church Life',
        subtitle: 'Bestseller in Church Bookshop',
        category: 'Marketplace Book',
        route: '/marketplace',
        icon: LucideIcons.bookOpen,
        matchPercentage: 94,
        themeColor: const Color(0xFF10B981),
      ),
    );

    list.add(
      RecommendationItem(
        id: 'rec_e1',
        title: 'All-Church Friday Worship Night',
        subtitle: 'Fellowship & Intercession Gathering',
        category: 'Upcoming Event',
        route: '/events',
        icon: LucideIcons.calendar,
        matchPercentage: 92,
        themeColor: const Color(0xFFF59E0B),
      ),
    );

    list.add(
      RecommendationItem(
        id: 'rec_p1',
        title: 'National Healing & Youth Revival',
        subtitle: 'Intercede with 240+ Prayer Partners',
        category: 'Prayer Wall Pick',
        route: '/prayer-wall',
        icon: LucideIcons.heartHandshake,
        matchPercentage: 95,
        themeColor: const Color(0xFFEC4899),
      ),
    );

    return list;
  }
}

final recommendationEngineServiceProvider = Provider<RecommendationEngineService>((ref) {
  return RecommendationEngineService(Supabase.instance.client);
});

final universalRecommendationsProvider = FutureProvider.autoDispose<List<RecommendationItem>>((ref) async {
  final tenant = ref.watch(currentTenantProvider);
  final tenantId = tenant?.id ?? 'zm_1';
  final service = ref.watch(recommendationEngineServiceProvider);
  return service.getRecommendations(tenantId);
});

class RecommendationCarouselWidget extends ConsumerWidget {
  const RecommendationCarouselWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recsAsync = ref.watch(universalRecommendationsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(LucideIcons.sparkles, color: Color(0xFFD97706), size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Recommended For You',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
              TextButton(
                onPressed: () => context.push('/sermons'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
                child: const Text('Explore All'),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 145,
          child: recsAsync.when(
            data: (items) => ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return GestureDetector(
                  onTap: () => context.push(item.route),
                  child: Container(
                    width: 260,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: item.themeColor.withValues(alpha: 0.25),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: item.themeColor.withValues(alpha: 0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: item.themeColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                item.category,
                                style: TextStyle(
                                  color: item.themeColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade100,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${item.matchPercentage}% Match',
                                style: TextStyle(
                                  color: Colors.amber.shade900,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            loading: () => ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: 3,
              itemBuilder: (_, __) => Container(
                width: 240,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}
