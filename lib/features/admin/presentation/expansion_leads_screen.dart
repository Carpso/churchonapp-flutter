import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ExpansionLeadsScreen extends ConsumerStatefulWidget {
  const ExpansionLeadsScreen({super.key});

  @override
  ConsumerState<ExpansionLeadsScreen> createState() => _ExpansionLeadsScreenState();
}

class _ExpansionLeadsScreenState extends ConsumerState<ExpansionLeadsScreen> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>>? _leads;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLeads();
  }

  Future<void> _loadLeads() async {
    setState(() {
      _error = null;
      _leads = null;
    });
    try {
      final data = await _client
          .from('expansion_leads')
          .select('*')
          .order('created_at', ascending: false)
          .limit(200);
      if (mounted) setState(() => _leads = data);
    } catch (e) {
      debugPrint('Error loading expansion leads: $e');
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _updateStatus(Map<String, dynamic> lead, String status) async {
    try {
      await _client.from('expansion_leads').update({'status': status}).eq('id', lead['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Marked "${lead['church_name']}" as $status'), backgroundColor: Colors.green),
        );
        _loadLeads();
      }
    } catch (e) {
      debugPrint('Failed to update lead: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text("Expansion Leads", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(LucideIcons.refreshCw), onPressed: _leads == null ? null : _loadLeads),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.alertTriangle, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            const Text("Failed to load expansion leads"),
            const SizedBox(height: 8),
            TextButton(onPressed: _loadLeads, child: const Text("Retry")),
          ],
        ),
      );
    }
    if (_leads == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_leads!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.mapPin, size: 56, color: theme.colorScheme.onSurface.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            const Text("No expansion leads yet", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text("Leads from the website's 'Tell us which church to add' form appear here.", style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadLeads,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _leads!.length,
        itemBuilder: (context, index) => _buildLeadCard(theme, _leads![index]),
      ),
    );
  }

  Widget _buildLeadCard(ThemeData theme, Map<String, dynamic> lead) {
    final churchName = lead['church_name']?.toString() ?? 'Unknown Church';
    final location = lead['location']?.toString() ?? '';
    final status = lead['status']?.toString() ?? 'new';
    final createdAt = lead['created_at']?.toString();
    final statusColor = status == 'new' ? Colors.orange : (status == 'contacted' ? theme.primaryColor : Colors.green);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.church, color: theme.colorScheme.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(churchName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                child: Text(status.toUpperCase(), style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          if (location.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(LucideIcons.mapPin, size: 14, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                const SizedBox(width: 6),
                Text(location, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.7))),
              ],
            ),
          ],
          if (lead['phone_number'] != null && lead['phone_number'].toString().trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(LucideIcons.phone, size: 14, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                const SizedBox(width: 6),
                Text(lead['phone_number'].toString(), style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.7), fontWeight: FontWeight.w600)),
              ],
            ),
          ],
          if (createdAt != null) ...[
            const SizedBox(height: 8),
            Text('Requested: ${_formatDate(createdAt)}', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (status == 'new') ...[
                OutlinedButton(
                  onPressed: () => _updateStatus(lead, 'contacted'),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12), minimumSize: const Size(0, 36)),
                  child: const Text("Mark Contacted", style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 8),
              ],
              OutlinedButton(
                onPressed: () => _updateStatus(lead, 'onboarded'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12), minimumSize: const Size(0, 36)),
                child: const Text("Onboarded", style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => _showLeadDetails(lead),
                child: const Text("Details", style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showLeadDetails(Map<String, dynamic> lead) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(lead['church_name']?.toString() ?? 'Lead Details', style: const TextStyle(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailRow("Location", lead['location']?.toString() ?? '—'),
              _detailRow("Phone", lead['phone_number']?.toString() ?? '—'),
              _detailRow("Type", lead['interest_type']?.toString() ?? '—'),
              _detailRow("Status", lead['status']?.toString() ?? '—'),
              _detailRow("Created", lead['created_at']?.toString() ?? '—'),
              _detailRow("User ID", lead['user_id']?.toString() ?? '—'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Close")),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5))),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}
