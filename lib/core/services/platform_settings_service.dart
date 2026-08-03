import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'plan_service.dart';

class PlatformSettings {
  final double onboardingFee;
  final double goldMonthlyFee;
  final double platinumMonthlyFee;
  final String coaMoMoNumber;
  final String coaMoMoName;
  final String coaTreasuryPhone;

  // Fee configuration (remote-configurable)
  final double coaFeePercent;
  final double momoFeePercent;
  final double cardFeePercent;
  final double businessCutPercent;
  final double minFeeKwacha;

  /// Lipila MoMo disbursement fee (1.5% real rate, wallet 68907) — deducted
  /// from every payout amount before calling lipila-payout.
  final double lipilaDisbursementFeePercent;

  /// COA's cut on money out (1% fallback, min K3) — deducted alongside the
  /// Lipila disbursement fee via FeeConfig.payoutNet().
  final double coaPayoutFeePercent;

  /// Carpso ride base fare (K10 fallback when not configured).
  final double rideBaseFareKwacha;

  /// Carpso delivery base fare (K15 fallback, Yango-comparable).
  final double rideDeliveryBaseFareKwacha;

  /// Carpso delivery per-km rate (K8 fallback, Yango-comparable).
  final double rideDeliveryPerKmKwacha;

  PlatformSettings({
    required this.onboardingFee,
    required this.goldMonthlyFee,
    required this.platinumMonthlyFee,
    this.coaMoMoNumber = '0976847775',
    this.coaMoMoName = 'Church On App Official',
    this.coaTreasuryPhone = '2609776847775',
    this.coaFeePercent = 0.01,
    this.momoFeePercent = 0.015,
    this.cardFeePercent = 0.025,
    this.businessCutPercent = 0.10,
    this.minFeeKwacha = 3.0,
    this.lipilaDisbursementFeePercent = 0.015,
    this.coaPayoutFeePercent = 0.01,
    this.rideBaseFareKwacha = 10.0,
    this.rideDeliveryBaseFareKwacha = 15.0,
    this.rideDeliveryPerKmKwacha = 8.0,
  });

  factory PlatformSettings.fromList(List<dynamic> list) {
    double onboarding = PlanLimits.onboardingFeeKwacha;
    double gold = PlanLimits.forPlan(TenantPlan.gold).monthlyPriceKwacha;
    double platinum = PlanLimits.forPlan(TenantPlan.platinum).monthlyPriceKwacha;
    String momoNumber = '0977000000';
    String momoName = 'Church On App Official';
    String treasuryPhone = '260977000000';
    double coaFee = 0.01;
    double momoFee = 0.015;
    double cardFee = 0.025;
    double businessCut = 0.10;
    double minFee = 3.0;
    double disbFee = 0.015;
    double coaPayoutFee = 0.01;
    double rideBaseFare = 10.0;
    double deliveryBaseFare = 15.0;
    double deliveryPerKm = 8.0;

    for (var row in list) {
      if (row is Map) {
        final key = row['key'];
        final val = row['value']?.toString() ?? '';
        if (key == 'onboarding_fee') {
          final numVal = double.tryParse(val);
          if (numVal != null) onboarding = numVal;
        } else if (key == 'gold_monthly_fee') {
          final numVal = double.tryParse(val);
          if (numVal != null) gold = numVal;
        } else if (key == 'platinum_monthly_fee') {
          final numVal = double.tryParse(val);
          if (numVal != null) platinum = numVal;
        } else if (key == 'coa_momo_number') {
          if (val.isNotEmpty) momoNumber = val;
        } else if (key == 'coa_momo_name') {
          if (val.isNotEmpty) momoName = val;
        } else if (key == 'coa_treasury_phone') {
          if (val.isNotEmpty) treasuryPhone = val;
        } else if (key == 'coa_fee_percent') {
          final numVal = double.tryParse(val);
          if (numVal != null) coaFee = numVal;
        } else if (key == 'momo_fee_percent') {
          final numVal = double.tryParse(val);
          if (numVal != null) momoFee = numVal;
        } else if (key == 'card_fee_percent') {
          final numVal = double.tryParse(val);
          if (numVal != null) cardFee = numVal;
        } else if (key == 'business_cut_percent') {
          final numVal = double.tryParse(val);
          if (numVal != null) businessCut = numVal;
        } else if (key == 'min_fee_kwacha') {
          final numVal = double.tryParse(val);
          if (numVal != null) minFee = numVal;
        } else if (key == 'lipila_disbursement_fee_percent') {
          final numVal = double.tryParse(val);
          if (numVal != null) disbFee = numVal;
        } else if (key == 'coa_payout_fee_percent') {
          final numVal = double.tryParse(val);
          if (numVal != null) coaPayoutFee = numVal;
        } else if (key == 'ride_base_fare_kwacha') {
          final numVal = double.tryParse(val);
          if (numVal != null) rideBaseFare = numVal;
        } else if (key == 'ride_delivery_base_fare_kwacha') {
          final numVal = double.tryParse(val);
          if (numVal != null) deliveryBaseFare = numVal;
        } else if (key == 'ride_delivery_per_km_kwacha') {
          final numVal = double.tryParse(val);
          if (numVal != null) deliveryPerKm = numVal;
        }
      }
    }

    return PlatformSettings(
      onboardingFee: onboarding,
      goldMonthlyFee: gold,
      platinumMonthlyFee: platinum,
      coaMoMoNumber: momoNumber,
      coaMoMoName: momoName,
      coaTreasuryPhone: treasuryPhone,
      coaFeePercent: coaFee,
      momoFeePercent: momoFee,
      cardFeePercent: cardFee,
      businessCutPercent: businessCut,
      minFeeKwacha: minFee,
      lipilaDisbursementFeePercent: disbFee,
      coaPayoutFeePercent: coaPayoutFee,
      rideBaseFareKwacha: rideBaseFare,
      rideDeliveryBaseFareKwacha: deliveryBaseFare,
      rideDeliveryPerKmKwacha: deliveryPerKm,
    );
  }
}

class PlatformSettingsService {
  final SupabaseClient _client;
  PlatformSettingsService(this._client);

  Future<PlatformSettings> fetchSettings() async {
    try {
      final data = await _client.from('platform_settings').select();
      return PlatformSettings.fromList(data);
    } catch (e) {
      debugPrint('Error fetching platform settings: $e');
      return PlatformSettings(
        onboardingFee: PlanLimits.onboardingFeeKwacha,
        goldMonthlyFee: PlanLimits.forPlan(TenantPlan.gold).monthlyPriceKwacha,
        platinumMonthlyFee: PlanLimits.forPlan(TenantPlan.platinum).monthlyPriceKwacha,
      );
    }
  }

  Future<void> updateSettings({
    required double onboardingFee,
    required double goldMonthlyFee,
    required double platinumMonthlyFee,
    String? coaMoMoNumber,
    String? coaMoMoName,
    String? coaTreasuryPhone,
    double? coaFeePercent,
    double? momoFeePercent,
    double? cardFeePercent,
    double? businessCutPercent,
    double? minFeeKwacha,
    double? lipilaDisbursementFeePercent,
    double? coaPayoutFeePercent,
    double? rideBaseFareKwacha,
    double? rideDeliveryBaseFareKwacha,
    double? rideDeliveryPerKmKwacha,
  }) async {
    try {
      final upserts = [
        {'key': 'onboarding_fee', 'value': onboardingFee.toString()},
        {'key': 'gold_monthly_fee', 'value': goldMonthlyFee.toString()},
        {'key': 'platinum_monthly_fee', 'value': platinumMonthlyFee.toString()},
      ];
      if (coaMoMoNumber != null) {
        upserts.add({'key': 'coa_momo_number', 'value': coaMoMoNumber});
      }
      if (coaMoMoName != null) {
        upserts.add({'key': 'coa_momo_name', 'value': coaMoMoName});
      }
      if (coaTreasuryPhone != null) {
        upserts.add({'key': 'coa_treasury_phone', 'value': coaTreasuryPhone});
      }
      if (coaFeePercent != null) {
        upserts.add({'key': 'coa_fee_percent', 'value': coaFeePercent.toString()});
      }
      if (momoFeePercent != null) {
        upserts.add({'key': 'momo_fee_percent', 'value': momoFeePercent.toString()});
      }
      if (cardFeePercent != null) {
        upserts.add({'key': 'card_fee_percent', 'value': cardFeePercent.toString()});
      }
      if (businessCutPercent != null) {
        upserts.add({'key': 'business_cut_percent', 'value': businessCutPercent.toString()});
      }
      if (minFeeKwacha != null) {
        upserts.add({'key': 'min_fee_kwacha', 'value': minFeeKwacha.toString()});
      }
      if (lipilaDisbursementFeePercent != null) {
        upserts.add({'key': 'lipila_disbursement_fee_percent', 'value': lipilaDisbursementFeePercent.toString()});
      }
      if (coaPayoutFeePercent != null) {
        upserts.add({'key': 'coa_payout_fee_percent', 'value': coaPayoutFeePercent.toString()});
      }
      if (rideBaseFareKwacha != null) {
        upserts.add({'key': 'ride_base_fare_kwacha', 'value': rideBaseFareKwacha.toString()});
      }
      if (rideDeliveryBaseFareKwacha != null) {
        upserts.add({'key': 'ride_delivery_base_fare_kwacha', 'value': rideDeliveryBaseFareKwacha.toString()});
      }
      if (rideDeliveryPerKmKwacha != null) {
        upserts.add({'key': 'ride_delivery_per_km_kwacha', 'value': rideDeliveryPerKmKwacha.toString()});
      }
      await _client.from('platform_settings').upsert(upserts);
    } catch (e) {
      debugPrint('Error updating platform settings: $e');
      rethrow;
    }
  }
}

final platformSettingsServiceProvider = Provider((ref) {
  final client = Supabase.instance.client;
  return PlatformSettingsService(client);
});

final platformSettingsProvider = FutureProvider<PlatformSettings>((ref) async {
  return ref.watch(platformSettingsServiceProvider).fetchSettings();
});
