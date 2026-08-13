import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:latlong2/latlong.dart';
import 'package:church_on_app/features/transport/data/ride_pricing_provider.dart';
import 'package:church_on_app/features/transport/data/transport_service.dart';
import 'package:church_on_app/features/admin/data/promo_service.dart';

class VehicleSelectionSheet extends ConsumerStatefulWidget {
  final LatLng pickupLatLng;
  final LatLng destLatLng;
  final VoidCallback onRequestRide;

  const VehicleSelectionSheet({
    super.key,
    required this.pickupLatLng,
    required this.destLatLng,
    required this.onRequestRide,
  });

  @override
  ConsumerState<VehicleSelectionSheet> createState() => _VehicleSelectionSheetState();
}

class _VehicleSelectionSheetState extends ConsumerState<VehicleSelectionSheet> {
  final _promoCodeController = TextEditingController();

  @override
  void dispose() {
    _promoCodeController.dispose();
    super.dispose();
  }

  static String formatZmw(double amount) {
    if (amount == amount.roundToDouble() && amount < 1000) {
      return "K ${amount.toInt()}";
    }
    return "K ${amount.toStringAsFixed(2)}";
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pricing = ref.watch(ridePricingProvider);

    if (pricing.isCalculating) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: theme.primaryColor),
              const SizedBox(height: 16),
              Text(
                "Calculating best fare...",
                style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
              ),
            ],
          ),
        ),
      );
    }

    if (pricing.estimatedPrice == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [theme.colorScheme.surface, theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 30, offset: const Offset(0, -5))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildFareCard(context, ref, pricing, theme),
          const SizedBox(height: 20),
          _buildRequestButton(context, ref, pricing, theme),
        ],
      ),
    );
  }

  Widget _buildFareCard(
    BuildContext context,
    WidgetRef ref,
    RidePricingState pricing,
    ThemeData theme,
  ) {
    final desc = pricing.selectedCategory == 'bus'
        ? 'Find a Bus Route'
        : (pricing.selectedCategory == 'marketplace')
            ? 'Deliver Goods'
            : (pricing.selectedCategory == 'bookshop')
                ? 'Book Delivery'
                : 'Personal Transport';

    final isDelivery = pricing.selectedCategory == 'marketplace' ||
        pricing.selectedCategory == 'bookshop';
    final baseFare = isDelivery ? kDeliveryDefaultBaseFare : kCarpsoDefaultBaseFare;
    final perKmRate = isDelivery ? kDeliveryPerKmRate : kCarpsoPerKmRate;
    final distance = pricing.distanceKm;
    final tripMinutes = distance != null ? (distance / kCarpsoCitySpeedKmh * 60).ceil() : null;

    final driversAsync = ref.watch(activeDriversStreamProvider);
    double? nearestDriverKm;
    if (distance != null) {
      final drivers = driversAsync.value ?? const [];
      for (final d in drivers) {
        final dKm = const Distance()
            .as(LengthUnit.Kilometer, widget.pickupLatLng, LatLng(d.lat, d.lng));
        if (nearestDriverKm == null || dKm < nearestDriverKm) {
          nearestDriverKm = dKm;
        }
      }
    }
    final driverPickupMinutes = nearestDriverKm != null
        ? (nearestDriverKm / 30.0 * 60).ceil()
        : null;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [const Color(0xFF1E293B), const Color(0xFF0F172A)],
        ),
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: theme.primaryColor.withValues(alpha: 0.15), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "ESTIMATED FARE",
                      style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      pricing.selectedCategory == 'bus'
                          ? "Shared Bus Route Ride"
                          : (pricing.selectedCategory == 'marketplace' || pricing.selectedCategory == 'bookshop')
                              ? "Cargo Delivery"
                              : "Standard Carpso Ride",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(desc, style: const TextStyle(fontSize: 11, color: Colors.white54)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(formatZmw(pricing.totalPayable), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.amberAccent), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const Text("incl. processing fee", style: TextStyle(fontSize: 11, color: Colors.white38)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _infoChip(theme, "Base K${baseFare.toStringAsFixed(0)}", LucideIcons.tag),
              if (distance != null)
                _infoChip(theme,
                    "K${perKmRate.toStringAsFixed(0)}/km × ${distance.toStringAsFixed(1)} km",
                    LucideIcons.ruler),
              if (isDelivery)
                _infoChip(theme, "Fixed fare · No negotiation", LucideIcons.lock)
              else
                _infoChip(theme, "Negotiable with driver", LucideIcons.messageSquare),
              if (tripMinutes != null)
                _infoChip(theme, "~$tripMinutes min trip", LucideIcons.clock),
              if (driverPickupMinutes != null)
                _infoChip(theme, "Nearest driver ~$driverPickupMinutes min away",
                    LucideIcons.navigation),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(LucideIcons.sparkles, color: theme.primaryColor, size: 14),
              const SizedBox(width: 8),
              Text(
                "Includes Prayer Mode & Security",
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            decoration: InputDecoration(
              hintText: "Enter promo code",
              prefixIcon: const Icon(LucideIcons.tag, size: 18),
              suffixIcon: TextButton(
                onPressed: () async {
                  final code = _promoCodeController.text.trim();
                  if (code.isEmpty) return;
                  final promo = await ref.read(promoServicesProvider).getByPromoCode(code);
                  if (promo == null) {
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid or expired promo code")));
                    return;
                  }
                  if (promo.discountPercent != null) {
                    ref.read(ridePricingProvider.notifier).applyDiscount(promo.discountPercent!);
                  } else if (promo.discountAmountZmw != null) {
                    ref.read(ridePricingProvider.notifier).applyFlatDiscount(promo.discountAmountZmw!);
                  }
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Promo applied! ${promo.discountPercent ?? promo.discountAmountZmw}% off")));
                  _promoCodeController.clear();
                },
                child: const Text("Apply", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            controller: _promoCodeController,
          ),
        ],
      ),
    );
  }

  Widget _infoChip(ThemeData theme, String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.amberAccent),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _buildRequestButton(
    BuildContext context,
    WidgetRef ref,
    RidePricingState pricing,
    ThemeData theme,
  ) {
    final isDelivery = pricing.selectedCategory == 'marketplace' ||
        pricing.selectedCategory == 'bookshop';

    return ElevatedButton(
      onPressed: () => widget.onRequestRide(),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.amberAccent,
        foregroundColor: Colors.black,
        minimumSize: const Size(double.infinity, 65),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        elevation: 10,
        shadowColor: Colors.amberAccent.withValues(alpha: 0.4),
      ),
      child: Text(
        isDelivery ? "REQUEST CARGO DELIVERY" : "REQUEST CARPSO RIDE",
        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1.5, color: Colors.black),
      ),
    );
  }
}
