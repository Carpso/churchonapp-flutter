import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/widgets/premium_toast.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/services/tenant_sms_service.dart';
import 'package:church_on_app/core/utils/connectivity_util.dart';
import 'sms/buy_sms_credits_screen.dart';

class GlobalBroadcastScreen extends ConsumerStatefulWidget {
  const GlobalBroadcastScreen({super.key});

  @override
  ConsumerState<GlobalBroadcastScreen> createState() => _GlobalBroadcastScreenState();
}

class _GlobalBroadcastScreenState extends ConsumerState<GlobalBroadcastScreen> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  String _selectedTarget = "All Members";
  String _selectedChannel = "Push Notification";
  bool _sending = false;
  List<Map<String, dynamic>> _history = [];

  final _targets = ["All Members", "Pastoral Staff", "Ushers/Helpers", "Transport Drivers", "Youth & Teens", "Women's Fellowship", "Men's Ministry"];
  final _channels = ["Push Notification", "In-App Popup Alert", "SMS"];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final data = await Supabase.instance.client
          .from('notifications')
          .select('title, message, target_audience, channel, created_at')
          .order('created_at', ascending: false)
          .limit(50);
      if (mounted) setState(() => _history = data);
    } catch (e) {
      debugPrint('Failed to load notification history: $e');
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendBroadcast() async {
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    if (title.isEmpty || body.isEmpty) {
      PremiumToast.showWarning(context, "Please fill in the title and broadcast message!");
      return;
    }

    setState(() => _sending = true);
    try {
      if (_selectedChannel == "SMS") {
        await _sendSmsBroadcast(body);
        return;
      }

      await Supabase.instance.client.from('notifications').insert({
        'title': title,
        'message': body,
        'target_audience': _selectedTarget,
        'channel': _selectedChannel,
        'priority': 'high',
        'created_by': Supabase.instance.client.auth.currentUser?.id,
        'created_at': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        PremiumToast.showSuccess(context, "Broadcast sent to $_selectedTarget via $_selectedChannel", title: "Message Dispatched");
        _titleCtrl.clear();
        _bodyCtrl.clear();
        _loadHistory();
      }
    } catch (e) {
      if (mounted) PremiumToast.showError(context, "Failed: ${e.toString().replaceFirst("Exception: ", "")}");
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendSmsBroadcast(String body) async {
    final tenant = ref.read(currentTenantProvider);
    if (tenant == null) {
      if (mounted) PremiumToast.showError(context, "No tenant selected");
      return;
    }

    // Get member phone numbers for the selected audience
    final client = Supabase.instance.client;
    List<Map<String, dynamic>> members;

    try {
      final query = client.from('profiles').select('phone').not('phone', 'is', null).eq('tenant_id', tenant.id);
      if (_selectedTarget != "All Members") {
        final roleMap = {
          "Pastoral Staff": "pastor",
          "Ushers/Helpers": "usher",
          "Transport Drivers": "driver",
          "Youth & Teens": "youth",
          "Women's Fellowship": "women",
          "Men's Ministry": "men",
        };
        final role = roleMap[_selectedTarget];
        if (role != null) {
          members = await query.eq('role', role);
        } else {
          members = await query;
        }
      } else {
        members = await query;
      }
    } catch (e) {
      if (mounted) PremiumToast.showError(context, "Failed to load member contacts");
      setState(() => _sending = false);
      return;
    }

    final phones = members.map((m) => m['phone']?.toString() ?? '').where((p) => p.isNotEmpty).toList();
    if (phones.isEmpty) {
      if (mounted) PremiumToast.showWarning(context, "No phone numbers found for this audience");
      setState(() => _sending = false);
      return;
    }

    final service = ref.read(tenantSmsServiceProvider);
    final success = await service.sendBroadcast(
      tenantId: tenant.id,
      phoneNumbers: phones,
      message: body,
      audienceLabel: _selectedTarget,
    );

    if (mounted) {
      if (success) {
        PremiumToast.showSuccess(context, "SMS sent to ${phones.length} recipients", title: "SMS Broadcast Sent");
        _titleCtrl.clear();
        _bodyCtrl.clear();
      } else {
        PremiumToast.showError(context, "SMS broadcast failed. Check credit balance.");
      }
      _loadHistory();
      setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Global Broadcast", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            Text("Send push alerts or SMS to the church", style: TextStyle(color: Colors.grey.shade600, fontSize: 11, fontWeight: FontWeight.normal)),
          ],
        ),
        actions: [
          if (_selectedChannel == "SMS")
            IconButton(
              icon: const Icon(LucideIcons.creditCard, color: Colors.blueAccent),
              tooltip: "Buy SMS Credits",
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BuySmsCreditsScreen())),
            ),
        ],
      ),
      body: OfflineAwareWrapper(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildForm()),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
                child: Text("DISPATCH HISTORY (${_history.length})", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey, letterSpacing: 1.5)),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.only(left: 20, right: 20, bottom: 40),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _buildHistoryItem(_history[index]),
                  childCount: _history.length,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    final tenant = ref.read(currentTenantProvider);
    final balanceAsync = tenant != null
        ? ref.watch(smsBalanceProvider(tenant.id))
        : const AsyncValue.data(null);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("CREATE NEW DISPATCH", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.5)),
            const SizedBox(height: 20),
            TextField(
              controller: _titleCtrl,
              decoration: InputDecoration(labelText: "Broadcast Title", hintText: "Enter title...", border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)), prefixIcon: const Icon(LucideIcons.type, size: 20)),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _bodyCtrl,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: "Message Body", hintText: "Type what you want to broadcast...", alignLabelWithHint: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                prefixIcon: const Padding(padding: EdgeInsets.only(bottom: 60), child: Icon(LucideIcons.messageSquare, size: 20)),
              ),
            ),
            const SizedBox(height: 20),
            const Text("TARGET AUDIENCE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(15)),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedTarget, isExpanded: true,
                  items: _targets.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (val) { if (val != null) setState(() => _selectedTarget = val); },
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text("DISPATCH CHANNEL", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(15)),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedChannel, isExpanded: true,
                  items: _channels.map((c) => DropdownMenuItem(value: c, child: _channelLabel(c))).toList(),
                  onChanged: (val) { if (val != null) setState(() => _selectedChannel = val); },
                ),
              ),
            ),
            if (_selectedChannel == "SMS") ...[
              const SizedBox(height: 12),
              balanceAsync.when(
                data: (balance) {
                  final balanceVal = balance;
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(LucideIcons.messageCircle, size: 16, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Text("$balanceVal SMS credits", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade800, fontSize: 13)),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BuySmsCreditsScreen())),
                          child: const Text("Buy more", style: TextStyle(fontSize: 11)),
                        ),
                      ],
                    ),
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ],
            const SizedBox(height: 35),
            ElevatedButton(
              onPressed: _sending ? null : _sendBroadcast,
              style: ElevatedButton.styleFrom(
                backgroundColor: _selectedChannel == "SMS" ? Colors.green : Colors.purple,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 60), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                elevation: 5, shadowColor: (_selectedChannel == "SMS" ? Colors.green : Colors.purple).withValues(alpha: 0.3),
              ),
              child: _sending
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(_selectedChannel == "SMS" ? LucideIcons.messageCircle : LucideIcons.send),
                        const SizedBox(width: 10),
                        Text(_selectedChannel == "SMS" ? "SEND SMS BROADCAST" : "SEND GLOBAL BROADCAST",
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _channelLabel(String channel) {
    IconData icon;
    Color color;
    switch (channel) {
      case "SMS":
        icon = LucideIcons.messageCircle;
        color = Colors.green;
        break;
      case "In-App Popup Alert":
        icon = LucideIcons.bell;
        color = Colors.orange;
        break;
      default:
        icon = LucideIcons.bellRing;
        color = Colors.purple;
    }
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(channel),
      ],
    );
  }

  Widget _buildHistoryItem(Map<String, dynamic> h) {
    final channel = h['channel']?.toString() ?? '';
    final isSms = channel == "SMS";

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.01), blurRadius: 10)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(h['title']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
              if (h['created_at'] != null)
                Text(_formatTime(DateTime.parse(h['created_at'])), style: const TextStyle(color: Colors.grey, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 8),
          Text(h['message']?.toString() ?? '', style: TextStyle(color: Colors.grey.shade700, fontSize: 13, height: 1.3)),
          const SizedBox(height: 12),
          Row(
            children: [
              if (h['target_audience'] != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSms ? Colors.green.withValues(alpha: 0.1) : Colors.purple.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(h['target_audience'].toString(),
                      style: TextStyle(color: isSms ? Colors.green : Colors.purple, fontSize: 9, fontWeight: FontWeight.bold)),
                ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isSms ? Colors.green.withValues(alpha: 0.1) : Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(channel, style: TextStyle(color: isSms ? Colors.green : Colors.blue, fontSize: 9, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return "${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
  }
}
