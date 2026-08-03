import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/services/supabase_service.dart';
import 'package:church_on_app/core/services/navigation_service.dart';
import 'package:church_on_app/core/theme/app_theme.dart';

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
const String _chReminders = 'coa_reminders';
const String _chQuiz = 'coa_quiz';
const String _chVolunteers = 'coa_volunteers';
const String _chOrders = 'coa_orders';
const String _chRoles = 'coa_roles';
const String _chJobs = 'coa_jobs';
const String _chRide = 'coa_rides';
const String _chWorship = 'coa_worship';

class NotificationService {
  final SupabaseClient _client;
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  final List<RealtimeChannel> _channels = [];
  String? _listeningUserId;
  String? _listeningTenantId;

  NotificationService(this._client);

  // ── Cross-service burst control ─────────────────────────────────────────
  // Content-keyed dedup window. Shared with the profile NotificationService
  // (static) so the SAME event surfacing via multiple paths (realtime channel
  // + notifications-table stream + FCM foreground) only shows ONCE.
  static const _dedupWindow = Duration(seconds: 30);
  static final Map<String, DateTime> _recentlyShown = {};

  static String contentKey(String channelId, String title, String body) =>
      '$channelId|${title.trim()}|${body.trim()}';

  static bool isDuplicate(String key) {
    final last = _recentlyShown[key];
    return last != null && DateTime.now().difference(last) < _dedupWindow;
  }

  static void markShown(String key) {
    _recentlyShown[key] = DateTime.now();
    if (_recentlyShown.length > 200) {
      final cutoff = DateTime.now().subtract(_dedupWindow * 4);
      _recentlyShown.removeWhere((_, t) => t.isBefore(cutoff));
    }
  }

  void stopListening() {
    for (final ch in _channels) {
      try { ch.unsubscribe(); } catch (_) {}
    }
    _channels.clear();
    _listeningUserId = null;
    _listeningTenantId = null;
  }

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
          _chAnnouncements, 'Updates',
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
          _chKlips, 'Klips',
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
    _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _chReminders, 'Daily Reminders',
          description: 'Daily Bible study and devotion reminders',
          importance: Importance.high,
          playSound: true,
        ));
    _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _chQuiz, 'Bible Quiz & Competitions',
          description: 'PvP challenge alerts, competitions & leaderboard updates',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ));
    _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _chVolunteers, 'Volunteer Roster',
          description: 'Shift assignment alerts and reminders',
          importance: Importance.high,
          playSound: true,
        ));
    _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _chOrders, 'Bookshop & Store Orders',
          description: 'Order status updates, dispatch and delivery alerts',
          importance: Importance.high,
          playSound: true,
        ));
    _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _chRoles, 'Role & Leadership Approvals',
          description: 'Role updates, leader verification and badge approvals',
          importance: Importance.max,
          playSound: true,
        ));
    _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _chJobs, 'Job Portal & Careers',
          description: 'Job applications, interview invites, and status updates',
          importance: Importance.high,
          playSound: true,
        ));
    _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _chRide, 'Carpso Ride & Commute',
          description: 'Driver matching, ride status updates, and ETA alerts',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ));
    _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _chWorship, 'Worship & Setlists',
          description: 'Sunday worship setlists, lyrics, and song additions',
          importance: Importance.high,
          playSound: true,
        ));
  }

  void _onNotificationTap(NotificationResponse response) {
    final actionId = response.actionId;
    final payload = response.payload;

    final context = NavigationService.navigatorKey.currentContext;
    if (context == null) return;

    try {
      // Check action button taps first
      if (actionId != null && actionId.isNotEmpty) {
        switch (actionId) {
          case 'action_chat_reply':
          case 'action_profile':
            GoRouter.of(context).push('/profile');
            return;
          case 'action_post_view':
          case 'action_community':
          case 'action_connect':
          case 'action_prayer_wall':
          case 'action_testimony_read':
          case 'action_quiz_play':
          case 'action_quiz_rank':
            GoRouter.of(context).push('/connect');
            return;
          case 'action_wallet':
          case 'action_receipt':
            GoRouter.of(context).push('/wallet');
            return;
          case 'action_announcement':
          case 'action_church':
            GoRouter.of(context).go('/');
            return;
          case 'action_event':
          case 'action_event_map':
            if (payload != null && payload.startsWith('event:')) {
              final id = payload.split(':')[1];
              GoRouter.of(context).push('/events/$id');
            } else {
              GoRouter.of(context).push('/connect');
            }
            return;
          case 'action_klip_watch':
            if (payload != null && payload.startsWith('klip:')) {
              final id = payload.split(':')[1];
              GoRouter.of(context).push('/klips/$id');
            } else {
              GoRouter.of(context).push('/connect');
            }
            return;
          case 'action_fasting_log':
          case 'action_devotions':
          case 'action_read_bible':
            GoRouter.of(context).push('/devotions');
            return;
          case 'action_volunteer_roster':
          case 'action_admin_hub':
            GoRouter.of(context).push('/admin/volunteer-schedule');
            return;
          case 'action_order_track':
          case 'action_bookshop':
            GoRouter.of(context).push('/admin/orders');
            return;
          case 'action_role_view':
            GoRouter.of(context).push('/profile');
            return;
          case 'action_job_view':
            GoRouter.of(context).push('/job-notifications');
            return;
          case 'action_job_portal':
            GoRouter.of(context).push('/jobs');
            return;
          case 'action_ride':
          case 'action_ride_map':
            GoRouter.of(context).push('/ride');
            return;
          case 'action_worship':
          case 'action_lyrics':
            GoRouter.of(context).push('/admin/worship-lyrics');
            return;
        }
      }

      if (payload == null || payload.isEmpty) return;

      // Handle Deep Link URLs (e.g., https://churchonapp.com/events/123 or coa://wallet)
      if (payload.startsWith('http://') || payload.startsWith('https://')) {
        final uri = Uri.parse(payload);
        GoRouter.of(context).go(uri.path);
        return;
      }

      final parts = payload.split(':');
      if (parts.length != 2) return;

      final type = parts[0];
      final id = parts[1];

      switch (type) {
        case 'chat':
          GoRouter.of(context).push('/chat/$id');
        case 'post':
          GoRouter.of(context).push('/connect');
        case 'payment':
          GoRouter.of(context).push('/wallet');
        case 'announcement':
          GoRouter.of(context).go('/');
        case 'event':
          GoRouter.of(context).push('/events/$id');
        case 'prayer':
          GoRouter.of(context).push('/connect');
        case 'testimony':
          GoRouter.of(context).push('/connect');
        case 'klip':
          GoRouter.of(context).push('/klips/$id');
        case 'fasting':
          GoRouter.of(context).push('/devotions');
        case 'job':
          GoRouter.of(context).push('/job-notifications');
        case 'quiz':
          GoRouter.of(context).go('/connect');
        case 'volunteer':
          GoRouter.of(context).push('/admin/volunteer-schedule');
        case 'order':
          GoRouter.of(context).push('/admin/orders');
        case 'role':
          GoRouter.of(context).push('/profile');
        case 'ride':
          GoRouter.of(context).push('/ride');
        case 'worship':
          GoRouter.of(context).push('/admin/worship-lyrics');
        default:
          GoRouter.of(context).go('/');
      }
    } catch (_) {
      GoRouter.of(context).go('/');
    }
  }

  // ── Start all Supabase Realtime listeners ─────────────────────────────────
  /// Idempotent: repeated calls (app start + auth-restore `signedIn` event +
  /// re-logins) with the same user/tenant are ignored. A different user/tenant
  /// first tears down the old channels — this prevents duplicate subscriptions
  /// that make every live event fire the local notification twice.
  void startListening(String userId, String tenantId) {
    if (_listeningUserId == userId && _listeningTenantId == tenantId) return;
    stopListening();
    _listeningUserId = userId;
    _listeningTenantId = tenantId;

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
    _listenForBibleQuiz(userId, tenantId);
    _listenForVolunteerAssignments(userId);
    _listenForOrders(userId);
    _listenForRoleApprovals(userId);
    _listenForRides(userId);
    _listenForWorshipSetlists(tenantId);
  }

  // ── 1. Chat messages ──────────────────────────────────────────────────────
  void _listenForChatMessages(String userId) {
    final ch = _client
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
    _channels.add(ch);
  }

  // ── 2. Social posts ────────────────────────────────────────────────────────
  void _listenForSocialPosts(String tenantId) {
    final ch = _client
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
    _channels.add(ch);
  }

  // ── 3. Payments ────────────────────────────────────────────────────────────
  void _listenForPayments(String userId) {
    final ch = _client
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
    _channels.add(ch);
  }

  // ── 4. Announcements ───────────────────────────────────────────────────────
  void listenForAnnouncements(String tenantId) {
    final ch = _client
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
    _channels.add(ch);
  }

  // ── 5. Events ──────────────────────────────────────────────────────────────
  void _listenForEvents(String tenantId) {
    final ch = _client
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
    _channels.add(ch);
  }

  // ── 6. Prayers ─────────────────────────────────────────────────────────────
  void _listenForPrayers(String tenantId) {
    final ch = _client
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
    _channels.add(ch);
  }

  // ── 7. Testimonies ─────────────────────────────────────────────────────────
  void _listenForTestimonies(String tenantId) {
    final ch = _client
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
    _channels.add(ch);
  }

  // ── 8. Kingdom Klips ───────────────────────────────────────────────────────
  void _listenForKlips(String tenantId) {
    final ch = _client
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
              title: '🎬 New Klip',
              body: '$userName shared a new video clip.',
              channelId: _chKlips,
              channelName: 'Klips',
              payload: 'klip:${data['id']}',
            );
          },
        )
        .subscribe();
    _channels.add(ch);
  }

  // ── 9. Job notifications ─────────────────────────────────────────────────────
  void _listenForJobs(String userId) {
    final ch = _client
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
              channelId: _chJobs,
              channelName: 'Job Portal & Careers',
              payload: 'job:${data['id']}',
            );
          },
        )
        .subscribe();
    _channels.add(ch);
  }

  // ── 10. Fasting ─────────────────────────────────────────────────────────────
  void _listenForFasting(String userId) {
    final ch = _client
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
    _channels.add(ch);
  }

  // ── 11. Bible Quiz & Competitions ──────────────────────────────────────────
  void _listenForBibleQuiz(String userId, String tenantId) {
    final ch = _client
        .channel('quiz-competitions-$tenantId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'church_competitions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'tenant_id',
            value: tenantId,
          ),
          callback: (payload) async {
            final data = payload.newRecord;
            final title = data['title'] as String? ?? 'Bible Quiz';
            final entryFee = (data['entry_fee'] as num?)?.toDouble() ?? 0.0;
            final feeText = entryFee > 0 ? ' (Entry: K${entryFee.toStringAsFixed(2)})' : ' (Free)';
            await _show(
              id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
              title: '⚔️ New Bible Quiz: $title',
              body: 'A new church competition has been announced!$feeText Join the challenge now.',
              channelId: _chQuiz,
              channelName: 'Bible Quiz & Competitions',
              payload: 'quiz:${data['id']}',
            );
          },
        )
        .subscribe();
    _channels.add(ch);
  }

  // ── 12. Volunteer Roster Assignments ─────────────────────────────────────────
  void _listenForVolunteerAssignments(String userId) {
    final ch = _client
        .channel('volunteers-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'volunteer_schedules',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'volunteer_id',
            value: userId,
          ),
          callback: (payload) async {
            final data = payload.newRecord;
            final ministry = data['ministry'] as String? ?? 'Ministry';
            final role = data['role'] as String? ?? 'Volunteer';
            final date = data['schedule_date'] as String? ?? '';
            await _show(
              id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
              title: '📋 New Volunteer Shift Assigned',
              body: 'You have been scheduled as $role for $ministry on $date.',
              channelId: _chVolunteers,
              channelName: 'Volunteer Roster',
              payload: 'volunteer:${data['id']}',
            );
          },
        )
        .subscribe();
    _channels.add(ch);
  }

  // ── 13. Bookshop & Store Orders ──────────────────────────────────────────────
  void _listenForOrders(String userId) {
    final ch = _client
        .channel('orders-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'book_orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) async {
            final data = payload.newRecord;
            final status = data['status'] as String? ?? 'processing';
            final title = data['item_title'] as String? ?? 'Book/Item';
            await _show(
              id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
              title: '📚 Bookshop Order Update',
              body: 'Your order for "$title" is now ${status.toUpperCase()}.',
              channelId: _chOrders,
              channelName: 'Bookshop & Store Orders',
              payload: 'order:${data['id']}',
            );
          },
        )
        .subscribe();
    _channels.add(ch);
  }

  // ── 14. Role & Leadership Approvals ──────────────────────────────────────────
  void _listenForRoleApprovals(String userId) {
    final ch = _client
        .channel('roles-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'profiles',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: userId,
          ),
          callback: (payload) async {
            final oldData = payload.oldRecord;
            final newData = payload.newRecord;
            if (oldData['role'] != newData['role']) {
              final newRole = (newData['role'] as String? ?? 'Member').replaceAll('_', ' ');
              await _show(
                id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                title: '🛡️ Role Status Updated',
                body: 'Your account role has been updated to ${newRole.toUpperCase()}.',
                channelId: _chRoles,
                channelName: 'Role & Leadership Approvals',
                payload: 'role:${newData['id']}',
              );
            }
          },
        )
        .subscribe();
    _channels.add(ch);
  }

  // ── 15. Carpso Ride & Commute ──────────────────────────────────────────────────
  void _listenForRides(String userId) {
    final ch = _client
        .channel('rides-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'ride_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'rider_id',
            value: userId,
          ),
          callback: (payload) async {
            final data = payload.newRecord;
            final status = data['status'] as String? ?? 'requested';
            final fare = (data['fare_amount'] as num?)?.toDouble() ?? 0.0;
            final fareText = fare > 0 ? ' (K${fare.toStringAsFixed(0)})' : '';
            await _show(
              id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
              title: '🚕 Carpso Ride Update',
              body: 'Your ride request is now ${status.toUpperCase()}$fareText.',
              channelId: _chRide,
              channelName: 'Carpso Ride & Commute',
              payload: 'ride:${data['id']}',
            );
          },
        )
        .subscribe();
    _channels.add(ch);
  }

  // ── 16. Worship Lyrics & Sunday Setlists ────────────────────────────────────
  void _listenForWorshipSetlists(String tenantId) {
    final ch = _client
        .channel('worship-setlists-$tenantId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'worship_setlists',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'tenant_id',
            value: tenantId,
          ),
          callback: (payload) async {
            final data = payload.newRecord;
            final title = data['title'] as String? ?? 'Sunday Setlist';
            final serviceDate = data['service_date'] as String? ?? '';
            await _show(
              id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
              title: '🎶 New Sunday Worship Setlist',
              body: '"$title" has been published for $serviceDate.',
              channelId: _chWorship,
              channelName: 'Worship & Setlists',
              payload: 'worship:${data['id']}',
            );
          },
        )
        .subscribe();
    _channels.add(ch);
  }

  String _iconForChannel(String channelId) {
    switch (channelId) {
      case _chChat:
      case _chPosts:
        return '@drawable/ic_notif_chat';
      case _chPayments:
      case _chOrders:
        return '@drawable/ic_notif_payment';
      case _chAnnouncements:
      case _chReminders:
        return '@drawable/ic_notif_general';
      case _chEvents:
        return '@drawable/ic_notif_event';
      case _chPrayers:
      case _chTestimonies:
      case _chFasting:
        return '@drawable/ic_notif_prayer';
      case _chKlips:
        return '@drawable/ic_notif_klip';
      case _chQuiz:
        return '@drawable/ic_notif_quiz';
      case _chVolunteers:
        return '@drawable/ic_notif_volunteers';
      case _chRoles:
        return '@drawable/ic_notif_role';
      case _chJobs:
        return '@drawable/ic_notif_job';
      case _chRide:
        return '@drawable/ic_notif_ride';
      case _chWorship:
        return '@drawable/ic_notif_worship';
      default:
        return '@drawable/ic_notif_general';
    }
  }

  // ── Generic show helper ────────────────────────────────────────────────────
  Future<void> _show({
    required int id,
    required String title,
    required String body,
    required String channelId,
    required String channelName,
    String? payload,
    Importance importance = Importance.max,
    Priority priority = Priority.max,
  }) async {
    // 1. Content-keyed dedup (30s window). The same event can arrive via
    // multiple paths (realtime channel, notifications-table stream, FCM
    // foreground) — only the first copy shows.
    final key = contentKey(channelId, title, body);
    if (isDuplicate(key)) return;
    markShown(key);

    // 2. Burst coalescing: queue per channel, flush in batches. When FCM
    // delivers a backlog of queued pushes after the device comes back online,
    // a burst collapses into ONE summary per channel instead of firing every
    // message at once.
    _pending.putIfAbsent(channelId, () => []).add(_PendingNotification(
          title: title,
          body: body,
          channelName: channelName,
          payload: payload,
        ));
    _scheduleFlush();
  }

  // ── Burst coalescing machinery ─────────────────────────────────────────────
  static const _flushInterval = Duration(milliseconds: 1200);
  final Map<String, List<_PendingNotification>> _pending = {};
  Timer? _flushTimer;
  bool _flushScheduled = false;

  void _scheduleFlush() {
    if (_flushScheduled) return;
    _flushScheduled = true;
    _flushTimer ??= Timer.periodic(_flushInterval, (_) => _flush());
  }

  Future<void> _flush() async {
    if (_pending.isEmpty) {
      _flushScheduled = false;
      _flushTimer?.cancel();
      _flushTimer = null;
      return;
    }

    final batch = Map<String, List<_PendingNotification>>.from(_pending);
    _pending.clear();

    for (final entry in batch.entries) {
      final items = entry.value;
      if (items.isEmpty) continue;
      final channelId = entry.key;
      final last = items.last;

      if (items.length == 1) {
        await _showNow(
          id: last.contentKey.hashCode,
          title: last.title,
          body: last.body,
          channelId: channelId,
          channelName: last.channelName,
          payload: last.payload,
        );
      } else {
        // Burst detected: one summary per channel (stable ID so repeated
        // summaries replace each other rather than stacking).
        await _showNow(
          id: channelId.hashCode,
          title: last.title,
          body: 'You have ${items.length} new updates from ${last.channelName}.',
          channelId: channelId,
          channelName: last.channelName,
          payload: last.payload,
        );
      }
    }
  }

  Future<void> _showNow({
    required int id,
    required String title,
    required String body,
    required String channelId,
    required String channelName,
    String? payload,
    Importance importance = Importance.max,
    Priority priority = Priority.max,
  }) async {
    List<AndroidNotificationAction> channelActions = const [
      AndroidNotificationAction(
        'action_open',
        '📖 Open App',
        showsUserInterface: true,
      ),
    ];

    if (channelId == _chChat) {
      channelActions = const [
        AndroidNotificationAction('action_chat_reply', '💬 Open Chat', showsUserInterface: true),
        AndroidNotificationAction('action_profile', '👤 View Profile', showsUserInterface: true),
      ];
    } else if (channelId == _chPosts) {
      channelActions = const [
        AndroidNotificationAction('action_post_view', '💬 View Feed', showsUserInterface: true),
        AndroidNotificationAction('action_community', '👥 Community', showsUserInterface: true),
      ];
    } else if (channelId == _chPayments) {
      channelActions = const [
        AndroidNotificationAction('action_wallet', '💳 View Wallet', showsUserInterface: true),
        AndroidNotificationAction('action_receipt', '📄 Transactions', showsUserInterface: true),
      ];
    } else if (channelId == _chAnnouncements) {
      channelActions = const [
        AndroidNotificationAction('action_announcement', '📢 Read Notice', showsUserInterface: true),
        AndroidNotificationAction('action_church', '⛪ Church Hub', showsUserInterface: true),
      ];
    } else if (channelId == _chEvents) {
      channelActions = const [
        AndroidNotificationAction('action_event', '🎫 View Ticket', showsUserInterface: true),
        AndroidNotificationAction('action_event_map', '📍 Location', showsUserInterface: true),
      ];
    } else if (channelId == _chPrayers) {
      channelActions = const [
        AndroidNotificationAction('action_prayer_wall', '🙏 Prayer Wall', showsUserInterface: true),
        AndroidNotificationAction('action_connect', '💬 Intercessors', showsUserInterface: true),
      ];
    } else if (channelId == _chTestimonies) {
      channelActions = const [
        AndroidNotificationAction('action_testimony_read', '🙌 Praise God', showsUserInterface: true),
        AndroidNotificationAction('action_connect', '📖 Read Stories', showsUserInterface: true),
      ];
    } else if (channelId == _chKlips) {
      channelActions = const [
        AndroidNotificationAction('action_klip_watch', '▶️ Watch Klip', showsUserInterface: true),
        AndroidNotificationAction('action_connect', '❤️ Discover', showsUserInterface: true),
      ];
    } else if (channelId == _chFasting) {
      channelActions = const [
        AndroidNotificationAction('action_fasting_log', '🕊️ Fasting Log', showsUserInterface: true),
        AndroidNotificationAction('action_devotions', '📖 Daily Verse', showsUserInterface: true),
      ];
    } else if (channelId == _chReminders) {
      channelActions = const [
        AndroidNotificationAction('action_read_bible', '📖 Read Bible', showsUserInterface: true),
        AndroidNotificationAction('action_devotions', '🌅 Devotions', showsUserInterface: true),
      ];
    } else if (channelId == _chQuiz) {
      channelActions = const [
        AndroidNotificationAction('action_quiz_play', '⚔️ Play Quiz', showsUserInterface: true),
        AndroidNotificationAction('action_quiz_rank', '🏆 Leaderboard', showsUserInterface: true),
      ];
    } else if (channelId == _chVolunteers) {
      channelActions = const [
        AndroidNotificationAction('action_volunteer_roster', '📋 View Roster', showsUserInterface: true),
        AndroidNotificationAction('action_admin_hub', '👑 Admin Hub', showsUserInterface: true),
      ];
    } else if (channelId == _chOrders) {
      channelActions = const [
        AndroidNotificationAction('action_order_track', '📦 Track Order', showsUserInterface: true),
        AndroidNotificationAction('action_bookshop', '🛍️ Bookshop', showsUserInterface: true),
      ];
    } else if (channelId == _chRoles) {
      channelActions = const [
        AndroidNotificationAction('action_role_view', '👑 View Profile', showsUserInterface: true),
        AndroidNotificationAction('action_admin_hub', '📜 Role Badges', showsUserInterface: true),
      ];
    } else if (channelId == _chJobs) {
      channelActions = const [
        AndroidNotificationAction('action_job_view', '📋 Applications', showsUserInterface: true),
        AndroidNotificationAction('action_job_portal', '💼 Job Portal', showsUserInterface: true),
      ];
    } else if (channelId == _chRide) {
      channelActions = const [
        AndroidNotificationAction('action_ride', '🚕 View Ride', showsUserInterface: true),
        AndroidNotificationAction('action_ride_map', '📍 Live Map', showsUserInterface: true),
      ];
    } else if (channelId == _chWorship) {
      channelActions = const [
        AndroidNotificationAction('action_worship', '🎵 View Lyrics', showsUserInterface: true),
        AndroidNotificationAction('action_lyrics', '📖 Open Chords', showsUserInterface: true),
      ];
    }

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      importance: importance,
      priority: priority,
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
        summaryText: 'Church On App',
      ),
      icon: _iconForChannel(channelId),
      largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      color: kSunflowerYellow,
      subText: 'Church On App',
      visibility: NotificationVisibility.public,
      actions: channelActions,
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

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String channelId = _chAnnouncements,
    String channelName = 'Announcements',
    String? payload,
  }) => _show(
    id: id,
    title: title,
    body: body,
    channelId: channelId,
    channelName: channelName,
    payload: payload,
  );

  static const int _dailyReminderId = 99999;

  Future<void> scheduleDailyReminder({required int hour, required int minute}) async {
    await _plugin.cancel(id: _dailyReminderId);

    final androidDetails = AndroidNotificationDetails(
      _chReminders,
      'Daily Reminders',
      channelDescription: 'Daily Bible study and devotion reminders',
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: const BigTextStyleInformation(
        'Time for your daily devotion! Open Deep Study to continue your streak. 🕊️',
        contentTitle: '📖 Daily Bible Study',
        summaryText: 'Church On App',
      ),
      icon: '@mipmap/ic_launcher',
      largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      color: kSunflowerYellow,
      subText: 'Church On App',
      visibility: NotificationVisibility.public,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    final details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _plugin.periodicallyShow(
      id: _dailyReminderId,
      title: '📖 Daily Bible Study',
      body: 'Time for your daily devotion! Open Deep Study to continue your streak.',
      repeatInterval: RepeatInterval.daily,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  Future<void> cancelDailyReminder() async {
    await _plugin.cancel(id: _dailyReminderId);
  }

  static const int _weeklyReminderId = 99998;

  Future<void> scheduleWeeklyReminder({required String day, required int hour, required int minute}) async {
    await _plugin.cancel(id: _weeklyReminderId);
    final dayIndex = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'].indexOf(day);
    if (dayIndex < 0) return;

    final androidDetails = AndroidNotificationDetails(
      _chReminders,
      'Weekly Reminders',
      channelDescription: 'Weekly study reminder',
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(
        'It\'s $day — time for your weekly deep study session! 🕊️',
        contentTitle: '📖 Weekly Bible Study',
        summaryText: 'Church On App',
      ),
      icon: '@mipmap/ic_launcher',
      largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      color: kSunflowerYellow,
      subText: 'Church On App',
      visibility: NotificationVisibility.public,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    final details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _plugin.periodicallyShow(
      id: _weeklyReminderId,
      title: '📖 Weekly Bible Study',
      body: 'It\'s $day — time for your weekly deep study session!',
      repeatInterval: RepeatInterval.weekly,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
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

  final _overlayController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get overlayStream => _overlayController.stream;

  Future<void> sendNotification({
    required String title,
    required String body,
    String? userId,
    String? type,
    String? referenceId,
    String? channelId,
    String? payload,
  }) async {
    _overlayController.add({
      'title': title,
      'body': body,
      'type': type,
      'userId': userId,
      'referenceId': referenceId,
    });
    await _show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      channelId: channelId ?? _chAnnouncements,
      channelName: 'Announcements',
      payload: payload,
    );
  }

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

class _PendingNotification {
  final String title;
  final String body;
  final String channelName;
  final String? payload;

  _PendingNotification({
    required this.title,
    required this.body,
    required this.channelName,
    this.payload,
  });

  String get contentKey => '$title|${body.trim()}';
}

final notificationServiceProvider = Provider((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return NotificationService(client);
});
