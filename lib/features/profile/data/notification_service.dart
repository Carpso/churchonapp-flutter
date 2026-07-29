import 'package:flutter/foundation.dart';
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
  final Set<String> _shownIds = {};

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

    // Request permissions for Android (13+) and iOS
    try {
      final androidImplementation = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        await androidImplementation.requestNotificationsPermission();
      }
      final iosImplementation = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      if (iosImplementation != null) {
        await iosImplementation.requestPermissions(alert: true, badge: true, sound: true);
      }
    } catch (e) {
      debugPrint('Error requesting notification permissions: $e');
    }

    final currentUser = _client.auth.currentUser;
    if (currentUser == null) return;

    // 2. Fetch Catch-up Notifications (sent while phone or app was OFF)
    try {
      final unread = await _client
          .from('notifications')
          .select()
          .eq('user_id', currentUser.id)
          .eq('is_read', false);
      
      for (final n in unread) {
        final id = n['id'] as String;
        _shownIds.add(id);
        await _showLocalNotification(
          id.hashCode,
          n['title'] ?? 'Update',
          n['body'] ?? '',
        );
        await _markAsRead(id);
      }
    } catch (e) {
      debugPrint('Error fetching catch-up notifications: $e');
    }

    // 3. Persistent Supabase Real-time Listener (Proprietary VPS Infrastructure)
    // Listens for 'notifications' table inserts specifically for the current user.
    _client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', currentUser.id)
        .order('created_at', ascending: false)
        .limit(1)
        .listen((data) {
          if (data.isNotEmpty) {
            final latest = data.first;
            final id = latest['id'] as String;
            // Skip if already shown by the catch-up loop
            if (_shownIds.contains(id)) return;
            // Only show if not read and fresh (last 1 minute)
            final createdAt = DateTime.parse(latest['created_at']);
            final diff = DateTime.now().difference(createdAt).inMinutes;

            if (latest['is_read'] == false && diff <= 1) {
              _shownIds.add(id);
              _showLocalNotification(
                id.hashCode,
                latest['title'] ?? 'Update',
                latest['body'] ?? '',
              );
              _markAsRead(id);
            }
          }
        });
  }

  Future<void> _showLocalNotification(int id, String title, String body) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'kingdom_alerts',
      'Alerts',
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

final profileNotificationServiceProvider = Provider((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return NotificationService(client, ref);
});

