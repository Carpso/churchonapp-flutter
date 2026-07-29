import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:church_on_app/core/widgets/premium_toast.dart';
import 'package:church_on_app/core/services/code_generator_service.dart';
import 'package:church_on_app/features/events/data/event_service.dart';

class TicketDetailScreen extends ConsumerStatefulWidget {
  final ChurchEvent event;
  const TicketDetailScreen({super.key, required this.event});

  @override
  ConsumerState<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends ConsumerState<TicketDetailScreen> {
  bool _isLoadingRsvp = false;
  String? _existingRsvp;
  String? _ticketId;
  String? _ticketType;
  int _ticketQuantity = 1;

  @override
  void initState() {
    super.initState();
    _loadRsvpStatus();
    _generateTicketId();
  }

  Future<void> _generateTicketId() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      final existing = await Supabase.instance.client
          .from('event_registrations')
          .select('id, ticket_type, ticket_quantity')
          .eq('event_id', widget.event.id)
          .eq('user_id', user.id)
          .maybeSingle();
      if (existing != null) {
        setState(() {
          _ticketId = existing['id'];
          _ticketType = existing['ticket_type'] ?? 'General';
          _ticketQuantity = existing['ticket_quantity'] ?? 1;
        });
      } else {
        final created = await Supabase.instance.client
            .from('event_registrations')
            .insert({
              'event_id': widget.event.id,
              'user_id': user.id,
              'ticket_type': 'General',
              'ticket_quantity': 1,
              'rsvp_status': 'Going',
            })
            .select('id')
            .single();
        setState(() {
          _ticketId = created['id'];
          _ticketType = 'General';
          _ticketQuantity = 1;
        });
      }
    } catch (_) {
      final codeGen = ref.read(codeGeneratorProvider);
      final ticketId = await codeGen.generateTicketId();
      setState(() => _ticketId = ticketId);
    }
  }

  String get _qrData => 'coa://event/${widget.event.id}/ticket/$_ticketId';

  Future<void> _loadRsvpStatus() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      final existing = await Supabase.instance.client
          .from('event_registrations')
          .select('rsvp_status')
          .eq('event_id', widget.event.id)
          .eq('user_id', user.id)
          .maybeSingle();
      if (existing != null && existing['rsvp_status'] != null) {
        setState(() => _existingRsvp = existing['rsvp_status'].toString());
      }
    } catch (e) {
      debugPrint('Error checking RSVP status: $e');
    }
  }

  Future<void> _updateRsvp(String status) async {
    setState(() => _isLoadingRsvp = true);
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      PremiumToast.showError(context, "Please login to RSVP", title: "Auth Required");
      setState(() => _isLoadingRsvp = false);
      return;
    }
    try {
      final existing = await Supabase.instance.client
          .from('event_registrations')
          .select('id')
          .eq('event_id', widget.event.id)
          .eq('user_id', user.id)
          .maybeSingle();
      if (existing != null) {
        await Supabase.instance.client
            .from('event_registrations')
            .update({'rsvp_status': status})
            .eq('id', existing['id']);
      } else {
        await Supabase.instance.client.from('event_registrations').insert({
          'event_id': widget.event.id,
          'user_id': user.id,
          'rsvp_status': status,
        });
      }
      setState(() => _existingRsvp = status);
      if (!mounted) return;
      PremiumToast.showSuccess(context, "RSVP updated to $status", title: "Status Updated");
    } catch (e) {
      if (!mounted) return;
      PremiumToast.showError(context, "Failed to update RSVP", title: "Error");
    }
    if (mounted) setState(() => _isLoadingRsvp = false);
  }

  Future<Uint8List> _buildPdf() async {
    final pdf = pw.Document();
    final event = widget.event;
    final primaryPdfColor = PdfColor.fromInt(Theme.of(context).primaryColor.toARGB32());

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(20),
        build: (context) {
          return pw.Column(
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.all(20),
                decoration: pw.BoxDecoration(
                  gradient: pw.LinearGradient(
                    colors: [primaryPdfColor, PdfColors.orange],
                    begin: pw.Alignment.topLeft,
                    end: pw.Alignment.bottomRight,
                  ),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(16)),
                ),
                child: pw.Column(
                  children: [
                    pw.Icon(pw.IconData(0xe004), color: PdfColors.white, size: 40),
                    pw.SizedBox(height: 12),
                    pw.Text(event.title, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.white), textAlign: pw.TextAlign.center),
                    pw.SizedBox(height: 8),
                    pw.Text(DateFormat.yMMMd().format(event.date), style: pw.TextStyle(fontSize: 12, color: PdfColors.white)),
                    pw.SizedBox(height: 4),
                    pw.Text(event.location, style: pw.TextStyle(fontSize: 12, color: PdfColors.white)),
                    pw.SizedBox(height: 16),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      decoration: pw.BoxDecoration(color: PdfColor.fromInt(0x33FFFFFF), borderRadius: const pw.BorderRadius.all(pw.Radius.circular(20))),
                      child: pw.Text(
                        event.ticketPrice == 0 ? "FREE" : "K${event.ticketPrice.toStringAsFixed(0)}",
                        style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
                ),
                child: pw.Column(
                  children: [
                    pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                      pw.Text('Ticket ID', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                      pw.Text(_ticketId ?? event.id, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    ]),
                    pw.SizedBox(height: 8),
                    pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                      pw.Text('Type', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                      pw.Text(_ticketType ?? 'General', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    ]),
                    pw.SizedBox(height: 8),
                    pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                      pw.Text('Qty', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                      pw.Text('$_ticketQuantity', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    ]),
                    pw.SizedBox(height: 8),
                    pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                      pw.Text('Status', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                      pw.Text('VALID', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.green)),
                    ]),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Divider(),
              pw.SizedBox(height: 12),
              pw.Text('Present this ticket at the event entrance', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500)),
              pw.Text('Church On App - Digital Ticket', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey400)),
              pw.Text('ID: ${_ticketId ?? event.id}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey400)),
            ],
          );
        },
      ),
    );
    return pdf.save();
  }

  Future<void> _downloadPdf() async {
    final bytes = await _buildPdf();
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/ticket_${(_ticketId ?? widget.event.id).replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}.pdf');
    await file.writeAsBytes(bytes);
    if (!mounted) return;
    PremiumToast.showSuccess(context, 'Ticket saved to Downloads', title: 'Downloaded');
  }

  Future<void> _sharePdf() async {
    final bytes = await _buildPdf();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/ticket_${(_ticketId ?? widget.event.id).replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}.pdf');
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: '🎫 ${widget.event.title} - Church On App Ticket'));
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final isFree = event.ticketPrice == 0;

    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text("My Ticket", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.share2),
            onPressed: _sharePdf,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Ticket Card
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(25),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, 8))],
              ),
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Theme.of(context).primaryColor, Colors.orangeAccent],
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Column(
                      children: [
                        // Top portion
                        Container(
                          padding: const EdgeInsets.all(25),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Icon(LucideIcons.ticket, color: Colors.white, size: 40),
                              const SizedBox(height: 15),
                              Text(event.title, style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white), textAlign: TextAlign.center),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(LucideIcons.calendar, color: Colors.white70, size: 16),
                                  const SizedBox(width: 6),
                                  Text(DateFormat.yMMMd().format(event.date), style: const TextStyle(color: Colors.white70, fontSize: 13)),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(LucideIcons.mapPin, color: Colors.white70, size: 16),
                                  const SizedBox(width: 6),
                                  Text(event.location, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  isFree ? "FREE" : "K${event.ticketPrice.toStringAsFixed(0)}",
                                  style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Dashed divider
                        Container(
                          height: 1,
                          margin: const EdgeInsets.symmetric(horizontal: 20),
                          child: LayoutBuilder(builder: (ctx, constraints) {
                            return Flex(
                              direction: Axis.horizontal,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: List.generate((constraints.constrainWidth() / 10).floor(), (_) => const SizedBox(width: 5, height: 1, child: DecoratedBox(decoration: BoxDecoration(color: Colors.white38)))),
                            );
                          }),
                        ),
                        // Bottom portion - QR Code and details
                        Container(
                          padding: const EdgeInsets.all(25),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(15),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Column(
                                  children: [
                                    if (_ticketId != null)
                                      QrImageView(
                                        data: _qrData,
                                        version: QrVersions.auto,
                                        size: 120,
                                        backgroundColor: Colors.white,
                                        eyeStyle: QrEyeStyle(
                                          eyeShape: QrEyeShape.square,
                                          color: Theme.of(context).primaryColor,
                                        ),
                                        dataModuleStyle: QrDataModuleStyle(
                                          dataModuleShape: QrDataModuleShape.square,
                                          color: Theme.of(context).primaryColor,
                                        ),
                                      )
                                    else
                                      Icon(LucideIcons.qrCode, size: 80, color: Theme.of(context).primaryColor),
                                    const SizedBox(height: 8),
                                    Text(
                                      _ticketId ?? event.id,
                                      style: TextStyle(fontSize: 9, color: Colors.grey.shade600, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text("Scan at Entry", style: const TextStyle(color: Colors.white54, fontSize: 11)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Left cutout
                  Positioned(left: -10, top: 180, child: Container(width: 20, height: 20, decoration: BoxDecoration(color: const Color(0xFFFFFAEB), shape: BoxShape.circle))),
                  Positioned(right: -10, top: 180, child: Container(width: 20, height: 20, decoration: BoxDecoration(color: const Color(0xFFFFFAEB), shape: BoxShape.circle))),
                ],
              ),
            ),
            const SizedBox(height: 25),

            // Payment Status
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isFree ? Colors.green.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(isFree ? LucideIcons.checkCircle : LucideIcons.clock, color: isFree ? Colors.green : Colors.orange, size: 24),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Payment Status", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        Text(isFree ? "FREE - No payment required" : "Paid - K${event.ticketPrice.toStringAsFixed(0)}", style: TextStyle(color: isFree ? Colors.green : Colors.orange, fontSize: 12)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isFree ? Colors.green.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(isFree ? "FREE" : "PAID", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: isFree ? Colors.green : Colors.orange)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 15),

            // Ticket Type
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.purple.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                    child: const Icon(LucideIcons.tag, color: Colors.purple, size: 24),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Ticket Type", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        Text("${_ticketType ?? 'General'} × $_ticketQuantity", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: Colors.purple.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                    child: Text((_ticketType ?? 'GENERAL').toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.purple)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 15),

            // RSVP Status
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("RSVP Status", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 15),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: ['Going', 'Maybe', 'Not Going'].map((status) {
                      final selected = (_existingRsvp ?? 'Going') == status;
                      Color color;
                      IconData icon;
                      switch (status) {
                        case 'Going': color = Colors.green; icon = LucideIcons.checkCircle; break;
                        case 'Maybe': color = Colors.orange; icon = LucideIcons.helpCircle; break;
                        default: color = Colors.red; icon = LucideIcons.xCircle; break;
                      }
                      return GestureDetector(
                        onTap: _isLoadingRsvp ? null : () => _updateRsvp(status),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: selected ? color.withValues(alpha: 0.1) : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: selected ? color : Colors.grey.shade200, width: selected ? 2 : 1),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(icon, size: 16, color: selected ? color : Colors.grey),
                              const SizedBox(width: 6),
                              Text(status, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: selected ? color : Colors.grey)),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  if (_isLoadingRsvp) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _sharePdf,
                    icon: const Icon(LucideIcons.share2, size: 18),
                    label: const Text("Share PDF", style: TextStyle(fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _downloadPdf,
                    icon: const Icon(LucideIcons.download, size: 18, color: Colors.white),
                    label: const Text("Download PDF", style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}
