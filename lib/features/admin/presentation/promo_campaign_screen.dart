import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import 'package:church_on_app/core/services/supabase_service.dart';
import 'package:church_on_app/core/widgets/premium_toast.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import '../data/promo_service.dart';

class PromoCampaignScreen extends ConsumerStatefulWidget {
  const PromoCampaignScreen({super.key});

  @override
  ConsumerState<PromoCampaignScreen> createState() => _PromoCampaignScreenState();
}

class _PromoCampaignScreenState extends ConsumerState<PromoCampaignScreen> {
  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);
    return profileAsync.when(
      data: (profile) {
        if (profile == null || !(profile.isSuperadmin || profile.isEmployee)) {
          return Scaffold(
            appBar: AppBar(title: const Text('Promo Campaigns')),
            body: const Center(child: Text('Access denied. Superadmin or COA employee access required.')),
          );
        }
        return _buildContent(context);
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Promo Campaigns')),
        body: Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final campaignsAsync = ref.watch(allPromoCampaignsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Promo Campaigns'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.plus),
            onPressed: () => _showCampaignDialog(null),
          ),
        ],
      ),
      body: campaignsAsync.when(
        data: (campaigns) => campaigns.isEmpty
            ? const Center(child: Text('No campaigns yet. Tap + to create one.'))
            : ListView.builder(
                itemCount: campaigns.length,
                itemBuilder: (context, index) {
                  final c = campaigns[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ListTile(
                          leading: Icon(
                            c.campaignType == 'referral' ? LucideIcons.users :
                            c.campaignType == 'registration_bonus' ? LucideIcons.gift :
                            c.campaignType == 'promo_code' ? LucideIcons.tag :
                            c.campaignType == 'seasonal' ? LucideIcons.calendar :
                            LucideIcons.megaphone,
                            color: Colors.amber, size: 32,
                          ),
                          title: Text(c.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${c.campaignType}${c.promoCode != null ? ' — ${c.promoCode}' : ''}'),
                              if (c.isRedeemable)
                                const Text('Active', style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold))
                              else
                                Text(c.isExpired ? 'Expired' : c.isFullyRedeemed ? 'Fully Redeemed' : 'Inactive',
                                  style: const TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('${c.currentRedemptions}${c.maxRedemptions != null ? '/${c.maxRedemptions}' : ''}',
                                style: const TextStyle(fontSize: 12)),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(LucideIcons.pencil, size: 18),
                                onPressed: () => _showCampaignDialog(c),
                              ),
                            ],
                          ),
                        ),
                        if (c.description != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: Text(c.description!, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                          ),
                        if (c.bonusCoins > 0 || c.discountAmountZmw != null || c.budgetZmw != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: Wrap(
                              spacing: 8,
                              children: [
                                if (c.bonusCoins > 0)
                                  _chip('${c.bonusCoins} CC', Colors.amber),
                                if (c.discountAmountZmw != null)
                                  _chip('K${c.discountAmountZmw!.toStringAsFixed(0)} off', Colors.green),
                                if (c.budgetZmw != null)
                                  _chip('K${c.budgetZmw!.toStringAsFixed(0)} budget', Colors.blue),
                              ],
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
        loading: () => const Center(child: ListSkeleton()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  void _showCampaignDialog(PromoCampaign? existing) {
    final titleC = TextEditingController(text: existing?.title);
    final descC = TextEditingController(text: existing?.description ?? '');
    final codeC = TextEditingController(text: existing?.promoCode ?? '');
    final urlC = TextEditingController(text: existing?.targetUrl ?? '');
    final imgC = TextEditingController(text: existing?.imageUrl ?? '');
    String type = existing?.campaignType ?? 'promo_code';
    String placement = existing?.placement ?? 'home';
    int bonusCoins = existing?.bonusCoins ?? 0;
    double discountZmw = existing?.discountAmountZmw ?? 0;
    double budgetZmw = existing?.budgetZmw ?? 0;
    int maxRedemptions = existing?.maxRedemptions ?? 0;
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(existing == null ? 'New Campaign' : 'Edit Campaign'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: titleC, decoration: const InputDecoration(labelText: 'Title'), textCapitalization: TextCapitalization.sentences),
                TextField(controller: descC, decoration: const InputDecoration(labelText: 'Description'), maxLines: 2, textCapitalization: TextCapitalization.sentences),
                DropdownButtonFormField(
                  initialValue: type,
                  items: const [
                    DropdownMenuItem(value: 'referral', child: Text('Referral Program')),
                    DropdownMenuItem(value: 'registration_bonus', child: Text('Registration Bonus')),
                    DropdownMenuItem(value: 'promo_code', child: Text('Promo Code')),
                    DropdownMenuItem(value: 'seasonal', child: Text('Seasonal Campaign')),
                    DropdownMenuItem(value: 'ad_campaign', child: Text('Ad Campaign')),
                  ],
                  onChanged: (v) => setState(() => type = v!),
                  decoration: const InputDecoration(labelText: 'Campaign Type'),
                ),
                TextField(controller: codeC, decoration: const InputDecoration(labelText: 'Promo Code (optional)'), textCapitalization: TextCapitalization.characters),
                TextField(controller: imgC, decoration: const InputDecoration(labelText: 'Image URL'), keyboardType: TextInputType.url),
                TextField(controller: urlC, decoration: const InputDecoration(labelText: 'Target URL'), keyboardType: TextInputType.url),
                DropdownButtonFormField(
                  initialValue: placement,
                  items: const ['home', 'quiz', 'events', 'marketplace', 'all'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (v) => setState(() => placement = v!),
                  decoration: const InputDecoration(labelText: 'Placement'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: TextField(
                      controller: TextEditingController(text: bonusCoins.toString()),
                      decoration: const InputDecoration(labelText: 'Bonus Coins', isDense: true),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => bonusCoins = int.tryParse(v) ?? 0,
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(
                      controller: TextEditingController(text: discountZmw > 0 ? discountZmw.toStringAsFixed(0) : ''),
                      decoration: const InputDecoration(labelText: 'Discount (ZMW)', isDense: true),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => discountZmw = double.tryParse(v) ?? 0,
                    )),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: TextField(
                      controller: TextEditingController(text: budgetZmw > 0 ? budgetZmw.toStringAsFixed(0) : ''),
                      decoration: const InputDecoration(labelText: 'Budget (ZMW)', isDense: true),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => budgetZmw = double.tryParse(v) ?? 0,
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(
                      controller: TextEditingController(text: maxRedemptions > 0 ? maxRedemptions.toString() : ''),
                      decoration: const InputDecoration(labelText: 'Max Redemptions', isDense: true),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => maxRedemptions = int.tryParse(v) ?? 0,
                    )),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: isSubmitting ? null : () async {
                setState(() => isSubmitting = true);
                try {
                  final userId = ref.read(supabaseServiceProvider).client.auth.currentUser?.id ?? '';
                  final data = {
                    'title': titleC.text,
                    'description': descC.text.isNotEmpty ? descC.text : null,
                    'campaign_type': type,
                    'promo_code': codeC.text.isNotEmpty ? codeC.text.toUpperCase() : null,
                    'bonus_coins': bonusCoins > 0 ? bonusCoins : null,
                    'discount_amount_zmw': discountZmw > 0 ? discountZmw : null,
                    'budget_zmw': budgetZmw > 0 ? budgetZmw : null,
                    'max_redemptions': maxRedemptions > 0 ? maxRedemptions : null,
                    'placement': placement,
                    'image_url': imgC.text.isNotEmpty ? imgC.text : null,
                    'target_url': urlC.text.isNotEmpty ? urlC.text : null,
                    'is_active': true,
                    'created_by': userId,
                  };
                  if (existing == null) {
                    await ref.read(promoServicesProvider).createCampaign(data);
                  } else {
                    await ref.read(promoServicesProvider).updateCampaign(existing.id, data);
                  }
                  ref.invalidate(allPromoCampaignsProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (ctx.mounted) PremiumToast.showSuccess(ctx, existing == null ? 'Campaign created!' : 'Campaign updated!');
                } catch (e) {
                  if (!ctx.mounted) return;
                  PremiumToast.showError(ctx, 'Failed: $e');
                } finally {
                  setState(() => isSubmitting = false);
                }
              },
              child: isSubmitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(existing == null ? 'Create' : 'Update'),
            ),
          ],
        ),
      ),
    );
  }
}
