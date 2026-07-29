import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/features/finance/data/finance_service.dart';
import 'package:church_on_app/features/finance/data/pledge_service.dart';
import 'package:church_on_app/features/finance/presentation/lipila_payment_gateway.dart';

class MyPledgesScreen extends ConsumerStatefulWidget {
  const MyPledgesScreen({super.key});

  @override
  ConsumerState<MyPledgesScreen> createState() => _MyPledgesScreenState();
}

class _MyPledgesScreenState extends ConsumerState<MyPledgesScreen> {
  final _totalCtrl = TextEditingController();
  final _cyclesCtrl = TextEditingController();
  String _category = 'Building Fund';
  String _frequency = 'monthly';
  bool _showForm = false;
  bool _isSubmitting = false;

  final List<String> _categories = ['Building Fund', 'Mission', 'Outreach', 'General', 'Other'];
  final List<String> _frequencies = ['weekly', 'monthly', 'quarterly'];

  @override
  void dispose() {
    _totalCtrl.dispose();
    _cyclesCtrl.dispose();
    super.dispose();
  }

  double get _perCycle {
    final total = double.tryParse(_totalCtrl.text) ?? 0;
    final cycles = int.tryParse(_cyclesCtrl.text) ?? 0;
    if (cycles <= 0) return 0;
    return (total / cycles);
  }

  Future<void> _submitPledge() async {
    final total = double.tryParse(_totalCtrl.text) ?? 0;
    final cycles = int.tryParse(_cyclesCtrl.text) ?? 0;
    if (total <= 0 || cycles <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Enter a valid total and number of installments.")));
      return;
    }
    final tenant = ref.read(currentTenantProvider);
    if (tenant == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Select a church first.")));
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await ref.read(pledgeServiceProvider).createPledge(
        tenantId: tenant.id,
        category: _category,
        totalAmount: total,
        amountPerCycle: _perCycle,
        frequency: _frequency,
        installments: cycles,
      );
      _totalCtrl.clear();
      _cyclesCtrl.clear();
      setState(() => _showForm = false);
      ref.invalidate(myPledgesProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Pledge committed! God bless your faithfulness.")));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to commit pledge: ${e.toString().replaceFirst('Exception: ', '')}")),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _payInstallment(Pledge pledge) {
    final tenant = ref.read(currentTenantProvider);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return LipilaPaymentGateway(
          amount: pledge.amountPerCycle,
          description: "Pledge: ${pledge.category}",
          category: pledge.category.toLowerCase(),
          recipientName: tenant?.name ?? "Local Church",
          recipientAccount: tenant?.treasurerPhone ?? "CHURCH-OFFICIAL-AC",
          paymentReason: "${pledge.category} Pledge Installment",
          onComplete: (success, txId) async {
            if (ctx.mounted) Navigator.pop(ctx);
            if (success && txId != null) {
              await ref.read(pledgeServiceProvider).recordInstallmentPayment(pledge.id, pledge.amountPerCycle);
              await ref.read(financeServiceProvider).logTransaction(
                pledge.amountPerCycle,
                pledge.category.toLowerCase(),
                txId,
                tenantId: tenant?.id,
                recipientName: tenant?.name,
                recipientPhone: tenant?.treasurerPhone,
              );
              ref.invalidate(myPledgesProvider);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Installment paid. Thank you!")));
              }
            }
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final pledgesAsync = ref.watch(myPledgesProvider);
    final tenant = ref.watch(currentTenantProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text("My Pledges", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).colorScheme.surface,
      ),
      body: pledgesAsync.when(
        data: (pledges) {
          final totalPledged = pledges.fold(0.0, (s, p) => s + p.totalAmount);
          final totalPaid = pledges.fold(0.0, (s, p) => s + p.paidAmount);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(25),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(25),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _summaryStat("Pledged", totalPledged),
                      _summaryStat("Paid", totalPaid),
                      _summaryStat("Remaining", (totalPledged - totalPaid).clamp(0, double.infinity)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (tenant != null)
                  ElevatedButton.icon(
                    onPressed: () => setState(() => _showForm = !_showForm),
                    icon: Icon(_showForm ? LucideIcons.minus : LucideIcons.plus, color: Colors.white),
                    label: Text(_showForm ? "CANCEL" : "MAKE A PLEDGE", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 55),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                  ),
                if (_showForm) _buildPledgeForm(),
                const SizedBox(height: 25),
                Text("My Commitments", style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 15),
                if (pledges.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 30),
                    child: Center(child: Text("No pledges yet. Make your first commitment above.")),
                  )
                else
                  ...pledges.map((p) => _buildPledgeCard(p)),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text("Error: $e")),
      ),
    );
  }

  Widget _summaryStat(String label, double value) {
    return Column(
      children: [
        Text("K ${value.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(label.toUpperCase(), style: const TextStyle(color: Colors.white60, fontSize: 9, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildPledgeForm() {
    return Container(
      margin: const EdgeInsets.only(top: 15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(25)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("New Pledge", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 15),
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: _inputDecoration("Category"),
            items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            onChanged: (v) => setState(() => _category = v!),
          ),
          const SizedBox(height: 15),
          TextField(
            controller: _totalCtrl,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: _inputDecoration("Total amount (K)"),
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _cyclesCtrl,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: _inputDecoration("Installments"),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _frequency,
                  decoration: _inputDecoration("Frequency"),
                  items: _frequencies.map((f) => DropdownMenuItem(value: f, child: Text(f[0].toUpperCase() + f.substring(1)))).toList(),
                  onChanged: (v) => setState(() => _frequency = v!),
                ),
              ),
            ],
          ),
          if (_perCycle > 0) ...[
            const SizedBox(height: 12),
            Text(
              "K ${_perCycle.toStringAsFixed(2)} per ${_frequency.toLowerCase()} × ${_cyclesCtrl.text} cycles",
              style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _isSubmitting ? null : _submitPledge,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
              minimumSize: const Size(double.infinity, 55),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
            child: _isSubmitting
                ? const CircularProgressIndicator(strokeWidth: 2, color: Colors.black)
                : const Text("COMMIT PLEDGE", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
      );

  Widget _buildPledgeCard(Pledge p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(p.category, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: p.isComplete ? Colors.green.withValues(alpha: 0.12) : Colors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  p.isComplete ? "FULFILLED" : p.status.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: p.isComplete ? Colors.green : Colors.amber.shade800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: p.progress,
            minHeight: 8,
            backgroundColor: Colors.grey.shade300,
            color: Colors.amber,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 8),
          Text(
            "K ${p.paidAmount.toStringAsFixed(2)} of K ${p.totalAmount.toStringAsFixed(2)}  •  ${p.cyclesPaid}/${p.installments} cycles",
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 12),
          ),
          const SizedBox(height: 12),
          if (!p.isComplete)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _payInstallment(p),
                icon: const Icon(LucideIcons.creditCard, size: 16, color: Colors.white),
                label: Text("PAY K ${p.amountPerCycle.toStringAsFixed(2)} INSTALLMENT", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
