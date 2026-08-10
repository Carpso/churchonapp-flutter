import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/widgets/profile_avatar.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/services/coins_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AttendanceScannerScreen extends ConsumerStatefulWidget {
  const AttendanceScannerScreen({super.key});

  @override
  ConsumerState<AttendanceScannerScreen> createState() => _AttendanceScannerScreenState();
}

class _AttendanceScannerScreenState extends ConsumerState<AttendanceScannerScreen> {
  MobileScannerController? _scanner;
  bool _isProcessing = false;
  String? _lastScanName;
  String? _lastScanAvatar;
  String? _lastScanStatus;
  int _totalScanned = 0;
  int _totalToday = 0;
  final Set<String> _scannedToday = {};
  final List<_ScanRecord> _recentScans = [];

  @override
  void initState() {
    super.initState();
    _scanner = MobileScannerController();
    _loadStats();
  }

  @override
  void dispose() {
    _scanner?.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    final tenant = ref.read(currentTenantProvider);
    if (tenant == null) return;
    try {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final res = await Supabase.instance.client
          .from('attendance_logs')
          .select('user_id')
          .eq('tenant_id', tenant.id)
          .gte('check_in_time', today);
      final ids = (res as List).map((r) => r['user_id']?.toString() ?? '').toSet();
      _scannedToday.addAll(ids);
      setState(() => _totalToday = _scannedToday.length);
    } catch (_) {}
  }

  Future<void> _handleScan(String rawValue) async {
    if (_isProcessing) return;
    final userId = _extractUserId(rawValue);
    if (userId.isEmpty) return;

    if (_scannedToday.contains(userId)) {
      HapticFeedback.heavyImpact();
      setState(() {
        _lastScanName = 'Already checked in';
        _lastScanStatus = 'duplicate';
      });
      return;
    }

    setState(() => _isProcessing = true);
    HapticFeedback.mediumImpact();

    final tenant = ref.read(currentTenantProvider);
    if (tenant == null) return;

    try {
      // Fetch member info
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('full_name, avatar_url')
          .eq('id', userId)
          .maybeSingle();

      // Record attendance
      await Supabase.instance.client.from('attendance_logs').insert({
        'user_id': userId,
        'tenant_id': tenant.id,
        'check_in_time': DateTime.now().toIso8601String(),
      });

      final coins = await ref.read(coinsServiceProvider).addAttendanceCoins();

      _scannedToday.add(userId);
      final record = _ScanRecord(
        name: profile?['full_name'] ?? 'Member',
        avatar: profile?['avatar_url'],
        coins: coins,
      );
      _recentScans.insert(0, record);
      if (_recentScans.length > 20) _recentScans.removeLast();

      setState(() {
        _totalScanned++;
        _totalToday = _scannedToday.length;
        _lastScanName = record.name;
        _lastScanAvatar = record.avatar;
        _lastScanStatus = 'success';
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _lastScanName = 'Scan error';
        _lastScanStatus = 'error';
        _isProcessing = false;
      });
    } finally {
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        setState(() {
          _lastScanName = null;
          _lastScanStatus = null;
        });
      }
    }
  }

  String _extractUserId(String raw) {
    if (raw.length == 36 && raw.contains('-')) return raw; // UUID
    // Try parsing from coa:// QR or other formats
    final uri = Uri.tryParse(raw);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.last;
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Attendance Scanner"),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Stats bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            color: Colors.grey.shade900,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _stat('Today', '$_totalToday', LucideIcons.calendar),
                _stat('Total', '$_totalScanned', LucideIcons.users),
                _stat('Recent', '${_recentScans.length}', LucideIcons.clock),
              ],
            ),
          ),
          // Scanner
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                MobileScanner(
                  controller: _scanner,
                  onDetect: (capture) {
                    for (final b in capture.barcodes) {
                      if (b.rawValue != null) _handleScan(b.rawValue!);
                    }
                  },
                ),
                // Scan frame
                Center(
                  child: Container(
                    width: 250,
                    height: 250,
                    decoration: BoxDecoration(
                      border: Border.all(color: _isProcessing ? Colors.green : Colors.white.withValues(alpha: 0.7), width: 3),
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
                // Last scan status
                if (_lastScanName != null)
                  Positioned(
                    top: 16,
                    left: 20,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _lastScanStatus == 'success' ? Colors.green : _lastScanStatus == 'duplicate' ? Colors.orange : Colors.red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                        child: Row(
                          children: [
                            if (_lastScanName != null && _lastScanName != 'Already checked in' && _lastScanName != 'Scan error')
                              ProfileAvatar(avatarUrl: _lastScanAvatar, name: _lastScanName, radius: 16),
                            const SizedBox(width: 10),
                          Expanded(child: Text(_lastScanName!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                          Icon(
                            _lastScanStatus == 'success' ? LucideIcons.checkCircle : LucideIcons.alertCircle,
                            color: Colors.white,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Recent scans
          if (_recentScans.isNotEmpty)
            Container(
              height: 150,
              color: Colors.grey.shade900,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(padding: EdgeInsets.all(12), child: Text("Recent Check-ins", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13))),
                  Expanded(
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _recentScans.length,
                      itemBuilder: (_, i) => Container(
                        width: 100,
                        margin: const EdgeInsets.only(left: 12),
                        child: Column(
                          children: [
                            ProfileAvatar(avatarUrl: _recentScans[i].avatar, name: _recentScans[i].name, radius: 24),
                            const SizedBox(height: 4),
                            Text(_recentScans[i].name, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11)),
                            Text('+${_recentScans[i].coins} CC', style: TextStyle(color: Colors.amberAccent, fontSize: 10)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, IconData icon) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white54, size: 18),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
      ],
    );
  }
}

class _ScanRecord {
  final String name;
  final String? avatar;
  final int coins;
  const _ScanRecord({required this.name, this.avatar, this.coins = 0});
}
