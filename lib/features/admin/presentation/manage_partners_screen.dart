import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../finance/data/partner_tenant_service.dart';

class ManagePartnersScreen extends ConsumerStatefulWidget {
  const ManagePartnersScreen({super.key});

  @override
  ConsumerState<ManagePartnersScreen> createState() => _ManagePartnersScreenState();
}

class _ManagePartnersScreenState extends ConsumerState<ManagePartnersScreen> {
  List<PartnerTenant> _partners = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPartners();
  }

  Future<void> _loadPartners() async {
    setState(() => _isLoading = true);
    final svc = ref.read(partnerTenantServiceProvider);
    final list = await svc.getPartnerTenants();
    if (mounted) {
      setState(() {
        _partners = list;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Manage Partner Tenants", style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.plusCircle),
            onPressed: _showAddPartnerDialog,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _partners.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(LucideIcons.store, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      const Text("No partner tenants registered yet"),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _showAddPartnerDialog,
                        icon: const Icon(LucideIcons.plus),
                        label: const Text("Add First Partner"),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _partners.length,
                  itemBuilder: (context, index) {
                    final partner = _partners[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFFFFDA03).withValues(alpha: 0.2),
                          child: Icon(
                            partner.type == 'bookshop' ? LucideIcons.bookOpen : (partner.type == 'coffee_shop' ? LucideIcons.coffee : LucideIcons.store),
                            color: Colors.brown,
                          ),
                        ),
                        title: Text(partner.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("${partner.type.toUpperCase()} • ${partner.location ?? 'No location'}"),
                        trailing: IconButton(
                          icon: Icon(LucideIcons.plusSquare, color: Theme.of(context).primaryColor),
                          tooltip: "Add Offer",
                          onPressed: () => _showAddOfferDialog(partner),
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  void _showAddPartnerDialog() async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final locCtrl = TextEditingController();
    String partnerType = 'bookshop';

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("Add COA Partner Tenant"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: "Partner Name", hintText: "e.g. Grace Coffee Shop")),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: partnerType,
                  items: const [
                    DropdownMenuItem(value: 'bookshop', child: Text("Bookshop")),
                    DropdownMenuItem(value: 'coffee_shop', child: Text("Coffee Shop")),
                    DropdownMenuItem(value: 'restaurant', child: Text("Restaurant")),
                    DropdownMenuItem(value: 'other', child: Text("Other Retail")),
                  ],
                  onChanged: (v) => setDialogState(() => partnerType = v ?? 'bookshop'),
                  decoration: const InputDecoration(labelText: "Partner Category"),
                ),
                const SizedBox(height: 12),
                TextField(controller: locCtrl, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: "Location", hintText: "e.g. East Park Mall, Lusaka")),
                const SizedBox(height: 12),
                TextField(controller: descCtrl, maxLines: 2, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: "Description", hintText: "Brief partner description")),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Save Partner"),
            ),
          ],
        ),
      ),
    );

    if (result == true && nameCtrl.text.trim().isNotEmpty) {
      try {
        await ref.read(partnerTenantServiceProvider).createPartnerTenant(
          name: nameCtrl.text.trim(),
          type: partnerType,
          description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
          location: locCtrl.text.trim().isEmpty ? null : locCtrl.text.trim(),
        );
        _loadPartners();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Partner tenant added!"), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  void _showAddOfferDialog(PartnerTenant partner) async {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final coinsCtrl = TextEditingController(text: "500");

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Add Offer for ${partner.name}"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: "Offer Title", hintText: "e.g. K50 Voucher")),
              const SizedBox(height: 12),
              TextField(controller: coinsCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Coins Required (CC)", hintText: "500")),
              const SizedBox(height: 12),
              TextField(controller: descCtrl, maxLines: 2, decoration: const InputDecoration(labelText: "Description", hintText: "Details on offer redemption")),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Save Offer"),
          ),
        ],
      ),
    );

    if (result == true && titleCtrl.text.trim().isNotEmpty) {
      final coins = int.tryParse(coinsCtrl.text.trim()) ?? 500;
      try {
        await ref.read(partnerTenantServiceProvider).createPartnerOffer(
          partnerId: partner.id,
          title: titleCtrl.text.trim(),
          coinsRequired: coins,
          description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Partner offer added!"), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
          );
        }
      }
    }
  }
}
