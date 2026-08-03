import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../data/admin_service.dart';

class WithdrawalApprovalScreen extends ConsumerStatefulWidget {
  const WithdrawalApprovalScreen({super.key});

  @override
  ConsumerState<WithdrawalApprovalScreen> createState() => _WithdrawalApprovalScreenState();
}

class _WithdrawalApprovalScreenState extends ConsumerState<WithdrawalApprovalScreen> {
  bool _loading = false;
  List<Map<String, dynamic>> _requests = [];

  @override
  void initState() {
    super.initState();
    _fetchRequests();
  }

  void _fetchRequests() async {
    setState(() => _loading = true);
    final data = await ref.read(adminServiceProvider).getPayoutRequests();
    setState(() {
      _requests = data;
      _loading = false;
    });
  }

  void _process(String id, String status) async {
    await ref.read(adminServiceProvider).processPayout(id, status);
    _fetchRequests();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Payout marked as $status")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Payout Queue"),
        actions: [
          IconButton(icon: const Icon(LucideIcons.refreshCw), onPressed: _fetchRequests),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _requests.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: _requests.length,
                  itemBuilder: (context, index) => _buildRequestCard(_requests[index]),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.checkCircle2, color: Colors.green.withValues(alpha: 0.2), size: 100),
          const SizedBox(height: 20),
          const Text("All Clear!", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const Text("No pending payout requests found.", style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> request) {
    final status = request['status'] as String;
    final isPending = status == 'pending';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(request['profiles']['full_name'] ?? 'Unknown Member', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text("K ${request['amount']}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.green)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(LucideIcons.phone, size: 14, color: Colors.grey),
              const SizedBox(width: 8),
              Text("${request['network']}: ${request['mobile_number']}", style: const TextStyle(color: Colors.grey, fontSize: 13)),
            ],
          ),
          const Divider(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStatusBadge(status),
              if (isPending)
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(LucideIcons.xCircle, color: Colors.red),
                      onPressed: () => _process(request['id'], 'failed'),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: () => _process(request['id'], 'processed'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text("SETTLE"),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color = Colors.orange;
    if (status == 'processed') color = Colors.green;
    if (status == 'failed') color = Colors.red;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 10),
      ),
    );
  }
}

