import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Realtime presence: updates the caller's `last_seen` periodically and
/// streams another user's `last_seen` so chat can show real online status.
class PresenceService {
  final SupabaseClient _client;
  PresenceService(this._client);

  Timer? _heartbeat;
  StreamSubscription<List<Map<String, dynamic>>>? _sub;

  /// Start a heartbeat that bumps the current user's `last_seen` every 30s.
  void startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) => beat());
    beat();
  }

  Future<void> beat() async {
    try {
      await _client.rpc('heartbeat_presence');
    } catch (e) {
      debugPrint('Presence heartbeat error: $e');
    }
  }

  /// Stream whether [userId] is online (last_seen within 60s).
  Stream<bool> watchOnline(String userId) {
    final controller = StreamController<bool>.broadcast();

    bool eval(DateTime? lastSeen) {
      if (lastSeen == null) return false;
      return DateTime.now().difference(lastSeen).inSeconds < 60;
    }

    _sub?.cancel();
    _sub = _client
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('id', userId)
        .map((data) => List<Map<String, dynamic>>.from(data))
        .listen((data) {
      if (data.isEmpty) return;
      final lastSeenRaw = data.first['last_seen'];
      final lastSeen = lastSeenRaw is String
          ? DateTime.tryParse(lastSeenRaw)
          : null;
      controller.add(eval(lastSeen));
    }, onError: (e) => debugPrint('Presence watch error: $e'));

    return controller.stream.distinct();
  }

  /// Stream the set of online user ids among [userIds] on a single realtime
  /// channel (last_seen within 60s). Returns a broadcast stream that emits
  /// the current online set whenever any member's presence changes.
  Stream<Set<String>> watchOnlineIds(List<String> userIds) {
    final controller = StreamController<Set<String>>.broadcast();
    if (userIds.isEmpty) {
      controller.add(const <String>{});
      return controller.stream;
    }

    Set<String> eval(List<Map<String, dynamic>> rows) {
      final now = DateTime.now();
      return rows
          .where((r) {
            final lastSeenRaw = r['last_seen'];
            final lastSeen = lastSeenRaw is String
                ? DateTime.tryParse(lastSeenRaw)
                : null;
            return lastSeen != null &&
                now.difference(lastSeen).inSeconds < 60;
          })
          .map((r) => r['id'].toString())
          .toSet();
    }

    final channel = _client
        .channel('presence_members_${userIds.hashCode}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'profiles',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.inFilter,
            column: 'id',
            value: userIds,
          ),
          callback: (payload) {
            final newRow = Map<String, dynamic>.from(payload.newRecord);
            controller.add(eval([newRow]));
          },
        )
        .subscribe();

    Future<void> fetchInitial() async {
      try {
        final data = await _client
            .from('profiles')
            .select('id, last_seen')
            .inFilter('id', userIds);
        if (!controller.isClosed) {
          controller.add(eval(List<Map<String, dynamic>>.from(data)));
        }
      } catch (e) {
        debugPrint('Presence batch fetch error: $e');
      }
    }

    fetchInitial();

    controller.onCancel = () {
      _client.removeChannel(channel);
    };

    return controller.stream;
  }

  void dispose() {
    _heartbeat?.cancel();
    _sub?.cancel();
  }
}

final presenceServiceProvider = Provider<PresenceService>((ref) {
  return PresenceService(Supabase.instance.client);
});
