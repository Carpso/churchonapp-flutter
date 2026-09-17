import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart'
  if (dart.library.html) 'package:church_on_app/core/services/messaging_stub.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/services/supabase_service.dart';
import 'package:church_on_app/core/services/notification_service.dart';
import 'package:church_on_app/core/services/navigation_service.dart';
import 'package:go_router/go_router.dart';

/// Top-level background handler — must be `@pragma('vm:entry-point')` so
/// the Android engine can locate it when the app is terminated.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  debugPrint('[FCM] onBackgroundMessage: ${message.notification?.title} ${message.data}');
  // Show a heads-up notification even when the app is killed.
  // We cannot use Riverpod here — create a raw plugin instance.
  try {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(android: androidSettings, iOS: iosSettings);
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(settings: initSettings);

    final data = message.data;
    final type = (data['type'] ?? data['notification_type'] ?? 'general').toString();
    final channelId = _channelForType(type);
    final channelName = _channelNameForType(type);
    final importance = _importanceForType(type);
    final priority = Priority.max;
    final isRide = channelId == 'coa_rides';
    final category = _categoryForChannel(channelId);

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: 'Church On App notifications',
      importance: importance,
      priority: priority,
      playSound: true,
      enableVibration: true,
      enableLights: true,
      category: category,
      fullScreenIntent: isRide,
      visibility: NotificationVisibility.public,
      icon: _iconForType(type),
      styleInformation: BigTextStyleInformation(
        message.notification?.body ?? data['body'] ?? '',
        contentTitle: message.notification?.title ?? data['title'] ?? 'Church On App',
        summaryText: 'Church On App',
      ),
    );
    const iosDetails = DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true);
    final title = message.notification?.title ?? data['title'] ?? 'Church On App';
    final body = message.notification?.body ?? data['body'] ?? 'You have a new update';
    final payload = data['payload'] as String? ?? (data['reference_id'] != null ? '${data['type']}:${data['reference_id']}' : null);
    await plugin.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: payload,
    );
  } catch (e) {
    debugPrint('[FCM] background show failed: $e');
  }
}

String _channelForType(String type) {
  switch (type) {
    case 'chat':
    case 'chat_message':
      return 'coa_chat';
    case 'payment':
    case 'payment_confirmed':
      return 'coa_payments';
    case 'ride':
    case 'ride_update':
    case 'ride_accepted':
    case 'ride_counter':
      return 'coa_rides';
    case 'order':
      return 'coa_orders';
    case 'event':
      return 'coa_events';
    case 'prayer':
      return 'coa_prayers';
    case 'testimony':
      return 'coa_testimonies';
    case 'klip':
      return 'coa_klips';
    case 'quiz':
    case 'pvp_invite':
    case 'pvp_result':
      return 'coa_quiz';
    case 'role':
      return 'coa_roles';
    case 'job':
      return 'coa_jobs';
    case 'volunteer':
      return 'coa_volunteers';
    case 'worship':
      return 'coa_worship';
    case 'incoming_call':
      return 'coa_rides';
    default:
      return 'coa_announcements';
  }
}

String _channelNameForType(String type) {
  switch (type) {
    case 'chat':
    case 'chat_message':
      return 'Chat Messages';
    case 'payment':
      return 'Payments';
    case 'ride':
    case 'ride_update':
      return 'Carpso Ride & Commute';
    case 'order':
      return 'Bookshop & Store Orders';
    case 'event':
      return 'Events';
    case 'prayer':
      return 'Prayers';
    case 'testimony':
      return 'Testimonies';
    case 'klip':
      return 'Klips';
    case 'quiz':
      return 'Bible Quiz & Competitions';
    case 'role':
      return 'Role & Leadership Approvals';
    case 'job':
      return 'Job Portal & Careers';
    case 'volunteer':
      return 'Volunteer Roster';
    case 'worship':
      return 'Worship & Setlists';
    default:
      return 'Updates';
  }
}

Importance _importanceForType(String type) {
  switch (type) {
    case 'ride':
    case 'ride_update':
    case 'ride_accepted':
    case 'ride_counter':
    case 'chat':
    case 'chat_message':
    case 'payment':
    case 'role':
    case 'quiz':
    case 'incoming_call':
      return Importance.max;
    default:
      return Importance.high;
  }
}

AndroidNotificationCategory? _categoryForChannel(String channelId) {
  switch (channelId) {
    case 'coa_rides':
      return AndroidNotificationCategory.call;
    case 'coa_chat':
      return AndroidNotificationCategory.message;
    case 'coa_payments':
    case 'coa_orders':
      return AndroidNotificationCategory.alarm;
    case 'coa_events':
    case 'coa_reminders':
      return AndroidNotificationCategory.reminder;
    default:
      return null;
  }
}

String _iconForType(String type) {
  switch (type) {
    case 'chat':
    case 'post':
      return 'ic_notif_chat';
    case 'payment':
    case 'order':
      return 'ic_notif_payment';
    case 'event':
      return 'ic_notif_event';
    case 'prayer':
    case 'testimony':
    case 'fasting':
      return 'ic_notif_prayer';
    case 'klip':
      return 'ic_notif_klip';
    case 'quiz':
      return 'ic_notif_quiz';
    case 'volunteer':
      return 'ic_notif_volunteers';
    case 'role':
      return 'ic_notif_role';
    case 'job':
      return 'ic_notif_job';
    case 'ride':
      return 'ic_notif_ride';
    case 'worship':
      return 'ic_notif_worship';
    default:
      return 'ic_notif_general';
  }
}

class FcmService {
  final WidgetRef ref;
  String? _token;

  FcmService(this.ref);

  Future<void> init() async {
    final messaging = FirebaseMessaging.instance;

    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Register background handler BEFORE anything else.
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    _token = await messaging.getToken();
    if (_token != null) {
      await _storeToken(_token!);
    }

    messaging.onTokenRefresh.listen(_storeToken);

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('[FCM] onMessage: ${message.notification?.title} data=${message.data}');
      final notification = message.notification;
      final data = message.data;
      final type = (data['type'] ?? 'general').toString();
      final channelId = _channelForType(type);
      final channelName = _channelNameForType(type);
      final title = notification?.title ?? data['title']?.toString() ?? 'Church On App';
      final body = notification?.body ?? data['body']?.toString() ?? '';
      // Build payload for navigation: prefer explicit payload, else type:reference_id
      String? payload = data['payload']?.toString();
      payload ??= data['reference_id'] != null ? '${data['type']}:${data['reference_id']}' : null;
      // If ride type, try to build ride payload
      if (payload == null && type.contains('ride') && data['ride_id'] != null) {
        payload = 'ride:${data['ride_id']}';
      }
      ref.read(notificationServiceProvider).sendNotification(
        title: title,
        body: body,
        channelId: channelId,
        channelName: channelName,
        payload: payload,
      );
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('[FCM] onMessageOpenedApp: ${message.notification?.title} data=${message.data}');
      _handleMessageTap(message);
    });

    // Handle cold-start: user tapped notification while app was terminated.
    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('[FCM] getInitialMessage: ${initialMessage.notification?.title} data=${initialMessage.data}');
      // Delay navigation until GoRouter is ready.
      Future.delayed(const Duration(seconds: 1), () => _handleMessageTap(initialMessage));
    }
  }

  void _handleMessageTap(RemoteMessage message) {
    final context = NavigationService.navigatorKey.currentContext;
    if (context == null) return;
    final data = message.data;
    String? payload = data['payload']?.toString();
    payload ??= data['reference_id'] != null ? '${data['type']}:${data['reference_id']}' : null;
    if (payload == null && data['ride_id'] != null) {
      payload = 'ride:${data['ride_id']}';
    }
    if (payload == null) {
      final type = data['type']?.toString() ?? 'general';
      // Map notification tap to appropriate screen without id.
      switch (type) {
        case 'ride':
        case 'ride_update':
        case 'ride_accepted':
          GoRouter.of(context).push('/ride');
          return;
        case 'chat':
        case 'chat_message':
          GoRouter.of(context).push('/connect');
          return;
        case 'incoming_call':
          GoRouter.of(context).push('/call');
          return;
        case 'pvp_invite':
        case 'pvp_match':
        case 'pvp_result':
        case 'pvp_rematch':
          GoRouter.of(context).push('/quiz');
          return;
        case 'order':
          GoRouter.of(context).push('/marketplace');
          return;
        case 'sermon':
          GoRouter.of(context).push('/sermons');
          return;
        case 'event':
          GoRouter.of(context).push('/events');
          return;
        case 'payment':
        case 'wallet':
          GoRouter.of(context).push('/wallet');
          return;
        case 'role':
          GoRouter.of(context).push('/profile');
          return;
        case 'testimony':
        case 'prayer':
        case 'bible_study':
        case 'fundraising':
        case 'group_contribution':
        case 'pledge_completed':
        case 'baptism':
        case 'missions_donation':
          GoRouter.of(context).push('/connect');
          return;
        case 'driver_approval':
        case 'sos_alert':
        case 'church_approved':
        case 'kyc_approved':
        case 'kyc_rejected':
          GoRouter.of(context).push('/profile');
          return;
        case 'quiz':
          GoRouter.of(context).push('/quiz');
          return;
        default:
          GoRouter.of(context).go('/');
          return;
      }
    }
    // Reuse the same routing as local notification taps: treat payload as navigation.
    try {
      if (payload.startsWith('http')) {
        final uri = Uri.parse(payload);
        GoRouter.of(context).go(uri.path);
        return;
      }
      final parts = payload.split(':');
      if (parts.length == 2) {
        final type = parts[0];
        final id = parts[1];
        switch (type) {
          case 'chat':
            GoRouter.of(context).push('/chat/$id');
            return;
          case 'ride':
          case 'incoming_call':
            GoRouter.of(context).push('/ride');
            return;
          case 'payment':
            GoRouter.of(context).push('/wallet');
            return;
          case 'event':
            GoRouter.of(context).push('/events/$id');
            return;
          case 'pvp_invite':
          case 'pvp_match':
          case 'pvp_result':
          case 'pvp_rematch':
            GoRouter.of(context).push('/quiz/invite/$id');
            return;
          case 'sermon':
            GoRouter.of(context).push('/sermon/$id');
            return;
          case 'post':
            GoRouter.of(context).push('/posts/$id');
            return;
          case 'klip':
            GoRouter.of(context).push('/klips/$id');
            return;
          case 'job':
            GoRouter.of(context).push('/jobs/$id');
            return;
          case 'order':
            GoRouter.of(context).push('/marketplace');
            return;
          case 'testimony':
          case 'prayer':
          case 'bible_study':
          case 'fundraising':
          case 'group_contribution':
          case 'pledge_completed':
          case 'baptism':
          case 'missions_donation':
            GoRouter.of(context).push('/connect');
            return;
          case 'role':
          case 'driver_approval':
          case 'sos_alert':
          case 'church_approved':
          case 'kyc_approved':
          case 'kyc_rejected':
            GoRouter.of(context).push('/profile');
            return;
          case 'quiz':
            GoRouter.of(context).push('/quiz');
            return;
          default:
            GoRouter.of(context).go('/');
            return;
        }
      }
      GoRouter.of(context).go('/');
    } catch (_) {
      GoRouter.of(context).go('/');
    }
  }

  /// Fetches the current FCM token and persists it.
  ///
  /// Must be called after sign-in (and on resume): the initial [init] commonly
  /// runs before the user is authenticated, and `_storeToken` silently drops the
  /// token when there is no session — so `profiles.fcm_token` stayed NULL and
  /// the server had no device to push to.
  Future<void> syncToken() async {
    try {
      if (ref.read(supabaseServiceProvider).client.auth.currentUser == null) {
        return;
      }
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _storeToken(token);
    } catch (e) {
      debugPrint('[FCM] syncToken failed: $e');
    }
  }

  Future<void> _storeToken(String token) async {
    _token = token;
    final user = ref.read(supabaseServiceProvider).client.auth.currentUser;
    if (user == null) return;
    try {
      await ref
          .read(supabaseServiceProvider)
          .client
          .from('profiles')
          .update({'fcm_token': token}).eq('id', user.id);
      debugPrint('[FCM] token stored for ${user.id}');
    } catch (e) {
      debugPrint('[FCM] token store failed: $e');
    }
  }
}
