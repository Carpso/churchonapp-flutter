import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import 'package:church_on_app/core/widgets/premium_toast.dart';

/// Admin screen for editing subscription pricing
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
    {'key': 'silver_monthly_price', 'label': 'Silver Monthly Price', 'default': '150'},
    {'key': 'silver_monthly_label', 'label': 'Silver Monthly Label', 'default': 'K150/month'},
    {'key': 'gold_yearly_price', 'label': 'Gold Yearly Price', 'default': '1500'},
    {'key': 'gold_yearly_label', 'label': 'Gold Yearly Label', 'default': 'K1,500/year'},
    {'key': 'church_subscription_price', 'label': 'Church Subscription Price', 'default': '1500'},
    {'key': 'meeting_monthly_price', 'label': 'Meeting Monthly Price', 'default': '150'},
    {'key': 'meeting_yearly_price', 'label': 'Meeting Yearly Price', 'default': '1500'},
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
        title: const Text("Subscription Pricing"),
        actions: [
          _saving
              ? const Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
              : IconButton(onPressed: _saveSettings, icon: const Icon(Icons.save)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text("User Subscriptions", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _buildField('silver_monthly_price', 'Silver Monthly Price (K)'),
          _buildField('silver_monthly_label', 'Silver Monthly Label'),
          _buildField('gold_yearly_price', 'Gold Yearly Price (K)'),
          _buildField('gold_yearly_label', 'Gold Yearly Label'),
          const Divider(height: 40),
          const Text("Church Subscription", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _buildField('church_subscription_price', 'Church Price (K)'),
          const Divider(height: 40),
          const Text("Other Services", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _buildField('meeting_monthly_price', 'Meeting Monthly (K)'),
          _buildField('meeting_yearly_price', 'Meeting Yearly (K)'),
          const SizedBox(height: 30),
          // Preview
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Preview", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text("Silver: ${_controllers['silver_monthly_label']?.text ?? 'K150/month'}"),
                Text("Gold: ${_controllers['gold_yearly_label']?.text ?? 'K1,500/year'}"),
                Text("Church: K${_controllers['church_subscription_price']?.text ?? '1,500'}"),
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
