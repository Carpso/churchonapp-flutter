import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/tenant_service.dart';

class ConnectedChurch {
  final String id;
  final String name;
  final String? location;
  final String? logoUrl;
  final int memberCount;
  final bool isConnected;

  ConnectedChurch({
    required this.id,
    required this.name,
    this.location,
    this.logoUrl,
    this.memberCount = 0,
    this.isConnected = false,
  });

  factory ConnectedChurch.fromMap(Map<String, dynamic> map) {
    return ConnectedChurch(
      id: map['id']?.toString() ?? '',
      name: map['name'] ?? 'Unknown Church',
      location: map['address'] ?? map['location'],
      logoUrl: map['logo_url'] ?? map['logo'],
      memberCount: map['member_count'] ?? 0,
      isConnected: map['is_connected'] ?? false,
    );
  }
}

class NetworkActivity {
  final String id;
  final String churchName;
  final String churchId;
  final String type;
  final String title;
  final String? description;
  final String? referenceId;
  final DateTime createdAt;

  NetworkActivity({
    required this.id,
    required this.churchName,
    required this.churchId,
    required this.type,
    required this.title,
    this.description,
    this.referenceId,
    required this.createdAt,
  });

  factory NetworkActivity.fromMap(Map<String, dynamic> map) {
    return NetworkActivity(
      id: map['id']?.toString() ?? '',
      churchName: map['church_name'] ?? map['churches']?['name'] ?? 'Unknown Church',
      churchId: map['church_id'] ?? '',
      type: map['type'] ?? 'sermon',
      title: map['title'] ?? '',
      description: map['description'] ?? map['excerpt'],
      referenceId: map['reference_id'],
      createdAt: DateTime.parse(map['created_at'] ?? DateTime.now().toIso8601String()),
    );
  }
}

class PastorMessage {
  final String id;
  final String pastorName;
  final String? pastorPhoto;
  final String title;
  final String excerpt;
  final String content;
  final DateTime createdAt;

  PastorMessage({
    required this.id,
    required this.pastorName,
    this.pastorPhoto,
    required this.title,
    required this.excerpt,
    required this.content,
    required this.createdAt,
  });

  factory PastorMessage.fromMap(Map<String, dynamic> map) {
    return PastorMessage(
      id: map['id']?.toString() ?? '',
      pastorName: map['pastor_name'] ?? map['author_name'] ?? 'Pastor',
      pastorPhoto: map['pastor_photo'] ?? map['author_photo'],
      title: map['title'] ?? 'Untitled',
      excerpt: map['excerpt'] ?? map['content']?.toString().substring(0, (map['content']?.toString().length ?? 100).clamp(0, 100)) ?? '',
      content: map['content'] ?? map['excerpt'] ?? '',
      createdAt: DateTime.parse(map['created_at'] ?? DateTime.now().toIso8601String()),
    );
  }
}

class NetworkService {
  final SupabaseClient _client;
  final Ref _ref;
  NetworkService(this._client, this._ref);

  Future<List<ConnectedChurch>> fetchConnectedChurches({String? search}) async {
    try {
      final tenant = _ref.read(currentTenantProvider);

      var query = _client
          .from('churches')
          .select('*, church_connections!left(connected_church_id)');

      if (tenant != null) {
        query = query.neq('id', tenant.id);
      }

      PostgrestFilterBuilder<PostgrestList> filterBuilder = query;
      if (search != null && search.isNotEmpty) {
        filterBuilder = filterBuilder.or('name.ilike.%$search%,address.ilike.%$search%');
      }
      final data = await filterBuilder.limit(50);
      return (data as List).map((map) => ConnectedChurch.fromMap(map)).toList();
    } catch (e) {
      debugPrint('Error fetching connected churches: $e');
      return _getMockChurches(search);
    }
  }

  Stream<List<NetworkActivity>> streamNetworkActivity() {
    try {
      return _client
          .from('network_activity')
          .stream(primaryKey: ['id'])
          .order('created_at', ascending: false)
          .limit(50)
          .map((data) => data.map((map) => NetworkActivity.fromMap(map)).toList());
    } catch (e) {
      return Stream.value(_getMockActivities());
    }
  }

  Future<void> connectToChurch(String churchId) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client.from('church_connections').insert({
      'user_id': user.id,
      'connected_church_id': churchId,
    });
  }

  Future<List<PastorMessage>> fetchPastorMessages() async {
    try {
      final tenant = _ref.read(currentTenantProvider);
      if (tenant == null) return _getMockPastorMessages();

      final data = await _client
          .from('pastors_corner')
          .select()
          .eq('church_id', tenant.id)
          .order('created_at', ascending: false);

      final messages = (data as List).map((map) => PastorMessage.fromMap(map)).toList();
      if (messages.isEmpty) return _getMockPastorMessages();
      return messages;
    } catch (e) {
      debugPrint('Error fetching pastor messages: $e');
      return _getMockPastorMessages();
    }
  }

  List<ConnectedChurch> _getMockChurches(String? search) {
    final churches = [
      ConnectedChurch(id: 'c1', name: 'Bread of Life Church Int.', location: 'Makeni Road, Lusaka', memberCount: 1240),
      ConnectedChurch(id: 'c2', name: 'Mount Zion Christian Centre', location: 'Chamba Valley, Lusaka', memberCount: 890),
      ConnectedChurch(id: 'c3', name: 'Harvest House International', location: 'Leopards Hill, Lusaka', memberCount: 2100),
      ConnectedChurch(id: 'c4', name: 'Celebration Church International', location: 'Borrowdale Rd, Harare', memberCount: 3400),
      ConnectedChurch(id: 'c5', name: 'Kitwe Chapel', location: 'Obote Avenue, Kitwe', memberCount: 560),
    ];
    if (search != null && search.isNotEmpty) {
      final q = search.toLowerCase();
      return churches.where((c) => c.name.toLowerCase().contains(q) || (c.location?.toLowerCase().contains(q) ?? false)).toList();
    }
    return churches;
  }

  List<NetworkActivity> _getMockActivities() {
    return [
      NetworkActivity(id: 'a1', churchName: 'Bread of Life Church', churchId: 'c1', type: 'sermon', title: 'The Path to Faithful Stewardship', description: 'Pastor John shared a powerful message on stewardship and faith.', createdAt: DateTime.now().subtract(const Duration(hours: 2))),
      NetworkActivity(id: 'a2', churchName: 'Mount Zion Centre', churchId: 'c2', type: 'event', title: 'Night of Worship', description: 'Join us for a night of worship and prayer.', createdAt: DateTime.now().subtract(const Duration(hours: 5))),
      NetworkActivity(id: 'a3', churchName: 'Celebration Church', churchId: 'c4', type: 'prayer', title: 'Prayer Request: Healing', description: 'Please pray for our community healing service.', createdAt: DateTime.now().subtract(const Duration(days: 1))),
      NetworkActivity(id: 'a4', churchName: 'Harvest House', churchId: 'c3', type: 'sermon', title: 'Grace Abounding', description: 'A sermon on the unending grace of God.', createdAt: DateTime.now().subtract(const Duration(days: 2))),
    ];
  }

  List<PastorMessage> _getMockPastorMessages() {
    return [
      PastorMessage(id: 'p1', pastorName: 'Pastor John', title: 'Walking in Faith', excerpt: 'Faith is the substance of things hoped for, the evidence of things not seen...', content: 'Faith is the substance of things hoped for, the evidence of things not seen. In our walk with Christ, we must learn to trust God even when we cannot see the outcome. Remember that God is faithful and His promises are true. Keep pressing forward in faith, knowing that He who began a good work in you will carry it on to completion.\n\nLet us encourage one another daily and build each other up in our most holy faith.', createdAt: DateTime.now().subtract(const Duration(days: 1))),
      PastorMessage(id: 'p2', pastorName: 'Pastor John', title: 'The Power of Unity', excerpt: 'When we come together in unity, God commands a blessing...', content: 'When we come together in unity, God commands a blessing. The early church was marked by their unity and devotion to fellowship. As a church family, we must prioritize our togetherness and support one another through every season of life.', createdAt: DateTime.now().subtract(const Duration(days: 4))),
      PastorMessage(id: 'p3', pastorName: 'Pastor John', title: 'Season of Breakthrough', excerpt: 'I sense that this is a season of breakthrough for our church...', content: 'I sense that this is a season of breakthrough for our church. God is doing a new thing in our midst. Open your eyes and see the opportunities He is placing before you. This is the time to step out in faith and claim the victories He has prepared for us.', createdAt: DateTime.now().subtract(const Duration(days: 7))),
    ];
  }
}

final networkServiceProvider = Provider((ref) => NetworkService(Supabase.instance.client, ref));

final connectedChurchesProvider = FutureProvider.family<List<ConnectedChurch>, String?>((ref, search) async {
  return ref.watch(networkServiceProvider).fetchConnectedChurches(search: search);
});

final networkActivityStreamProvider = StreamProvider<List<NetworkActivity>>((ref) {
  return ref.watch(networkServiceProvider).streamNetworkActivity();
});

final pastorMessagesProvider = FutureProvider<List<PastorMessage>>((ref) async {
  return ref.watch(networkServiceProvider).fetchPastorMessages();
});
