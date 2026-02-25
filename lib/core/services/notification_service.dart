import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/services/supabase_service.dart';
import 'package:church_on_app/core/services/tenant_service.dart';

class NotificationService {
  final SupabaseClient _client;
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  NotificationService(this._client);

  Future<void> init() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(android: androidSettings, iOS: iosSettings);
    await _notifications.initialize(settings: initSettings);
  }

  void listenForAnnouncements(String tenantId) {
    _client
        .channel('announcements-$tenantId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'service_reports',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'tenant_id',
            value: tenantId,
          ),
          callback: (payload) {
            final data = payload.newRecord;
            if (data['type'] == 'announcement') {
              _showLocalNotification(
                title: "New Announcement: ${data['title']}",
                body: data['description'] ?? "Check the app for updates.",
              );
            }
          },
        )
        .subscribe();
  }

  Future<void> _showLocalNotification({required String title, required String body}) async {
    const androidDetails = AndroidNotificationDetails(
      'coa_announcements',
      'Church Announcements',
      importance: Importance.max,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const platformDetails = NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _notifications.show(
      id: DateTime.now().millisecond,
      title: title,
      body: body,
      notificationDetails: platformDetails,
    );
  }
}

final notificationServiceProvider = Provider((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return NotificationService(client);
});

