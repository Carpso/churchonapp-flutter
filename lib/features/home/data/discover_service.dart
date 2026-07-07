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

      if (sermonsData.isEmpty && popularData.isEmpty) {
        return _getMockContent();
      }

      return RecommendedContent(
        recommendedSermons: sermonsData,
        upcomingEvents: eventsData,
        popularContent: popularData,
        newThisWeek: newData,
      );
    } catch (e) {
      debugPrint('Error fetching recommendations: $e');
      return _getMockContent();
    }
  }

  RecommendedContent _getMockContent() {
    return RecommendedContent(
      recommendedSermons: [
        Sermon(id: 's1', title: 'The Path to Faithful Stewardship', preacher: 'Pastor John Doe', thumbnailUrl: 'https://images.unsplash.com/photo-1438232992991-995b7058bbb3?w=800', videoUrl: '', createdAt: DateTime.now()),
        Sermon(id: 's2', title: 'Grace Abounding', preacher: 'Pastor Hope', thumbnailUrl: 'https://images.unsplash.com/photo-1543165796-5426273ea430?w=800', videoUrl: '', createdAt: DateTime.now()),
        Sermon(id: 's3', title: 'Walking in Divine Purpose', preacher: 'Pastor Sarah', thumbnailUrl: 'https://images.unsplash.com/photo-1504052434568-3adbf6a1b1e8?w=800', videoUrl: '', createdAt: DateTime.now()),
      ],
      upcomingEvents: [
        {'id': 'e1', 'title': 'Night of Worship', 'date': DateTime.now().add(const Duration(days: 3)).toIso8601String(), 'location': 'Main Sanctuary', 'image_url': 'https://images.unsplash.com/photo-1444464666168-49d633b867ad?w=800'},
        {'id': 'e2', 'title': 'Youth Bible Study', 'date': DateTime.now().add(const Duration(days: 5)).toIso8601String(), 'location': 'Fellowship Hall', 'image_url': 'https://images.unsplash.com/photo-1523580494863-6f3031224c94?w=800'},
        {'id': 'e3', 'title': 'Community Outreach', 'date': DateTime.now().add(const Duration(days: 10)).toIso8601String(), 'location': 'City Center', 'image_url': 'https://images.unsplash.com/photo-1488521787991-ed7bbaae773c?w=800'},
      ],
      popularContent: [
        Sermon(id: 's4', title: 'Faith That Moves Mountains', preacher: 'Pastor John Doe', thumbnailUrl: 'https://images.unsplash.com/photo-1470115637082-9fb4a8f96e0f?w=800', videoUrl: '', createdAt: DateTime.now()),
        Sermon(id: 's5', title: 'The Armor of God', preacher: 'Pastor Hope', thumbnailUrl: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=800', videoUrl: '', createdAt: DateTime.now()),
      ],
      newThisWeek: [
        Sermon(id: 's6', title: 'New Season, New Anointing', preacher: 'Pastor Sarah', thumbnailUrl: 'https://images.unsplash.com/photo-1519741497674-611481863552?w=800', videoUrl: '', createdAt: DateTime.now()),
        Sermon(id: 's7', title: 'Prayer That Changes Nations', preacher: 'Pastor John Doe', thumbnailUrl: 'https://images.unsplash.com/photo-1446776811953-b23d57bd21aa?w=800', videoUrl: '', createdAt: DateTime.now()),
      ],
    );
  }
}

final discoverServiceProvider = Provider((ref) => DiscoverService(Supabase.instance.client, ref));

final discoverContentProvider = FutureProvider<RecommendedContent>((ref) async {
  return ref.watch(discoverServiceProvider).fetchRecommendations();
});
