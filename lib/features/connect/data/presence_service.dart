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

  void dispose() {
    _heartbeat?.cancel();
    _sub?.cancel();
  }
}

final presenceServiceProvider = Provider<PresenceService>((ref) {
  return PresenceService(Supabase.instance.client);
});
