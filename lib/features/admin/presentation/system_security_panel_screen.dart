import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


class SystemSecurityPanelScreen extends ConsumerStatefulWidget {
  const SystemSecurityPanelScreen({super.key});

  @override
  ConsumerState<SystemSecurityPanelScreen> createState() => _SystemSecurityPanelScreenState();
}

class _SystemSecurityPanelScreenState extends ConsumerState<SystemSecurityPanelScreen> {
  bool _isLoading = true;
  bool _isFrozen = false;
  String? _freezeReason;
  int _auditCount = 0;
  int _securityEventCount = 0;
  List<Map<String, dynamic>> _recentAudits = [];
  List<Map<String, dynamic>> _recentSecurityEvents = [];
  String _tab = 'overview';

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    try {
      final lockRes = await Supabase.instance.client
          .from('system_lock_state')
          .select('is_locked, reason')
          .order('created_at', ascending: false)
          .limit(1);

      final auditRes = await Supabase.instance.client
          .from('audit_logs')
          .select('id, action, entity_type, details, created_at')
          .order('created_at', ascending: false)
          .limit(30);

      final securityRes = await Supabase.instance.client
          .from('security_events')
          .select('id, event_type, severity, details, created_at')
          .order('created_at', ascending: false)
          .limit(30);

      if (mounted) {
        setState(() {
          if (lockRes.isNotEmpty) {
            _isFrozen = lockRes[0]['is_locked'] == true;
            _freezeReason = lockRes[0]['reason'];
          }
          _recentAudits = List<Map<String, dynamic>>.from(auditRes);
          _recentSecurityEvents = List<Map<String, dynamic>>.from(securityRes);
          _auditCount = auditRes.length;
          _securityEventCount = securityRes.length;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  Future<void> _toggleFreeze() async {
    final reason = _isFrozen ? null : await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Freeze System"),
        content: const Text("This will lock all platform operations. All RPCs will be blocked."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, "Scheduled maintenance"), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text("FREEZE")),
        ],
      ),
    );
    if (!_isFrozen && reason == null) return;
    try {
      await Supabase.instance.client.rpc('toggle_system_freeze', params: {'p_locked': !_isFrozen, 'p_reason': reason ?? ''});
      await _loadAll();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_isFrozen ? "System unfrozen" : "System frozen")));
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
        title: const Text("System Security", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [IconButton(icon: const Icon(LucideIcons.refreshCw), onPressed: _isLoading ? null : _loadAll)],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFreezeCard(theme),
                    const SizedBox(height: 25),
                    _buildTabRow(theme),
                    const SizedBox(height: 20),
                    if (_tab == 'overview') _buildOverview(theme),
                    if (_tab == 'audit') ..._buildAuditList(theme),
                    if (_tab == 'security') ..._buildSecurityList(theme),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildFreezeCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _isFrozen ? [Colors.red.shade800, Colors.red.shade600] : [Colors.green.shade700, Colors.green.shade500],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: (_isFrozen ? Colors.red : Colors.green).shade200.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(_isFrozen ? LucideIcons.shieldOff : LucideIcons.shieldCheck, color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_isFrozen ? "System Frozen" : "System Operational", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                if (_freezeReason != null) Text(_freezeReason!, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11)),
              ],
            )),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
              child: Text("$_auditCount audit events", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 11)),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
              child: Text("$_securityEventCount security events", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 11)),
            ),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _toggleFreeze,
              icon: Icon(_isFrozen ? LucideIcons.unlock : LucideIcons.lock, size: 16),
              label: Text(_isFrozen ? "Unfreeze System" : "Freeze System"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: _isFrozen ? Colors.red : Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabRow(ThemeData theme) {
    return Row(children: [
      _tabBtn("Overview", 'overview'),
      const SizedBox(width: 8),
      _tabBtn("Audit Logs", 'audit'),
      const SizedBox(width: 8),
      _tabBtn("Security Events", 'security'),
    ]);
  }

  Widget _tabBtn(String label, String value) {
    final selected = _tab == value;
    return GestureDetector(
      onTap: () => setState(() => _tab = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.red.shade600 : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? Colors.red.shade600 : Colors.grey.shade300),
        ),
        child: Text(label, style: TextStyle(color: selected ? Colors.white : Colors.grey.shade700, fontWeight: FontWeight.w600, fontSize: 11)),
      ),
    );
  }

  Widget _buildOverview(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Recent Activity", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 16),
          if (_recentAudits.isEmpty) Text("No audit logs", style: TextStyle(color: Colors.grey.shade500)),
          ..._recentAudits.take(5).map((a) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Icon(LucideIcons.circle, size: 8, color: Colors.teal.shade400),
              const SizedBox(width: 10),
              Expanded(child: Text(a['action'] as String? ?? '', style: const TextStyle(fontSize: 12))),
              Text(_formatDate(a['created_at']?.toString() ?? ''), style: TextStyle(color: Colors.grey.shade500, fontSize: 10)),
            ]),
          )),
        ],
      ),
    );
  }

  List<Widget> _buildAuditList(ThemeData theme) {
    if (_recentAudits.isEmpty) return [Center(child: Padding(padding: const EdgeInsets.all(40), child: Text("No audit logs", style: TextStyle(color: Colors.grey.shade500))))];
    return _recentAudits.map((a) {
      final action = a['action'] as String? ?? 'unknown';
      final entity = a['entity_type'] as String? ?? '';
      final date = _formatDate(a['created_at']?.toString() ?? '');
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Icon(_auditIcon(action), size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(action, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
              Text(entity, style: TextStyle(color: Colors.grey.shade500, fontSize: 10)),
            ],
          )),
          Text(date, style: TextStyle(color: Colors.grey.shade500, fontSize: 10)),
        ]),
      );
    }).toList();
  }

  List<Widget> _buildSecurityList(ThemeData theme) {
    if (_recentSecurityEvents.isEmpty) return [Center(child: Padding(padding: const EdgeInsets.all(40), child: Text("No security events", style: TextStyle(color: Colors.grey.shade500))))];
    return _recentSecurityEvents.map((e) {
      final type = e['event_type'] as String? ?? 'unknown';
      final severity = e['severity'] as String? ?? 'info';
      final eventDate = _formatDate(e['created_at']?.toString() ?? '');
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: severity == 'critical' ? Colors.red.shade200 : Colors.transparent),
        ),
        child: Row(children: [
          Icon(
            severity == 'critical' ? LucideIcons.alertTriangle : severity == 'warning' ? LucideIcons.alertCircle : LucideIcons.info,
            size: 16, color: severity == 'critical' ? Colors.red : severity == 'warning' ? Colors.amber : Colors.blue,
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(type, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
              Text(severity, style: TextStyle(color: Colors.grey.shade500, fontSize: 10)),
            ],
          )),
          Text(eventDate, style: TextStyle(color: Colors.grey.shade500, fontSize: 10)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: severity == 'critical' ? Colors.red.withValues(alpha: 0.1) : severity == 'warning' ? Colors.amber.withValues(alpha: 0.1) : Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(severity, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: severity == 'critical' ? Colors.red : severity == 'warning' ? Colors.amber.shade800 : Colors.blue)),
          ),
        ]),
      );
    }).toList();
  }

  IconData _auditIcon(String action) {
    if (action.contains('freeze')) return LucideIcons.shieldOff;
    if (action.contains('unfreeze')) return LucideIcons.shield;
    if (action.contains('transaction')) return LucideIcons.creditCard;
    if (action.contains('tenant')) return LucideIcons.building;
    if (action.contains('church')) return LucideIcons.home;
    return LucideIcons.fileText;
  }

  String _formatDate(String dateStr) {
    final dt = DateTime.tryParse(dateStr);
    if (dt == null) return '';
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
