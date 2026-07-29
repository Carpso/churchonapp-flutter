import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DbSeeder {
  static Future<void> seedAll() async {
    final client = Supabase.instance.client;

    // 1. Seed Churches (Tenants)
    final churches = [
      {
        'id': 'd0f8c8b0-0000-0000-0000-000000000001',
        'slug': 'bol',
        'name': 'Bread of Life Church',
        'logo_url': 'https://images.unsplash.com/photo-1438232992991-995b7058bbb3?w=800',
        'latitude': -15.4214,
        'longitude': 28.2861,
        'primary_color': '#FFD700',
        'accent_color': '#1A1A1A',
      },
      {
        'id': 'd0f8c8b0-0000-0000-0000-000000000002',
        'slug': 'miracle',
        'name': 'Miracle Life Family',
        'logo_url': 'https://images.unsplash.com/photo-1510133755869-79a639739569?w=800',
        'latitude': -15.3900,
        'longitude': 28.3200,
        'primary_color': '#1E40AF',
        'accent_color': '#FFFFFF',
      },
      {
        'id': 'd0f8c8b0-0000-0000-0000-000000000003',
        'slug': 'prophetic',
        'name': 'Prophetic Impact Ministries',
        'logo_url': 'https://images.unsplash.com/photo-1516280440614-37939bbacd81?w=800',
        'latitude': -15.4500,
        'longitude': 28.2500,
        'primary_color': '#B8860B',
        'accent_color': '#000000',
      }
    ];

    try {
      await client.from('churches').upsert(churches);
    } catch (e) {
      debugPrint('Error seeding churches: $e');
    }

    // 2. Seed Prayers
    final prayers = [
      {
        'user_name': 'Mary Banda',
        'content': 'Interceding for the healings of the sick in our community. We believe in the power of the blood of Jesus.',
        'category': 'healing',
        'prayer_count': 42,
        'prayed_by': [],
        'is_anonymous': false,
        'ai_encouragement': 'He was wounded for our transgressions; by his stripes we are healed.',
        'created_at': DateTime.now().toIso8601String(),
      },
      {
        'user_name': 'Anonymous Priest',
        'content': 'Lord, provide for the orphans in the Lusaka district. Let them feel your fatherly love today.',
        'category': 'mission',
        'prayer_count': 156,
        'prayed_by': [],
        'is_anonymous': true,
        'ai_encouragement': 'A father to the fatherless is God in his holy habitation.',
        'created_at': DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
      }
    ];

    try {
      await client.from('prayers').insert(prayers);
    } catch (e) {
      debugPrint('Error seeding prayers: $e');
    }

    // 3. Seed News
    final news = [
      {
        'title': 'The Great Awakening: Zambia 2026',
        'excerpt': 'A move of God is sweeping through the Copperbelt region.',
        'content': 'Pastors from all over the country are gathering for a week of prayer and fasting...',
        'author_name': 'Evangelist Paul',
        'image_url': 'https://images.unsplash.com/photo-1490730141103-6cac27aaab94?w=800',
        'created_at': DateTime.now().toIso8601String(),
      },
      {
        'title': 'New Tech Hub at COA HQ',
        'excerpt': 'Bridging the gap between ministry and innovation.',
        'content': 'The new office will house 50 developers dedicated to building church tools.',
        'author_name': 'Tech Director Luke',
        'image_url': 'https://images.unsplash.com/photo-1512389142860-9c449e58a543?w=800',
        'created_at': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
      }
    ];

    try {
      await client.from('kingdom_news').insert(news);
    } catch (e) {
      debugPrint('Error seeding news: $e');
    }

    // 4. Seed Sermons
    final sermons = [
      {
        'church_id': 'd0f8c8b0-0000-0000-0000-000000000001',
        'title': 'Walking in the Spirit',
        'preacher': 'Bishop Joe Imakando',
        'video_url': 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        'thumbnail_url': 'https://images.unsplash.com/photo-1438232992991-995b7058bbb3?w=800',
        'category': 'lifestyle',
      },
      {
        'church_id': 'd0f8c8b0-0000-0000-0000-000000000002',
        'title': 'The Power of Favor',
        'preacher': 'Pastor Conrad Mbewe',
        'video_url': 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        'thumbnail_url': 'https://images.unsplash.com/photo-1510133755869-79a639739569?w=800',
        'category': 'theology',
      },
      // Rock Of Ages Chapel Kabulonga sermon
      {
        'tenant_id': '00000000-0000-0000-0000-000000000036',
        'church_id': '00000000-0000-0000-0000-000000000036',
        'title': 'The Power of Persistent Prayer',
        'preacher': 'Pastor Chola Musonda',
        'video_url': 'https://assets.mixkit.co/videos/preview/mixkit-pastor-preaching-at-a-church-service-34538-large.mp4',
        'thumbnail_url': 'https://images.unsplash.com/photo-1507699622108-4be3abd695ad?w=800',
        'category': 'faith',
      },
    ];

    try {
      await client.from('sermons').insert(sermons);
    } catch (e) {
      debugPrint('Error seeding sermons: $e');
    }

    // 5. Seed Jobs
    final jobs = [
      {
        'title': 'Senior App Developer',
        'company': 'Church On App LTD',
        'location': 'Lusaka, Zambia',
        'type': 'Full-time',
        'salary_range': 'K25,000 - K40,000',
        'description': 'Help us build the sovereign network for the faith.',
      },
      {
        'title': 'Social Media Manager',
        'company': 'Prophetic Ministries',
        'location': 'Remote',
        'type': 'Contract',
        'salary_range': 'K5,000 - K8,000',
        'description': 'Manage our global outreach channels.',
      }
    ];

    try {
      await client.from('jobs').insert(jobs);
    } catch (e) {
      debugPrint('Error seeding jobs: $e');
    }

    // 6. Seed Klips
    final klips = [
      {
        'user_name': 'Worship Leader Sarah',
        'description': 'Quick snippet from Sunday worship! 🔥',
        'video_url': 'https://assets.mixkit.co/videos/preview/mixkit-girl-singing-into-a-microphone-in-a-studio-34537-large.mp4',
        'thumbnail_url': 'https://images.unsplash.com/photo-1516280440614-37939bbacd81?w=400',
        'likes': 1205,
      },
      {
        'user_name': 'Prophet Amos',
        'description': 'Word of Encourgement for your week.',
        'video_url': 'https://assets.mixkit.co/videos/preview/mixkit-man-delivering-a-speech-on-a-stage-40436-large.mp4',
        'thumbnail_url': 'https://images.unsplash.com/photo-1544427928-c49cdfebf4ad?w=400',
        'likes': 890,
      }
    ];

    try {
      await client.from('klips').insert(klips);
    } catch (e) {
      debugPrint('Error seeding klips: $e');
    }

    // 7. Seed Events
    final events = [
      {
        'title': 'Zambia Shall Be Saved Conference',
        'description': 'A massive gathering of believers at the Heroes Stadium.',
        'location': 'Heroes Stadium, Lusaka',
        'date': DateTime.now().add(const Duration(days: 14)).toIso8601String(),
        'image_url': 'https://images.unsplash.com/photo-1501281668745-f7f57925c3b4?w=800',
        'ticket_price': 50.0,
        'category': 'Conference',
      },
      {
        'title': 'Night of Miracles',
        'description': 'Experience the healing power of God.',
        'location': 'Miracle Life Main Hall',
        'date': DateTime.now().add(const Duration(days: 3)).toIso8601String(),
        'image_url': 'https://images.unsplash.com/photo-1490730141103-6cac27aaab94?w=800',
        'ticket_price': 0.0,
        'category': 'Concert',
      }
    ];

    try {
      await client.from('events').insert(events);
    } catch (e) {
      debugPrint('Error seeding events: $e');
    }

    // 8. Seed Social Posts
    final posts = [
      {
        'content': 'Taking the Gospel to the digital frontier! 🚀',
        'media_url': 'https://images.unsplash.com/photo-1512389142860-9c449e58a543?w=800',
        'media_type': 'image',
        'likes_count': 342,
        'category': 'general',
      },
      {
        'content': 'God is doing something new in our generation. Stay expectant!',
        'media_url': null,
        'media_type': null,
        'likes_count': 120,
        'category': 'prophetic',
      }
    ];

    try {
      await client.from('social_posts').insert(posts);
    } catch (e) {
      debugPrint('Error seeding posts: $e');
    }

    // 9. Seed Testimonies
    final testimonies = [
      {
        'user_name': 'Brother Isaac',
        'content': 'I was looking for a job for 2 years. After joining the COA prayer wall, I got 3 offers in one week! God is faithful.',
        'category': 'Career',
        'likes': 89,
      },
      {
        'user_name': 'Sister Grace',
        'content': 'Healed from chronic back pain during the Sunday broadcast. Praise Jesus!',
        'category': 'Healing',
        'likes': 250,
      }
    ];

    try {
      await client.from('testimonies').insert(testimonies);
    } catch (e) {
      debugPrint('Error seeding testimonies: $e');
    }
  }
}
