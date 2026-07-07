import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
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
    final tenant = ref.watch(currentTenantProvider);
    if (tenant == null) return const Scaffold(body: Center(child: Text("Select a Church")));

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text("Yearly Program Planner", style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
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
            return _buildEmptyState(tenant.id);
          }

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: programs.length,
            itemBuilder: (context, index) {
              final program = programs[index];
              return _buildProgramCard(program);
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(String tenantId) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.calendar, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 20),
          Text("No annual programs planned yet", style: TextStyle(color: Colors.grey[500], fontSize: 16)),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: () => _showAddProgramDialog(context, tenantId),
            child: const Text("Create First Program"),
          ),
        ],
      ),
    );
  }

  Widget _buildProgramCard(Map<String, dynamic> program) {
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
                Text(program['title'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text(program['description'] ?? "No details provided", style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          if (program['is_central'] == true)
            const Chip(
              label: Text("MAJOR", style: TextStyle(fontSize: 8, color: Colors.white)),
              backgroundColor: Colors.red,
              padding: EdgeInsets.zero,
            ),
        ],
      ),
    );
  }

  void _showAddProgramDialog(BuildContext context, String tenantId) {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Add Annual Program"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: titleCtrl, decoration: const InputDecoration(hintText: "Program Title")),
            TextField(controller: descCtrl, decoration: const InputDecoration(hintText: "Description")),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                final date = await showDatePicker(context: context, initialDate: selectedDate, firstDate: DateTime.now(), lastDate: DateTime(2030));
                if (date != null) selectedDate = date;
              },
              child: const Text("Select Date"),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              await _client.from('year_planner').insert({
                'tenant_id': tenantId,
                'title': titleCtrl.text,
                'description': descCtrl.text,
                'event_date': selectedDate.toIso8601String(),
              });
              if (!context.mounted) return;
              Navigator.pop(context);
            },
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }
}

