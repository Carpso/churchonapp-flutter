import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';

class ContentModerationScreen extends ConsumerStatefulWidget {
  const ContentModerationScreen({super.key});

  @override
  ConsumerState<ContentModerationScreen> createState() => _ContentModerationScreenState();
}

class _ContentModerationScreenState extends ConsumerState<ContentModerationScreen> {
  bool _isLoading = true;
  String? _tab = 'prayers';
  List<Map<String, dynamic>> _pendingPrayers = [];
  List<Map<String, dynamic>> _pendingTestimonies = [];

  @override
  void initState() {
    super.initState();
    _loadQueue();
  }

  Future<void> _loadQueue() async {
    setState(() => _isLoading = true);
    final tenantId = ref.read(profileProvider).value?.tenantId;
    if (tenantId == null) { setState(() => _isLoading = false); return; }

    try {
      final prayersRes = await Supabase.instance.client
          .from('prayers')
          .select('id, title, content, created_at, user_id')
          .eq('tenant_id', tenantId)
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      final testimoniesRes = await Supabase.instance.client
          .from('testimonies')
          .select('id, title, content, created_at, user_id')
          .eq('tenant_id', tenantId)
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _pendingPrayers = List<Map<String, dynamic>>.from(prayersRes);
          _pendingTestimonies = List<Map<String, dynamic>>.from(testimoniesRes);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _approveItem(String table, String id) async {
    try {
      await Supabase.instance.client.rpc('approve_pending_item', params: {
        'p_table': table,
        'p_item_id': id,
        'p_reviewer_id': ref.read(profileProvider).value?.id ?? '',
      });
      await _loadQueue();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Approved")));
    } catch (e) {
      try {
        await Supabase.instance.client.from(table).update({'status': 'approved', 'reviewed_by': ref.read(profileProvider).value?.id, 'reviewed_at': DateTime.now().toIso8601String()}).eq('id', id);
        await _loadQueue();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Approved")));
      } catch (e2) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e2")));
      }
    }
  }

  Future<void> _rejectItem(String table, String id) async {
    try {
      await Supabase.instance.client.from(table).update({'status': 'rejected', 'reviewed_by': ref.read(profileProvider).value?.id, 'reviewed_at': DateTime.now().toIso8601String()}).eq('id', id);
      await _loadQueue();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Rejected")));
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
        title: const Text("Content Moderation", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [IconButton(icon: const Icon(LucideIcons.refreshCw), onPressed: _isLoading ? null : _loadQueue)],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadQueue,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      _tabBtn("Prayers (${_pendingPrayers.length})", 'prayers'),
                      const SizedBox(width: 8),
                      _tabBtn("Testimonies (${_pendingTestimonies.length})", 'testimonies'),
                    ]),
                    const SizedBox(height: 20),
                    if (_tab == 'prayers') ..._buildList(theme, _pendingPrayers, 'prayer'),
                    if (_tab == 'testimonies') ..._buildList(theme, _pendingTestimonies, 'testimony'),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _tabBtn(String label, String value) {
    final selected = _tab == value;
    return GestureDetector(
      onTap: () => setState(() => _tab = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.amber.shade600 : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? Colors.amber.shade600 : Colors.grey.shade300),
        ),
        child: Text(label, style: TextStyle(color: selected ? Colors.white : Colors.grey.shade700, fontWeight: FontWeight.w600, fontSize: 12)),
      ),
    );
  }

  List<Widget> _buildList(ThemeData theme, List<Map<String, dynamic>> items, String type) {
    if (items.isEmpty) return [Center(child: Padding(padding: const EdgeInsets.all(40), child: Text("No pending $type items", style: TextStyle(color: Colors.grey.shade500))))];
    return items.map((item) {
      final id = item['id'] as String? ?? '';
      final title = item['title'] as String? ?? 'Untitled';
      final content = item['content'] as String? ?? '';
      final dateStr = item['created_at']?.toString() ?? '';
      final date = DateFormat('MMM d, HH:mm').format(DateTime.tryParse(dateStr) ?? DateTime.now());
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(type == 'prayer' ? LucideIcons.hand : LucideIcons.messageSquare, size: 16, color: Colors.amber.shade600),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
              Text(date, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
            ]),
            if (content.isNotEmpty) Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(content, style: TextStyle(color: Colors.grey.shade700, fontSize: 12), maxLines: 3, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              GestureDetector(
                onTap: () => _rejectItem(type == 'prayer' ? 'prayers' : 'testimonies', id),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(LucideIcons.x, size: 12, color: Colors.red),
                    SizedBox(width: 4),
                    Text("Reject", style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600, fontSize: 11)),
                  ]),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _approveItem(type == 'prayer' ? 'prayers' : 'testimonies', id),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(LucideIcons.check, size: 12, color: Colors.green),
                    SizedBox(width: 4),
                    Text("Approve", style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600, fontSize: 11)),
                  ]),
                ),
              ),
            ]),
          ],
        ),
      );
    }).toList();
  }
}
