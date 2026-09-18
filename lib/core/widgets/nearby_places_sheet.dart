import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../config/app_constants.dart';
import '../services/nearby_places_service.dart';

/// Bottom-sheet "Nearby" search. Returns the tapped [NearbyPlace] or null.
Future<NearbyPlace?> showNearbyPlacesSheet(
  BuildContext context, {
  required LatLng center,
  double radiusMeters = 2000,
  NearbyCategory? initialCategory,
}) {
  return showModalBottomSheet<NearbyPlace>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _NearbyPlacesSheet(
      center: center,
      radiusMeters: radiusMeters,
      initialCategory: initialCategory,
    ),
  );
}

IconData nearbyCategoryIcon(NearbyCategory category) {
  switch (category) {
    case NearbyCategory.fuel:
      return LucideIcons.fuel;
    case NearbyCategory.restaurant:
      return LucideIcons.utensilsCrossed;
    case NearbyCategory.cafe:
      return LucideIcons.coffee;
    case NearbyCategory.bank:
      return LucideIcons.landmark;
    case NearbyCategory.hospital:
      return LucideIcons.stethoscope;
    case NearbyCategory.supermarket:
      return LucideIcons.shoppingCart;
    case NearbyCategory.hotel:
      return LucideIcons.bedDouble;
    case NearbyCategory.church:
      return LucideIcons.church;
    case NearbyCategory.police:
      return LucideIcons.shield;
    case NearbyCategory.busStation:
      return LucideIcons.bus;
    case NearbyCategory.parking:
      return LucideIcons.parkingSquare;
  }
}

String formatNearbyDistance(double km) {
  if (km < 1) return '${(km * 1000).round()} m';
  return '${km.toStringAsFixed(km < 10 ? 1 : 0)} km';
}

class _NearbyPlacesSheet extends ConsumerStatefulWidget {
  const _NearbyPlacesSheet({
    required this.center,
    required this.radiusMeters,
    this.initialCategory,
  });

  final LatLng center;
  final double radiusMeters;
  final NearbyCategory? initialCategory;

  @override
  ConsumerState<_NearbyPlacesSheet> createState() => _NearbyPlacesSheetState();
}

class _NearbyPlacesSheetState extends ConsumerState<_NearbyPlacesSheet> {
  NearbyCategory? _category;

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = (
      lat: widget.center.latitude,
      lng: widget.center.longitude,
      radiusMeters: widget.radiusMeters,
      category: _category,
    );
    final async = ref.watch(nearbyPlacesProvider(query));

    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Icon(LucideIcons.compass, color: theme.primaryColor, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Nearby places',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                Text(
                  'within ${(widget.radiusMeters / 1000).toStringAsFixed(0)} km',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _chip(theme, null, 'All'),
                for (final c in NearbyCategory.values)
                  _chip(theme, c, c.label, icon: nearbyCategoryIcon(c)),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: async.when(
              loading: () => Center(
                child: CircularProgressIndicator(color: theme.primaryColor),
              ),
              error: (e, _) => _message(
                theme,
                LucideIcons.wifiOff,
                'Could not load places nearby',
                'Check your connection and try again.',
              ),
              data: (places) {
                if (places.isEmpty) {
                  return _message(
                    theme,
                    LucideIcons.mapPinOff,
                    'No places found',
                    'Try another category or a wider area.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(nearbyPlacesProvider),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                    itemCount: places.length,
                    itemBuilder: (context, i) => _tile(theme, places[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(ThemeData theme, NearbyCategory? category, String label,
      {IconData? icon}) {
    final selected = _category == category;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: selected,
        showCheckmark: false,
        avatar: icon != null
            ? Icon(icon,
                size: 15,
                color: selected ? AppConstants.primaryDark : theme.primaryColor)
            : null,
        label: Text(label, style: const TextStyle(fontSize: 12)),
        labelStyle: TextStyle(
          color: selected ? AppConstants.primaryDark : theme.colorScheme.onSurface,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        ),
        backgroundColor: theme.cardColor,
        selectedColor: AppConstants.sunflowerYellow,
        onSelected: (_) => setState(() => _category = category),
      ),
    );
  }

  Widget _tile(ThemeData theme, NearbyPlace place) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).pop(place),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: theme.primaryColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(nearbyCategoryIcon(place.category),
                    size: 20, color: theme.primaryColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      place.address ?? place.category.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                formatNearbyDistance(place.distanceKm),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: theme.primaryColor,
                ),
              ),
              const SizedBox(width: 4),
              Icon(LucideIcons.chevronRight,
                  size: 18, color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _message(
      ThemeData theme, IconData icon, String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 42, color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
            const SizedBox(height: 14),
            Text(title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
