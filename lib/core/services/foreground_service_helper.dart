import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class ForegroundServiceHelper {
  static const String channelMediaPlayback = 'media_playback';
  static const String channelLocationSharing = 'location_sharing';
  static const String channelDataSync = 'data_sync';

  static Future<void> createNotificationChannels({FlutterLocalNotificationsPlugin? plugin}) async {
    final p = plugin ?? FlutterLocalNotificationsPlugin();
    await p.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    );

    final android = p.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    await android.createNotificationChannel(const AndroidNotificationChannel(
      channelMediaPlayback,
      'Media Playback',
      description: 'Ongoing media playback (sermons, radio, music)',
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
    ));

    await android.createNotificationChannel(const AndroidNotificationChannel(
      channelLocationSharing,
      'Location Sharing',
      description: 'Active ride tracking and location sharing',
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
    ));

    await android.createNotificationChannel(const AndroidNotificationChannel(
      channelDataSync,
      'Data Sync',
      description: 'Background data synchronization',
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
    ));

    debugPrint('ForegroundServiceHelper: Notification channels created');
  }
}
