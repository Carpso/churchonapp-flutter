import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';

class KidsZoneResource {
  final String id;
  final String title;
  final String? description;
  final String category; // 'bible_story', 'activity', 'coloring', 'game', 'lesson', 'video', 'song'
  final String? imageUrl;
  final String? contentUrl;
  final int ageMin;
  final int ageMax;
  final int sortOrder;
  final bool isFree;

  KidsZoneResource({
    this.id = '',
    required this.title,
    this.description = '',
    this.category = 'activity',
    this.imageUrl,
    this.contentUrl,
    this.ageMin = 3,
    this.ageMax = 12,
    this.sortOrder = 0,
    required this.isFree,
  });

  IconData get categoryIcon {
    switch (category) {
      case 'bible_story': return LucideIcons.bookOpen;
      case 'activity': return LucideIcons.puzzle;
      case 'coloring': return LucideIcons.penTool;
      case 'game': return LucideIcons.gamepad;
      case 'lesson': return LucideIcons.video;
      case 'video': return LucideIcons.play;
      case 'song': return LucideIcons.music;
      default: return LucideIcons.star;
    }
  }

  factory KidsZoneResource.fromMap(Map<String, dynamic> map) {
    return KidsZoneResource(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      category: map['category']?.toString() ?? 'activity',
      imageUrl: map['image_url']?.toString(),
      contentUrl: map['content_url']?.toString(),
      ageMin: int.tryParse(map['age_min']?.toString() ?? '3') ?? 3,
      ageMax: int.tryParse(map['age_max']?.toString() ?? '12') ?? 12,
      sortOrder: int.tryParse(map['sort_order']?.toString() ?? '0') ?? 0,
      isFree: map['is_free'] != false,
    );
  }
}

class KidsService {
  final SupabaseClient _client;
  KidsService(this._client);

  Future<List<KidsZoneResource>> fetchKidsResources() async {
    final response = await _client
        .from('kids_zone_resources')
        .select()
        .order('sort_order', ascending: true);

    return (response as List).map((r) => KidsZoneResource.fromMap(r)).toList();
  }
}

final kidsServiceProvider = Provider((ref) => KidsService(Supabase.instance.client));

final kidsResourcesProvider = FutureProvider<List<KidsZoneResource>>((ref) async {
  return ref.watch(kidsServiceProvider).fetchKidsResources();
});
