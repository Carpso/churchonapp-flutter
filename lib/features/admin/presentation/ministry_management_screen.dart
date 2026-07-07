import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/services/tenant_service.dart';

final ministriesStreamProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final tenant = ref.watch(currentTenantProvider);
  if (tenant == null) return const Stream.empty();
  final client = Supabase.instance.client;
  return client
      .from('ministries')
      .stream(primaryKey: ['id'])
      .eq('tenant_id', tenant.id)
      .order('name')
      .map((data) => List<Map<String, dynamic>>.from(data));
});

final ministryMembersCountProvider = FutureProvider.family<int, String>((ref, ministryId) async {
  final client = Supabase.instance.client;
  final res = await client
      .from('ministry_members')
      .select('id')
      .eq('ministry_id', ministryId);
  return (res as List).length;
});

class MinistryManagementScreen extends ConsumerStatefulWidget {
  const MinistryManagementScreen({super.key});

  @override
  ConsumerState<MinistryManagementScreen> createState() => _MinistryManagementScreenState();
}

class _MinistryManagementScreenState extends ConsumerState<MinistryManagementScreen> {
  final _client = Supabase.instance.client;

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(currentTenantProvider);
    if (tenant == null) {
      return const Scaffold(
        backgroundColor: Color(0xFFFFFAEB),
        body: Center(child: Text('Select a church first')),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text('Ministry Management'),
        backgroundColor: const Color(0xFFFFFAEB),
        elevation: 0,
        foregroundColor: Colors.black87,
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.plus),
            onPressed: () => _showMinistryForm(context, tenant.id, null),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(ministriesStreamProvider);
        },
        child: ref.watch(ministriesStreamProvider).when(
          data: (ministries) {
            if (ministries.isEmpty) return _buildEmptyState(tenant.id);
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
              itemCount: ministries.length,
              itemBuilder: (context, index) => _buildMinistryCard(ministries[index], tenant.id),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('Error: $err')),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showMinistryForm(context, tenant.id, null),
        backgroundColor: Colors.amber,
        child: const Icon(LucideIcons.plus, color: Colors.white),
      ),
    );
  }

  Widget _buildEmptyState(String tenantId) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.church, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 20),
          Text('No ministries defined', style: TextStyle(color: Colors.grey[500], fontSize: 16)),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: () => _showMinistryForm(context, tenantId, null),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            child: const Text('Create Ministry'),
          ),
        ],
      ),
    );
  }

  Widget _buildMinistryCard(Map<String, dynamic> ministry, String tenantId) {
    final isActive = ministry['is_active'] != false;
    final leaderId = ministry['leader_id'] as String?;
    final ministryId = ministry['id'].toString();
    final memberCount = ref.watch(ministryMembersCountProvider(ministryId));

    return FutureBuilder<Map<String, dynamic>?>(
      future: leaderId != null
          ? _client.from('profiles').select('full_name').eq('id', leaderId).maybeSingle()
          : Future.value(null),
      builder: (context, leaderSnapshot) {
        final leaderName = leaderSnapshot.data?['full_name']?.toString() ?? 'No leader';
        return GestureDetector(
          onTap: () => _showMinistryForm(context, tenantId, ministry),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isActive ? Colors.amber.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(LucideIcons.church, color: isActive ? Colors.amber : Colors.grey, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ministry['name']?.toString() ?? 'Unnamed Ministry',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(LucideIcons.user, size: 12, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text(leaderName, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                          const SizedBox(width: 12),
                          memberCount.when(
                            data: (count) => Row(
                              children: [
                                Icon(LucideIcons.users, size: 12, color: Colors.grey[500]),
                                const SizedBox(width: 4),
                                Text('$count', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                              ],
                            ),
                            loading: () => const SizedBox(width: 16, height: 12),
                            error: (_, __) => const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isActive ? Colors.green.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isActive ? 'ACTIVE' : 'INACTIVE',
                    style: TextStyle(
                      color: isActive ? Colors.green : Colors.grey,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showMinistryForm(BuildContext context, String tenantId, Map<String, dynamic>? ministry) {
    final isEditing = ministry != null;
    final nameController = TextEditingController(text: ministry?['name']?.toString() ?? '');
    final descController = TextEditingController(text: ministry?['description']?.toString() ?? '');
    final meetingDayController = TextEditingController(text: ministry?['meeting_day']?.toString() ?? '');
    final meetingTimeController = TextEditingController(text: ministry?['meeting_time']?.toString() ?? '');
    final meetingLocationController = TextEditingController(text: ministry?['meeting_location']?.toString() ?? '');
    final selectedLeaderId = ValueNotifier<String?>(ministry?['leader_id']?.toString());
    final selectedLeaderName = ValueNotifier<String?>(ministry?['leader_name']?.toString());
    final isActive = ValueNotifier<bool>(ministry?['is_active'] != false);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: const BoxDecoration(
                color: Color(0xFFFFFAEB),
                borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            isEditing ? 'Edit Ministry' : 'New Ministry',
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(LucideIcons.x),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSheetField('Ministry Name', nameController, LucideIcons.type),
                          const SizedBox(height: 16),
                          _buildSheetField('Description', descController, LucideIcons.fileText, maxLines: 3),
                          const SizedBox(height: 16),
                          _buildLeaderPicker(selectedLeaderId, selectedLeaderName, tenantId),
                          const SizedBox(height: 16),
                          _buildSheetField('Meeting Day (e.g. Sunday)', meetingDayController, LucideIcons.calendarDays),
                          const SizedBox(height: 16),
                          _buildSheetField('Meeting Time (e.g. 09:00 AM)', meetingTimeController, LucideIcons.clock),
                          const SizedBox(height: 16),
                          _buildSheetField('Location', meetingLocationController, LucideIcons.mapPin),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              const Text('Active', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                              const Spacer(),
                              Switch(
                                value: isActive.value,
                                onChanged: (v) => setSheetState(() => isActive.value = v),
                                activeTrackColor: Colors.green,
                              ),
                            ],
                          ),
                          const SizedBox(height: 30),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: () async {
                                final data = {
                                  'tenant_id': tenantId,
                                  'name': nameController.text.trim(),
                                  'description': descController.text.trim(),
                                  'leader_id': selectedLeaderId.value,
                                  'meeting_day': meetingDayController.text.trim(),
                                  'meeting_time': meetingTimeController.text.trim(),
                                  'meeting_location': meetingLocationController.text.trim(),
                                  'is_active': isActive.value,
                                };
                                try {
                                  if (isEditing) {
                                    await _client.from('ministries').update(data).eq('id', ministry['id']);
                                  } else {
                                    await _client.from('ministries').insert(data);
                                  }
                                  ref.invalidate(ministriesStreamProvider);
                                  if (ctx.mounted) Navigator.pop(ctx);
                                } catch (e) {
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error: $e')));
                                  }
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.amber,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                              ),
                              child: Text(
                                isEditing ? 'Update Ministry' : 'Create Ministry',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSheetField(String label, TextEditingController controller, IconData icon, {int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 5)],
          ),
          child: TextField(
            controller: controller,
            maxLines: maxLines,
            decoration: InputDecoration(
              prefixIcon: Icon(icon, size: 18, color: Colors.grey),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLeaderPicker(ValueNotifier<String?> selectedId, ValueNotifier<String?> selectedName, String tenantId) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Leader', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () async {
            final profiles = await _client
                .from('profiles')
                .select('id, full_name')
                .eq('tenant_id', tenantId)
                .order('full_name');
            if (!mounted) return;
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Select Leader'),
                content: SizedBox(
                  width: double.maxFinite,
                  height: 300,
                  child: ListView.builder(
                    itemCount: (profiles as List).length,
                    itemBuilder: (context, index) {
                      final p = profiles[index];
                      final isSelected = selectedId.value == p['id'].toString();
                      return ListTile(
                        title: Text(p['full_name']?.toString() ?? 'Unknown'),
                        trailing: isSelected ? const Icon(LucideIcons.checkCircle, color: Colors.amber) : null,
                        onTap: () {
                          selectedId.value = p['id'].toString();
                          selectedName.value = p['full_name']?.toString();
                          Navigator.pop(ctx);
                        },
                      );
                    },
                  ),
                ),
              ),
            );
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 5)],
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.user, size: 18, color: Colors.grey),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    selectedName.value ?? 'Tap to select a leader',
                    style: TextStyle(color: selectedName.value != null ? Colors.black87 : Colors.grey, fontSize: 14),
                  ),
                ),
                const Icon(LucideIcons.chevronDown, size: 18, color: Colors.grey),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
