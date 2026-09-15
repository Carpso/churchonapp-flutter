import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:church_on_app/core/config/app_constants.dart';
import 'package:church_on_app/core/widgets/premium_toast.dart';
import 'package:church_on_app/features/admin/data/organization_service.dart';

/// Organisation & Branch manager (superadmin / COA).
///
/// A BRANCH is just a `churches` row linked to an `organizations` row via
/// `churches.organization_id`. The bishop owns the organisation and manages all
/// its branches; a pastor manages only their own branch. This screen is where
/// COA/superadmin actually CREATE the link (previously nothing wrote
/// `organization_id`, so the branch model was unusable).
class OrganizationBranchesScreen extends ConsumerStatefulWidget {
  const OrganizationBranchesScreen({super.key});

  @override
  ConsumerState<OrganizationBranchesScreen> createState() =>
      _OrganizationBranchesScreenState();
}

class _OrganizationBranchesScreenState
    extends ConsumerState<OrganizationBranchesScreen> {
  SupabaseClient get _client => Supabase.instance.client;

  List<Map<String, dynamic>> _orgs = [];
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _unassigned = [];
  String? _selectedOrgId;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final orgs = await _client
          .from('organizations')
          .select('id, name, code, logo_url, bishop_id')
          .order('name');
      _orgs = List<Map<String, dynamic>>.from(orgs as List);

      if (_orgs.isNotEmpty && _selectedOrgId == null) {
        _selectedOrgId = _orgs.first['id']?.toString();
      }

      if (_selectedOrgId != null) {
        final branches = await _client
            .from('churches')
            .select('id, name, address, logo_url, is_verified, organization_id')
            .eq('organization_id', _selectedOrgId!)
            .order('name');
        _branches = List<Map<String, dynamic>>.from(branches as List);
      } else {
        _branches = [];
      }

      final unassigned = await _client
          .from('churches')
          .select('id, name, address')
          .isFilter('organization_id', null)
          .order('name')
          .limit(200);
      _unassigned = List<Map<String, dynamic>>.from(unassigned as List);
    } catch (e) {
      debugPrint('OrganizationBranches: load failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createOrg() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New organisation'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'e.g. Apostolic Church of Zambia',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('CREATE'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;

    setState(() => _busy = true);
    try {
      final id = await ref.read(organizationServiceProvider).createOrganization(name);
      if (id != null) _selectedOrgId = id;
      await _load();
      if (mounted) PremiumToast.showSuccess(context, 'Organisation created.');
    } catch (e) {
      if (mounted) PremiumToast.showError(context, 'Failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _attachChurch() async {
    if (_selectedOrgId == null) return;
    if (_unassigned.isEmpty) {
      PremiumToast.showWarning(context, 'No unassigned churches available.');
      return;
    }
    final chosen = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.7,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('ATTACH A CHURCH AS A BRANCH',
                style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: _unassigned.length,
                itemBuilder: (_, i) {
                  final c = _unassigned[i];
                  return ListTile(
                    leading: const Icon(LucideIcons.church),
                    title: Text(c['name']?.toString() ?? 'Church'),
                    subtitle: Text(c['address']?.toString() ?? ''),
                    onTap: () => Navigator.pop(ctx, c),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (chosen == null) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(organizationServiceProvider)
          .linkChurchToOrg(chosen['id'].toString(), _selectedOrgId!);
      await _load();
      if (mounted) {
        PremiumToast.showSuccess(
            context, '${chosen['name']} is now a branch.');
      }
    } catch (e) {
      if (mounted) PremiumToast.showError(context, 'Failed to attach: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _detach(Map<String, dynamic> church) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(organizationServiceProvider)
          .unlinkChurchFromOrg(church['id'].toString());
      await _load();
      if (mounted) {
        PremiumToast.showSuccess(context, '${church['name']} detached.');
      }
    } catch (e) {
      if (mounted) PremiumToast.showError(context, 'Failed to detach: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedOrg = _orgs.firstWhere(
      (o) => o['id']?.toString() == _selectedOrgId,
      orElse: () => const {},
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Organisations & Branches',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'New organisation',
            icon: const Icon(LucideIcons.plusCircle),
            onPressed: _busy ? null : _createOrg,
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(LucideIcons.refreshCw, size: 18),
            onPressed: _load,
          ),
        ],
      ),
      floatingActionButton: _selectedOrgId == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _busy ? null : _attachChurch,
              backgroundColor: AppConstants.sunflowerYellow,
              foregroundColor: AppConstants.primaryDark,
              icon: const Icon(LucideIcons.link),
              label: const Text('ATTACH CHURCH',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              children: [
                // Organisation selector
                if (_orgs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No organisations yet.\nTap + to create one, then attach churches as branches.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                else
                  DropdownButtonFormField<String>(
                    initialValue: _selectedOrgId,
                    decoration: const InputDecoration(
                      labelText: 'Organisation (owned by its bishop)',
                      border: OutlineInputBorder(),
                    ),
                    items: _orgs
                        .map((o) => DropdownMenuItem(
                              value: o['id'].toString(),
                              child: Text(o['name']?.toString() ?? ''),
                            ))
                        .toList(),
                    onChanged: (v) {
                      setState(() => _selectedOrgId = v);
                      _load();
                    },
                  ),

                const SizedBox(height: 20),
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 16,
                      decoration: BoxDecoration(
                          color: theme.primaryColor,
                          borderRadius: BorderRadius.circular(2)),
                    ),
                    const SizedBox(width: 8),
                    Text('BRANCHES (${_branches.length})',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 10),

                if (_selectedOrgId != null && _branches.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'No branches linked yet. The bishop of this organisation will see every branch you attach.',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ),

                ..._branches.map((c) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              AppConstants.sunflowerYellow.withValues(alpha: 0.25),
                          child: const Icon(LucideIcons.church, size: 18),
                        ),
                        title: Text(c['name']?.toString() ?? 'Church',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: Text(c['address']?.toString() ?? '',
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: IconButton(
                          tooltip: 'Detach from organisation',
                          icon: const Icon(LucideIcons.unlink, size: 18),
                          onPressed: _busy ? null : () => _detach(c),
                        ),
                      ),
                    )),

                if (selectedOrg['bishop_id'] == null &&
                    _selectedOrgId != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber),
                    ),
                    child: const Text(
                      'This organisation has no bishop assigned yet. Assign one so the right leader can manage these branches.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
