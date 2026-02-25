import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';

/// Hybrid Notification Service optimized for Self-Hosted Supabase VPS.
/// This implementation prioritizes privacy and cost-efficiency by avoiding 3rd party clouds.
/// Note: Real-time updates delivered via WebSockets provide low-latency alerts 
/// while the app is in foreground or background (minimized).
class NotificationService {
  final SupabaseClient _client;
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  NotificationService(this._client, this.ref);
  final Ref ref;

  Future<void> init() async {
    // 1. Setup Local Notifications for visual alerts
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: DarwinInitializationSettings(),
    );

    await _notificationsPlugin.initialize(settings: initializationSettings);

    // 2. Persistent Supabase Real-time Listener (Proprietary VPS Infrastructure)
    // Listens for 'notifications' table inserts specifically for the current user.
    final currentUser = _client.auth.currentUser;
    if (currentUser == null) return;

    _client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', currentUser.id)
        .order('created_at', ascending: false)
        .limit(1)
        .listen((data) {
          if (data.isNotEmpty) {
            final latest = data.first;
            // Only show if not read and fresh (last 1 minute)
            final createdAt = DateTime.parse(latest['created_at']);
            final diff = DateTime.now().difference(createdAt).inMinutes;
            
            if (latest['is_read'] == false && diff <= 1) {
              _showLocalNotification(
                latest['id'].hashCode,
                latest['title'],
                latest['body'],
              );
              _markAsRead(latest['id']);
            }
          }
        });
  }

  Future<void> _showLocalNotification(int id, String title, String body) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'kingdom_alerts',
      'Kingdom Alerts',
      channelDescription: 'Real-time church updates via VPS',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
    );
    
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);
        
    await _notificationsPlugin.show(id: id, title: title, body: body, notificationDetails: platformChannelSpecifics);
  }

  Future<void> _markAsRead(String id) async {
    await _client.from('notifications').update({'is_read': true}).eq('id', id);
  }

  /// Broadcast a notification internally via the VPS database.
  Future<void> sendNotification({required String userId, required String title, required String body}) async {
    await _client.from('notifications').insert({
      'user_id': userId,
      'title': title,
      'body': body,
    });
  }
}

final notificationServiceProvider = Provider((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return NotificationService(client, ref);
});

