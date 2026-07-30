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
    final base = isNegotiating && offeredFare != null ? offeredFare! : estimatedPrice ?? 0;
    if (discountPercent > 0) return base * (1 - discountPercent / 100);
    if (flatDiscount > 0) return (base - flatDiscount).clamp(0, base);
    return base;
  }

  double get platformFee => displayPrice * 0.01 > 3.00 ? displayPrice * 0.01 : 3.00;

  double get totalPayable => displayPrice + platformFee;

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

class RidePricingNotifier extends Notifier<RidePricingState> {
  static const _baseFarePerKm = 5.0;
  static const _minimumTotalFare = 15.0;
  static const _deliveryMultiplier = 1.3;
  static const _heavyWeightSurcharge = 10.0;

  @override
  RidePricingState build() => const RidePricingState();

  void setCategory(String category) {
    state = state.copyWith(selectedCategory: category, clearOffer: true);
    if (state.estimatedPrice != null) recalculate();
  }

  void setWeight(String weight) {
    state = state.copyWith(selectedWeight: weight);
    if (state.estimatedPrice != null) recalculate();
  }

  void setOffer(double offer) {
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

    double price = distance * _baseFarePerKm;
    price = price < _minimumTotalFare ? _minimumTotalFare : price;

    if (state.selectedCategory == 'marketplace' ||
        state.selectedCategory == 'bookshop') {
      price *= _deliveryMultiplier;
      if (state.selectedWeight == 'Heavy') {
        price += _heavyWeightSurcharge;
      } else if (state.selectedWeight == 'Medium') {
        price += _heavyWeightSurcharge / 2;
      }
    }

    state = state.copyWith(
      isCalculating: false,
      estimatedPrice: double.tryParse(price.toStringAsFixed(2)) ?? 0.0,
      clearOffer: true,
    );
  }

  void recalculate() {
    if (state.distanceKm != null) {
      final distance = state.distanceKm!;
      double price = distance * _baseFarePerKm;
      price = price < _minimumTotalFare ? _minimumTotalFare : price;

      if (state.selectedCategory == 'marketplace' ||
          state.selectedCategory == 'bookshop') {
        price *= _deliveryMultiplier;
        if (state.selectedWeight == 'Heavy') {
          price += _heavyWeightSurcharge;
        } else if (state.selectedWeight == 'Medium') {
          price += _heavyWeightSurcharge / 2;
        }
      }

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
    const earthRadius = 6371.0;
    final dLat = _toRad(b.latitude - a.latitude);
    final dLon = _toRad(b.longitude - a.longitude);
    final a1 = (dLat / 2) * (dLat / 2);
    final a2 = (_toRad(a.latitude)) * (_toRad(b.latitude)) * (dLon / 2) * (dLon / 2);
    final c = 2 * 2 * (a1 + a2).clamp(0.0, 1.0);
    return earthRadius * c;
  }

  static double _toRad(double deg) => deg * (3.141592653589793 / 180.0);
}

final ridePricingProvider =
    NotifierProvider<RidePricingNotifier, RidePricingState>(
  RidePricingNotifier.new,
);
