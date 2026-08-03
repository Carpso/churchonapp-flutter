import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';

class TenantLeaseManagementScreen extends ConsumerStatefulWidget {
  const TenantLeaseManagementScreen({super.key});

  @override
  ConsumerState<TenantLeaseManagementScreen> createState() => _TenantLeaseManagementScreenState();
}

class _TenantLeaseManagementScreenState extends ConsumerState<TenantLeaseManagementScreen> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _tenants = [];
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _loadTenants();
  }

  Future<void> _loadTenants() async {
    setState(() => _isLoading = true);
    try {
      final res = await Supabase.instance.client
          .from('tenants')
          .select('id, name, type, is_active, created_at')
          .order('created_at', ascending: false);
      if (mounted) setState(() { _tenants = List<Map<String, dynamic>>.from(res); _isLoading = false; _error = null; });
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _error = e.toString(); });
    }
  }

  List<Map<String, dynamic>> get _filteredTenants {
    if (_filter == 'all') return _tenants;
    if (_filter == 'active') return _tenants.where((t) => t['is_active'] == true).toList();
    return _tenants.where((t) => t['is_active'] != true).toList();
  }

  Future<void> _toggleTenantStatus(Map<String, dynamic> tenant) async {
    final id = tenant['id'] as String;
    final active = tenant['is_active'] == true;
    try {
      await Supabase.instance.client.rpc(
        active ? 'suspend_tenant' : 'reactivate_tenant',
        params: {'p_tenant_id': id},
      );
      await _loadTenants();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(active ? "Tenant suspended" : "Tenant reactivated")));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _extendTrial(String churchId) async {
    final daysStr = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Extend Trial"),
        content: TextField(
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: "Extra days", hintText: "30"),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, "30"), child: const Text("EXTEND 30 DAYS")),
        ],
      ),
    );
    if (daysStr == null || daysStr.isEmpty) return;
    final days = int.tryParse(daysStr) ?? 30;
    try {
      await Supabase.instance.client.rpc('extend_church_trial', params: {'p_church_id': churchId, 'p_extra_days': days});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Trial extended by $days days")));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Tenant Lease Management", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [IconButton(icon: const Icon(LucideIcons.refreshCw), onPressed: _isLoading ? null : _loadTenants)],
      ),
      body: _isLoading
          ? const Center(child: ShimmerLoader.rectangular(height: 200))
          : _error != null
              ? Center(child: Text("Error: $_error"))
              : Column(
                  children: [
                    _buildFilterBar(theme),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _loadTenants,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          itemCount: _filteredTenants.length + 1,
                          itemBuilder: (_, i) {
                            if (i == 0) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Text("${_filteredTenants.length} tenants", style: TextStyle(color: Colors.grey.shade600)),
                              );
                            }
                            final t = _filteredTenants[i - 1];
                            return _buildTenantCard(theme, t);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildFilterBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(children: [
        _filterChip("All", 'all'),
        const SizedBox(width: 8),
        _filterChip("Active", 'active'),
        const SizedBox(width: 8),
        _filterChip("Suspended", 'suspended'),
      ]),
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.teal : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? Colors.teal : Colors.grey.shade300),
        ),
        child: Text(label, style: TextStyle(color: selected ? Colors.white : Colors.grey.shade700, fontWeight: FontWeight.w600, fontSize: 12)),
      ),
    );
  }

  Widget _buildTenantCard(ThemeData theme, Map<String, dynamic> tenant) {
    final id = tenant['id'] as String? ?? '';
    final name = tenant['name'] as String? ?? 'Unnamed';
    final type = tenant['type'] as String? ?? 'unknown';
    final active = tenant['is_active'] == true;
    final date = tenant['created_at']?.toString() ?? '';
    final formattedDate = date.isNotEmpty ? DateFormat('MMM d, yyyy').format(DateTime.tryParse(date) ?? DateTime.now()) : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: active ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(active ? LucideIcons.checkCircle : LucideIcons.xCircle, size: 18, color: active ? Colors.green : Colors.red),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
              child: Text(type, style: TextStyle(fontSize: 9, color: Colors.grey.shade600)),
            ),
          ]),
          if (formattedDate.isNotEmpty) Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text("Created $formattedDate", style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          ),
          const SizedBox(height: 12),
          Row(children: [
            _actionBtn(theme, "Extend Trial", LucideIcons.clock, Colors.teal, () => _extendTrial(id)),
            const SizedBox(width: 8),
            _actionBtn(theme, active ? "Suspend" : "Reactivate", active ? LucideIcons.shieldOff : LucideIcons.shield, active ? Colors.red : Colors.green, () => _toggleTenantStatus(tenant)),
          ]),
        ],
      ),
    );
  }

  Widget _actionBtn(ThemeData theme, String label, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}
