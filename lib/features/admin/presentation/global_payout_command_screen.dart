import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../data/admin_service.dart';

class GlobalPayoutCommandScreen extends ConsumerStatefulWidget {
  const GlobalPayoutCommandScreen({super.key});

  @override
  ConsumerState<GlobalPayoutCommandScreen> createState() => _GlobalPayoutCommandScreenState();
}

class _GlobalPayoutCommandScreenState extends ConsumerState<GlobalPayoutCommandScreen> {
  List<Map<String, dynamic>> _payoutRequests = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() => _isLoading = true);
    final requests = await ref.read(adminServiceProvider).getPayoutRequests();
    setState(() {
      _payoutRequests = requests;
      _isLoading = false;
    });
  }

  void _executePayout(Map<String, dynamic> request) async {
    setState(() => _isLoading = true);
    
    final result = await ref.read(adminServiceProvider).executeLipilaPayout(
      userId: request['user_id'],
      amount: (request['amount'] as num).toDouble(),
      phone: request['mobile_number'],
      network: request['network'],
    );

    if (result['success']) {
      await ref.read(adminServiceProvider).processPayout(request['id'], 'processed');
      await _loadRequests();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Lipila Payout Successful. Ref: ${result['reference']}")),
        );
      }
    } else {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Payout Failed: ${result['error']}"), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Dark Command Center
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text("Global Payout Command", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Colors.greenAccent))
        : _payoutRequests.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              padding: const EdgeInsets.all(25),
              itemCount: _payoutRequests.length,
              itemBuilder: (context, index) => _buildPayoutCard(_payoutRequests[index]),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.wallet, size: 80, color: Colors.white.withValues(alpha: 0.1)),
          const SizedBox(height: 20),
          const Text("No pending global payout requests.", style: TextStyle(color: Colors.white38)),
        ],
      ),
    );
  }

  Widget _buildPayoutCard(Map<String, dynamic> request) {
    final bool isProcessed = request['status'] == 'processed';

    return Container(
      margin: const EdgeInsets.only(bottom: 25),
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: isProcessed ? Colors.green.withValues(alpha: 0.2) : Colors.white10),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.greenAccent.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: const Icon(LucideIcons.user, color: Colors.greenAccent, size: 20),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(request['profiles']['full_name'] ?? "Worker", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    Text("${request['network'].toUpperCase()} | ${request['mobile_number']}", style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  ],
                ),
              ),
              Text("K ${request['amount']}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
            ],
          ),
          const Divider(height: 40, color: Colors.white10),
          if (!isProcessed)
            ElevatedButton(
              onPressed: () => _executePayout(request),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent,
                foregroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              child: const Text("EXECUTE LIPILA SETTLEMENT", style: TextStyle(fontWeight: FontWeight.bold)),
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(LucideIcons.checkCircle, color: Colors.green, size: 16),
                const SizedBox(width: 10),
                const Text("SETTLED VIA LIPILA", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2)),
              ],
            ),
        ],
      ),
    );
  }
}

