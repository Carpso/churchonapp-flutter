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
    {'key': 'quiz_lease_fee', 'label': 'Quiz Engine Lease Fee (K)', 'default': PlanLimits.quizLeaseFeeKwacha.toStringAsFixed(0)},
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
      for (final field in _pricingFields) {
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
      for (final field in _pricingFields) {
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
      final updates = _pricingFields.map((f) {
        final key = f['key'] ?? '';
        return {
          'key': key,
          'value': (_controllers[key]?.text ?? '').trim(),
        };
      }).toList();
      await client.from('platform_settings').upsert(updates, onConflict: 'key');
      if (mounted) PremiumToast.showSuccess(context, "Pricing updated!");
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
          _buildField('quiz_lease_fee', 'Quiz Engine Lease Fee (K/mo)'),
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
                Text("Quiz Lease: K${_controllers['quiz_lease_fee']?.text ?? '250'}/mo"),
                const Divider(height: 20),
                Text("Onboarding: K${_controllers['onboarding_fee']?.text ?? '500'} (one-time, includes 30 days free Platinum)"),
                Text("Platform fee: 1% per transaction (min K3) + Lipila charges"),
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
