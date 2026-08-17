import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';


class UnifiedFinancialAuditScreen extends ConsumerStatefulWidget {
  const UnifiedFinancialAuditScreen({super.key});

  @override
  ConsumerState<UnifiedFinancialAuditScreen> createState() => _UnifiedFinancialAuditScreenState();
}

class _UnifiedFinancialAuditScreenState extends ConsumerState<UnifiedFinancialAuditScreen> {
  bool _isLoading = true;
  String? _error;
  int _totalTransactions = 0;
  int _totalWalletTx = 0;
  double _totalVolume = 0;
  double _platformFees = 0;
  double _fundraisingRaised = 0;
  List<Map<String, dynamic>> _recentTransactions = [];
  List<Map<String, dynamic>> _fundraisingGoals = [];
  String _activeTab = 'transactions';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final txsRes = await Supabase.instance.client
          .from('transactions')
          .select('id, amount, platform_fee, category, created_at, user_id, tenant_id')
          .order('created_at', ascending: false)
          .limit(50);

      final fundraisingRes = await Supabase.instance.client
          .from('fundraising_campaigns')
          .select('id, title, target_amount, raised_amount, status')
          .order('created_at', ascending: false)
          .limit(50);

      final walletRes = await Supabase.instance.client
          .from('wallet_transactions')
          .select('id, amount, type, created_at')
          .limit(100);

      double totalVol = 0, fees = 0;
      for (final t in txsRes) {
        totalVol += (t['amount'] as num?)?.toDouble() ?? 0;
        fees += (t['platform_fee'] as num?)?.toDouble() ?? 0;
      }
      double fundRaised = 0;
      for (final f in fundraisingRes) {
        fundRaised += (f['raised_amount'] as num?)?.toDouble() ?? 0;
      }

      if (mounted) {
        setState(() {
          _totalTransactions = (txsRes as List).length;
          _totalWalletTx = (walletRes as List).length;
          _totalVolume = totalVol;
          _platformFees = fees;
          _fundraisingRaised = fundRaised;
          _recentTransactions = List<Map<String, dynamic>>.from(txsRes);
          _fundraisingGoals = List<Map<String, dynamic>>.from(fundraisingRes);
          _isLoading = false; _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Financial Audit Engine", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [IconButton(icon: const Icon(LucideIcons.refreshCw), onPressed: _isLoading ? null : _loadData)],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text("Error: $_error"))
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildUnifiedSummary(theme),
                        const SizedBox(height: 25),
                        _buildTabBar(theme),
                        const SizedBox(height: 20),
                        if (_activeTab == 'transactions') ..._buildTransactionList(theme),
                        if (_activeTab == 'fundraising') ..._buildFundraisingList(theme),
                        if (_activeTab == 'wallet') ..._buildWalletSection(theme),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildUnifiedSummary(ThemeData theme) {
    final currency = NumberFormat.currency(symbol: 'K ', decimalDigits: 0);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [theme.primaryColor, theme.primaryColor.withValues(alpha: 0.7)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: theme.primaryColor.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Unified Ledger", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _summaryItem("Total Volume", currency.format(_totalVolume)),
            _summaryItem("Platform Fees", currency.format(_platformFees)),
          ]),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _summaryItem("Transactions", _formatNum(_totalTransactions)),
            _summaryItem("Fundraising", currency.format(_fundraisingRaised)),
            _summaryItem("Wallet TX", _formatNum(_totalWalletTx)),
          ]),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String value) {
    return Column(children: [
      Text(value, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 18)),
      Text(label, style: TextStyle(color: Colors.black.withValues(alpha: 0.55), fontSize: 11)),
    ]);
  }

  Widget _buildTabBar(ThemeData theme) {
    return Row(children: [
      _tab("Transactions", 'transactions'),
      const SizedBox(width: 8),
      _tab("Fundraising", 'fundraising'),
      const SizedBox(width: 8),
      _tab("Wallet", 'wallet'),
    ]);
  }

  Widget _tab(String label, String value) {
    final selected = _activeTab == value;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Theme.of(context).primaryColor : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? Theme.of(context).primaryColor : Colors.grey.shade300),
        ),
        child: Text(label, style: TextStyle(color: selected ? Colors.black : Colors.grey.shade700, fontWeight: FontWeight.w600, fontSize: 12)),
      ),
    );
  }

  List<Widget> _buildTransactionList(ThemeData theme) {
    if (_recentTransactions.isEmpty) return [Center(child: Padding(padding: const EdgeInsets.all(40), child: Text("No transactions", style: TextStyle(color: Colors.grey.shade500))))];
    return _recentTransactions.map((tx) {
      final amount = (tx['amount'] as num?)?.toDouble() ?? 0;
      final type = tx['category'] as String? ?? 'general';
      final date = tx['created_at']?.toString() ?? '';
      final formattedDate = date.isNotEmpty ? DateFormat('MMM d, HH:mm').format(DateTime.tryParse(date) ?? DateTime.now()) : '';
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: _txColor(type).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(_txIcon(type), size: 16, color: _txColor(type)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(type, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              Text(formattedDate, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
            ],
          )),
          Text("K ${NumberFormat.decimalPattern().format(amount)}", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF7A5C00))),
        ]),
      );
    }).toList();
  }

  List<Widget> _buildFundraisingList(ThemeData theme) {
    if (_fundraisingGoals.isEmpty) return [Center(child: Padding(padding: const EdgeInsets.all(40), child: Text("No campaigns", style: TextStyle(color: Colors.grey.shade500))))];
    return _fundraisingGoals.map((f) {
      final title = f['title'] as String? ?? 'Untitled';
      final target = (f['target_amount'] as num?)?.toDouble() ?? 0;
      final raised = (f['raised_amount'] as num?)?.toDouble() ?? 0;
                  final progress = target > 0 ? (raised / target).clamp(0.0, 1.0).toDouble() : 0.0;
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
              Text("${(progress * 100).toStringAsFixed(0)}%", style: TextStyle(color: const Color(0xFF7A5C00), fontWeight: FontWeight.bold, fontSize: 12)),
            ]),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: progress, backgroundColor: Colors.grey.shade200, valueColor: AlwaysStoppedAnimation(Theme.of(context).primaryColor), minHeight: 8),
            ),
            const SizedBox(height: 6),
            Text("K ${NumberFormat.decimalPattern().format(raised)} of K ${NumberFormat.decimalPattern().format(target)}", style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
          ],
        ),
      );
    }).toList();
  }

  List<Widget> _buildWalletSection(ThemeData theme) {
    return [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          Column(children: [Text(_formatNum(_totalWalletTx), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22)), Text("Wallet TX", style: TextStyle(color: Colors.grey.shade500, fontSize: 11))]),
          Column(children: [Icon(LucideIcons.arrowUpDown, color: Theme.of(context).primaryColor.withValues(alpha: 0.7)), const Text("")]),
        ]),
      ),
    ];
  }

  Color _txColor(String type) {
    switch (type) {
      case 'tithe': return Theme.of(context).primaryColor;
      case 'giving': return Colors.green;
      case 'offering': return Colors.amber;
      case 'payout': return Colors.red;
      default: return Theme.of(context).primaryColor;
    }
  }

  IconData _txIcon(String type) {
    switch (type) {
      case 'tithe': return LucideIcons.church;
      case 'giving': return LucideIcons.heart;
      case 'offering': return LucideIcons.gift;
      case 'payout': return LucideIcons.send;
      default: return LucideIcons.creditCard;
    }
  }

  String _formatNum(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return n.toString();
  }
}
