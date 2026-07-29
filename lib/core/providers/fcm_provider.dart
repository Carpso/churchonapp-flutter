import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/services/fcm_service.dart';

FcmService? _fcmInstance;

FcmService? get fcmInstance => _fcmInstance;

set fcmInstance(FcmService? instance) => _fcmInstance = instance;

final fcmServiceProvider = Provider<FcmService?>((ref) => _fcmInstance);
