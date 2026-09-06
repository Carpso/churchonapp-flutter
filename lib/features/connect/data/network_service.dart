import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/tenant_service.dart';

class ConnectedChurch {
  final String id;
  final String? tenantId;
  final String name;
  final String? location;
  final String? logoUrl;
  final int memberCount;
  final bool isConnected;
  final String? nextProgramName;
  final DateTime? nextProgramDate;

  ConnectedChurch({
    required this.id,
    this.tenantId,
    required this.name,
    this.location,
    this.logoUrl,
    this.memberCount = 0,
    this.isConnected = false,
    this.nextProgramName,
    this.nextProgramDate,
  });

  factory ConnectedChurch.fromMap(Map<String, dynamic> map) {
    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      try {
        return DateTime.parse(v.toString());
      } catch (_) {
        return null;
      }
    }

    return ConnectedChurch(
      id: map['id']?.toString() ?? '',
      tenantId: map['tenant_id']?.toString(),
      name: map['name'] ?? 'Unknown Church',
      location: map['address'] ?? map['location'],
      logoUrl: map['logo_url'] ?? map['logo'],
      memberCount: map['member_count'] ?? 0,
      isConnected: map['is_connected'] ?? false,
      nextProgramName: map['next_program_name'],
      nextProgramDate: parseDate(map['next_program_date']),
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
    final content = (map['content'] ?? map['excerpt'] ?? '').toString();
    return PastorMessage(
      id: map['id']?.toString() ?? '',
      pastorName: map['pastor_name'] ?? map['author_name'] ?? 'Pastor',
      pastorPhoto: map['pastor_photo'] ?? map['author_photo'],
      title: map['title'] ?? 'Untitled',
      excerpt: map['excerpt']?.toString() ??
          (content.length <= 140 ? content : '${content.substring(0, 140)}…'),
      content: content,
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

      var query = _client.from('churches').select('*, church_connections!left(connected_church_id)');

      if (tenant != null) {
        query = query.neq('id', tenant.id);
      }

      PostgrestFilterBuilder<PostgrestList> filterBuilder = query;
      if (search != null && search.isNotEmpty) {
        filterBuilder = filterBuilder.or('name.ilike.%$search%,address.ilike.%$search%');
      }
      final data = await filterBuilder.limit(50);

      final memberCounts = <String, int>{};
      try {
        final counts = await _client.rpc('get_church_member_counts');
        if (counts is List) {
          for (final row in counts) {
            final churchId = (row as Map)['church_id']?.toString();
            if (churchId != null) {
              memberCounts[churchId] = ((row['member_count'] as num?) ?? 0).toInt();
            }
          }
        }
      } catch (e) {
        debugPrint('Error fetching member counts: $e');
      }

      final programs = <String, Map<String, dynamic>>{};
      try {
        final progs = await _client.rpc('get_connected_church_programs', params: {'p_limit': 50});
        if (progs is List) {
          for (final row in progs) {
            final churchId = (row as Map)['church_id']?.toString();
            if (churchId != null) {
              programs[churchId] = Map<String, dynamic>.from(row);
            }
          }
        }
      } catch (e) {
        debugPrint('Error fetching connected church programs: $e');
      }

      return (data as List).map((map) {
        final churchId = map['id']?.toString() ?? '';
        final prog = programs[churchId];
        return ConnectedChurch.fromMap({
          ...map,
          'member_count': memberCounts[churchId] ?? 0,
          'next_program_name': prog?['ministry_name'] != null
              ? '${prog!['ministry_name']} • ${prog['scheduled_for'] != null ? prog['scheduled_for'].toString().split('T').first : ''}'
              : null,
          'next_program_date': prog?['scheduled_for'],
        });
      }).toList();
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
          .map((data) {
        final rows = data
            .map((map) => NetworkActivity.fromMap(map))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return rows.length > 50 ? rows.sublist(0, 50) : rows;
      });
    } catch (e) {
      return const Stream.empty();
    }
  }

  Future<void> connectToChurch(String churchId) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    final existing = await _client
        .from('church_connections')
        .select('id')
        .eq('user_id', user.id)
        .eq('connected_church_id', churchId)
        .maybeSingle();
    if (existing != null) return;
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
