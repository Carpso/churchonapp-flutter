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
  final void Function(String driverId) onDriverSelected;

  const VehicleSelectionSheet({
    super.key,
    required this.pickupLatLng,
    required this.destLatLng,
    required this.onRequestRide,
    required this.onDriverSelected,
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
    if (amount == amount.roundToDouble() && amount < 10000) {
      return "K ${amount.toInt()}";
    }
    final formatted = amount.toStringAsFixed(2);
    final parts = formatted.split('.');
    final intPart = parts[0].replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    return "K $intPart.${parts[1]}";
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pricing = ref.watch(ridePricingProvider);
    final driversAsync = ref.watch(activeDriversStreamProvider);

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
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildFareCard(context, ref, pricing, theme),
          const SizedBox(height: 20),
          _buildRequestButton(context, ref, pricing, driversAsync, theme),
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

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.1)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "ESTIMATED FARE",
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    pricing.selectedCategory == 'bus'
                        ? "Shared Bus Route Ride"
                        : (pricing.selectedCategory == 'marketplace' ||
                                pricing.selectedCategory == 'bookshop')
                            ? "Cargo Delivery"
                            : "Standard Carpso Ride",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    desc,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatZmw(pricing.totalPayable),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                  Text(
                    "${formatZmw(pricing.displayPrice)} + ${formatZmw(pricing.platformFee)} fee",
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.primaryColor.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (pricing.distanceKm != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(LucideIcons.ruler, size: 12, color: theme.primaryColor),
                const SizedBox(width: 4),
                Text(
                  "${pricing.distanceKm!.toStringAsFixed(1)} km",
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
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
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            controller: _promoCodeController,
          ),
        ],
      ),
    );
  }

  Widget _buildRequestButton(
    BuildContext context,
    WidgetRef ref,
    RidePricingState pricing,
    AsyncValue<List<RideRegistration>> driversAsync,
    ThemeData theme,
  ) {
    return driversAsync.when(
      data: (drivers) {
        final isDelivery = pricing.selectedCategory == 'marketplace' ||
            pricing.selectedCategory == 'bookshop';

        return ElevatedButton(
          onPressed: drivers.isEmpty
              ? null
              : () => _showDriverSelection(context, ref, drivers, isDelivery, theme),
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.primaryColor,
            minimumSize: const Size(double.infinity, 65),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
            elevation: 8,
            shadowColor: theme.primaryColor.withValues(alpha: 0.5),
          ),
          child: Text(
            isDelivery ? "REQUEST CARGO DELIVERY" : "REQUEST CARPSO RIDE",
            style: TextStyle(
              color: theme.colorScheme.onSecondary,
              fontWeight: FontWeight.w900,
              fontSize: 14,
              letterSpacing: 1.5,
            ),
          ),
        );
      },
      loading: () => const SizedBox(
        height: 65,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => const SizedBox.shrink(),
    );
  }

  void _showDriverSelection(
    BuildContext context,
    WidgetRef ref,
    List<RideRegistration> drivers,
    bool isDelivery,
    ThemeData theme,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _DriverListContent(
        drivers: drivers,
        isDelivery: isDelivery,
        onDriverSelected: (driverId) {
          Navigator.pop(ctx);
          widget.onDriverSelected(driverId);
        },
      ),
    );
  }
}

class _DriverListContent extends StatelessWidget {
  final List<RideRegistration> drivers;
  final bool isDelivery;
  final ValueChanged<String> onDriverSelected;

  const _DriverListContent({
    required this.drivers,
    required this.isDelivery,
    required this.onDriverSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final driverType = isDelivery ? 'Courier' : 'Carpso Ride Driver';

    return Container(
      height: MediaQuery.of(context).size.height * 0.5,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 15),
            width: 50,
            height: 5,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 25),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Available ${driverType}s",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                Text(
                  "${drivers.length} Nearby",
                  style: TextStyle(
                    color: theme.primaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Divider(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: drivers.length,
              itemBuilder: (context, index) {
                final driver = drivers[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(15),
                    leading: CircleAvatar(
                      backgroundColor: theme.primaryColor.withValues(alpha: 0.1),
                      child: Icon(LucideIcons.user, color: theme.primaryColor),
                    ),
                    title: Text(
                      "$driverType #${index + 1}",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(driver.vehicleInfo ?? 'Standard Vehicle'),
                    trailing: ElevatedButton(
                      onPressed: () => onDriverSelected(driver.userId),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.primaryColor,
                        foregroundColor: theme.colorScheme.onSecondary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        "SELECT",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
