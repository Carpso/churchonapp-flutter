import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/services/supabase_service.dart';

class Devotion {
  final String id;
  final String title;
  final String reference;
  final String scriptureText;
  final String reflection;
  final String prayer;
  final DateTime date;
  final bool isToday;

  Devotion({
    required this.id,
    required this.title,
    required this.reference,
    required this.scriptureText,
    required this.reflection,
    required this.prayer,
    required this.date,
    this.isToday = false,
  });

  factory Devotion.fromMap(Map<String, dynamic> map, {bool isToday = false}) {
    return Devotion(
      id: map['id']?.toString() ?? '',
      title: map['title'] ?? map['reference'] ?? 'Daily Devotion',
      reference: map['reference'] ?? map['media_url'] ?? 'Scripture',
      scriptureText: map['scripture_text'] ?? map['text'] ?? map['content'] ?? '',
      reflection: map['reflection'] ?? map['commentary'] ?? 'Reflect on how this scripture speaks to your life today.',
      prayer: map['prayer'] ?? 'Lord, help me to apply Your word to my heart. Amen.',
      date: map['created_at'] != null ? DateTime.parse(map['created_at']) : DateTime.now(),
      isToday: isToday,
    );
  }

  String get excerpt {
    final text = scriptureText.isNotEmpty ? scriptureText : reflection;
    if (text.length <= 120) return text;
    return '${text.substring(0, 120)}...';
  }

  String get formattedDate {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

class DevotionService {
  final SupabaseClient _client;
  DevotionService(this._client);

  Future<List<Devotion>> fetchDevotions() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    try {
      final data = await _client
          .from('daily_bible_verses')
          .select()
          .order('created_at', ascending: false)
          .limit(50);

      if (data.isNotEmpty) {
        return data.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          final createdAt = item['created_at'] != null
              ? DateTime.parse(item['created_at'])
              : DateTime.now();
          final createdDate = DateTime(createdAt.year, createdAt.month, createdAt.day);
          return Devotion.fromMap(item, isToday: createdDate == todayStart && index == 0);
        }).toList();
      }
    } catch (e) {
      debugPrint('DevotionService: daily_bible_verses query failed: $e');
    }

    try {
      final data = await _client
          .from('devotions')
          .select()
          .order('created_at', ascending: false)
          .limit(50);

      if (data.isNotEmpty) {
        return data.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          final createdAt = item['created_at'] != null
              ? DateTime.parse(item['created_at'])
              : DateTime.now();
          final createdDate = DateTime(createdAt.year, createdAt.month, createdAt.day);
          return Devotion.fromMap(item, isToday: createdDate == todayStart && index == 0);
        }).toList();
      }
    } catch (e) {
      debugPrint('DevotionService: devotions table query failed: $e');
    }

    return _fallbackDevotions(todayStart);
  }

  Future<Devotion?> fetchTodaysDevotion() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));

    try {
      final data = await _client
          .from('daily_bible_verses')
          .select()
          .gte('created_at', todayStart.toIso8601String())
          .lt('created_at', todayEnd.toIso8601String())
          .order('created_at')
          .limit(1)
          .maybeSingle();

      if (data != null) {
        return Devotion.fromMap(data, isToday: true);
      }
    } catch (e) {
      debugPrint('DevotionService: today query failed: $e');
    }

    return null;
  }

  List<Devotion> _fallbackDevotions(DateTime todayStart) {
    return [
      Devotion(
        id: 'fallback_1',
        title: 'Jeremiah 29:11',
        reference: 'Jeremiah 29:11',
        scriptureText: 'For I know the thoughts that I think toward you, saith the Lord, thoughts of peace, and not of evil, to give you an expected end.',
        reflection: 'God has a plan for your life. Even when circumstances seem uncertain, His thoughts toward you are good. Trust in His divine purpose and timing.',
        prayer: 'Heavenly Father, thank You for Your good plans for my life. Help me to trust You even when I cannot see the full picture. Give me peace in the waiting. In Jesus\' name, Amen.',
        date: todayStart,
        isToday: true,
      ),
      Devotion(
        id: 'fallback_2',
        title: 'Psalm 23:1',
        reference: 'Psalm 23:1',
        scriptureText: 'The Lord is my shepherd; I shall not want.',
        reflection: 'David declares complete trust in the Lord\'s provision. When we recognize God as our Shepherd, we can rest in the assurance that He will provide for every need.',
        prayer: 'Lord, You are my Shepherd. Help me to rely on Your guidance and provision. Quiet my anxious heart and help me to rest in Your care. Amen.',
        date: todayStart.subtract(const Duration(days: 1)),
      ),
      Devotion(
        id: 'fallback_3',
        title: 'Philippians 4:13',
        reference: 'Philippians 4:13',
        scriptureText: 'I can do all things through Christ which strengtheneth me.',
        reflection: 'Paul reminds us that our strength comes from Christ, not ourselves. Whatever challenges we face, we can overcome them through His power working in us.',
        prayer: 'Father, I draw my strength from You. When I feel weak, remind me that Your grace is sufficient. Help me to face today with confidence in Christ. Amen.',
        date: todayStart.subtract(const Duration(days: 2)),
      ),
      Devotion(
        id: 'fallback_4',
        title: 'Romans 8:28',
        reference: 'Romans 8:28',
        scriptureText: 'And we know that all things work together for good to them that love God, to them who are the called according to his purpose.',
        reflection: 'God is sovereign over every circumstance. He weaves even the difficult moments into a tapestry of good for those who love Him and are called according to His purpose.',
        prayer: 'Lord, help me to see Your hand in every situation. Give me faith to believe that You are working all things for my good and Your glory. Amen.',
        date: todayStart.subtract(const Duration(days: 3)),
      ),
    ];
  }
}

final devotionServiceProvider = Provider((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return DevotionService(client);
});

final devotionsProvider = FutureProvider<List<Devotion>>((ref) async {
  return ref.watch(devotionServiceProvider).fetchDevotions();
});

final todaysDevotionProvider = FutureProvider<Devotion?>((ref) async {
  return ref.watch(devotionServiceProvider).fetchTodaysDevotion();
});
