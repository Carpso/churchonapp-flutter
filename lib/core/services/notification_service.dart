import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/services/supabase_service.dart';
import 'package:church_on_app/core/services/navigation_service.dart';

// ─── Notification Channel IDs ─────────────────────────────────────────────────
const String _chChat = 'coa_chat';
const String _chPosts = 'coa_posts';
const String _chPayments = 'coa_payments';
const String _chAnnouncements = 'coa_announcements';
const String _chEvents = 'coa_events';
const String _chPrayers = 'coa_prayers';
const String _chTestimonies = 'coa_testimonies';
const String _chKlips = 'coa_klips';
const String _chFasting = 'coa_fasting';

class NotificationService {
  final SupabaseClient _client;
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  NotificationService(this._client);

  // ── Init ──────────────────────────────────────────────────────────────────
  Future<void> init() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(android: androidSettings, iOS: iosSettings);

    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Request permissions on Android 13+
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _createChannels();
  }

  void _createChannels() {
    _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _chChat, 'Chat Messages',
          description: 'Notifications for new chat messages',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ));
    _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _chPosts, 'Church Social',
          description: 'New posts from your church community',
          importance: Importance.defaultImportance,
        ));
    _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _chPayments, 'Payments',
          description: 'Payment confirmations and receipts',
          importance: Importance.max,
          playSound: true,
        ));
    _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _chAnnouncements, 'Announcements',
          description: 'Church announcements and alerts',
          importance: Importance.high,
        ));
    _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _chEvents, 'Events',
          description: 'Event reminders and updates',
          importance: Importance.high,
          playSound: true,
        ));
    _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _chPrayers, 'Prayers',
          description: 'Prayer requests and intercessions',
          importance: Importance.defaultImportance,
        ));
    _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _chTestimonies, 'Testimonies',
          description: 'New testimonies shared',
          importance: Importance.defaultImportance,
        ));
    _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _chKlips, 'Kingdom Klips',
          description: 'New video clips uploaded',
          importance: Importance.defaultImportance,
        ));
    _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _chFasting, 'Fasting',
          description: 'Fasting reminders and updates',
          importance: Importance.high,
        ));
  }

  void _onNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;

    final parts = payload.split(':');
    if (parts.length != 2) return;

    final type = parts[0];
    final id = parts[1];

    final context = NavigationService.navigatorKey.currentContext;
    if (context == null) return;

    switch (type) {
      case 'chat':
        GoRouter.of(context).go('/chat/$id');
      case 'post':
        GoRouter.of(context).go('/connect');
      case 'payment':
        GoRouter.of(context).go('/wallet');
      case 'announcement':
        GoRouter.of(context).go('/');
      case 'event':
        GoRouter.of(context).go('/events/$id');
      case 'prayer':
        GoRouter.of(context).go('/connect');
      case 'testimony':
        GoRouter.of(context).go('/connect');
      case 'klip':
        GoRouter.of(context).go('/klips/$id');
      case 'fasting':
        GoRouter.of(context).go('/');
      case 'job':
        GoRouter.of(context).go('/job-notifications');
    }
  }

  // ── Start all Supabase Realtime listeners ─────────────────────────────────
  void startListening(String userId, String tenantId) {
    _listenForChatMessages(userId);
    _listenForSocialPosts(tenantId);
    _listenForPayments(userId);
    listenForAnnouncements(tenantId);
    _listenForEvents(tenantId);
    _listenForPrayers(tenantId);
    _listenForTestimonies(tenantId);
    _listenForKlips(tenantId);
    _listenForFasting(userId);
    _listenForJobs(userId);
  }

  // ── 1. Chat messages ──────────────────────────────────────────────────────
  void _listenForChatMessages(String userId) {
    _client
        .channel('chat-notifications-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'receiver_id',
            value: userId,
          ),
          callback: (payload) async {
            final data = payload.newRecord;
            final senderId = data['sender_id'] as String?;
            String senderName = 'Someone';
            if (senderId != null) {
              try {
                final profile = await _client
                    .from('profiles')
                    .select('full_name')
                    .eq('id', senderId)
                    .maybeSingle();
                senderName = profile?['full_name'] ?? 'Someone';
              } catch (e) {
                debugPrint('Failed to fetch sender profile: $e');
              }
            }
            final content = data['content'] as String? ?? 'New message';
            final groupId = data['group_id'] as String?;

            await _show(
              id: userId.hashCode ^ (senderId?.hashCode ?? 0),
              title: groupId != null ? '💬 Group Message' : '💬 $senderName',
              body: groupId != null ? '$senderName: $content' : content,
              channelId: _chChat,
              channelName: 'Chat Messages',
              payload: 'chat:${data['id']}',
            );
          },
        )
        .subscribe();
  }

  // ── 2. Social posts ────────────────────────────────────────────────────────
  void _listenForSocialPosts(String tenantId) {
    _client
        .channel('social-posts-$tenantId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'social_posts',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'tenant_id',
            value: tenantId,
          ),
          callback: (payload) async {
            final data = payload.newRecord;
            final poster = data['user_name'] as String? ?? 'A member';
            final rawContent = data['content'] as String? ?? '';
            final content = rawContent.length > 60 ? rawContent.substring(0, 60) : rawContent;
            await _show(
              id: (data['id'] as String? ?? '').hashCode,
              title: '🏛️ New Church Post',
              body: '$poster shared: $content',
              channelId: _chPosts,
              channelName: 'Church Social',
              payload: 'post:${data['id']}',
            );
          },
        )
        .subscribe();
  }

  // ── 3. Payments ────────────────────────────────────────────────────────────
  void _listenForPayments(String userId) {
    _client
        .channel('payments-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'transactions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) async {
            final data = payload.newRecord;
            final amount = data['amount'] ?? '';
            final currency = data['currency'] ?? 'ZMW';
            final status = (data['status'] as String? ?? 'pending').toUpperCase();
            await _show(
              id: (data['id'] as String? ?? '').hashCode,
              title: '💳 Payment $status',
              body: 'Your transaction of $currency $amount has been $status.',
              channelId: _chPayments,
              channelName: 'Payments',
              payload: 'payment:${data['id']}',
            );
          },
        )
        .subscribe();
  }

  // ── 4. Announcements ───────────────────────────────────────────────────────
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
          callback: (payload) async {
            final data = payload.newRecord;
            await _show(
              id: DateTime.now().millisecond,
              title: '📢 ${data['title'] ?? 'New Announcement'}',
              body: data['description'] ?? 'Check the app for updates.',
              channelId: _chAnnouncements,
              channelName: 'Announcements',
              payload: 'announcement:${data['id']}',
            );
          },
        )
        .subscribe();
  }

  // ── 5. Events ──────────────────────────────────────────────────────────────
  void _listenForEvents(String tenantId) {
    _client
        .channel('events-$tenantId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'events',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'tenant_id',
            value: tenantId,
          ),
          callback: (payload) async {
            final data = payload.newRecord;
            final title = data['title'] as String? ?? 'New Event';
            await _show(
              id: DateTime.now().millisecond,
              title: '📅 New Event',
              body: '$title is coming up! Check the events page.',
              channelId: _chEvents,
              channelName: 'Events',
              payload: 'event:${data['id']}',
            );
          },
        )
        .subscribe();
  }

  // ── 6. Prayers ─────────────────────────────────────────────────────────────
  void _listenForPrayers(String tenantId) {
    _client
        .channel('prayers-$tenantId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'prayers',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'tenant_id',
            value: tenantId,
          ),
          callback: (payload) async {
            final data = payload.newRecord;
            final userName = data['user_name'] as String? ?? 'A member';
            final content = data['content'] as String? ?? '';
            final preview = content.length > 60 ? '${content.substring(0, 60)}...' : content;
            await _show(
              id: DateTime.now().millisecond,
              title: '🙏 Prayer Request',
              body: '$userName shared: $preview',
              channelId: _chPrayers,
              channelName: 'Prayers',
              payload: 'prayer:${data['id']}',
            );
          },
        )
        .subscribe();
  }

  // ── 7. Testimonies ─────────────────────────────────────────────────────────
  void _listenForTestimonies(String tenantId) {
    _client
        .channel('testimonies-$tenantId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'testimonies',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'tenant_id',
            value: tenantId,
          ),
          callback: (payload) async {
            final data = payload.newRecord;
            final userName = data['user_name'] as String? ?? 'A member';
            final content = data['content'] as String? ?? '';
            final preview = content.length > 60 ? '${content.substring(0, 60)}...' : content;
            await _show(
              id: DateTime.now().millisecond,
              title: '🌟 New Testimony',
              body: '$userName testified: $preview',
              channelId: _chTestimonies,
              channelName: 'Testimonies',
              payload: 'testimony:${data['id']}',
            );
          },
        )
        .subscribe();
  }

  // ── 8. Kingdom Klips ───────────────────────────────────────────────────────
  void _listenForKlips(String tenantId) {
    _client
        .channel('klips-$tenantId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'klips',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'tenant_id',
            value: tenantId,
          ),
          callback: (payload) async {
            final data = payload.newRecord;
            final userName = data['user_name'] as String? ?? 'A member';
            await _show(
              id: DateTime.now().millisecond,
              title: '🎬 New Kingdom Klip',
              body: '$userName shared a new video clip.',
              channelId: _chKlips,
              channelName: 'Kingdom Klips',
              payload: 'klip:${data['id']}',
            );
          },
        )
        .subscribe();
  }

  // ── 9. Job notifications ─────────────────────────────────────────────────────
  void _listenForJobs(String userId) {
    _client
        .channel('jobs-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'job_notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) async {
            final data = payload.newRecord;
            final message = data['message'] as String? ?? 'New job update';
            final type = data['type'] as String? ?? 'status_change';
            final emoji = type == 'new_application' ? '📋' : type == 'job_expiring' ? '⚠️' : '🔄';
            await _show(
              id: DateTime.now().millisecond,
              title: '$emoji Job Update',
              body: message,
              channelId: _chAnnouncements,
              channelName: 'Job Notifications',
              payload: 'job:${data['id']}',
            );
          },
        )
        .subscribe();
  }

  // ── 10. Fasting ─────────────────────────────────────────────────────────────
  void _listenForFasting(String userId) {
    _client
        .channel('fasting-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'fasting_logs',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) async {
            final data = payload.newRecord;
            final fastType = data['fast_type'] as String? ?? 'Fast';
            await _show(
              id: DateTime.now().millisecond,
              title: '🕊️ Fasting Update',
              body: 'Your $fastType has been logged. Stay strong!',
              channelId: _chFasting,
              channelName: 'Fasting',
              payload: 'fasting:${data['id']}',
            );
          },
        )
        .subscribe();
  }

  // ── Generic show helper ────────────────────────────────────────────────────
  Future<void> _show({
    required int id,
    required String title,
    required String body,
    required String channelId,
    required String channelName,
    String? payload,
    Importance importance = Importance.high,
    Priority priority = Priority.high,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      importance: importance,
      priority: priority,
      styleInformation: BigTextStyleInformation(body),
      icon: '@mipmap/ic_launcher',
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: payload,
    );
  }

  // ── Manual trigger helpers (for testing) ──────────────────────────────────
  Future<void> showChatNotification(String sender, String message) => _show(
        id: sender.hashCode,
        title: '💬 $sender',
        body: message,
        channelId: _chChat,
        channelName: 'Chat Messages',
      );

  Future<void> showPaymentNotification(String amount, String status) => _show(
        id: DateTime.now().millisecond,
        title: '💳 Payment $status',
        body: 'Your payment of $amount has been $status.',
        channelId: _chPayments,
        channelName: 'Payments',
        importance: Importance.max,
        priority: Priority.max,
      );
}

final notificationServiceProvider = Provider((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return NotificationService(client);
});
