import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/profile_provider.dart';
import '../../../core/widgets/error_retry_widget.dart';

/// Superadmin / COA-employee only: browse every registered church and edit
/// its registration details (contact, pastor, address, payouts, service times).
class ChurchDirectoryEditScreen extends ConsumerStatefulWidget {
  const ChurchDirectoryEditScreen({super.key});

  @override
  ConsumerState<ChurchDirectoryEditScreen> createState() => _ChurchDirectoryEditScreenState();
}

class _ChurchDirectoryEditScreenState extends ConsumerState<ChurchDirectoryEditScreen> {
  List<Map<String, dynamic>> _churches = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await Supabase.instance.client
          .from('churches')
          .select(
            'id, name, slug, logo_url, address, location, country, contact_phone, pastor_name, pastor_phone, treasurer_phone, payout_mobile, payout_network, is_verified, subscription_status, service_times, social_links, directions, tenant_id, subscription_ends_at',
          )
          .order('name', ascending: true);
      if (mounted) {
        setState(() {
          _churches = (res as List).cast<Map<String, dynamic>>();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).value;
    final isAllowed = profile?.isSuperadmin == true || profile?.isEmployee == true;

    return Scaffold(
      appBar: AppBar(title: const Text("Church Directory Editor")),
      body: !isAllowed
          ? const Center(child: Text("Access restricted to platform admins."))
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? ErrorRetryWidget(message: _error!, onRetry: _load)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _churches.length,
                        itemBuilder: (context, index) {
                          final church = _churches[index];
                          return _ChurchTile(
                            church: church,
                            onEdit: () async {
                              final changed = await Navigator.of(context).push<bool>(
                                MaterialPageRoute(
                                  builder: (_) => _ChurchEditScreen(church: church),
                                ),
                              );
                              if (changed == true) _load();
                            },
                          );
                        },
                      ),
                    ),
    );
  }
}

class _ChurchTile extends StatelessWidget {
  final Map<String, dynamic> church;
  final VoidCallback onEdit;
  const _ChurchTile({required this.church, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final verified = church['is_verified'] == true;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: verified ? Colors.green.withValues(alpha: 0.15) : Colors.orange.withValues(alpha: 0.15),
          child: Icon(
            verified ? LucideIcons.badgeCheck : LucideIcons.clock,
            color: verified ? Colors.green : Colors.orange,
            size: 20,
          ),
        ),
        title: Text(church['name']?.toString() ?? 'Unnamed church'),
        subtitle: Text(
          [
            church['address']?.toString() ?? '',
            church['country']?.toString() ?? '',
            church['contact_phone']?.toString() ?? '',
          ].where((s) => s.isNotEmpty).join(' • '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.edit_outlined, size: 20),
        onTap: onEdit,
      ),
    );
  }
}

class _ChurchEditScreen extends StatefulWidget {
  final Map<String, dynamic> church;
  const _ChurchEditScreen({required this.church});

  @override
  State<_ChurchEditScreen> createState() => _ChurchEditScreenState();
}

class _ChurchEditScreenState extends State<_ChurchEditScreen> {
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _location;
  late final TextEditingController _country;
  late final TextEditingController _contactPhone;
  late final TextEditingController _pastorName;
  late final TextEditingController _pastorPhone;
  late final TextEditingController _treasurerPhone;
  late final TextEditingController _payoutMobile;
  late final TextEditingController _payoutNetwork;
  late final TextEditingController _serviceTimes;
  late final TextEditingController _socialLinks;
  late final TextEditingController _directions;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    String v(String key) => widget.church[key]?.toString() ?? '';
    _name = TextEditingController(text: v('name'));
    _address = TextEditingController(text: v('address'));
    _location = TextEditingController(text: v('location'));
    _country = TextEditingController(text: v('country'));
    _contactPhone = TextEditingController(text: v('contact_phone'));
    _pastorName = TextEditingController(text: v('pastor_name'));
    _pastorPhone = TextEditingController(text: v('pastor_phone'));
    _treasurerPhone = TextEditingController(text: v('treasurer_phone'));
    _payoutMobile = TextEditingController(text: v('payout_mobile'));
    _payoutNetwork = TextEditingController(text: v('payout_network'));
    _serviceTimes = TextEditingController(text: v('service_times'));
    _socialLinks = TextEditingController(text: v('social_links'));
    _directions = TextEditingController(text: v('directions'));
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _location.dispose();
    _country.dispose();
    _contactPhone.dispose();
    _pastorName.dispose();
    _pastorPhone.dispose();
    _treasurerPhone.dispose();
    _payoutMobile.dispose();
    _payoutNetwork.dispose();
    _serviceTimes.dispose();
    _socialLinks.dispose();
    _directions.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await Supabase.instance.client
          .from('churches')
          .update({
            'name': _name.text.trim(),
            'address': _address.text.trim().isEmpty ? null : _address.text.trim(),
            'location': _location.text.trim().isEmpty ? null : _location.text.trim(),
            'country': _country.text.trim().isEmpty ? null : _country.text.trim(),
            'contact_phone': _contactPhone.text.trim().isEmpty ? null : _contactPhone.text.trim(),
            'pastor_name': _pastorName.text.trim().isEmpty ? null : _pastorName.text.trim(),
            'pastor_phone': _pastorPhone.text.trim().isEmpty ? null : _pastorPhone.text.trim(),
            'treasurer_phone': _treasurerPhone.text.trim().isEmpty ? null : _treasurerPhone.text.trim(),
            'payout_mobile': _payoutMobile.text.trim().isEmpty ? null : _payoutMobile.text.trim(),
            'payout_network': _payoutNetwork.text.trim().isEmpty ? null : _payoutNetwork.text.trim(),
            'service_times': _serviceTimes.text.trim().isEmpty ? null : _serviceTimes.text.trim(),
            'social_links': _socialLinks.text.trim().isEmpty ? null : _socialLinks.text.trim(),
            'directions': _directions.text.trim().isEmpty ? null : _directions.text.trim(),
          })
          .eq('id', widget.church['id']);

      // Sync the tenant row name when the church name changes
      final tenantId = widget.church['tenant_id']?.toString();
      if (tenantId != null && tenantId.isNotEmpty && _name.text.trim().isNotEmpty) {
        await Supabase.instance.client
            .from('tenants')
            .update({'name': _name.text.trim()})
            .eq('id', tenantId);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Church details updated"),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Update failed: $e"),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Edit Church Details")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _field("Church Name", _name),
          _field("Address", _address),
          _field("Location", _location),
          _field("Country", _country),
          _field("Contact Phone", _contactPhone, keyboardType: TextInputType.phone),
          _field("Pastor Name", _pastorName),
          _field("Pastor Phone", _pastorPhone, keyboardType: TextInputType.phone),
          _field("Treasurer Phone", _treasurerPhone, keyboardType: TextInputType.phone),
          _field("Payout Mobile", _payoutMobile, keyboardType: TextInputType.phone),
          _field("Payout Network", _payoutNetwork),
          _field("Service Times", _serviceTimes),
          _field("Social Links", _socialLinks),
          _field("Directions", _directions),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? "Saving..." : "Save Changes"),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController controller, {TextInputType? keyboardType}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}