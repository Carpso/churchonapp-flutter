import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/utils/connectivity_util.dart';
import 'package:church_on_app/core/services/cache_service.dart';
import 'package:church_on_app/core/services/offline_service.dart';

final connectivityStatusProvider = connectivityProvider;

final offlineQueueCountProvider = StreamProvider<int>((ref) {
  final svc = ref.watch(offlineServiceProvider);
  return svc.queueLengthStream;
});

final cacheServiceProvider2 = cacheServiceProvider;

final offlineServiceProvider2 = offlineServiceProvider;
