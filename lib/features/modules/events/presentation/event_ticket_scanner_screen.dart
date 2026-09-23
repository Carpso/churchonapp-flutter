import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:church_on_app/features/events/data/event_ticketing_service.dart';

/// Host-side ticket scanner. Every scan is validated SERVER-SIDE by the
/// `validate_event_ticket` RPC, which marks a ticket used exactly once and is
/// idempotent (a re-scan returns `already_used`, never a second admission).
class EventTicketScannerScreen extends ConsumerStatefulWidget {
  final String eventId;
  final String eventTitle;

  const EventTicketScannerScreen({
    super.key,
    required this.eventId,
    required this.eventTitle,
  });

  @override
  ConsumerState<EventTicketScannerScreen> createState() => _EventTicketScannerScreenState();
}

class _EventTicketScannerScreenState extends ConsumerState<EventTicketScannerScreen> {
  MobileScannerController? _scannerController;
  bool _isProcessing = false;
  int _totalTickets = 0;
  int _totalCheckedIn = 0;
  final List<Map<String, dynamic>> _recentScans = [];

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final rows = await Supabase.instance.client
          .from('event_tickets')
          .select('id, status')
          .eq('event_id', widget.eventId);
      final list = List<Map<String, dynamic>>.from(rows);
      final checkedIn = list.where((r) => r['status'] == 'used').length;
      final valid = list.where((r) => r['status'] != 'refunded' && r['status'] != 'cancelled').length;
      if (mounted) {
        setState(() {
          _totalTickets = valid;
          _totalCheckedIn = checkedIn;
        });
      }
    } catch (e) {
      debugPrint('Error fetching ticket stats: $e');
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;
    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue;
      if (code != null && code.isNotEmpty) {
        _validateTicket(_extractTicketCode(code));
        break;
      }
    }
  }

  /// QR payloads are `COA-TKT-…|<deep-link>`; legacy `coa://event/<id>/ticket/<regId>`
  /// codes are passed through unchanged (the server rejects them as invalid).
  String _extractTicketCode(String code) {
    if (code.contains('|')) return code.split('|').first.trim();
    final uri = Uri.tryParse(code);
    if (uri != null && uri.scheme == 'coa' && uri.host == 'event') {
      final segments = uri.pathSegments;
      if (segments.isNotEmpty) return segments.last;
    }
    return code.trim();
  }

  Future<void> _validateTicket(String ticketCode) async {
    if (_isProcessing || ticketCode.isEmpty) return;
    setState(() => _isProcessing = true);

    try {
      final result = await ref
          .read(eventTicketingServiceProvider)
          .validate(eventId: widget.eventId, ticketCode: ticketCode);

      final success = result.isValid;
      final color = success
          ? Colors.green
          : result.isAlreadyUsed
              ? Colors.orange
              : Colors.red;
      final icon = success
          ? LucideIcons.checkCircle
          : result.isAlreadyUsed
              ? LucideIcons.alertTriangle
              : LucideIcons.xCircle;

      _showResultSheet(
        success: success,
        title: success ? 'Welcome!' : (result.isAlreadyUsed ? 'Already Checked In' : 'Invalid Ticket'),
        subtitle: result.message,
        icon: icon,
        color: color,
        name: result.attendeeName,
      );

      setState(() {
        if (success) _totalCheckedIn++;
        _recentScans.insert(0, {
          'name': result.attendeeName ?? 'Unknown',
          'status': success ? 'success' : (result.isAlreadyUsed ? 'duplicate' : 'invalid'),
          'time': DateTime.now(),
        });
        if (_recentScans.length > 20) _recentScans.removeLast();
        _isProcessing = false;
      });
    } catch (e) {
      _showResultSheet(
        success: false,
        title: 'Scan Error',
        subtitle: e.toString(),
        icon: LucideIcons.alertTriangle,
        color: Colors.orange,
      );
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _manualEntry() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter ticket code'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'COA-TKT-2026-XXXXXX'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Validate'),
          ),
        ],
      ),
    );
    if (code != null && code.isNotEmpty) {
      await _validateTicket(_extractTicketCode(code));
    }
  }

  void _showResultSheet({
    required bool success,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    String? name,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(ctx).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 48),
            ),
            const SizedBox(height: 16),
            Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 8),
            Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 13), textAlign: TextAlign.center),
            if (name != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                child: Text(name, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
              ),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              child: Text(success ? 'CONTINUE SCANNING' : 'TRY AGAIN',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
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
        backgroundColor: Colors.black,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ticket Scanner', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            Text(widget.eventTitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: 'Enter code manually',
            icon: const Icon(Icons.keyboard, color: Colors.white),
            onPressed: _isProcessing ? null : _manualEntry,
          ),
          IconButton(
            icon: Icon(_scannerController?.torchEnabled == true ? Icons.flash_on : Icons.flash_off, color: Colors.white),
            onPressed: () => _scannerController?.toggleTorch(),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[900],
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('CHECKED IN', _totalCheckedIn.toString(), Colors.green),
                _buildStatItem('TICKETS', _totalTickets.toString(), Theme.of(context).primaryColor),
                _buildStatItem('REMAINING', (_totalTickets - _totalCheckedIn).toString(), Colors.orange),
              ],
            ),
          ),
          Expanded(
            flex: 4,
            child: Stack(
              children: [
                MobileScanner(
                  onDetect: _onDetect,
                  controller: _scannerController ??= MobileScannerController(
                    detectionSpeed: DetectionSpeed.normal,
                    facing: CameraFacing.back,
                  ),
                ),
                CustomPaint(painter: _ScannerOverlayPainter(), child: Container()),
                Positioned(
                  bottom: 20,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        const Icon(Icons.qr_code_scanner, color: Colors.white70, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _isProcessing ? 'Processing ticket...' : 'Point camera at ticket QR code',
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ),
                        if (_isProcessing)
                          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              color: Colors.grey[900],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('RECENT SCANS', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                        if (_recentScans.isNotEmpty)
                          TextButton(
                            onPressed: () => setState(() => _recentScans.clear()),
                            child: const Text('Clear', style: TextStyle(color: Colors.white54, fontSize: 11)),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _recentScans.isEmpty
                        ? const Center(child: Text('No scans yet', style: TextStyle(color: Colors.white54, fontSize: 12)))
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _recentScans.length.clamp(0, 6),
                            itemBuilder: (context, index) {
                              final scan = _recentScans[index];
                              final isSuccess = scan['status'] == 'success';
                              final time = scan['time'] as DateTime;
                              return Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Row(
                                  children: [
                                    Icon(isSuccess ? Icons.check_circle : Icons.cancel,
                                        color: isSuccess ? Colors.green : Colors.red, size: 16),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(scan['name'],
                                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                                    ),
                                    Text('${time.hour}:${time.minute.toString().padLeft(2, '0')}',
                                        style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(color: color, fontSize: 28, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
      ],
    );
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    super.dispose();
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.fill;

    final scanArea = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2 - 40),
      width: size.width * 0.7,
      height: size.width * 0.7,
    );

    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(scanArea, const Radius.circular(20)))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawRRect(RRect.fromRectAndRadius(scanArea, const Radius.circular(20)), borderPaint);

    final cornerPaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    const cornerLength = 30.0;
    canvas.drawLine(Offset(scanArea.left, scanArea.top + cornerLength), Offset(scanArea.left, scanArea.top), cornerPaint);
    canvas.drawLine(Offset(scanArea.left, scanArea.top), Offset(scanArea.left + cornerLength, scanArea.top), cornerPaint);
    canvas.drawLine(Offset(scanArea.right - cornerLength, scanArea.top), Offset(scanArea.right, scanArea.top), cornerPaint);
    canvas.drawLine(Offset(scanArea.right, scanArea.top), Offset(scanArea.right, scanArea.top + cornerLength), cornerPaint);
    canvas.drawLine(Offset(scanArea.left, scanArea.bottom - cornerLength), Offset(scanArea.left, scanArea.bottom), cornerPaint);
    canvas.drawLine(Offset(scanArea.left, scanArea.bottom), Offset(scanArea.left + cornerLength, scanArea.bottom), cornerPaint);
    canvas.drawLine(Offset(scanArea.right - cornerLength, scanArea.bottom), Offset(scanArea.right, scanArea.bottom), cornerPaint);
    canvas.drawLine(Offset(scanArea.right, scanArea.bottom - cornerLength), Offset(scanArea.right, scanArea.bottom), cornerPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
