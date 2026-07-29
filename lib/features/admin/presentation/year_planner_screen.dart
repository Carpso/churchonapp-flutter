import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/features/planner/data/planner_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class YearPlannerScreen extends ConsumerStatefulWidget {
  const YearPlannerScreen({super.key});

  @override
  ConsumerState<YearPlannerScreen> createState() => _YearPlannerScreenState();
}

class _YearPlannerScreenState extends ConsumerState<YearPlannerScreen> {
  final _client = Supabase.instance.client;

  @override
  Widget build(BuildContext context) {
    // Wire PlannerService into year planner feature lifecycle
    ref.watch(plannerServiceProvider);
    final tenant = ref.watch(currentTenantProvider);
    if (tenant == null) return const Scaffold(body: Center(child: Text("Select a Church")));

    final userProfileAsync = ref.watch(profileProvider);
    bool isAdmin = false;
    userProfileAsync.whenData((p) { isAdmin = p?.isAdminOrHigher ?? false; });

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text("Yearly Program Planner", style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(LucideIcons.plusCircle, color: Colors.blue),
              onPressed: () => _showAddProgramDialog(context, tenant.id),
            ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _client
            .from('year_planner')
            .stream(primaryKey: ['id'])
            .eq('tenant_id', tenant.id)
            .order('event_date', ascending: true),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final programs = snapshot.data ?? [];
          if (programs.isEmpty) {
            return _buildEmptyState(tenant.id, isAdmin);
          }

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: programs.length,
            itemBuilder: (context, index) {
              final program = programs[index];
              return _buildProgramCard(program, tenant.id, isAdmin);
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(String tenantId, bool isAdmin) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.calendar, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 20),
          Text("No annual programs planned yet", style: TextStyle(color: Colors.grey[500], fontSize: 16)),
          const SizedBox(height: 10),
          if (isAdmin)
            ElevatedButton(
              onPressed: () => _showAddProgramDialog(context, tenantId),
              child: const Text("Create First Program"),
            ),
        ],
      ),
    );
  }

  Widget _buildProgramCard(Map<String, dynamic> program, String tenantId, bool isAdmin) {
    final date = DateTime.parse(program['event_date']);
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(15)),
            child: Column(
              children: [
                Text(DateFormat('MMM').format(date).toUpperCase(), style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 10)),
                Text(DateFormat('dd').format(date), style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w900, fontSize: 18)),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  program['title'],
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
                const SizedBox(height: 4),
                Text(
                  program['description'] ?? "No details provided",
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ],
            ),
          ),
          if (program['is_central'] == true)
            const Chip(
              label: Text("MAJOR", style: TextStyle(fontSize: 8, color: Colors.white)),
              backgroundColor: Colors.red,
              padding: EdgeInsets.zero,
            ),
          if (isAdmin) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(LucideIcons.pencil, size: 18, color: Colors.grey.shade400),
              onPressed: () => _showEditProgramDialog(context, program, tenantId),
            ),
          ],
        ],
      ),
    );
  }

  void _showAddProgramDialog(BuildContext context, String tenantId) {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now();
    bool isMajor = false;
    bool isSaving = false;
    String? titleError;
    final tenant = ref.read(currentTenantProvider);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Add Annual Program", style: TextStyle(fontSize: 18)),
              if (tenant != null)
                Text(
                  tenant.name,
                  style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.normal),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: InputDecoration(
                    labelText: "Program Title",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    errorText: titleError,
                  ),
                  onChanged: (_) { if (titleError != null) setDialogState(() => titleError = null); },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  decoration: InputDecoration(
                    labelText: "Description",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 15),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(LucideIcons.calendar, size: 16, color: Colors.blue),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(DateFormat('MMM dd, yyyy').format(selectedDate), style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final date = await showDatePicker(context: context, initialDate: selectedDate, firstDate: DateTime.now(), lastDate: DateTime(2030));
                          if (date != null) setDialogState(() => selectedDate = date);
                        },
                        icon: const Icon(LucideIcons.edit, size: 16),
                        label: const Text("Pick Date"),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Checkbox(
                      value: isMajor,
                      onChanged: (v) => setDialogState(() => isMajor = v ?? false),
                    ),
                    const Flexible(child: Text("Mark as Major Event", overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: isSaving ? null : () => Navigator.pop(context), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: isSaving ? null : () async {
                if (titleCtrl.text.trim().isEmpty) {
                  setDialogState(() => titleError = "Title is required");
                  return;
                }
                setDialogState(() => isSaving = true);
                try {
                  await _client.from('year_planner').insert({
                    'tenant_id': tenantId,
                    'title': titleCtrl.text.trim(),
                    'description': descCtrl.text.trim(),
                    'event_date': selectedDate.toIso8601String(),
                    'is_central': isMajor,
                  });
                  if (!context.mounted) return;
                  Navigator.pop(context);
                } catch (e) {
                  setDialogState(() => isSaving = false);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
                  }
                }
              },
              child: isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text("Add"),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditProgramDialog(BuildContext context, Map<String, dynamic> program, String tenantId) {
    final titleCtrl = TextEditingController(text: program['title'] ?? '');
    final descCtrl = TextEditingController(text: program['description'] ?? '');
    DateTime selectedDate = DateTime.parse(program['event_date']);
    bool isMajor = program['is_central'] == true;
    bool isSaving = false;
    String? titleError;
    final tenant = ref.read(currentTenantProvider);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Edit Program", style: TextStyle(fontSize: 18)),
              if (tenant != null)
                Text(
                  tenant.name,
                  style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.normal),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: InputDecoration(
                    labelText: "Program Title",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    errorText: titleError,
                  ),
                  onChanged: (_) { if (titleError != null) setDialogState(() => titleError = null); },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  decoration: InputDecoration(
                    labelText: "Description",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 15),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(LucideIcons.calendar, size: 16, color: Colors.blue),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(DateFormat('MMM dd, yyyy').format(selectedDate), style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final date = await showDatePicker(context: context, initialDate: selectedDate, firstDate: DateTime(2024), lastDate: DateTime(2030));
                          if (date != null) setDialogState(() => selectedDate = date);
                        },
                        icon: const Icon(LucideIcons.edit, size: 16),
                        label: const Text("Pick Date"),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Checkbox(
                      value: isMajor,
                      onChanged: (v) => setDialogState(() => isMajor = v ?? false),
                    ),
                    const Flexible(child: Text("Mark as Major Event", overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text("Delete Program?"),
                    content: const Text("This action cannot be undone."),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text("Delete", style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
                if (confirmed == true && context.mounted) {
                  await _client.from('year_planner').delete().eq('id', program['id']);
                  if (!context.mounted) return;
                  Navigator.pop(context);
                }
              },
              child: const Text("Delete", style: TextStyle(color: Colors.red)),
            ),
            TextButton(onPressed: isSaving ? null : () => Navigator.pop(context), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: isSaving ? null : () async {
                if (titleCtrl.text.trim().isEmpty) {
                  setDialogState(() => titleError = "Title is required");
                  return;
                }
                setDialogState(() => isSaving = true);
                try {
                  await _client.from('year_planner').update({
                    'title': titleCtrl.text.trim(),
                    'description': descCtrl.text.trim(),
                    'event_date': selectedDate.toIso8601String(),
                    'is_central': isMajor,
                  }).eq('id', program['id']);
                  if (!context.mounted) return;
                  Navigator.pop(context);
                } catch (e) {
                  setDialogState(() => isSaving = false);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
                  }
                }
              },
              child: isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text("Save"),
            ),
          ],
        ),
      ),
    );
  }
}
