import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:church_on_app/core/config/fee_config.dart';
import 'package:church_on_app/core/config/remote_config.dart';

class RidePricingState {
  final bool isCalculating;
  final double? estimatedPrice;
  final double? offeredFare;
  final bool isNegotiating;
  final String selectedCategory;
  final String selectedWeight;
  final double? distanceKm;
  final int discountPercent;
  final double flatDiscount;

  const RidePricingState({
    this.isCalculating = false,
    this.estimatedPrice,
    this.offeredFare,
    this.isNegotiating = false,
    this.selectedCategory = 'people',
    this.selectedWeight = 'Light',
    this.distanceKm,
    this.discountPercent = 0,
    this.flatDiscount = 0,
  });

  double get displayPrice {
    final isDelivery = selectedCategory == 'marketplace' ||
        selectedCategory == 'bookshop';
    // Delivery fees are fixed — offers/negotiation only apply to rides.
    final base = !isDelivery && isNegotiating && offeredFare != null
        ? offeredFare!
        : estimatedPrice ?? 0;
    if (discountPercent > 0) return base * (1 - discountPercent / 100);
    if (flatDiscount > 0) return (base - flatDiscount).clamp(0, base);
    return base;
  }

  // Platform fee = 1% COA + Lipila fees (shown to rider)
  // Business cut (10%) is deducted from driver at settlement
  double platformFee(FeeConfig fees) => fees.platformFee(displayPrice);

  double totalPayable(FeeConfig fees) => displayPrice + platformFee(fees);

  RidePricingState copyWith({
    bool? isCalculating,
    double? estimatedPrice,
    double? offeredFare,
    bool? isNegotiating,
    String? selectedCategory,
    String? selectedWeight,
    double? distanceKm,
    int? discountPercent,
    double? flatDiscount,
    bool clearOffer = false,
    bool clearDiscount = false,
  }) {
    return RidePricingState(
      isCalculating: isCalculating ?? this.isCalculating,
      estimatedPrice: estimatedPrice ?? this.estimatedPrice,
      offeredFare: clearOffer ? null : (offeredFare ?? this.offeredFare),
      isNegotiating: clearOffer ? false : (isNegotiating ?? this.isNegotiating),
      selectedCategory: selectedCategory ?? this.selectedCategory,
      selectedWeight: selectedWeight ?? this.selectedWeight,
      distanceKm: distanceKm ?? this.distanceKm,
      discountPercent: clearDiscount ? 0 : (discountPercent ?? this.discountPercent),
      flatDiscount: clearDiscount ? 0 : (flatDiscount ?? this.flatDiscount),
    );
  }
}

/// Per-kilometre Carpso rate (K5/km — well-known standard rate).
const double kCarpsoPerKmRate = 5.0;

/// Delivery per-km rate benchmarked against Yango delivery (Zambia market).
const double kDeliveryPerKmRate = 8.0;

/// Average city speed used for trip-time estimates (km/h).
const double kCarpsoCitySpeedKmh = 25.0;

/// Default base fare applied when no remote config exists (K10).
const double kCarpsoDefaultBaseFare = 10.0;

/// Default delivery base fare (Yango-comparable, K15).
const double kDeliveryDefaultBaseFare = 15.0;

/// Minimum payable fare for delivery (Yango-comparable, K20).
const double kDeliveryMinFare = 20.0;

/// Weight surcharges for cargo delivery.
const double kMediumWeightSurcharge = 5.0;
const double kHeavyWeightSurcharge = 10.0;

class RidePricingNotifier extends Notifier<RidePricingState> {
  static const _minimumTotalFare = 15.0;

  @override
  RidePricingState build() => const RidePricingState();

  bool get _isDelivery =>
      state.selectedCategory == 'marketplace' ||
      state.selectedCategory == 'bookshop';

  /// Base fare charged before distance — remote-configurable via
  /// `platform_settings.ride_base_fare_kwacha`, falls back to K10.
  /// Deliveries use a separate Yango-comparable base (K15 fallback).
  double get _baseFare {
    final fees = ref.read(feeConfigProvider).value;
    if (_isDelivery) {
      return fees?.rideDeliveryBaseFareKwacha ?? kDeliveryDefaultBaseFare;
    }
    return fees?.rideBaseFareKwacha ?? kCarpsoDefaultBaseFare;
  }

  double get _perKmRate =>
      _isDelivery
          ? (ref.read(feeConfigProvider).value?.rideDeliveryPerKmKwacha ??
              kDeliveryPerKmRate)
          : ref.read(remoteConfigProvider).value?.getDouble(
                  'ride_per_km_kwacha',
                  kCarpsoPerKmRate,
                ) ??
              kCarpsoPerKmRate;

  double get _minFare {
    final rc = ref.read(remoteConfigProvider).value;
    if (_isDelivery) {
      return rc?.getDouble('ride_delivery_min_fare_kwacha', kDeliveryMinFare) ??
          kDeliveryMinFare;
    }
    return rc?.getDouble('ride_min_total_fare_kwacha', _minimumTotalFare) ??
        _minimumTotalFare;
  }

  double get _weightSurcharge {
    final rc = ref.read(remoteConfigProvider).value;
    if (state.selectedWeight == 'Heavy') {
      return rc?.getDouble('ride_heavy_weight_surcharge_kwacha', kHeavyWeightSurcharge) ??
          kHeavyWeightSurcharge;
    }
    if (state.selectedWeight == 'Medium') {
      return rc?.getDouble('ride_medium_weight_surcharge_kwacha', kMediumWeightSurcharge) ??
          kMediumWeightSurcharge;
    }
    return 0;
  }

  /// Core fare formula — rides/bus: base + per-km (min K15).
  /// Delivery: Yango-comparable base + per-km (min K20) + weight surcharge.
  double _estimate(double distance) {
    final price = _baseFare + distance * _perKmRate + _weightSurcharge;
    return price < _minFare ? _minFare : price;
  }

  void setCategory(String category) {
    state = state.copyWith(selectedCategory: category, clearOffer: true);
    if (state.estimatedPrice != null) recalculate();
  }

  void setWeight(String weight) {
    state = state.copyWith(selectedWeight: weight);
    if (state.estimatedPrice != null) recalculate();
  }

  void setOffer(double offer) {
    // Delivery fees are FIXED — only rides are negotiable.
    if (_isDelivery) return;
    state = state.copyWith(offeredFare: offer, isNegotiating: true);
  }

  void clearOffer() {
    state = state.copyWith(clearOffer: true);
  }

  Future<void> calculatePrice(LatLng pickup, LatLng dest) async {
    state = state.copyWith(isCalculating: true);

    final distance = _haversineDistance(pickup, dest);
    state = state.copyWith(distanceKm: distance);

    await Future.delayed(const Duration(milliseconds: 800));

    final price = _estimate(distance);

    state = state.copyWith(
      isCalculating: false,
      estimatedPrice: double.tryParse(price.toStringAsFixed(2)) ?? 0.0,
      clearOffer: true,
    );
  }

  void recalculate() {
    if (state.distanceKm != null) {
      final price = _estimate(state.distanceKm!);

      state = state.copyWith(
        estimatedPrice: double.tryParse(price.toStringAsFixed(2)) ?? 0.0,
        clearOffer: true,
      );
    }
  }

  void reset() {
    state = const RidePricingState();
  }

  void applyDiscount(int percent) {
    state = state.copyWith(discountPercent: percent, flatDiscount: 0);
  }

  void applyFlatDiscount(double amount) {
    state = state.copyWith(flatDiscount: amount, discountPercent: 0);
  }

  void clearDiscount() {
    state = state.copyWith(clearDiscount: true);
  }

  static double _haversineDistance(LatLng a, LatLng b) {
    return const Distance().as(LengthUnit.Kilometer, a, b);
  }
}

final ridePricingProvider =
    NotifierProvider<RidePricingNotifier, RidePricingState>(
  RidePricingNotifier.new,
);
