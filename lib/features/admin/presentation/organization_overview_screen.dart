import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import 'package:church_on_app/features/admin/data/organization_service.dart';

/// Read-only organisation view available to any member whose church belongs to
/// an organisation (branch pastors included). Shows the network's branches and
/// their real member counts via `get_organization_church_member_counts`.
///
/// The RPC is org-leadership gated; if the caller lacks rollup rights the screen
/// degrades to an explanatory state instead of showing fake numbers.
class OrganizationOverviewScreen extends ConsumerStatefulWidget {
  const OrganizationOverviewScreen({super.key});

  @override
  ConsumerState<OrganizationOverviewScreen> createState() => _OrganizationOverviewScreenState();
}

class _OrganizationOverviewScreenState extends ConsumerState<OrganizationOverviewScreen> {
  bool _isLoading = true;
  String? _error;
  bool _rollupDenied = false;
  String? _orgName;
  final List<Map<String, dynamic>> _branches = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final profile = ref.read(profileProvider).value;
    final orgSvc = ref.read(organizationServiceProvider);
    try {
      // Central resolution — `organizations.bishop_id = auth.uid()` first, then
      // the organisation the caller's church is linked to.
      final orgs = await orgSvc.resolveMyOrganisations(tenantId: profile?.tenantId);
      if (orgs.isEmpty) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _rollupDenied = false;
          _error = 'Your account is not linked to an organisation.';
        });
        return;
      }
      final orgId = orgs.first['id']?.toString();
      _orgName = orgs.first['name']?.toString();
      if (orgId == null || orgId.isEmpty) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _error = 'Your account is not linked to an organisation.';
        });
        return;
      }

      final counts = await orgSvc.getOrganizationChurchMemberCounts(orgId);
      if (!mounted) return;
      setState(() {
        _branches
          ..clear()
          ..addAll(counts);
        _isLoading = false;
        // An org with zero branches is NOT a permissions problem — only an
        // exception means the rollup was denied.
        _rollupDenied = false;
        _error = null;
      });
    } catch (e) {
      debugPrint('organization overview load failed: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _rollupDenied = true;
      });
    }
  }

  int get _totalMembers =>
      _branches.fold<int>(0, (s, e) => s + ((e['member_count'] as num?)?.toInt() ?? 0));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Organisation', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: theme.scaffoldBackgroundColor,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        actions: [IconButton(icon: const Icon(LucideIcons.refreshCw), onPressed: _isLoading ? null : _load)],
      ),
      body: _isLoading
          ? _buildShimmer()
          : (_error != null && _error!.contains('not linked'))
              ? _messageState(theme)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _buildHeader(theme),
                      const SizedBox(height: 20),
                      if (_rollupDenied)
                        _deniedCard(theme)
                      else ...[
                        Row(children: [
                          _summaryCard(theme, '${_branches.length}', 'Branches', LucideIcons.building),
                          const SizedBox(width: 14),
                          _summaryCard(theme, '$_totalMembers', 'Members', LucideIcons.users),
                        ]),
                        const SizedBox(height: 24),
                        Text('Branches', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                        const SizedBox(height: 12),
                        ..._branches.map((b) => _branchRow(theme, b)),
                      ],
                      const SizedBox(height: 40),
                    ]),
                  ),
                ),
    );
  }

  Widget _buildShimmer() => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          ShimmerLoader.rectangular(height: 130, width: double.infinity),
          const SizedBox(height: 20),
          Row(children: [Expanded(child: ShimmerLoader.rectangular(height: 90)), const SizedBox(width: 12), Expanded(child: ShimmerLoader.rectangular(height: 90))]),
          const SizedBox(height: 20),
          ...List.generate(3, (_) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ShimmerLoader.rectangular(height: 64),
              )),
        ]),
      );

  Widget _messageState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(LucideIcons.globe, size: 42, color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
          const SizedBox(height: 14),
          Text(_error ?? 'No organisation linked.',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
        ]),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [theme.primaryColor, const Color(0xFF1A1A1A)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(18)),
          child: const Icon(LucideIcons.globe, color: Colors.white, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_orgName?.isNotEmpty == true ? _orgName! : 'Organisation',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 19),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text('Network of churches you belong to',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12)),
          ]),
        ),
      ]),
    );
  }

  Widget _deniedCard(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(LucideIcons.lock, color: Colors.amber, size: 18),
          const SizedBox(width: 10),
          const Expanded(child: Text('Network rollups restricted', style: TextStyle(fontWeight: FontWeight.bold))),
        ]),
        const SizedBox(height: 8),
        Text(
          'Branch rollups are available to organisation leadership. Ask your bishop for network access to see per-branch totals.',
          style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 12, height: 1.4),
        ),
      ]),
    );
  }

  Widget _summaryCard(ThemeData theme, String value, String label, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: theme.primaryColor, size: 20),
          const SizedBox(height: 10),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          Text(label, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 11, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }

  Widget _branchRow(ThemeData theme, Map<String, dynamic> branch) {
    final name = branch['church_name']?.toString() ?? 'Branch';
    final members = (branch['member_count'] as num?)?.toInt() ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8)],
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: theme.primaryColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
          child: Icon(LucideIcons.church, color: theme.primaryColor, size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: theme.primaryColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
          child: Text('$members members', style: TextStyle(color: theme.primaryColor, fontSize: 11, fontWeight: FontWeight.bold)),
        ),
      ]),
    );
  }
}
