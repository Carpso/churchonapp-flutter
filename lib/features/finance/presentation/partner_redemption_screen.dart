import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/providers/profile_provider.dart';
import '../data/partner_tenant_service.dart';

class PartnerRedemptionScreen extends ConsumerStatefulWidget {
  const PartnerRedemptionScreen({super.key});

  @override
  ConsumerState<PartnerRedemptionScreen> createState() => _PartnerRedemptionScreenState();
}

class _PartnerRedemptionScreenState extends ConsumerState<PartnerRedemptionScreen> {
  List<PartnerTenant> _partners = [];
  bool _isLoading = true;
  String _selectedCategory = 'all';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final svc = ref.read(partnerTenantServiceProvider);
    final partners = await svc.getPartnerTenants();
    if (mounted) {
      setState(() {
        _partners = partners;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);
    final userCoins = (profileAsync.value?.coins ?? 0).toInt();

    final filteredPartners = _selectedCategory == 'all'
        ? _partners
        : _partners.where((p) => p.type == _selectedCategory).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text("Partner Coin Rewards", style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Coin Balance Card
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1A1A1A), Color(0xFF333333)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                )
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFDA03),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(LucideIcons.coins, color: Colors.black, size: 28),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("YOUR REWARD BALANCE", style: TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                    const SizedBox(height: 4),
                    Text("$userCoins CC", style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
                  ],
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text("VASP Compliant", style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600)),
                )
              ],
            ),
          ),

          // Category Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _buildCategoryChip('all', 'All Partners', LucideIcons.store),
                _buildCategoryChip('bookshop', 'Bookshops', LucideIcons.bookOpen),
                _buildCategoryChip('coffee_shop', 'Coffee & Cafes', LucideIcons.coffee),
                _buildCategoryChip('restaurant', 'Restaurants', LucideIcons.utensils),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Partners List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredPartners.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(LucideIcons.store, size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text("No partner offers in this category yet", style: TextStyle(color: Colors.grey.shade600)),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: filteredPartners.length,
                          itemBuilder: (context, index) {
                            return _buildPartnerCard(filteredPartners[index], userCoins);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(String id, String label, IconData icon) {
    final isSelected = _selectedCategory == id;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: isSelected,
        label: Row(
          children: [
            Icon(icon, size: 14, color: isSelected ? Colors.black : Colors.grey.shade700),
            const SizedBox(width: 6),
            Text(label),
          ],
        ),
        selectedColor: const Color(0xFFFFDA03),
        backgroundColor: Theme.of(context).colorScheme.surface,
        onSelected: (val) => setState(() => _selectedCategory = id),
      ),
    );
  }

  Widget _buildPartnerCard(PartnerTenant partner, int userCoins) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFDA03).withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    partner.type == 'bookshop' ? LucideIcons.bookOpen : (partner.type == 'coffee_shop' ? LucideIcons.coffee : LucideIcons.store),
                    color: Colors.brown,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(partner.name, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 16)),
                      if (partner.location != null)
                        Text(partner.location!, style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
            if (partner.description != null) ...[
              const SizedBox(height: 10),
              Text(partner.description!, style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
            ],
            const Divider(height: 24),

            // Offers List
            FutureBuilder<List<PartnerOffer>>(
              future: ref.read(partnerTenantServiceProvider).getPartnerOffers(partner.id),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  );
                }
                final offers = snapshot.data!;
                if (offers.isEmpty) {
                  return const Text("No active offers currently.", style: TextStyle(fontSize: 12, color: Colors.grey));
                }
                return Column(
                  children: offers.map((offer) => _buildOfferTile(offer, partner, userCoins)).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfferTile(PartnerOffer offer, PartnerTenant partner, int userCoins) {
    final canAfford = userCoins >= offer.coinsRequired;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(offer.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                if (offer.description != null)
                  Text(offer.description!, style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                const SizedBox(height: 4),
                Text("${offer.coinsRequired} CC", style: const TextStyle(color: Colors.brown, fontWeight: FontWeight.bold, fontSize: 12)),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: canAfford ? () => _confirmRedeem(offer, partner) : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFDA03),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(canAfford ? "REDEEM" : "NEED COINS", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  void _confirmRedeem(PartnerOffer offer, PartnerTenant partner) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Redeem ${offer.title}"),
        content: Text("Spend ${offer.coinsRequired} Church Coins to claim this voucher at ${partner.name}?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFFDA03), foregroundColor: Colors.black),
            child: const Text("Redeem Now"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final voucherCode = await ref.read(partnerTenantServiceProvider).redeemOffer(
        offerId: offer.id,
        partnerId: partner.id,
        coinsRequired: offer.coinsRequired,
        offerTitle: offer.title,
      );

      ref.invalidate(profileProvider);

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(LucideIcons.checkCircle2, color: Colors.green),
                SizedBox(width: 8),
                Text("Redemption Successful! 🎉"),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Show this digital voucher code at ${partner.name}:"),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(
                    voucherCode,
                    style: GoogleFonts.firaCode(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Colors.brown),
                  ),
                ),
              ],
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Done"),
              ),
            ],
          ),
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
