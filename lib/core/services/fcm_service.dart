import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/services/supabase_service.dart';

class FcmService {
  final WidgetRef ref;
  String? _token;

  FcmService(this.ref);

  Future<void> init() async {
    await Firebase.initializeApp();
    final messaging = FirebaseMessaging.instance;

    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    _token = await messaging.getToken();
    if (_token != null) {
      await _storeToken(_token!);
    }

    messaging.onTokenRefresh.listen(_storeToken);

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('[FCM] onMessage: ${message.notification?.title}');
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('[FCM] onMessageOpenedApp: ${message.notification?.title}');
    });
  }

  Future<void> _storeToken(String token) async {
    final user = ref.read(supabaseServiceProvider).client.auth.currentUser;
    if (user == null) return;
    await ref
        .read(supabaseServiceProvider)
        .client
        .from('profiles')
        .update({'fcm_token': token}).eq('id', user.id);
  }
}
