import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/services/coins_service.dart';
import 'package:church_on_app/features/connect/data/user_activity_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AttendanceScannerScreen extends ConsumerStatefulWidget {
  const AttendanceScannerScreen({super.key});

  @override
  ConsumerState<AttendanceScannerScreen> createState() => _AttendanceScannerScreenState();
}

class _AttendanceScannerScreenState extends ConsumerState<AttendanceScannerScreen> {
  bool _isProcessing = false;

  Future<void> _handleScan(String userId) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    final tenant = ref.read(currentTenantProvider);
    if (tenant == null) return;

    try {
      // Record attendance in Supabase
      await Supabase.instance.client.from('attendance_logs').insert({
        'user_id': userId,
        'tenant_id': tenant.id,
        'check_in_time': DateTime.now().toIso8601String(),
      });

      final coins = await ref.read(coinsServiceProvider).addAttendanceCoins();
      await ref.read(userActivityServiceProvider).logActivity(
        type: ActivityType.attendanceScanned,
        description: "Attendance check-in",
        coinsEarned: coins,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Member Checked In! +$coins coins earned."),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Scan Error: $e")));
      }
    } finally {
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("QR ATTENDANCE SCANNER")),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                if (barcode.rawValue != null) {
                  _handleScan(barcode.rawValue!);
                }
              }
            },
          ),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: _isProcessing ? Colors.blue : Colors.white, width: 4),
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          ),
          if (_isProcessing)
            const Center(child: CircularProgressIndicator(color: Colors.white)),
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                _isProcessing ? "PROCESSING..." : "SCAN MEMBER QR",
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

