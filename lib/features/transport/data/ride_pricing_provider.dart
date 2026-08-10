import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

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

  // Processing fee: COA 1% min K3 + Lipila K0.48
  double get processingFeeAmount => processingFee(displayPrice);

  double get totalPayable => displayPrice + processingFeeAmount;

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

/// Per-kilometre Carpso rate — K10/km for rides, K5/km for delivery.
const double kCarpsoPerKmRate = 10.0;
const double kDeliveryPerKmRate = 5.0;

/// Average city speed used for trip-time estimates (km/h).
const double kCarpsoCitySpeedKmh = 25.0;

/// Base fare: K15 ride, K7.50 delivery.
const double kCarpsoDefaultBaseFare = 15.0;
const double kDeliveryDefaultBaseFare = 7.50;

/// Minimum total fare (subtotal before processing fee): K30 for both.
const double kRideMinFare = 30.0;
const double kDeliveryMinFare = 30.0;

/// Weight surcharges for cargo delivery.
const double kMediumWeightSurcharge = 10.0;
const double kHeavyWeightSurcharge = 20.0;

/// Processing fee: COA 1% (min K3) + Lipila flat K0.48.
double processingFee(double amount) {
  final coa = amount * 0.01;
  return (coa < 3.0 ? 3.0 : coa) + 0.48;
}

class RidePricingNotifier extends Notifier<RidePricingState> {
  @override
  RidePricingState build() => const RidePricingState();

  bool get _isDelivery =>
      state.selectedCategory == 'marketplace' ||
      state.selectedCategory == 'bookshop';

  double get _baseFare {
    if (_isDelivery) return kDeliveryDefaultBaseFare;
    return kCarpsoDefaultBaseFare;
  }

  double get _perKmRate => _isDelivery ? kDeliveryPerKmRate : kCarpsoPerKmRate;

  double get _minFare => _isDelivery ? kDeliveryMinFare : kRideMinFare;

  double get _weightSurcharge {
    if (state.selectedWeight == 'Heavy') return kHeavyWeightSurcharge;
    if (state.selectedWeight == 'Medium') return kMediumWeightSurcharge;
    return 0;
  }

  /// Core fare formula: base + per-km (min K30) + weight surcharge.
  /// Ride: K15 base + K10/km. Delivery: K7.50 base + K5/km.
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
