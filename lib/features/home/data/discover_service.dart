import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/tenant_service.dart';
import 'sermon_service.dart';

class RecommendedContent {
  final List<Sermon> recommendedSermons;
  final List<Map<String, dynamic>> upcomingEvents;
  final List<Sermon> popularContent;
  final List<Sermon> newThisWeek;

  RecommendedContent({
    required this.recommendedSermons,
    required this.upcomingEvents,
    required this.popularContent,
    required this.newThisWeek,
  });
}

class DiscoverService {
  final SupabaseClient _client;
  final Ref _ref;
  DiscoverService(this._client, this._ref);

  Future<RecommendedContent> fetchRecommendations() async {
    final tenant = _ref.read(currentTenantProvider);
    final tenantId = tenant?.id;

    try {
      final sermonsFuture = _client
          .from('sermons')
          .select()
          .order('created_at', ascending: false)
          .limit(10);

      final popularFuture = _client
          .from('sermons')
          .select()
          .order('viewer_count', ascending: false)
          .limit(5);

      final newThisWeekFuture = _client
          .from('sermons')
          .select()
          .gte('created_at', DateTime.now().subtract(const Duration(days: 7)).toIso8601String())
          .order('created_at', ascending: false)
          .limit(5);

      List<Map<String, dynamic>> eventsData = [];
      if (tenantId != null) {
        final eventsRes = await _client
            .from('events')
            .select()
            .eq('tenant_id', tenantId)
            .gte('date', DateTime.now().toIso8601String())
            .order('date', ascending: true)
            .limit(3);
        eventsData = (eventsRes as List).cast<Map<String, dynamic>>();
      }

      final results = await Future.wait([sermonsFuture, popularFuture, newThisWeekFuture]);
      final sermonsData = (results[0] as List).map((s) => Sermon.fromMap(s)).toList();
      final popularData = (results[1] as List).map((s) => Sermon.fromMap(s)).toList();
      final newData = (results[2] as List).map((s) => Sermon.fromMap(s)).toList();

      return RecommendedContent(
        recommendedSermons: sermonsData,
        upcomingEvents: eventsData,
        popularContent: popularData,
        newThisWeek: newData,
      );
    } catch (e) {
      debugPrint('Error fetching recommendations: $e');
      return RecommendedContent(
        recommendedSermons: [],
        upcomingEvents: [],
        popularContent: [],
        newThisWeek: [],
      );
    }
  }
}

final discoverServiceProvider = Provider((ref) => DiscoverService(Supabase.instance.client, ref));

final discoverContentProvider = FutureProvider<RecommendedContent>((ref) async {
  return ref.watch(discoverServiceProvider).fetchRecommendations();
});
