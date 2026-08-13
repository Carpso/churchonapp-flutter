import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/services/coa_payment_service.dart';
import 'package:church_on_app/features/admin/data/admin_service.dart';

class WalletCommandCentreScreen extends ConsumerStatefulWidget {
  const WalletCommandCentreScreen({super.key});

  @override
  ConsumerState<WalletCommandCentreScreen> createState() => _WalletCommandCentreScreenState();
}

class _WalletCommandCentreScreenState extends ConsumerState<WalletCommandCentreScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab;
  String _statusFilter = '';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = ref.watch(coaPaymentStatsProvider);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Wallet Command Centre'),
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.amberAccent,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(icon: Icon(LucideIcons.arrowDownCircle), text: 'Collection'),
            Tab(icon: Icon(LucideIcons.arrowUpCircle), text: 'Disbursement'),
            Tab(icon: Icon(LucideIcons.activity), text: 'Log'),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildKpiRow(theme, stats),
          Expanded(
            child: TabBarView(controller: _tab, children: [
              _collectionTab(),
              _disbursementTab(),
              _activityLogTab(),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiRow(ThemeData theme, AsyncValue<Map<String, dynamic>> stats) {
    return stats.when(
      data: (s) {
        final pendingAmt = (s['pending_amount'] as num?)?.toDouble() ?? 0;
        final settledAmt = (s['settled_today_amount'] as num?)?.toDouble() ?? 0;
        final failedAmt = (s['failed_amount'] as num?)?.toDouble() ?? 0;
        final pendingCnt = (s['pending_count'] as num?)?.toInt() ?? 0;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: theme.colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              _kpi('Pending', '$pendingCnt\nK${_fmt(pendingAmt)}', Colors.orange),
              const SizedBox(width: 8),
              _kpi('Settled Today', 'K${_fmt(settledAmt)}', Colors.green),
              const SizedBox(width: 8),
              _kpi('Failed', 'K${_fmt(failedAmt)}', Colors.red),
              const SizedBox(width: 8),
              _networkKpi('MTN', s['mtn_settled'] ?? 0),
              _networkKpi('Airtel', s['airtel_settled'] ?? 0),
            ],
          ),
        );
      },
      loading: () => const SizedBox(height: 56, child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))),
      error: (e, _) => _kpi('Error', e.toString(), Colors.red),
    );
  }

  Widget _kpi(String label, String value, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w600)),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: color), maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
    ),
  );

  Widget _networkKpi(String label, dynamic amt) {
    final v = 'K${_fmt((amt as num?)?.toDouble() ?? 0)}';
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
        child: Column(children: [
          Text(label, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w600)),
          Text(v, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
        ]),
      ),
    );
  }

  Widget _collectionTab() {
    final payments = ref.watch(allCoaPaymentsStreamProvider(_statusFilter));
    return Column(
      children: [
        _filterBar(),
        Expanded(
          child: payments.when(
            data: (list) => list.isEmpty
                ? const Center(child: Text('No payments found'))
                : ListView.builder(itemCount: list.length, itemBuilder: (_, i) => _paymentRow(list[i])),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
          ),
        ),
      ],
    );
  }

  Widget _filterBar() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    child: Row(children: [
      const Text('Filter:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      const SizedBox(width: 8),
      Expanded(
        child: DropdownButtonFormField<String>(
          value: _statusFilter.isEmpty ? null : _statusFilter,
          items: const [
            DropdownMenuItem(value: '', child: Text('All')),
            DropdownMenuItem(value: 'pending', child: Text('Pending')),
            DropdownMenuItem(value: 'settled', child: Text('Settled')),
            DropdownMenuItem(value: 'failed', child: Text('Failed')),
            DropdownMenuItem(value: 'approved', child: Text('Approved')),
          ],
          onChanged: (v) => setState(() => _statusFilter = v ?? ''),
          decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4), border: OutlineInputBorder()),
        ),
      ),
    ]),
  );

  Widget _paymentRow(CoaPayment p) {
    final c = p.status == 'settled' ? Colors.green : p.status == 'pending' ? Colors.orange : p.status == 'failed' ? Colors.red : Colors.grey;
    return ListTile(
      dense: true,
      leading: CircleAvatar(radius: 16, backgroundColor: c.withValues(alpha: 0.2), child: Icon(LucideIcons.arrowDownCircle, size: 16, color: c)),
      title: Text('K${_fmt(p.amount)}  ${p.network ?? '—'}  ${p.phoneNumber ?? ''}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      subtitle: Text('${p.paymentRef} · ${_ago(p.createdAt)}', style: const TextStyle(fontSize: 10)),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
        child: Text(p.status.toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: c)),
      ),
      onTap: () => _showPaymentDetail(context, p),
    );
  }

  Widget _disbursementTab() => Consumer(
    builder: (context, ref, _) {
      return FutureBuilder<List<Map<String, dynamic>>>(
        future: ref.read(adminServiceProvider).getPayoutRequests(),
        builder: (ctx, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final list = snap.data!;
          if (list.isEmpty) return const Center(child: Text('No pending disbursements'));
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) {
              final r = list[i];
              final name = r['profiles']?['full_name'] ?? '—';
              final amt = (r['amount'] as num?)?.toDouble() ?? 0;
              final phone = r['mobile_number'] ?? '';
              final net = r['network'] ?? '';
              return ListTile(
                leading: const CircleAvatar(backgroundColor: Colors.amberAccent, child: Icon(LucideIcons.arrowUpCircle, color: Colors.black)),
                title: Text('K${_fmt(amt)} → $name', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Text('$net $phone', style: const TextStyle(fontSize: 10)),
                trailing: TextButton(
                  onPressed: () => _executeDisbursement(context, ref, r),
                  child: const Text('DISBURSE', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w700, fontSize: 11)),
                ),
              );
            },
          );
        },
      );
    },
  );

  Widget _activityLogTab() {
    final payments = ref.watch(allCoaPaymentsStreamProvider(''));
    return payments.when(
      data: (list) => ListView.builder(
        itemCount: list.length,
        itemBuilder: (_, i) {
          final p = list[i];
          return ListTile(
            dense: true,
            leading: Icon(p.status == 'settled' ? LucideIcons.checkCircle : LucideIcons.clock, size: 14, color: p.status == 'settled' ? Colors.green : Colors.grey),
            title: Text('K${_fmt(p.amount)} ${p.serviceType.isNotEmpty ? p.serviceType : 'payment'}', style: const TextStyle(fontSize: 11)),
            subtitle: Text('${p.network ?? ''}  ${_ago(p.createdAt)}', style: const TextStyle(fontSize: 9)),
            trailing: Text(p.paymentRef.substring(0, p.paymentRef.length > 8 ? 8 : p.paymentRef.length), style: const TextStyle(fontSize: 9)),
          );
        },
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('Stream error')),
    );
  }

  void _showPaymentDetail(BuildContext context, CoaPayment p) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Payment ${p.paymentRef}', style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kv('Amount', 'K${_fmt(p.amount)}'),
            _kv('Status', p.status),
            _kv('Service', p.serviceType.isNotEmpty ? p.serviceType : '—'),
            _kv('Network', p.network ?? '—'),
            _kv('Phone', p.phoneNumber ?? '—'),
            _kv('Created', p.createdAt.toString().substring(0, 19)),
            if (p.settledAt != null) _kv('Settled', p.settledAt.toString().substring(0, 19)),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CLOSE'))],
      ),
    );
  }

  void _executeDisbursement(BuildContext context, WidgetRef ref, Map<String, dynamic> r) async {
    final client = Supabase.instance.client;
    final id = r['id']?.toString() ?? '';
    final amount = (r['amount'] as num?)?.toDouble() ?? 0;
    await ref.read(adminServiceProvider).processPayout(id, 'processed');
    try {
      final result = await client.functions.invoke('lipila-payout', body: {
        'accountNumber': r['mobile_number'] ?? '',
        'amount': amount,
        'narration': 'Wallet command centre disbursement',
        'referenceId': id,
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.data is Map ? 'Disbursed: ${result.data}' : 'Disbursement triggered')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Disbursement error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Widget _kv(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(children: [Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)), Expanded(child: Text(value, style: const TextStyle(fontSize: 13)))]),
  );

  String _ago(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  String _fmt(double v) => v.toStringAsFixed(2);
}
