import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/services/platform_settings_service.dart';

/// Central source of truth for all fee calculations.
/// Reads from remote platform_settings table — no app update needed to change fees.
class FeeConfig {
  final double coaFeePercent;
  final double momoFeePercent;
  final double cardFeePercent;
  final double businessCutPercent;
  final double minFeeKwacha;

  /// Lipila MoMo disbursement fee (real rate 1.5%, wallet 68907) — deducted
  /// from every payout amount before calling lipila-payout.
  final double lipilaDisbursementFeePercent;

  /// COA's cut on money out: max(amount * coaPayoutFeePercent, minFeeKwacha).
  /// COA earns 1% (min K3) on every payout, mirroring the collection fee.
  final double coaPayoutFeePercent;

  /// Base fare charged per Carpso ride before distance is added (K10 fallback).
  final double rideBaseFareKwacha;

  /// Base fare for cargo delivery, benchmarked against Yango (K15 fallback).
  final double rideDeliveryBaseFareKwacha;

  /// Per-km rate for cargo delivery, Yango-comparable (K8 fallback).
  final double rideDeliveryPerKmKwacha;

  const FeeConfig({
    required this.coaFeePercent,
    required this.momoFeePercent,
    required this.cardFeePercent,
    required this.businessCutPercent,
    required this.minFeeKwacha,
    this.lipilaDisbursementFeePercent = 0.015,
    this.coaPayoutFeePercent = 0.01,
    this.rideBaseFareKwacha = 10.0,
    this.rideDeliveryBaseFareKwacha = 15.0,
    this.rideDeliveryPerKmKwacha = 8.0,
  });

  /// Build from remote PlatformSettings
  factory FeeConfig.fromSettings(PlatformSettings settings) {
    return FeeConfig(
      coaFeePercent: settings.coaFeePercent,
      momoFeePercent: settings.momoFeePercent,
      cardFeePercent: settings.cardFeePercent,
      businessCutPercent: settings.businessCutPercent,
      minFeeKwacha: settings.minFeeKwacha,
      lipilaDisbursementFeePercent: settings.lipilaDisbursementFeePercent,
      coaPayoutFeePercent: settings.coaPayoutFeePercent,
      rideBaseFareKwacha: settings.rideBaseFareKwacha,
      rideDeliveryBaseFareKwacha: settings.rideDeliveryBaseFareKwacha,
      rideDeliveryPerKmKwacha: settings.rideDeliveryPerKmKwacha,
    );
  }

  /// Local defaults (used when remote fetch fails)
  static const FeeConfig defaults = FeeConfig(
    coaFeePercent: 0.01,
    momoFeePercent: 0.025,
    cardFeePercent: 0.025,
    businessCutPercent: 0.10,
    minFeeKwacha: 3.0,
    lipilaDisbursementFeePercent: 0.015,
    coaPayoutFeePercent: 0.01,
    rideBaseFareKwacha: 10.0,
    rideDeliveryBaseFareKwacha: 15.0,
    rideDeliveryPerKmKwacha: 8.0,
  );

  // ── Customer-facing fee ──────────────────────────────────────────────

  /// Platform fee visible to customers = COA fee + Lipila payment processor fee.
  /// Applies to ALL transactions (giving, marketplace, events, rides).
  double platformFee(double amount, {bool isCard = false}) {
    final processorFee = isCard ? cardFeePercent : momoFeePercent;
    final raw = amount * (coaFeePercent + processorFee);
    return raw < minFeeKwacha ? minFeeKwacha : raw;
  }

  /// Total amount charged to customer (amount + platform fee).
  double totalCharged(double amount, {bool isCard = false}) {
    return amount + platformFee(amount, isCard: isCard);
  }

  /// Human-readable label for the platform fee.
  String platformFeeLabel({bool isCard = false}) {
    final total = (coaFeePercent + (isCard ? cardFeePercent : momoFeePercent)) * 100;
    return 'Platform Fee (${total.toStringAsFixed(1)}%, min K${minFeeKwacha.toStringAsFixed(0)})';
  }

  // ── Business/provider cut (deducted from seller/driver/organiser) ─────

  /// Commission deducted from business earnings at settlement.
  /// NOT shown to buyers — only visible in admin dashboards.
  double businessCut(double amount) => amount * businessCutPercent;

  /// Net amount a business receives after commission.
  double businessNet(double amount) => amount - businessCut(amount);

  // ── Lipila disbursement fee (real 1.5% on money out) ──────────────────

  /// Lipila's fee charged on the amount sent out of the wallet (payouts).
  double disbursementFee(double amount) => amount * lipilaDisbursementFeePercent;

  /// COA's cut on money out: max(1% of payout, min K3) — same shape as the
  /// collection platform fee, applied to every payout.
  double coaPayoutFee(double amount) {
    final raw = amount * coaPayoutFeePercent;
    return raw < minFeeKwacha ? minFeeKwacha : raw;
  }

  /// Amount actually sent to the recipient after Lipila's disbursement fee
  /// AND COA's payout fee. Applied at every lipila-payout call so the
  /// recipient gets exactly the promised net.
  double payoutNet(double amount) =>
      amount - disbursementFee(amount) - coaPayoutFee(amount);

  // ── Church giving (no business cut — churches subscribe to plans) ────

  /// Fee for church giving = platform fee only (church gets full amount).
  double givingFee(double amount, {bool isCard = false}) {
    return platformFee(amount, isCard: isCard);
  }

  // ── Breakdown for admin dashboards ───────────────────────────────────

  FeeBreakdown breakdown(double amount, {bool isCard = false}) {
    final processorFee = isCard ? cardFeePercent : momoFeePercent;
    final coaRevenue = amount * coaFeePercent;
    final lipilaFee = amount * processorFee;
    final total = coaRevenue + lipilaFee;
    final fee = total < minFeeKwacha ? minFeeKwacha : total;

    return FeeBreakdown(
      amount: amount,
      coaRevenue: coaRevenue,
      lipilaFee: lipilaFee,
      totalPlatformFee: fee,
      isCard: isCard,
    );
  }

  @override
  String toString() =>
      'FeeConfig(COA: ${(coaFeePercent * 100).toStringAsFixed(1)}%, '
      'MoMo: ${(momoFeePercent * 100).toStringAsFixed(1)}%, '
      'Card: ${(cardFeePercent * 100).toStringAsFixed(1)}%, '
      'Business: ${(businessCutPercent * 100).toStringAsFixed(0)}%, '
      'Disb: ${(lipilaDisbursementFeePercent * 100).toStringAsFixed(1)}%, '
      'COA Disb: ${(coaPayoutFeePercent * 100).toStringAsFixed(1)}%, '
      'Min: K${minFeeKwacha.toStringAsFixed(0)})';
}

/// Detailed fee breakdown for admin/superadmin dashboards.
class FeeBreakdown {
  final double amount;
  final double coaRevenue;
  final double lipilaFee;
  final double totalPlatformFee;
  final bool isCard;

  const FeeBreakdown({
    required this.amount,
    required this.coaRevenue,
    required this.lipilaFee,
    required this.totalPlatformFee,
    required this.isCard,
  });

  @override
  String toString() =>
      'FeeBreakdown(amount: K${amount.toStringAsFixed(2)}, '
      'COA: K${coaRevenue.toStringAsFixed(2)}, '
      'Lipila: K${lipilaFee.toStringAsFixed(2)}, '
      'Total: K${totalPlatformFee.toStringAsFixed(2)})';
}

// ── Riverpod providers ───────────────────────────────────────────────────

final feeConfigProvider = FutureProvider<FeeConfig>((ref) async {
  try {
    final client = Supabase.instance.client;
    final service = PlatformSettingsService(client);
    final settings = await service.fetchSettings();
    return FeeConfig.fromSettings(settings);
  } catch (e) {
    return FeeConfig.defaults;
  }
});
