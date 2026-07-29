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
      return [];
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
      return const Stream.empty();
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
      if (tenant == null) return [];

      final data = await _client
          .from('pastors_corner')
          .select()
          .eq('church_id', tenant.id)
          .order('created_at', ascending: false);

      final messages = (data as List).map((map) => PastorMessage.fromMap(map)).toList();
      return messages;
    } catch (e) {
      debugPrint('Error fetching pastor messages: $e');
      return [];
    }
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
