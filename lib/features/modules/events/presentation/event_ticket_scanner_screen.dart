import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EventTicketScannerScreen extends StatefulWidget {
  final String eventId;
  final String eventTitle;

  const EventTicketScannerScreen({
    super.key,
    required this.eventId,
    required this.eventTitle,
  });

  @override
  State<EventTicketScannerScreen> createState() => _EventTicketScannerScreenState();
}

class _EventTicketScannerScreenState extends State<EventTicketScannerScreen> {
  MobileScannerController? _scannerController;
  bool _isProcessing = false;
  int _totalScanned = 0;
  int _totalCheckedIn = 0;
  final List<Map<String, dynamic>> _recentScans = [];

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final regs = await Supabase.instance.client
          .from('event_registrations')
          .select('id, check_in_status')
          .eq('event_id', widget.eventId);
      final checkedIn = regs.where((r) => r['check_in_status'] == true).length;
      if (mounted) {
        setState(() {
          _totalScanned = regs.length;
          _totalCheckedIn = checkedIn;
        });
      }
    } catch (e) {
      debugPrint('Error fetching registration stats: $e');
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;
    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue;
      if (code != null && code.isNotEmpty) {
        _validateTicket(code);
        break;
      }
    }
  }

  String _extractRegistrationId(String code) {
    final uri = Uri.tryParse(code);
    if (uri != null && uri.scheme == 'coa' && uri.host == 'event') {
      final segments = uri.pathSegments;
      if (segments.length == 3 && segments[1] == 'ticket') {
        return segments[2];
      }
    }
    return code;
  }

  Future<void> _validateTicket(String ticketCode) async {
    if (_isProcessing) return;
    setState(() {
      _isProcessing = true;
    });

    try {
      final registrationId = _extractRegistrationId(ticketCode);

      final reg = await Supabase.instance.client
          .from('event_registrations')
          .select('id, user_id, check_in_status, profiles (full_name, avatar_url, phone_number)')
          .eq('event_id', widget.eventId)
          .eq('id', registrationId)
          .maybeSingle();

      if (reg == null) {
      _showResultSheet(
        success: false,
        title: 'Invalid Ticket',
        subtitle: 'This ticket is not valid for this event.',
        icon: LucideIcons.xCircle,
        color: Colors.red,
      );
      setState(() {
        _isProcessing = false;
      });
        return;
      }

      _processCheckIn(reg);
    } catch (e) {
      _showResultSheet(
        success: false,
        title: 'Scan Error',
        subtitle: 'Could not validate ticket. Please try again.',
        icon: LucideIcons.alertTriangle,
        color: Colors.orange,
      );
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _logScanAudit({
    required String registrationId,
    required String status,
    String? details,
  }) async {
    try {
      final scannerId = Supabase.instance.client.auth.currentUser?.id;
      if (scannerId == null) return;
      await Supabase.instance.client.from('scan_audit').insert({
        'event_id': widget.eventId,
        'registration_id': registrationId,
        'scanned_by': scannerId,
        'scan_type': 'ticket',
        'status': status,
        'details': details,
        'scanned_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Failed to log scan audit: $e');
    }
  }

  void _processCheckIn(Map<String, dynamic> reg) async {
    final profile = reg['profiles'] as Map<String, dynamic>?;
    final name = profile?['full_name'] ?? 'Unknown';
    final isCheckedIn = reg['check_in_status'] == true;

    if (isCheckedIn) {
      await _logScanAudit(
        registrationId: reg['id'],
        status: 'duplicate',
        details: '$name already checked in',
      );
      _showResultSheet(
        success: false,
        title: 'Already Checked In',
        subtitle: '$name has already been scanned in.',
        icon: LucideIcons.alertTriangle,
        color: Colors.orange,
        name: name,
      );
      setState(() {
        _recentScans.insert(0, {
          'name': name,
          'status': 'duplicate',
          'time': DateTime.now(),
        });
        _isProcessing = false;
      });
      return;
    }

    try {
      await Supabase.instance.client
          .from('event_registrations')
          .update({'check_in_status': true}).eq('id', reg['id']);

      // Write to event_checkins for audit trail
      try {
        final userId = Supabase.instance.client.auth.currentUser?.id;
        if (userId != null) {
          await Supabase.instance.client.from('event_checkins').insert({
            'event_id': widget.eventId,
            'registration_id': reg['id'],
            'scanned_by': userId,
          });
        }
      } catch (e) {
        debugPrint('Error recording check-in: $e');
      }

      await _logScanAudit(
        registrationId: reg['id'],
        status: 'success',
        details: '$name checked in successfully',
      );

      _showResultSheet(
        success: true,
        title: 'Welcome!',
        subtitle: '$name has been checked in successfully.',
        icon: LucideIcons.checkCircle,
        color: Colors.green,
        name: name,
      );
      setState(() {
        _totalCheckedIn++;
        _recentScans.insert(0, {
          'name': name,
          'status': 'success',
          'time': DateTime.now(),
        });
        _isProcessing = false;
      });
    } catch (e) {
      _showResultSheet(
        success: false,
        title: 'Check-in Failed',
        subtitle: 'Could not check in $name. Please try again.',
        icon: LucideIcons.xCircle,
        color: Colors.red,
      );
      setState(() => _isProcessing = false);
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
      builder: (_) => Container(
        padding: EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2)),
            ),
            SizedBox(height: 20),
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 48),
            ),
            SizedBox(height: 16),
            Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            SizedBox(height: 8),
            Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 13), textAlign: TextAlign.center),
            if (name != null) ...[
              SizedBox(height: 12),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(name, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
              ),
            ],
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                minimumSize: Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              child: Text(success ? 'CONTINUE SCANNING' : 'TRY AGAIN', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
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
            Text('Ticket Scanner', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            Text(widget.eventTitle, style: TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
        iconTheme: IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: Icon(_scannerController?.torchEnabled == true ? Icons.flash_on : Icons.flash_off, color: Colors.white),
            onPressed: () => _scannerController?.toggleTorch(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Stats bar
          Container(
            padding: EdgeInsets.all(16),
            color: Colors.grey[900],
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('CHECKED IN', _totalCheckedIn.toString(), Colors.green),
                _buildStatItem('REGISTERED', _totalScanned.toString(), Colors.blue),
                _buildStatItem('REMAINING', (_totalScanned - _totalCheckedIn).toString(), Colors.orange),
              ],
            ),
          ),
          // Scanner view
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
                // Scanner overlay
                CustomPaint(
                  painter: _ScannerOverlayPainter(),
                  child: Container(),
                ),
                // Instructions
                Positioned(
                  bottom: 20,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.qr_code_scanner, color: Colors.white70, size: 20),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _isProcessing ? 'Processing ticket...' : 'Point camera at ticket QR code',
                            style: TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ),
                        if (_isProcessing)
                          SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Recent scans
          Expanded(
            flex: 2,
            child: Container(
              color: Colors.grey[900],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('RECENT SCANS', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                        if (_recentScans.isNotEmpty)
                          TextButton(
                            onPressed: () => setState(() => _recentScans.clear()),
                            child: Text('Clear', style: TextStyle(color: Colors.white54, fontSize: 11)),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _recentScans.isEmpty
                        ? Center(
                            child: Text(
                              'No scans yet',
                              style: TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                          )
                        : ListView.builder(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _recentScans.length.clamp(0, 6),
                            itemBuilder: (context, index) {
                              final scan = _recentScans[index];
                              final isSuccess = scan['status'] == 'success';
                              final time = scan['time'] as DateTime;
                              return Container(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Row(
                                  children: [
                                    Icon(
                                      isSuccess ? Icons.check_circle : Icons.cancel,
                                      color: isSuccess ? Colors.green : Colors.red,
                                      size: 16,
                                    ),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        scan['name'],
                                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    Text(
                                      '${time.hour}:${time.minute.toString().padLeft(2, '0')}',
                                      style: TextStyle(color: Colors.white54, fontSize: 11),
                                    ),
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
        SizedBox(height: 4),
        Text(label, style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
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

    // Draw overlay with cutout
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(scanArea, Radius.circular(20)))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);

    // Draw scan area border
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawRRect(
      RRect.fromRectAndRadius(scanArea, Radius.circular(20)),
      borderPaint,
    );

    // Draw corner accents
    final cornerPaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    final cornerLength = 30.0;
    // Top-left
    canvas.drawLine(Offset(scanArea.left, scanArea.top + cornerLength), Offset(scanArea.left, scanArea.top), cornerPaint);
    canvas.drawLine(Offset(scanArea.left, scanArea.top), Offset(scanArea.left + cornerLength, scanArea.top), cornerPaint);
    // Top-right
    canvas.drawLine(Offset(scanArea.right - cornerLength, scanArea.top), Offset(scanArea.right, scanArea.top), cornerPaint);
    canvas.drawLine(Offset(scanArea.right, scanArea.top), Offset(scanArea.right, scanArea.top + cornerLength), cornerPaint);
    // Bottom-left
    canvas.drawLine(Offset(scanArea.left, scanArea.bottom - cornerLength), Offset(scanArea.left, scanArea.bottom), cornerPaint);
    canvas.drawLine(Offset(scanArea.left, scanArea.bottom), Offset(scanArea.left + cornerLength, scanArea.bottom), cornerPaint);
    // Bottom-right
    canvas.drawLine(Offset(scanArea.right - cornerLength, scanArea.bottom), Offset(scanArea.right, scanArea.bottom), cornerPaint);
    canvas.drawLine(Offset(scanArea.right, scanArea.bottom - cornerLength), Offset(scanArea.right, scanArea.bottom), cornerPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
