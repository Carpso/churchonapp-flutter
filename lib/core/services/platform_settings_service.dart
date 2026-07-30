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

  PlatformSettings({
    required this.onboardingFee,
    required this.goldMonthlyFee,
    required this.platinumMonthlyFee,
    this.coaMoMoNumber = '0977000000',
    this.coaMoMoName = 'Church On App Official',
    this.coaTreasuryPhone = '260977000000',
  });

  factory PlatformSettings.fromList(List<dynamic> list) {
    double onboarding = PlanLimits.onboardingFeeKwacha;
    double gold = PlanLimits.forPlan(TenantPlan.gold).monthlyPriceKwacha;
    double platinum = PlanLimits.forPlan(TenantPlan.platinum).monthlyPriceKwacha;
    String momoNumber = '0977000000';
    String momoName = 'Church On App Official';
    String treasuryPhone = '260977000000';

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
