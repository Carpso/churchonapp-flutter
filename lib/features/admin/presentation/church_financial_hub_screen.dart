import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';

class ChurchFinancialHubScreen extends ConsumerStatefulWidget {
  const ChurchFinancialHubScreen({super.key});

  @override
  ConsumerState<ChurchFinancialHubScreen> createState() => _ChurchFinancialHubScreenState();
}

class _ChurchFinancialHubScreenState extends ConsumerState<ChurchFinancialHubScreen> {
  bool _isLoading = true;
  double _totalGiving = 0;
  double _totalTithes = 0;
  double _fundraisingTotal = 0;
  double _groupContributionTotal = 0;
  List<Map<String, dynamic>> _fundraisers = [];
  List<Map<String, dynamic>> _groupContribs = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final tenantId = ref.read(profileProvider).value?.tenantId;
    if (tenantId == null) { setState(() => _isLoading = false); return; }

    try {
      final txsRes = await Supabase.instance.client
          .from('transactions')
          .select('amount, type')
          .eq('tenant_id', tenantId)
          .inFilter('type', ['giving', 'tithe', 'offering'])
          .gte('created_at', DateTime.now().subtract(const Duration(days: 30)).toIso8601String());

      final fundRes = await Supabase.instance.client
          .from('fundraising_campaigns')
          .select('id, title, target_amount, raised_amount, status')
          .eq('tenant_id', tenantId)
          .eq('status', 'active');

      final groupRes = await Supabase.instance.client
          .from('group_contributions')
          .select('id, title, target_amount, collected_amount, status')
          .eq('tenant_id', tenantId);

      double giving = 0, tithes = 0;
      for (final t in txsRes) {
        final type = t['type'] as String? ?? '';
        final amount = (t['amount'] as num?)?.toDouble() ?? 0;
        if (type == 'tithe') {
          tithes += amount;
        } else {
          giving += amount;
        }
      }

      double fundTotal = 0;
      for (final f in fundRes) {
        fundTotal += (f['raised_amount'] as num?)?.toDouble() ?? 0;
      }
      double groupTotal = 0;
      for (final g in groupRes) {
        groupTotal += (g['collected_amount'] as num?)?.toDouble() ?? 0;
      }

      if (mounted) {
        setState(() {
          _totalGiving = giving;
          _totalTithes = tithes;
          _fundraisingTotal = fundTotal;
          _groupContributionTotal = groupTotal;
          _fundraisers = List<Map<String, dynamic>>.from(fundRes);
          _groupContribs = List<Map<String, dynamic>>.from(groupRes);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Church Financial Hub", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [IconButton(icon: const Icon(LucideIcons.refreshCw), onPressed: _isLoading ? null : _loadData)],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSummaryCards(theme),
                    const SizedBox(height: 30),
                    const Text("Fundraising Campaigns", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 12),
                    ..._buildFundraiserList(theme),
                    const SizedBox(height: 30),
                    const Text("Group Contributions", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 12),
                    ..._buildGroupContribList(theme),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSummaryCards(ThemeData theme) {
    final currency = NumberFormat.currency(symbol: 'K ', decimalDigits: 0);
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.3,
      children: [
        _summaryCard("Tithes (30d)", currency.format(_totalTithes), LucideIcons.church, Colors.purple),
        _summaryCard("Giving (30d)", currency.format(_totalGiving), LucideIcons.heart, Colors.green),
        _summaryCard("Fundraising", currency.format(_fundraisingTotal), LucideIcons.trendingUp, Colors.amber),
        _summaryCard("Group Contribs", currency.format(_groupContributionTotal), LucideIcons.users, Colors.teal),
      ],
    );
  }

  Widget _summaryCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: color, size: 20),
        const Spacer(),
        Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.black87)),
        Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 10)),
      ]),
    );
  }

  List<Widget> _buildFundraiserList(ThemeData theme) {
    if (_fundraisers.isEmpty) return [Container(padding: const EdgeInsets.all(20), child: Center(child: Text("No active fundraisers", style: TextStyle(color: Colors.grey.shade500))))];
    return _fundraisers.map((f) {
      final title = f['title'] ?? 'Untitled';
      final target = (f['target_amount'] as num?)?.toDouble() ?? 0;
      final raised = (f['raised_amount'] as num?)?.toDouble() ?? 0;
      final progress = target > 0 ? (raised / target).clamp(0.0, 1.0).toDouble() : 0.0;
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 8),
          ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: progress, backgroundColor: Colors.grey.shade200, valueColor: AlwaysStoppedAnimation(Colors.amber.shade400), minHeight: 8)),
          const SizedBox(height: 6),
          Text("K ${NumberFormat.decimalPattern().format(raised)} of K ${NumberFormat.decimalPattern().format(target)} (${(progress * 100).toStringAsFixed(0)}%)", style: TextStyle(color: Colors.grey.shade500, fontSize: 10)),
        ]),
      );
    }).toList();
  }

  List<Widget> _buildGroupContribList(ThemeData theme) {
    if (_groupContribs.isEmpty) return [Container(padding: const EdgeInsets.all(20), child: Center(child: Text("No group contributions", style: TextStyle(color: Colors.grey.shade500))))];
    return _groupContribs.map((g) {
      final title = g['title'] ?? 'Untitled';
      final target = (g['target_amount'] as num?)?.toDouble() ?? 0;
      final collected = (g['collected_amount'] as num?)?.toDouble() ?? 0;
      final progress = target > 0 ? (collected / target).clamp(0.0, 1.0).toDouble() : 0.0;
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 8),
          ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: progress, backgroundColor: Colors.grey.shade200, valueColor: AlwaysStoppedAnimation(Colors.teal.shade400), minHeight: 8)),
          const SizedBox(height: 6),
          Text("K ${NumberFormat.decimalPattern().format(collected)} of K ${NumberFormat.decimalPattern().format(target)}", style: TextStyle(color: Colors.grey.shade500, fontSize: 10)),
        ]),
      );
    }).toList();
  }
}
