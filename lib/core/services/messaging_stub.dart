class FirebaseMessaging {
  static final FirebaseMessaging instance = FirebaseMessaging._();
  FirebaseMessaging._();

  static final Stream<RemoteMessage> onMessage = const Stream.empty();
  static final Stream<RemoteMessage> onMessageOpenedApp = const Stream.empty();
  static void onBackgroundMessage(Function handler) {}

  Future<String?> getToken() async => null;
  Stream<String> get onTokenRefresh => const Stream.empty();
  Future<RemoteMessage?> getInitialMessage() async => null;
  Future<void> setForegroundNotificationPresentationOptions({
    bool alert = true,
    bool badge = true,
    bool sound = true,
  }) async {}

  Future<NotificationSettings> requestPermission({
    bool alert = true,
    bool badge = true,
    bool sound = true,
    bool provisional = false,
  }) async => const NotificationSettings();
}

class RemoteMessage {
  final Map<String, dynamic> data;
  final RemoteNotification? notification;
  const RemoteMessage({this.data = const {}, this.notification});
}

class RemoteNotification {
  final String? title;
  final String? body;
  const RemoteNotification({this.title, this.body});
}

class NotificationSettings {
  const NotificationSettings();
  AuthorizationStatus get authorizationStatus => AuthorizationStatus.notDetermined;
}

enum AuthorizationStatus { notDetermined, authorized, provisional, denied }
