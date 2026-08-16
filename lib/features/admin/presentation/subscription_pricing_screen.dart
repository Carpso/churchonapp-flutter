import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import 'package:church_on_app/core/widgets/premium_toast.dart';
import 'package:church_on_app/core/services/plan_service.dart';

class SubscriptionPricingScreen extends ConsumerStatefulWidget {
  const SubscriptionPricingScreen({super.key});

  @override
  ConsumerState<SubscriptionPricingScreen> createState() => _SubscriptionPricingScreenState();
}

class _SubscriptionPricingScreenState extends ConsumerState<SubscriptionPricingScreen> {
  bool _loading = true;
  bool _saving = false;
  final Map<String, TextEditingController> _controllers = {};

  final _pricingFields = [
    {'key': 'onboarding_fee', 'label': 'Onboarding Fee (K)', 'default': PlanLimits.onboardingFeeKwacha.toStringAsFixed(0)},
    {'key': 'gold_monthly_fee', 'label': 'Gold Monthly Fee (K)', 'default': PlanLimits.forPlan(TenantPlan.gold).monthlyPriceKwacha.toStringAsFixed(0)},
    {'key': 'platinum_monthly_fee', 'label': 'Platinum Monthly Fee (K)', 'default': PlanLimits.forPlan(TenantPlan.platinum).monthlyPriceKwacha.toStringAsFixed(0)},
  ];

  final _feeFields = [
    {'key': 'coa_fee_percent', 'label': 'COA Fee % (e.g. 0.01 = 1%)', 'default': '0.01'},
    {'key': 'momo_fee_percent', 'label': 'MoMo Lipila Fee % (e.g. 0.025 = 2.5%)', 'default': '0.025'},
    {'key': 'card_fee_percent', 'label': 'Card Lipila Fee % (e.g. 0.025 = 2.5%)', 'default': '0.025'},
    {'key': 'business_cut_percent', 'label': 'Business Cut % (e.g. 0.10 = 10%)', 'default': '0.10'},
    {'key': 'lipila_disbursement_fee_percent', 'label': 'Lipila Disbursement Fee % (e.g. 0.015 = 1.5%)', 'default': '0.015'},
    {'key': 'coa_payout_fee_percent', 'label': 'COA Payout Fee % (e.g. 0.01 = 1%, min K3)', 'default': '0.01'},
    {'key': 'min_fee_kwacha', 'label': 'Min Platform Fee (K)', 'default': '3.0'},
  ];

  final _featureFields = [
    {'key': 'coins_daily_open_reward', 'label': 'Daily Open Coins', 'default': '25'},
    {'key': 'coins_streak_bonus_per_day', 'label': 'Streak Bonus per Day', 'default': '50'},
    {'key': 'coins_attendance_reward', 'label': 'Attendance Coins', 'default': '50'},
    {'key': 'coins_referral_reward', 'label': 'Referral Coins', 'default': '100'},
    {'key': 'coins_daily_collect_cooldown_sec', 'label': 'Daily Collect Cooldown (seconds)', 'default': '72000'},
    {'key': 'ride_per_km_kwacha', 'label': 'Carpso Ride per km (K)', 'default': '5'},
    {'key': 'ride_min_total_fare_kwacha', 'label': 'Ride Min Total Fare (K)', 'default': '15'},
    {'key': 'ride_delivery_min_fare_kwacha', 'label': 'Delivery Min Fare (K)', 'default': '20'},
    {'key': 'ride_medium_weight_surcharge_kwacha', 'label': 'Medium Weight Surcharge (K)', 'default': '5'},
    {'key': 'ride_heavy_weight_surcharge_kwacha', 'label': 'Heavy Weight Surcharge (K)', 'default': '10'},
    {'key': 'ride_avg_city_speed_kmh', 'label': 'Ride Avg City Speed (km/h)', 'default': '25'},
    {'key': 'quiz_prize_1st_kwacha', 'label': 'Quiz 1st Prize (K)', 'default': '500'},
    {'key': 'quiz_prize_2nd_kwacha', 'label': 'Quiz 2nd Prize (K)', 'default': '300'},
    {'key': 'quiz_prize_3rd_kwacha', 'label': 'Quiz 3rd Prize (K)', 'default': '150'},
    {'key': 'quiz_prize_1st_cc', 'label': 'Quiz 1st Prize (CC)', 'default': '500'},
    {'key': 'quiz_prize_2nd_cc', 'label': 'Quiz 2nd Prize (CC)', 'default': '300'},
    {'key': 'quiz_prize_3rd_cc', 'label': 'Quiz 3rd Prize (CC)', 'default': '150'},
    {'key': 'quiz_season_weeks', 'label': 'Quiz Season Length (weeks)', 'default': '12'},
    {'key': 'quiz_lease_fee_kwacha', 'label': 'Quiz Lease Fee (K)', 'default': '1500'},
    {'key': 'quiz_lease_fee_usd', 'label': 'Quiz Lease Fee (USD)', 'default': '50'},
    {'key': 'quiz_lease_fee_cc', 'label': 'Quiz Engine Lease Fee (CC)', 'default': '1500'},
    {'key': 'quiz_pass_cc_per_zmw', 'label': 'Pass CC rate (CC per K1)', 'default': '1.0'},
    {'key': 'subscription_trial_days', 'label': 'Trial Length (days)', 'default': '30'},
    {'key': 'subscription_renewal_days', 'label': 'Paid Renewal Length (days)', 'default': '365'},
    {'key': 'platinum_promo_days', 'label': 'Free Platinum Promo (days)', 'default': '30'},
    {'key': 'subscription_manual_payment_days', 'label': 'Manual Subscribe Grant (days)', 'default': '30'},
    {'key': 'event_commission_percent', 'label': 'Event Commission % (e.g. 0.10 = 10%)', 'default': '0.10'},
    {'key': 'marketplace_delivery_fee_kwacha', 'label': 'Marketplace Delivery Fee (K)', 'default': '15'},
    {'key': 'church_payout_min_kwacha', 'label': 'Church Auto-Payout Min Balance (K)', 'default': '100'},
    {'key': 'ride_payout_mobile', 'label': 'Carpso Ride Payout Number (platform receives ride/delivery cuts)', 'default': ''},
    {'key': 'ride_payout_network', 'label': 'Carpso Ride Payout Network (MTN/Airtel/Zamtel)', 'default': 'MTN'},
    {'key': 'giving_monthly_goal_kwacha', 'label': 'Personal Monthly Giving Goal (K)', 'default': '500'},
    {'key': 'church_monthly_goal_kwacha', 'label': 'Church Monthly Giving Goal (K)', 'default': '10000'},
    {'key': 'session_inactivity_minutes', 'label': 'Session Inactivity Timeout (minutes)', 'default': '5'},
    {'key': 'turnover_tax_percent', 'label': 'ZRA Turnover Tax % (e.g. 3.0 = 3%)', 'default': '3.0'},
    {'key': 'nhima_percent', 'label': 'NHIMA % of gross', 'default': '1.0'},
    {'key': 'napsa_percent', 'label': 'NAPSA % of gross', 'default': '5.0'},
    {'key': 'paye_threshold_kwacha', 'label': 'PAYE Tax-Free Threshold (K)', 'default': '5100'},
    {'key': 'paye_rate_percent', 'label': 'PAYE Rate % above threshold', 'default': '25.0'},
    {'key': 'coin_package_coins', 'label': 'Buy Coins: CC amounts (comma-separated)', 'default': '100,250,500,1000,2500'},
    {'key': 'coin_package_prices_kwacha', 'label': 'Buy Coins: Prices K (comma-separated, matches CC list)', 'default': '10,22,40,70,150'},
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final client = Supabase.instance.client;
      final res = await client.from('platform_settings').select('key, value');
      final resList = List<Map<String, dynamic>>.from(res);
      for (final field in [..._pricingFields, ..._feeFields, ..._featureFields]) {
        final key = field['key'] ?? '';
        if (key.isEmpty) continue;
        try {
          final match = resList.firstWhere((r) => r['key'] == field['key']);
          _controllers[key] = TextEditingController(text: match['value']?.toString() ?? field['default']);
        } catch (_) {
          _controllers[key] = TextEditingController(text: field['default']);
        }
      }
    } catch (e) {
      for (final field in [..._pricingFields, ..._feeFields, ..._featureFields]) {
        final key = field['key'] ?? '';
        if (key.isEmpty) continue;
        _controllers[key] = TextEditingController(text: field['default']);
      }
    }
    setState(() => _loading = false);
  }

  Future<void> _saveSettings() async {
    setState(() => _saving = true);
    try {
      final client = Supabase.instance.client;
      final allFields = [..._pricingFields, ..._feeFields, ..._featureFields];
      final updates = allFields.map((f) {
        final key = f['key'] ?? '';
        return {
          'key': key,
          'value': (_controllers[key]?.text ?? '').trim(),
        };
      }).toList();
      await client.from('platform_settings').upsert(updates, onConflict: 'key');
      if (mounted) PremiumToast.showSuccess(context, "Settings updated!");
    } catch (e) {
      if (mounted) PremiumToast.showError(context, "Failed to save: $e");
    }
    setState(() => _saving = false);
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: ListSkeleton()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Pricing & Plans"),
        actions: [
          _saving
              ? const Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
              : IconButton(onPressed: _saveSettings, icon: const Icon(Icons.save)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text("Church Plans", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text("Silver is always free. Gold and Platinum have monthly fees.", style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 16),
          _buildField('onboarding_fee', 'Onboarding Fee (K) — one-time'),
          _buildField('gold_monthly_fee', 'Gold Monthly Fee (K)'),
          _buildField('platinum_monthly_fee', 'Platinum Monthly Fee (K)'),
          _buildField('quiz_lease_fee_cc', 'Quiz Engine Lease Fee (CC) — buy CC with MoMo/card'),
          const Divider(height: 40),
          const Text("Fee Configuration", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text("Platform fees are remote-configurable. Changes take effect immediately for all users.", style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 16),
          _buildField('coa_fee_percent', 'COA Fee % (e.g. 0.01 = 1%)'),
          _buildField('momo_fee_percent', 'MoMo Lipila Fee % (e.g. 0.025 = 2.5%)'),
          _buildField('card_fee_percent', 'Card Lipila Fee % (e.g. 0.025 = 2.5%)'),
          _buildField('business_cut_percent', 'Business/Seller Cut % (e.g. 0.10 = 10%)'),
          _buildField('lipila_disbursement_fee_percent', 'Lipila Disbursement Fee % (e.g. 0.015 = 1.5%)'),
          _buildField('coa_payout_fee_percent', 'COA Payout Fee % (e.g. 0.01 = 1%, min K3)'),
          _buildField('min_fee_kwacha', 'Min Platform Fee (K)'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Customer Platform Fee = COA Fee + Lipila Fee. Business Cut is deducted from sellers/drivers at payout. Churches are exempt from business cut.",
                    style: const TextStyle(fontSize: 11, color: Color(0xFF7A5C00)),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 40),
          const Text("Feature Values", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text("Coin rewards, ride fares, quiz prizes and subscription terms. Remote-configurable — no app update needed.", style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 16),
          ..._featureFields.map((f) => _buildField(f['key'] ?? '', f['label'] ?? '')),
          const Divider(height: 40),
          const Text("SMS Bundles", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...PlanLimits.smsBundles.entries.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Icon(Icons.check_circle, size: 14, color: Colors.green.shade300),
                const SizedBox(width: 8),
                Text("K${e.key} → ${e.value} SMS credits", style: const TextStyle(fontSize: 13)),
              ],
            ),
          )),
          const SizedBox(height: 30),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Plan Overview", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text("Silver: Free (100 members, 10 events, 1GB)"),
                Text("Gold: K${_controllers['gold_monthly_fee']?.text ?? '100'}/mo (500 members, 50 events, 10GB)"),
                Text("Platinum: K${_controllers['platinum_monthly_fee']?.text ?? '500'}/mo (Unlimited, quiz hosting, priority)"),
                Text("Quiz Lease: ${_controllers['quiz_lease_fee_cc']?.text ?? '1500'} CC (buy CC with MoMo/card)"),
                const Divider(height: 20),
                Text("Onboarding: K${_controllers['onboarding_fee']?.text ?? '500'} (one-time, includes 30 days free Platinum)"),
                Text("Platform fee: 1% COA + Lipila (1.5% MoMo / 2.5% Card, min K3)"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField(String key, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: _controllers[key],
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
