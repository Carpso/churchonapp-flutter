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
  final String badge;
  final Color themeColor;

  RecommendationItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.category,
    required this.route,
    this.imageUrl,
    required this.icon,
    required this.badge,
    required this.themeColor,
  });
}

class RecommendationEngineService {
  final SupabaseClient _client;
  RecommendationEngineService(this._client);

  Future<List<RecommendationItem>> getRecommendations(String tenantId) async {
    final now = DateTime.now().toIso8601String();

    final Future<List<RecommendationItem>> sermonRec = () async {
      try {
        final rows = await _client
            .from('sermons')
            .select('id, title, speaker, thumbnail_url')
            .eq('tenant_id', tenantId)
            .order('created_at', ascending: false)
            .limit(1);
        if (rows.isEmpty) return const <RecommendationItem>[];
        final s = rows.first;
        return [
          RecommendationItem(
            id: s['id']?.toString() ?? 'sermon_rec',
            title: s['title'] ?? 'Latest Sermon',
            subtitle: s['speaker'] ?? 'Church Service',
            category: 'Audio Message',
            route: '/sermons',
            imageUrl: s['thumbnail_url'],
            icon: LucideIcons.headphones,
            badge: 'Latest',
            themeColor: const Color(0xFF8B5CF6),
          ),
        ];
      } catch (e) {
        debugPrint('RecommendationEngine: Error fetching sermon rec: $e');
        return const <RecommendationItem>[];
      }
    }();

    final Future<List<RecommendationItem>> productRec = () async {
      try {
        final rows = await _client
            .from('marketplace_items')
            .select('id, name, image, price')
            .eq('tenant_id', tenantId)
            .eq('status', 'active')
            .order('created_at', ascending: false)
            .limit(1);
        if (rows.isEmpty) return const <RecommendationItem>[];
        final p = rows.first;
        return [
          RecommendationItem(
            id: p['id']?.toString() ?? 'product_rec',
            title: p['name'] ?? 'Marketplace Item',
            subtitle: 'In the Marketplace',
            category: 'Marketplace Pick',
            route: '/marketplace',
            imageUrl: p['image'],
            icon: LucideIcons.shoppingBag,
            badge: 'Featured',
            themeColor: const Color(0xFF10B981),
          ),
        ];
      } catch (e) {
        debugPrint('RecommendationEngine: Error fetching product rec: $e');
        return const <RecommendationItem>[];
      }
    }();

    final Future<List<RecommendationItem>> eventRec = () async {
      try {
        final rows = await _client
            .from('events')
            .select('id, title, category, location, date')
            .eq('tenant_id', tenantId)
            .gte('date', now)
            .order('date', ascending: true)
            .limit(1);
        if (rows.isEmpty) return const <RecommendationItem>[];
        final e = rows.first;
        return [
          RecommendationItem(
            id: e['id']?.toString() ?? 'event_rec',
            title: e['title'] ?? 'Upcoming Event',
            subtitle: e['location'] ?? e['category'] ?? 'This week at church',
            category: 'Upcoming Event',
            route: '/events',
            imageUrl: null,
            icon: LucideIcons.calendar,
            badge: 'Save the date',
            themeColor: const Color(0xFFF59E0B),
          ),
        ];
      } catch (e) {
        debugPrint('RecommendationEngine: Error fetching event rec: $e');
        return const <RecommendationItem>[];
      }
    }();

    final Future<List<RecommendationItem>> prayerRec = () async {
      try {
        final rows = await _client
            .from('prayers')
            .select('id, content, user_name, prayer_count')
            .eq('tenant_id', tenantId)
            .order('prayer_count', ascending: false)
            .limit(1);
        if (rows.isEmpty) return const <RecommendationItem>[];
        final p = rows.first;
        final content = (p['content'] as String? ?? '').trim();
        return [
          RecommendationItem(
            id: p['id']?.toString() ?? 'prayer_rec',
            title: content.length > 40
                ? '${content.substring(0, 40).trim()}â€¦'
                : (content.isEmpty ? 'A Prayer Request' : content),
            subtitle: 'Join the prayer wall',
            category: 'Prayer Wall Pick',
            route: '/prayer-wall',
            imageUrl: null,
            icon: LucideIcons.heartHandshake,
            badge: 'Pray with us',
            themeColor: const Color(0xFFEC4899),
          ),
        ];
      } catch (e) {
        debugPrint('RecommendationEngine: Error fetching prayer rec: $e');
        return const <RecommendationItem>[];
      }
    }();

    final results = await Future.wait([sermonRec, productRec, eventRec, prayerRec]);
    return results.expand((r) => r).toList();
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
          height: 230,
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
                                item.badge,
                                style: TextStyle(
                                  color: Colors.amber.shade900,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (item.imageUrl != null && item.imageUrl!.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              item.imageUrl!,
                              height: 88,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              cacheWidth: 520,
                              errorBuilder: (_, __, ___) => Container(
                                height: 88,
                                color: item.themeColor.withValues(alpha: 0.08),
                              ),
                            ),
                          ),
                        ],
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
