import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final connectivityProvider = StreamProvider<bool>((ref) {
  return Connectivity().onConnectivityChanged.map((result) {
    return result.any((r) => r != ConnectivityResult.none);
  });
});

final isOnlineProvider = FutureProvider<bool>((ref) async {
  final result = await Connectivity().checkConnectivity();
  return result.any((r) => r != ConnectivityResult.none);
});

class ConnectivityUtil {
  static final Connectivity _connectivity = Connectivity();

  static Stream<bool> get onConnectivityChanged =>
      _connectivity.onConnectivityChanged.map(
          (result) => result.any((r) => r != ConnectivityResult.none));

  static Future<bool> isConnected() async {
    final result = await _connectivity.checkConnectivity();
    return result.any((r) => r != ConnectivityResult.none);
  }
}

class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(connectivityProvider);
    final isOffline = async.asData?.value == false;
    if (isOffline != true) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      color: Colors.red.shade800,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off, color: Colors.white.withValues(alpha: 0.9), size: 16),
          const SizedBox(width: 10),
          Text(
            "YOU ARE OFFLINE • Showing cached content",
            style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class OfflineAwareWrapper extends ConsumerWidget {
  final Widget child;
  const OfflineAwareWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        const OfflineBanner(),
        Expanded(child: child),
      ],
    );
  }
}
