import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import 'package:church_on_app/core/widgets/premium_toast.dart';
import 'package:church_on_app/features/events/data/event_ticketing_service.dart';
import 'package:church_on_app/features/give/presentation/lipila_payment_gateway.dart';
import 'package:church_on_app/features/modules/events/presentation/event_eticket_screen.dart';

/// Tier-based ticket purchase flow. Inventory + pricing are enforced by the
/// `reserve_event_tickets` RPC server-side — this screen never decides an
/// amount and never writes capacity itself.
class BuyTicketScreen extends ConsumerStatefulWidget {
  final String eventId;
  final String eventTitle;
  final String? organizerMomoPhone;
  final String? organizerMomoName;

  const BuyTicketScreen({
    super.key,
    required this.eventId,
    required this.eventTitle,
    this.organizerMomoPhone,
    this.organizerMomoName,
  });

  @override
  ConsumerState<BuyTicketScreen> createState() => _BuyTicketScreenState();
}

class _BuyTicketScreenState extends ConsumerState<BuyTicketScreen> {
  String? _selectedTierId;
  int _quantity = 1;
  bool _purchasing = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inventoryAsync = ref.watch(eventTicketInventoryProvider(widget.eventId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Get Tickets', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: inventoryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.alertTriangle, size: 48, color: Colors.orange),
                const SizedBox(height: 12),
                Text('Could not load tickets.\n$e', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => ref.invalidate(eventTicketInventoryProvider(widget.eventId)),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (inv) {
          final tiers = inv.tiers.where((t) => t.isActive).toList();
          if (tiers.isEmpty) {
            return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Tickets are not on sale yet.')));
          }
          final selected = tiers.firstWhere(
            (t) => t.id == _selectedTierId,
            orElse: () => tiers.first,
          );
          if (_selectedTierId == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _selectedTierId = selected.id);
            });
          }
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (inv.capacity > 0)
                      _CapacityBanner(inv: inv),
                    const SizedBox(height: 8),
                    ...tiers.map((t) => _TierCard(
                          tier: t,
                          selected: t.id == selected.id,
                          onTap: t.isSoldOut || !t.salesOpen
                              ? null
                              : () => setState(() {
                                    _selectedTierId = t.id;
                                    _quantity = 1;
                                  }),
                        )),
                    if (inv.soldOut) ...[
                      const SizedBox(height: 12),
                      _SoldOutCard(
                        waitlisted: false,
                        onWaitlist: _joinWaitlist,
                      ),
                    ],
                  ],
                ),
              ),
              _buildFooter(theme, inv, selected),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFooter(ThemeData theme, TicketInventory inv, EventTicketTier tier) {
    final maxQty = [
      tier.maxPerOrder,
      if (tier.remaining != null) tier.remaining!,
    ].reduce((a, b) => a < b ? a : b).clamp(0, 100).toInt();
    if (_quantity > maxQty && maxQty > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _quantity = maxQty);
      });
    }
    final canBuy = tier.salesOpen && !tier.isSoldOut && maxQty > 0;
    final total = tier.price * _quantity;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, -4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text('Quantity', style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                onPressed: canBuy && _quantity > 1 ? () => setState(() => _quantity--) : null,
                icon: const Icon(LucideIcons.minusCircle),
              ),
              Text('$_quantity', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              IconButton(
                onPressed: canBuy && _quantity < maxQty ? () => setState(() => _quantity++) : null,
                icon: const Icon(LucideIcons.plusCircle),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Total', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  Text(
                    total == 0 ? 'FREE' : 'K${total.toStringAsFixed(2)}',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              const Spacer(),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: (!canBuy || _purchasing) ? null : () => _purchase(tier, total),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.secondary,
                    minimumSize: const Size(double.infinity, 54),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  child: _purchasing
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(tier.isSoldOut ? 'SOLD OUT' : 'PURCHASE', style: TextStyle(color: theme.colorScheme.onSecondary, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _joinWaitlist() async {
    try {
      await ref.read(eventTicketingServiceProvider).joinWaitlist(
            eventId: widget.eventId,
            tierId: _selectedTierId,
          );
      if (!mounted) return;
      PremiumToast.showSuccess(context, "You're on the waitlist. We'll notify you if tickets free up.", title: 'Waitlisted');
      ref.invalidate(eventTicketInventoryProvider(widget.eventId));
    } catch (e) {
      if (!mounted) return;
      PremiumToast.showError(context, e.toString(), title: 'Waitlist');
    }
  }

  Future<void> _purchase(EventTicketTier tier, double total) async {
    if (tier.price <= 0) {
      await _reserve(tier, null);
      return;
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => LipilaPaymentGateway(
        amount: total,
        description: 'Ticket: ${widget.eventTitle}',
        category: 'event',
        recipientName: widget.organizerMomoName ?? 'Event Host',
        recipientAccount: widget.organizerMomoPhone,
        paymentReason: 'Ticket: ${widget.eventTitle}',
        onComplete: (success, txId) async {
          Navigator.pop(sheetCtx);
          if (!success) return;
          await _reserve(tier, txId);
        },
      ),
    );
  }

  Future<void> _reserve(EventTicketTier tier, String? paymentRef) async {
    setState(() => _purchasing = true);
    try {
      final res = await ref.read(eventTicketingServiceProvider).reserve(
            eventId: widget.eventId,
            tierId: tier.id,
            quantity: _quantity,
            paymentRef: paymentRef,
          );
      ref.invalidate(eventTicketInventoryProvider(widget.eventId));
      if (!mounted) return;
      setState(() => _purchasing = false);
      final paid = res['status'] == 'paid';
      PremiumToast.showSuccess(
        context,
        paid
            ? 'Your ticket${_quantity > 1 ? 's are' : ' is'} confirmed. Open My Tickets for the QR code.'
            : 'Tickets reserved — confirming your payment. They will activate automatically.',
        title: paid ? 'Ticket Purchased!' : 'Payment Pending',
      );
      final orderId = res['order_id']?.toString();
      if (orderId != null) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EventEticketScreen(
              ticketId: '',
              orderId: orderId,
              eventTitle: widget.eventTitle,
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _purchasing = false);
      PremiumToast.showError(context, e.toString(), title: 'Purchase Failed');
    }
  }
}

class _CapacityBanner extends StatelessWidget {
  final TicketInventory inv;
  const _CapacityBanner({required this.inv});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final low = inv.remaining > 0 && inv.remaining <= 20;
    final color = inv.soldOut ? Colors.red : (low ? Colors.orange : Colors.green);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Icon(inv.soldOut ? LucideIcons.xCircle : LucideIcons.flame, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              inv.soldOut
                  ? 'SOLD OUT'
                  : (low ? 'Only ${inv.remaining} left!' : '${inv.remaining} of ${inv.capacity} tickets remaining'),
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _TierCard extends StatelessWidget {
  final EventTicketTier tier;
  final bool selected;
  final VoidCallback? onTap;
  const _TierCard({required this.tier, required this.selected, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disabled = onTap == null;
    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? theme.colorScheme.secondary : Colors.grey.withValues(alpha: 0.2),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tier.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    if (tier.description != null && tier.description!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(tier.description!, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (tier.quantityTotal != null)
                          Text(
                            tier.isSoldOut ? 'Sold out' : '${tier.remaining} left',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: tier.isSoldOut ? Colors.red : Colors.green,
                            ),
                          ),
                        if (tier.salesEnd != null) ...[
                          const SizedBox(width: 10),
                          Text('Ends ${DateFormat.MMMd().format(tier.salesEnd!)}',
                              style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Text(
                tier.price == 0 ? 'FREE' : 'K${tier.price.toStringAsFixed(2)}',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SoldOutCard extends StatelessWidget {
  final bool waitlisted;
  final VoidCallback onWaitlist;
  const _SoldOutCard({required this.waitlisted, required this.onWaitlist});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          const Icon(LucideIcons.ticket, color: Colors.red, size: 36),
          const SizedBox(height: 8),
          const Text('This event is sold out', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Join the waitlist and we will notify you if a ticket is released.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: waitlisted ? null : onWaitlist,
            icon: const Icon(LucideIcons.bell, size: 16),
            label: Text(waitlisted ? 'ON WAITLIST' : 'JOIN WAITLIST'),
          ),
        ],
      ),
    );
  }
}
