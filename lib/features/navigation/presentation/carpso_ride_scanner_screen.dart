import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/services/coins_service.dart';
import 'package:church_on_app/features/connect/data/user_activity_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CarpsoRideScannerScreen extends ConsumerStatefulWidget {
  const CarpsoRideScannerScreen({super.key});

  @override
  ConsumerState<CarpsoRideScannerScreen> createState() => _CarpsoRideScannerScreenState();
}

class _CarpsoRideScannerScreenState extends ConsumerState<CarpsoRideScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _isProcessing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<bool> _userExists(String userId) async {
    try {
      final res = await Supabase.instance.client
          .from('profiles')
          .select('id')
          .eq('id', userId)
          .maybeSingle();
      return res != null;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _alreadyCheckedInToday(String userId, String tenantId) async {
    try {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final res = await Supabase.instance.client
          .from('attendance_logs')
          .select('id')
          .eq('user_id', userId)
          .eq('tenant_id', tenantId)
          .gte('check_in_time', startOfDay.toIso8601String())
          .maybeSingle();
      return res != null;
    } catch (_) {
      return false;
    }
  }

  Future<void> _handleScan(String userId) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final tenant = ref.read(currentTenantProvider);
      if (tenant == null) {
        _showToast("No church selected. Please select a church first.", Colors.red);
        return;
      }

      final exists = await _userExists(userId);
      if (!exists) {
        _showToast("Invalid QR code: User not found in system.", Colors.red);
        return;
      }

      final alreadyCheckedIn = await _alreadyCheckedInToday(userId, tenant.id);
      if (alreadyCheckedIn) {
        _showToast("This member has already checked in today.", Colors.orange);
        return;
      }

      await Supabase.instance.client.from('attendance_logs').insert({
        'user_id': userId,
        'tenant_id': tenant.id,
        'check_in_time': DateTime.now().toIso8601String(),
      });

      final coins = await ref.read(coinsServiceProvider).addAttendanceCoins();

      await ref.read(userActivityServiceProvider).logActivity(
        type: ActivityType.attendanceScanned,
        description: 'Checked in at ${tenant.name}',
        coinsEarned: coins,
      );

      _showResult("Faithful Attendance Checked In!", coins);
    } catch (e) {
      _showToast("Error: $e", Colors.red);
    } finally {
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showToast(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: color,
      duration: const Duration(seconds: 3),
    ));
    setState(() => _isProcessing = false);
  }

  void _showResult(String message, int coins) {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(40),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.checkCircle, color: Colors.green, size: 60),
            const SizedBox(height: 20),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text("+$coins Church Coins", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() => _isProcessing = false);
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              child: const Text("DONE"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text("Scan QR Code", style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              final barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                if (barcode.rawValue != null && !_isProcessing) {
                  _handleScan(barcode.rawValue!);
                  break;
                }
              }
            },
          ),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: _isProcessing ? Colors.amber : Colors.white, width: 3),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          if (_isProcessing)
            const Center(child: CircularProgressIndicator(color: Colors.amber)),
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                _isProcessing ? "PROCESSING..." : "SCAN MEMBER QR CODE",
                style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 1.2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
