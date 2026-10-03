import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/member_transfer_service.dart';
import 'member_transfer_request_sheet.dart';

/// Transfer letters in and out, with a printable letter.
///
/// Built around the way this actually happens on the ground: a member is
/// leaving, the secretary raises the transfer, the pastor approves it, and the
/// member carries a letter to the new church. The letter number is quotable over
/// the phone, because that is how it is used.
class MemberTransferScreen extends StatefulWidget {
  final String tenantId;
  final String churchName;

  const MemberTransferScreen({
    super.key,
    required this.tenantId,
    required this.churchName,
  });

  @override
  State<MemberTransferScreen> createState() => _MemberTransferScreenState();
}

class _MemberTransferScreenState extends State<MemberTransferScreen> {
  late final MemberTransferService _service =
      MemberTransferService(Supabase.instance.client);

  List<MemberTransfer> _transfers = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _service.fetchForChurch(widget.tenantId);
      if (!mounted) return;
      setState(() {
        _transfers = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load transfers.';
        _loading = false;
      });
    }
  }

  Future<void> _decide(MemberTransfer t, bool approve) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(approve ? 'Approve transfer?' : 'Decline transfer?'),
        content: Text(
          approve
              ? '${t.memberName ?? 'This member'} will be moved to '
                  '${t.toChurchName ?? 'the new church'}. This cannot be undone from here.'
              : 'The member will stay with the church and the request will be closed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(approve ? 'Approve' : 'Decline'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _service.decide(transferId: t.id, approve: approve);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(approve ? 'Transfer approved' : 'Transfer declined'),
      ));
      await _load();
    } on TransferException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pending = _transfers.where((t) => t.isPending).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transfers',
            style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openRequestSheet,
        icon: const Icon(Icons.person_add_alt),
        label: const Text('New transfer'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    children: [
                      if (pending.isNotEmpty) ...[
                        Text('AWAITING YOUR DECISION',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                              color: theme.colorScheme.error,
                            )),
                        const SizedBox(height: 8),
                        ...pending.map((t) => _card(t, theme, actionable: true)),
                        const SizedBox(height: 20),
                      ],
                      Text('RECENT',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                            color: theme.disabledColor,
                          )),
                      const SizedBox(height: 8),
                      if (_transfers.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: Text(
                              'No transfers yet.\n\nWhen a member moves to another '
                              'church, raise a transfer here and print the letter.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        )
                      else
                        ..._transfers
                            .where((t) => !t.isPending)
                            .map((t) => _card(t, theme, actionable: false)),
                    ],
                  ),
                ),
    );
  }

  Widget _card(MemberTransfer t, ThemeData theme, {required bool actionable}) {
    final done = t.status == TransferStatus.completed;
    final declined = t.status == TransferStatus.declined ||
        t.status == TransferStatus.cancelled;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(t.direction.icon, size: 18, color: theme.primaryColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    t.memberLine,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (done
                            ? Colors.green
                            : declined
                                ? Colors.grey
                                : Colors.orange)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    t.status.label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: done
                          ? Colors.green.shade700
                          : declined
                              ? Colors.grey.shade700
                              : Colors.orange.shade800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              t.direction == TransferDirection.outbound
                  ? '${t.fromChurchName ?? 'This church'}  →  ${t.toChurchName ?? 'new church'}'
                  : '${t.fromChurchName ?? 'Previous church'}  →  ${t.toChurchName ?? 'this church'}',
              style: theme.textTheme.bodySmall,
            ),
            if (t.letterNo != null) ...[
              const SizedBox(height: 4),
              Text('Ref ${t.letterNo}',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ],
            if (t.reason != null && t.reason!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Reason: ${t.reason}', style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                if (actionable) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _decide(t, false),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Decline'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _decide(t, true),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Approve'),
                    ),
                  ),
                ] else if (done)
                  TextButton.icon(
                    onPressed: () => _printLetter(t),
                    icon: const Icon(Icons.print_outlined, size: 18),
                    label: const Text('Print letter'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The letter itself. Deliberately plain and printable - this gets signed,
  /// carried and filed, often in black and white.
  Future<void> _printLetter(MemberTransfer t) async {
    final doc = pw.Document();
    final date = DateTime.now();
    String fmt(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

    doc.addPage(
      pw.MultiPage(
        build: (_) => [
          pw.Text(widget.churchName,
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text('LETTER OF TRANSFER', style: const pw.TextStyle(fontSize: 12)),
          pw.SizedBox(height: 4),
          pw.Text('Reference: ${t.letterNo ?? '-'}',
              style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 16),
          pw.Text('To Whom It May Concern',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 12),
          pw.Text(
            'This is to certify that ${t.memberName ?? 'the bearer'}'
            '${t.membershipYears != null && t.membershipYears! > 0 ? ', who has been in our fellowship for about ${t.membershipYears} ${t.membershipYears == 1 ? 'year' : 'years'}' : ''}, '
            'is a member in good standing of ${widget.churchName}.',
          ),
          pw.SizedBox(height: 10),
          if (t.reason != null && t.reason!.isNotEmpty) ...[
            pw.Text('Reason for transfer: ${t.reason}'),
            pw.SizedBox(height: 10),
          ],
          pw.Text(
            'We commend this member to the care and fellowship of '
            '${t.toChurchName ?? 'the church receiving them'} and pray for their '
            'continued grace and growth in the faith.',
          ),
          pw.SizedBox(height: 24),
          pw.Text('____________________________'),
          pw.Text('For ${widget.churchName}', style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 16),
          pw.Text('Date: ${fmt(date)}'),
          if (t.memberPhone != null)
            pw.Text('Contact: ${t.memberPhone}',
                style: const pw.TextStyle(fontSize: 10)),
        ],
      ),
    );

    await Printing.sharePdf(
      bytes: await doc.save(),
      filename: 'transfer-${(t.letterNo ?? t.id).replaceAll('/', '-')}.pdf',
    );
  }

  Future<void> _openRequestSheet() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => MemberTransferRequestSheet(
        tenantId: widget.tenantId,
        churchName: widget.churchName,
        service: _service,
      ),
    );
    if (created == true) await _load();
  }
}