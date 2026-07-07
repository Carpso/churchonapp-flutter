import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/features/admin/data/church_lead_service.dart';

class ChurchReferralScreen extends ConsumerStatefulWidget {
  const ChurchReferralScreen({super.key});

  @override
  ConsumerState<ChurchReferralScreen> createState() => _ChurchReferralScreenState();
}

class _ChurchReferralScreenState extends ConsumerState<ChurchReferralScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pastorNameC = TextEditingController();
  final _pastorPhoneC = TextEditingController();
  final _churchNameC = TextEditingController();
  final _churchLocationC = TextEditingController();
  final _notesC = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _pastorNameC.dispose();
    _pastorPhoneC.dispose();
    _churchNameC.dispose();
    _churchLocationC.dispose();
    _notesC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myLeads = ref.watch(myChurchLeadsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Can\'t Find Your Church?'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(LucideIcons.helpCircle, color: theme.colorScheme.primary, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'If your church is not registered, tell us your pastor\'s details and we\'ll contact them to get your church on the platform.',
                            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('Refer Your Pastor', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _pastorNameC,
                    decoration: const InputDecoration(labelText: 'Pastor/Leader Name *', border: OutlineInputBorder()),
                    validator: (v) => v?.isEmpty == true ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _pastorPhoneC,
                    decoration: const InputDecoration(labelText: 'Pastor/Leader Phone *', border: OutlineInputBorder(), hintText: '+260...'),
                    keyboardType: TextInputType.phone,
                    validator: (v) => v?.isEmpty == true ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _churchNameC,
                    decoration: const InputDecoration(labelText: 'Church Name', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _churchLocationC,
                    decoration: const InputDecoration(labelText: 'Church Location', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _notesC,
                    decoration: const InputDecoration(labelText: 'Additional Notes', border: OutlineInputBorder()),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _isSubmitting ? null : _submit,
                      icon: const Icon(LucideIcons.send),
                      label: Text(_isSubmitting ? 'Submitting...' : 'Submit Referral'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Text('Your Referrals', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            myLeads.when(
              data: (leads) => leads.isEmpty
                  ? const Text('No referrals yet', style: TextStyle(color: Colors.grey))
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: leads.length,
                      itemBuilder: (context, index) {
                        final lead = leads[index];
                        return ListTile(
                          leading: Icon(
                            lead.status == 'converted' ? LucideIcons.checkCircle : lead.status == 'contacted' ? LucideIcons.phone : LucideIcons.clock,
                            color: lead.status == 'converted' ? Colors.green : lead.status == 'contacted' ? Colors.blue : Colors.grey,
                          ),
                          title: Text(lead.pastorName),
                          subtitle: Text('${lead.churchName ?? "Unknown"} - ${lead.status}'),
                        );
                      },
                    ),
              loading: () => const CircularProgressIndicator(),
              error: (e, _) => Text('Error: $e'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      await ref.read(churchLeadServiceProvider).submitLead(
        pastorName: _pastorNameC.text.trim(),
        pastorPhone: _pastorPhoneC.text.trim(),
        churchName: _churchNameC.text.trim(),
        churchLocation: _churchLocationC.text.trim(),
        notes: _notesC.text.trim(),
      );
      _pastorNameC.clear();
      _pastorPhoneC.clear();
      _churchNameC.clear();
      _churchLocationC.clear();
      _notesC.clear();
      ref.invalidate(myChurchLeadsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Referral submitted! Our team will contact your pastor.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
