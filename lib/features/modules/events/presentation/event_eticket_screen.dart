import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:church_on_app/core/widgets/premium_toast.dart';
import 'package:church_on_app/features/events/data/event_ticketing_service.dart';

/// Real e-ticket viewer — QR code, status, receipt, transfer and (for the
/// event host) per-ticket refund. Backed entirely by `event_tickets` /
/// `event_ticket_orders` written by the ticketing RPCs.
class EventEticketScreen extends ConsumerStatefulWidget {
  final String? ticketId;
  final String? orderId;
  final String eventTitle;

  const EventEticketScreen({
    super.key,
    this.ticketId,
    this.orderId,
    this.eventTitle = 'Event',
  });

  @override
  ConsumerState<EventEticketScreen> createState() => _EventEticketScreenState();
}

class _EventEticketScreenState extends ConsumerState<EventEticketScreen> {
  List<EventTicket> _tickets = [];
  bool _loading = true;
  String? _error;
  bool _isHost = false;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final svc = ref.read(eventTicketingServiceProvider);
      List<EventTicket> tickets;
      if (widget.ticketId != null && widget.ticketId!.isNotEmpty) {
        final t = await svc.fetchTicket(widget.ticketId!);
        tickets = t == null ? [] : [t];
      } else if (widget.orderId != null) {
        tickets = await svc.fetchOrderTickets(widget.orderId!);
      } else {
        tickets = [];
      }
      var host = false;
      if (tickets.isNotEmpty) host = await svc.isEventHost(tickets.first.eventId);
      if (!mounted) return;
      setState(() {
        _tickets = tickets;
        _isHost = host;
        _loading = false;
        _error = tickets.isEmpty ? 'Ticket not found.' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'valid':
        return Colors.green;
      case 'used':
        return Colors.blue;
      case 'pending':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Ticket', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.ticket, size: 64, color: Colors.grey),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: _tickets
                      .map((t) => _buildTicketCard(context, t))
                      .toList(growable: false),
                ),
    );
  }

  Widget _buildTicketCard(BuildContext context, EventTicket t) {
    final theme = Theme.of(context);
    final statusColor = _statusColor(t.status);
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [theme.primaryColor, Colors.orangeAccent],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(LucideIcons.ticket, color: Colors.white, size: 26),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t.eventTitle ?? widget.eventTitle,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(20)),
                  child: Text(t.status.toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                [
                  if (t.eventDate != null) DateFormat.yMMMd().add_jm().format(t.eventDate!),
                  if (t.eventLocation != null && t.eventLocation!.isNotEmpty) t.eventLocation!,
                ].join('  •  '),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
              child: Column(
                children: [
                  QrImageView(
                    data: t.qrPayload,
                    version: QrVersions.auto,
                    size: 170,
                    backgroundColor: Colors.white,
                    eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: theme.primaryColor),
                    dataModuleStyle: QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: theme.primaryColor),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    t.ticketCode,
                    style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2, color: Colors.grey.shade800),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _ticketMeta('TIER', t.tierName ?? 'General'),
                _ticketMeta('PRICE', (t.unitPrice ?? 0) == 0 ? 'FREE' : 'K${(t.unitPrice ?? 0).toStringAsFixed(2)}'),
                _ticketMeta('ORDER', t.orderRef ?? '—'),
              ],
            ),
            if (t.checkedInAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('Checked in ${DateFormat.yMMMd().add_jm().format(t.checkedInAt!)}',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _actionChip(LucideIcons.share2, 'Share', () => _shareTicket(t)),
                _actionChip(LucideIcons.copy, 'Copy code', () => _copyCode(t)),
                _actionChip(LucideIcons.receipt, 'Receipt', () => _showReceipt(t)),
                if (t.isValid) _actionChip(LucideIcons.send, 'Transfer', () => _transfer(t)),
                if (_isHost && (t.isValid || t.status == 'pending'))
                  _actionChip(LucideIcons.undo2, 'Refund', () => _refund(t)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _ticketMeta(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
          const SizedBox(height: 2),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _actionChip(IconData icon, String label, VoidCallback onTap) {
    final busy = _busy.contains(label);
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            else
              Icon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Future<void> _shareTicket(EventTicket t) async {
    try {
      await SharePlus.instance.share(ShareParams(
        text: '🎫 ${t.eventTitle ?? widget.eventTitle}\n'
            'Ticket ${t.ticketCode}\n'
            '${t.eventDate != null ? DateFormat.yMMMd().add_jm().format(t.eventDate!) : ''}\n'
            'https://churchonapp.com/ticket/${t.id}',
      ));
    } catch (e) {
      if (mounted) PremiumToast.showError(context, e.toString(), title: 'Share');
    }
  }

  Future<void> _copyCode(EventTicket t) async {
    await Clipboard.setData(ClipboardData(text: t.ticketCode));
    if (mounted) PremiumToast.showSuccess(context, 'Ticket code copied.', title: 'Copied');
  }

  void _showReceipt(EventTicket t) {
    final unit = t.unitPrice ?? 0;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(LucideIcons.receipt, size: 20),
              SizedBox(width: 8),
              Text('Receipt', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            ]),
            const SizedBox(height: 16),
            _receiptRow('Event', t.eventTitle ?? widget.eventTitle),
            _receiptRow('Order', t.orderRef ?? '—'),
            _receiptRow('Ticket', t.ticketCode),
            _receiptRow('Tier', t.tierName ?? 'General'),
            _receiptRow('Unit price', unit == 0 ? 'FREE' : 'K${unit.toStringAsFixed(2)}'),
            _receiptRow('Status', t.status.toUpperCase()),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(
                        text: 'Church On App receipt\nOrder: ${t.orderRef}\nTicket: ${t.ticketCode}\n'
                            'Amount: ${unit == 0 ? 'FREE' : 'K${unit.toStringAsFixed(2)}'}',
                      ));
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) PremiumToast.showSuccess(context, 'Receipt copied.', title: 'Copied');
                    },
                    icon: const Icon(LucideIcons.copy, size: 16),
                    label: const Text('Copy'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _shareReceipt(t, unit);
                    },
                    icon: const Icon(LucideIcons.share2, size: 16),
                    label: const Text('Share'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareReceipt(EventTicket t, double unit) async {
    try {
      await SharePlus.instance.share(ShareParams(
        text: 'Church On App receipt\n${t.eventTitle ?? widget.eventTitle}\n'
            'Order ${t.orderRef}\nTicket ${t.ticketCode}\n'
            'Amount ${unit == 0 ? 'FREE' : 'K${unit.toStringAsFixed(2)}'}',
      ));
    } catch (e) {
      if (mounted) PremiumToast.showError(context, e.toString(), title: 'Share');
    }
  }

  Widget _receiptRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: Colors.grey))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Future<void> _transfer(EventTicket t) async {
    final recipientId = await _pickRecipient();
    if (recipientId == null) return;
    setState(() => _busy.add('Transfer'));
    try {
      await ref.read(eventTicketingServiceProvider).transfer(ticketId: t.id, toUserId: recipientId);
      if (!mounted) return;
      PremiumToast.showSuccess(context, 'Ticket transferred successfully.', title: 'Transferred');
      await _load();
    } catch (e) {
      if (mounted) PremiumToast.showError(context, e.toString(), title: 'Transfer Failed');
    } finally {
      if (mounted) setState(() => _busy.remove('Transfer'));
    }
  }

  Future<String?> _pickRecipient() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return null;
    final controller = TextEditingController();
    List<Map<String, dynamic>> results = [];
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
          Future<void> search(String q) async {
            final res = await Supabase.instance.client
                .from('profiles')
                .select('id, full_name, email')
                .neq('id', user.id)
                .or('full_name.ilike.%$q%,email.ilike.%$q%')
                .limit(25);
            setSheet(() => results = List<Map<String, dynamic>>.from(res));
          }

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.6,
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Transfer ticket to', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: controller,
                      decoration: const InputDecoration(
                        hintText: 'Search by name or email',
                        prefixIcon: Icon(LucideIcons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        if (v.trim().length >= 2) search(v.trim());
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: results.length,
                      itemBuilder: (_, i) {
                        final p = results[i];
                        return ListTile(
                          leading: const CircleAvatar(child: Icon(LucideIcons.user)),
                          title: Text(p['full_name'] ?? 'Member'),
                          subtitle: Text(p['email'] ?? ''),
                          onTap: () => Navigator.pop(ctx, p['id'].toString()),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  Future<void> _refund(EventTicket t) async {
    final reason = await _askReason();
    if (reason == null) return;
    setState(() => _busy.add('Refund'));
    try {
      await ref.read(eventTicketingServiceProvider).refund(ticketId: t.id, reason: reason);
      if (!mounted) return;
      PremiumToast.showSuccess(context, 'Ticket refunded (${(t.unitPrice ?? 0) == 0 ? 'free' : 'K${(t.unitPrice ?? 0).toStringAsFixed(2)}'}).', title: 'Refunded');
      await _load();
    } catch (e) {
      if (mounted) PremiumToast.showError(context, e.toString(), title: 'Refund Failed');
    } finally {
      if (mounted) setState(() => _busy.remove('Refund'));
    }
  }

  Future<String?> _askReason() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Refund ticket?'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Reason (optional)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim().isEmpty ? 'Host refund' : controller.text.trim()),
            child: const Text('Refund', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
