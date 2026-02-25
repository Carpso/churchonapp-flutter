import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

class ConnectivityUtil {
  static final Connectivity _connectivity = Connectivity();

  static Stream<List<ConnectivityResult>> get onConnectivityChanged => _connectivity.onConnectivityChanged;

  static Future<bool> isConnected() async {
    final List<ConnectivityResult> result = await _connectivity.checkConnectivity();
    return result.any((r) => r != ConnectivityResult.none);
  }
}

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ConnectivityResult>>(
      stream: ConnectivityUtil.onConnectivityChanged,
      builder: (context, snapshot) {
        final List<ConnectivityResult>? results = snapshot.data;
        final bool isOffline = results != null && !results.any((r) => r != ConnectivityResult.none);

        if (!isOffline) return const SizedBox.shrink();

        return Container(
          width: double.infinity,
          color: Colors.red,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.wifi_off, color: Colors.white, size: 16),
              SizedBox(width: 8),
              Text(
                "YOU ARE OFFLINE - CHECKING CONNECTION",
                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        );
      },
    );
  }
}
