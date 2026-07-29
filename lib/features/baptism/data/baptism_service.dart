import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BaptismService {
  final SupabaseClient _client;
  BaptismService(this._client);

  Future<void> notifyBaptismScheduled(String userId, String baptismId, String name, String date) async {
    try {
      await _client.functions.invoke('push-notifications', body: {
        'userId': userId,
        'title': '💧 Baptism Scheduled',
        'body': '$name is scheduled for baptism on $date',
        'data': {
          'type': 'baptism',
          'reference_id': baptismId,
          'channel_id': 'coa_events',
        },
      });
    } catch (e) {
      debugPrint('[BaptismService] Push failed: $e');
    }
  }

  Future<void> notifyBaptismCompleted(String userId, String baptismId, String name) async {
    try {
      await _client.functions.invoke('push-notifications', body: {
        'userId': userId,
        'title': '💧 Baptism Completed',
        'body': '$name has been baptized! Praise God!',
        'data': {
          'type': 'baptism',
          'reference_id': baptismId,
          'channel_id': 'coa_announcements',
        },
      });
    } catch (e) {
      debugPrint('[BaptismService] Push failed: $e');
    }
  }
}

final baptismServiceProvider = Provider((ref) => BaptismService(Supabase.instance.client));
