import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/services/tenant_service.dart';

class MemberAttendanceScreen extends ConsumerStatefulWidget {
  const MemberAttendanceScreen({super.key});

  @override
  ConsumerState<MemberAttendanceScreen> createState() =>
      _MemberAttendanceScreenState();
}

class _MemberAttendanceScreenState
    extends ConsumerState<MemberAttendanceScreen> {
  List<Map<String, dynamic>> _members = [];
  bool _loading = true;
  String? _error;
  String _query = '';

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<String?> _tenantId() async {
    final selected = ref.read(profileProvider).value?.tenantId;
    return selected ?? ref.read(currentTenantProvider)?.id;
  }

  Future<void> _loadMembers() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tenantId = await _tenantId();
      if (tenantId == null || tenantId.isEmpty) {
        throw Exception('No church tenant selected');
      }
      final result = await _client.rpc('get_tenant_member_attendance', params: {
        'p_tenant_id': tenantId,
        'p_months': 3,
      });
      final rows = result is List
          ? result
              .map((row) => Map<String, dynamic>.from(row as Map))
              .toList()
          : <Map<String, dynamic>>[];
      if (mounted) setState(() { _members = rows; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _recordAttendance() async {
    final tenantId = await _tenantId();
    if (tenantId == null) return;
    final members = await _client
        .from('profiles')
        .select('id, full_name')
        .eq('tenant_id', tenantId)
        .eq('role', 'member')
        .order('full_name');
    if (!mounted) return;
    String? selectedId;
    final serviceTypeController = TextEditingController(text: 'Sunday Service');
    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Record attendance'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedId,
                hint: const Text('Select member'),
                items: (members as List)
                    .map((member) => DropdownMenuItem<String>(
                          value: member['id']?.toString(),
                          child: Text(member['full_name']?.toString() ?? 'Unnamed member'),
                        ))
                    .toList(),
                onChanged: (value) => setDialogState(() => selectedId = value),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: serviceTypeController,
                decoration: const InputDecoration(labelText: 'Service type'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(context, {
                'user_id': selectedId,
                'service_type': serviceTypeController.text.trim(),
              }),
              child: const Text('Record'),
            ),
          ],
        ),
      ),
    );
    serviceTypeController.dispose();
    final userId = selected?['user_id']?.toString();
    if (userId == null || userId.isEmpty) return;
    await _client.rpc('record_member_attendance', params: {
      'p_user_id': userId,
      'p_tenant_id': tenantId,
      'p_service_date': DateTime.now().toIso8601String().substring(0, 10),
      'p_service_type': (selected?['service_type']?.toString().isNotEmpty ?? false)
          ? selected!['service_type']
          : 'Sunday Service',
    });
    await _loadMembers();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _members.where((member) {
      final name = member['full_name']?.toString().toLowerCase() ?? '';
      return name.contains(_query.toLowerCase());
    }).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Member Attendance'),
        actions: [
          IconButton(onPressed: _loadMembers, icon: const Icon(LucideIcons.refreshCw)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _recordAttendance,
        icon: const Icon(LucideIcons.userCheck),
        label: const Text('Record check-in'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, textAlign: TextAlign.center))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(LucideIcons.search),
                          hintText: 'Search members',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) => setState(() => _query = value),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Last 3 months • ${filtered.length} members',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _loadMembers,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final member = filtered[index];
                            final rate = (member['attendance_rate'] as num?)?.toDouble() ?? 0;
                            final attended = member['attended'] ?? 0;
                            final total = member['total_services'] ?? 0;
                            final color = rate >= 75 ? Colors.green : rate >= 40 ? Colors.orange : Colors.red;
                            return Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: color.withValues(alpha: 0.12),
                                  child: Icon(LucideIcons.user, color: color, size: 18),
                                ),
                                title: Text(member['full_name']?.toString() ?? 'Unnamed member'),
                                subtitle: Text('$attended of $total services attended'),
                                trailing: Text(
                                  '${rate.toStringAsFixed(0)}%',
                                  style: TextStyle(color: color, fontWeight: FontWeight.bold),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
