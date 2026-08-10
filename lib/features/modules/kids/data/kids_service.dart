import 'dart:async';
import 'package:flutter/foundation.dart';
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

  Future<void> uploadLesson({
    required String title,
    required String description,
    required String category,
    String? imageUrl,
    String? contentUrl,
    int? ageMin,
    int? ageMax,
    String? uploadedBy,
    String? tenantId,
  }) async {
    await _client.from('kids_zone_resources').insert({
      'title': title,
      'description': description,
      'category': category,
      'image_url': imageUrl ?? '',
      'content_url': contentUrl,
      'age_min': ageMin ?? 3,
      'age_max': ageMax ?? 12,
      'is_free': true,
      'uploaded_by': uploadedBy,
      'created_at': DateTime.now().toIso8601String(),
    });

    if (tenantId != null) {
      unawaited(notifyNewResource(tenantId, title, category));
    }
  }

  Future<void> seedFreeResources() async {
    final existing =
        await _client.from('kids_zone_resources').select('id').limit(1);
    if (existing.isNotEmpty) return;

    final resources = [
      {
        'title': 'David and Goliath',
        'description':
            "The classic Bible story of young David defeating the giant Goliath with God's help.",
        'category': 'bible_story',

        'content_url':
            'https://www.biblegateway.com/passage/?search=1+Samuel+17&version=NIV',
        'age_min': 3,
        'age_max': 12,
      },
      {
        'title': "Noah's Ark",
        'description':
            "Learn about Noah, the ark, and God's promise with the rainbow.",
        'category': 'bible_story',

        'content_url':
            'https://www.biblegateway.com/passage/?search=Genesis+6-9&version=NIV',
        'age_min': 3,
        'age_max': 10,
      },
      {
        'title': 'Moses and the Red Sea',
        'description':
            'Watch how God parted the Red Sea to save His people.',
        'category': 'bible_story',

        'age_min': 4,
        'age_max': 12,
      },
      {
        'title': 'Coloring: Jesus Loves Me',
        'description':
            "A fun coloring page about Jesus' love for children.",
        'category': 'coloring',

        'age_min': 3,
        'age_max': 8,
      },
      {
        'title': 'Memory Verse Game',
        'description':
            'Memorize John 3:16 with this fun matching game.',
        'category': 'activity',

        'age_min': 5,
        'age_max': 12,
      },
      {
        'title': 'The Fruit of the Spirit',
        'description':
            'A lesson on Galatians 5:22-23 - love, joy, peace, patience, kindness, goodness, faithfulness, gentleness, self-control.',
        'category': 'lesson',

        'content_url':
            'https://www.biblegateway.com/passage/?search=Mark+4:35-41&version=NIV',
        'age_min': 3,
        'age_max': 10,
      },
      {
        "title": "Daniel in the Lion's Den",
        'description':
            "Daniel's faith protected him from the lions. A story of courage and trust in God.",
        'category': 'bible_story',

        'content_url':
            'https://www.biblegateway.com/passage/?search=Daniel+6&version=NIV',
        'age_min': 4,
        'age_max': 12,
      },
      {
        'title': 'Worship Song: Jesus Loves Me',
        'description':
            "Sing along to the classic children's worship song.",
        'category': 'song',

        'content_url':
            'https://www.youtube.com/watch?v=6OqSqM1JxgQ',
        'age_min': 2,
        'age_max': 10,
      },
      {
        'title': 'Creation Story Coloring',
        'description':
            'Color the 7 days of creation as described in Genesis.',
        'category': 'coloring',

      },
      {
        'title': 'Easter: Jesus is Alive!',
        'description':
            "The story of Jesus' resurrection on Easter Sunday.",
        'category': 'bible_story',

        'content_url':
            'https://www.biblegateway.com/passage/?search=Luke+24&version=NIV',
        'age_min': 3,
        'age_max': 12,
      },
      {
        'title': 'Thanksgiving to God',
        'description':
            'A lesson about being thankful to God for all His blessings.',
        'category': 'lesson',

      },
    ];

    for (final r in resources) {
      await _client.from('kids_zone_resources').insert(r);
    }
  }

  Future<void> notifyNewResource(String tenantId, String title, String category) async {
    try {
      final members = await _client
          .from('profiles')
          .select('id')
          .eq('tenant_id', tenantId);

      if ((members as List).isNotEmpty) {
        final userIds = (members).map((m) => m['id'] as String).toList();
        final categoryLabel = category.replaceAll('_', ' ');
        await _client.functions.invoke('push-notifications', body: {
          'userIds': userIds,
          'title': '🎨 New Kids Resource',
          'body': '$title added to $categoryLabel',
          'data': {
            'type': 'kids_zone',
            'channel_id': 'coa_announcements',
          },
        });
      }
    } catch (e) {
      debugPrint('[KidsService] Push notification failed: $e');
    }
  }
}

final kidsServiceProvider = Provider((ref) => KidsService(Supabase.instance.client));

final kidsResourcesProvider = FutureProvider<List<KidsZoneResource>>((ref) async {
  return ref.watch(kidsServiceProvider).fetchKidsResources();
});
