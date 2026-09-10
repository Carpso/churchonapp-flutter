import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';

class BaptismRegistryScreen extends ConsumerStatefulWidget {
  const BaptismRegistryScreen({super.key});

  @override
  ConsumerState<BaptismRegistryScreen> createState() => _BaptismRegistryScreenState();
}

class _BaptismRegistryScreenState extends ConsumerState<BaptismRegistryScreen> {
  List<Map<String, dynamic>> _records = [];
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    setState(() => _loading = true);
    try {
      final client = Supabase.instance.client;
      final profile = ref.read(profileProvider).value;
      final tenantId = profile?.tenantId;
      if (tenantId == null) {
        setState(() { _records = []; _loading = false; });
        return;
      }
      final data = await client
          .from('baptisms')
          .select()
          .eq('tenant_id', tenantId)
          .order('date', ascending: false);
      setState(() { _records = List<Map<String, dynamic>>.from(data); _loading = false; });
    } catch (e) {
      setState(() { _records = []; _loading = false; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load baptisms: $e')));
      }
    }
  }

  Future<void> _addBaptism(String name, String minister, String location, DateTime date) async {
    try {
      final client = Supabase.instance.client;
      final profile = ref.read(profileProvider).value;
      final tenantId = profile?.tenantId;
      if (tenantId == null) return;
      await client.from('baptisms').insert({
        'name': name,
        'minister': minister,
        'location': location,
        'date': date.toIso8601String(),
        'tenant_id': tenantId,
        'created_by': client.auth.currentUser?.id,
        'status': 'Pending',
      });
      await _loadRecords();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Baptism record added'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to add: $e')));
      }
    }
  }

  Future<void> _approveBaptism(String id) async {
    try {
      final client = Supabase.instance.client;
      await client.from('baptisms').update({
        'status': 'Verified',
        'approved_by': client.auth.currentUser?.id,
        'approved_at': DateTime.now().toIso8601String(),
      }).eq('id', id);
      await _loadRecords();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Baptism verified'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to verify: $e')));
      }
    }
  }

  List<Map<String, dynamic>> get _filteredRecords {
    if (_search.isEmpty) return _records;
    return _records.where((r) =>
      (r['name']?.toString() ?? '').toLowerCase().contains(_search.toLowerCase()) ||
      (r['minister']?.toString() ?? '').toLowerCase().contains(_search.toLowerCase())
    ).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Baptism Registry", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.black,
        actions: [
          IconButton(icon: const Icon(LucideIcons.refreshCw, size: 18), onPressed: _loadRecords),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(25, 16, 25, 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search by name or minister...',
                prefixIcon: const Icon(LucideIcons.search, size: 18),
                fillColor: Colors.grey.shade100,
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredRecords.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.award, size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            Text('No baptism records yet', style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadRecords,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(25),
                          itemCount: _filteredRecords.length,
                          itemBuilder: (context, index) => _buildRecordCard(_filteredRecords[index]),
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.black,
        icon: const Icon(LucideIcons.plus),
        label: const Text("Register Baptism"),
      ),
    );
  }

  Widget _buildRecordCard(Map<String, dynamic> record) {
    final status = record['status']?.toString() ?? 'Pending';
    final isVerified = status == 'Verified';
    final dateStr = record['date']?.toString() ?? '';
    DateTime? date;
    try { date = DateTime.parse(dateStr); } catch (_) {}
    final displayId = (record['id']?.toString() ?? '').substring(0, 8).toUpperCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('#$displayId', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor, fontSize: 12)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isVerified ? Colors.green.withValues(alpha: 0.1) : Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(status.toUpperCase(), style: TextStyle(color: isVerified ? Colors.green : Colors.amber.shade900, fontWeight: FontWeight.bold, fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(record['name']?.toString() ?? 'Unknown', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          if (date != null) Text('Baptized on ${DateFormat('d MMMM yyyy').format(date)}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 12),
          Row(children: [
            const Icon(LucideIcons.user, size: 14, color: Colors.grey),
            const SizedBox(width: 6),
            Text('Minister: ${record['minister']?.toString() ?? 'N/A'}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            const Icon(LucideIcons.mapPin, size: 14, color: Colors.grey),
            const SizedBox(width: 6),
            Text('Location: ${record['location']?.toString() ?? 'N/A'}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ]),
          if (!isVerified) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _approveBaptism(record['id']),
                    icon: const Icon(LucideIcons.checkCircle, size: 16),
                    label: const Text('VERIFY'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.green,
                      side: const BorderSide(color: Colors.green),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (isVerified) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _viewCertificate(record),
              icon: const Icon(LucideIcons.award, size: 16),
              label: const Text("VIEW CERTIFICATE"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                foregroundColor: Theme.of(context).primaryColor,
                elevation: 0,
                minimumSize: const Size(double.infinity, 45),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _viewCertificate(Map<String, dynamic> record) {
    final dateStr = record['date']?.toString() ?? '';
    DateTime? date;
    try { date = DateTime.parse(dateStr); } catch (_) {}
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFFFAF0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30), side: const BorderSide(color: Colors.amber, width: 2)),
        content: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.award, color: Colors.amber, size: 70),
              const SizedBox(height: 20),
              const Text("CERTIFICATE OF BAPTISM", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF7A5C00))),
              const SizedBox(height: 20),
              const Text("This is to certify that", style: TextStyle(fontStyle: FontStyle.italic, fontSize: 13)),
              const SizedBox(height: 10),
              Text(record['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
              const SizedBox(height: 10),
              const Text("has been baptized in the name of the Father, and of the Son, and of the Holy Spirit.", textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
              const SizedBox(height: 25),
              const Divider(color: Colors.amber),
              const SizedBox(height: 15),
              Text("Officiated by: ${record['minister']?.toString() ?? ''}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              Text("Location: ${record['location']?.toString() ?? ''}", style: const TextStyle(fontSize: 11, color: Colors.grey)),
              if (date != null) ...[
                const SizedBox(height: 5),
                Text("Date: ${DateFormat('d MMMM yyyy').format(date)}", style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showAddDialog() {
    final nameCtrl = TextEditingController();
    final ministerCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
            padding: const EdgeInsets.all(25),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Register New Baptism", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                TextField(controller: nameCtrl, textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: "Baptist's Full Name", fillColor: Colors.white, filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none))),
                const SizedBox(height: 12),
                TextField(controller: ministerCtrl, textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: "Officiating Minister", fillColor: Colors.white, filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none))),
                const SizedBox(height: 12),
                TextField(controller: locationCtrl,
                  decoration: InputDecoration(labelText: "Church Branch/Location", fillColor: Colors.white, filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none))),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(LucideIcons.calendar),
                  title: Text('Date: ${DateFormat('d MMMM yyyy').format(selectedDate)}'),
                  trailing: const Icon(LucideIcons.chevronRight, size: 18),
                  onTap: () async {
                    final picked = await showDatePicker(context: context, initialDate: selectedDate, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365)));
                    if (picked != null) setSheetState(() => selectedDate = picked);
                  },
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    if (nameCtrl.text.isEmpty || ministerCtrl.text.isEmpty || locationCtrl.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all fields')));
                      return;
                    }
                    _addBaptism(nameCtrl.text, ministerCtrl.text, locationCtrl.text, selectedDate);
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.black,
                    minimumSize: const Size(double.infinity, 55),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  child: const Text("SUBMIT RECORD", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
