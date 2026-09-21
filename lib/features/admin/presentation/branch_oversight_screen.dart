import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:church_on_app/core/widgets/app_image.dart';
import 'package:church_on_app/core/widgets/app_error_view.dart';

/// Read-only, single-branch oversight view for a bishop/apostle.
///
/// Surfaces a branch's real month-to-date service metrics via the
/// server-authorised `get_church_service_summary` RPC (bishop-allowed for any
/// branch in the organisation) and links out to the branch map and the
/// network pastor reports. It never exposes pastor-level write tools.
class BranchOversightScreen extends ConsumerStatefulWidget {
  const BranchOversightScreen({
    super.key,
    required this.tenantId,
    required this.name,
    this.isVerified = false,
    this.logoUrl,
  });

  final String tenantId;
  final String name;
  final bool isVerified;
  final String? logoUrl;

  @override
  ConsumerState<BranchOversightScreen> createState() => _BranchOversightScreenState();
}

class _BranchOversightScreenState extends ConsumerState<BranchOversightScreen> {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic> _summary = const {};
  Map<String, dynamic> _monthly = const {};
  double _basketTotal = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final client = Supabase.instance.client;
    try {
      Map<String, dynamic> summary = const {};
      try {
        final res = await client
            .rpc('get_church_service_summary', params: {'p_tenant_id': widget.tenantId});
        summary = (res as Map<String, dynamic>?) ?? const {};
      } catch (e) {
        debugPrint('branch service summary failed: $e');
      }

      Map<String, dynamic> monthly = const {};
      try {
        final res = await client
            .rpc('get_church_monthly_stats', params: {'p_tenant_id': widget.tenantId});
        monthly = (res as Map<String, dynamic>?) ?? const {};
      } catch (e) {
        debugPrint('branch monthly stats failed: $e');
      }

      double basketTotal = 0;
      try {
        final res = await client.rpc('get_basket_summary', params: {
          'p_tenant_id': widget.tenantId,
          'p_days': 30,
        });
        for (final b in (res as List? ?? [])) {
          basketTotal += ((b as Map)['total_amount'] as num?)?.toDouble() ?? 0;
        }
      } catch (e) {
        debugPrint('branch basket summary failed: $e');
      }

      if (!mounted) return;
      setState(() {
        _summary = summary;
        _monthly = monthly;
        _basketTotal = basketTotal;
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      debugPrint('branch oversight load failed: $e');
      if (mounted) setState(() { _isLoading = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(widget.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: theme.scaffoldBackgroundColor,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(LucideIcons.refreshCw), onPressed: _isLoading ? null : _load),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? AppErrorView(error: _error, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _buildHeader(theme),
                      const SizedBox(height: 20),
                      Text('Month to Date', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                      const SizedBox(height: 12),
                      _buildMetrics(theme),
                      const SizedBox(height: 24),
                      Text('Oversight Actions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                      const SizedBox(height: 12),
                      _action(theme, LucideIcons.map, 'View Branch on Map', 'Locate this branch geographically', Colors.indigo,
                          () => context.push('/branch-locator')),
                      _action(theme, LucideIcons.fileText, 'Pastor Reports', 'Weekly service reports from this branch', theme.primaryColor,
                          () => context.push('/pastor-bishop-report')),
                      _action(theme, LucideIcons.barChart3, 'Central Treasury', 'Network-wide financial oversight', Colors.green,
                          () => context.push('/finance-dashboard')),
                      const SizedBox(height: 40),
                    ]),
                  ),
                ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final logo = widget.logoUrl;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [theme.primaryColor, theme.primaryColor.withValues(alpha: 0.72)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Row(children: [
        ClipOval(
          child: logo != null && logo.isNotEmpty
              ? AppImage(logo, width: 56, height: 56, fit: BoxFit.cover)
              : Container(
                  width: 56,
                  height: 56,
                  color: Colors.white.withValues(alpha: 0.2),
                  child: const Icon(LucideIcons.church, color: Colors.white, size: 26),
                ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.name,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (widget.isVerified ? Colors.green : Colors.orange).withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(widget.isVerified ? 'VERIFIED BRANCH' : 'UNVERIFIED BRANCH',
                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900)),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildMetrics(ThemeData theme) {
    final currency = NumberFormat.compactCurrency(symbol: 'K');
    final hasData = _summary.values.any((v) => (v as num?) != null && (v as num) > 0) ||
        (_monthly['tithes_mtd'] as num?)?.toDouble() != null ||
        _basketTotal > 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (!hasData)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.25)),
          ),
          child: Row(children: [
            const Icon(LucideIcons.info, color: Colors.amber, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'No service reports, giving or basket collections recorded for this branch this month yet.',
                style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.65), fontSize: 12, height: 1.4),
              ),
            ),
          ]),
        ),
      GridView.count(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 1.3,
        children: [
          _metric(theme, 'Service Reports', '${(_summary['service_count'] as num?)?.toInt() ?? 0}', LucideIcons.fileText, theme.primaryColor),
          _metric(theme, 'Attendance', '${(_summary['attendance'] as num?)?.toInt() ?? 0}', LucideIcons.calendarCheck, Colors.green),
          _metric(theme, 'Giving (MTD)', currency.format((_monthly['tithes_mtd'] as num?)?.toDouble() ?? 0), LucideIcons.church, Colors.orange),
          _metric(theme, 'Baskets (30d)', currency.format(_basketTotal), LucideIcons.piggyBank, Colors.teal),
          _metric(theme, 'Visitors', '${(_summary['visitors'] as num?)?.toInt() ?? 0}', LucideIcons.userPlus, Colors.indigo),
          _metric(theme, 'Salvations', '${(_summary['salvations'] as num?)?.toInt() ?? 0}', LucideIcons.heartPulse, Colors.red),
        ],
      ),
    ]);
  }

  Widget _metric(ThemeData theme, String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 20),
        const Spacer(),
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        Text(label, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 11, fontWeight: FontWeight.bold)),
      ]),
    );
  }

  Widget _action(ThemeData theme, IconData icon, String title, String subtitle, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                Text(subtitle, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 11)),
              ]),
            ),
            Icon(LucideIcons.chevronRight, size: 18, color: theme.colorScheme.onSurface.withValues(alpha: 0.2)),
          ]),
        ),
      );
}
