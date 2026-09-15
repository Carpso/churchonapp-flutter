import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/features/profile/data/emergency_contact.dart';
import 'package:church_on_app/features/profile/data/emergency_contact_service.dart';

/// Emergency contacts — YOUR numbers + the shared service/church directory.
///
/// Previously this screen was fully hardcoded (Police 911 etc.) and never read
/// `EmergencyContactService`, so a member could not store their own next-of-kin
/// numbers. It now loads the real `emergency_contacts` table: personal contacts
/// owned by the signed-in user, plus the shared national/church entries.
class EmergencyContactsScreen extends ConsumerStatefulWidget {
  const EmergencyContactsScreen({super.key});

  @override
  ConsumerState<EmergencyContactsScreen> createState() =>
      _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState
    extends ConsumerState<EmergencyContactsScreen> {
  List<EmergencyContact> _all = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  EmergencyContactService get _service => ref.read(emergencyContactServiceProvider);

  String? get _uid =>
      ref.read(profileProvider).value?.id;

  Future<void> _load() async {
    final tenantId = ref.read(profileProvider).value?.tenantId;
    final contacts = await _service.fetchEmergencyContacts(tenantId);
    if (!mounted) return;
    setState(() {
      _all = contacts;
      _loading = false;
    });
  }

  List<EmergencyContact> get _personal =>
      _all.where((c) => c.userId != null).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  List<EmergencyContact> get _shared =>
      _all.where((c) => c.userId == null).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  Future<void> _dial(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone.replaceAll(' ', ''));
    try {
      // `tel:` must leave the app — opening it in a webview silently did
      // nothing on Android.
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not dial $phone')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not dial $phone')),
        );
      }
    }
  }

  Future<void> _addOrEdit({EmergencyContact? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final formKey = GlobalKey<FormState>();

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(existing == null ? 'Add Contact' : 'Edit Contact',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextFormField(
                controller: nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. Mum, Dr. Banda',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone number',
                  hintText: 'e.g. 0961234567',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().length < 6) ? 'Enter a phone number' : null,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    if (formKey.currentState?.validate() != true) return;
                    Navigator.of(ctx).pop(true);
                  },
                  child: Text(existing == null ? 'SAVE CONTACT' : 'UPDATE CONTACT'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (saved != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final uid = _uid;
      final tenantId = ref.read(profileProvider).value?.tenantId;
      if (existing == null) {
        await _service.addContact(EmergencyContact(
          userId: uid,
          tenantId: tenantId,
          name: nameCtrl.text.trim(),
          phone: phoneCtrl.text.trim(),
          icon: 'user',
          category: 'personal',
          sortOrder: _personal.length,
        ));
      } else {
        await _service.updateContact(existing.copyWith(
          name: nameCtrl.text.trim(),
          phone: phoneCtrl.text.trim(),
        ));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save contact: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(EmergencyContact contact) async {
    final id = contact.id;
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${contact.name}?'),
        content: const Text('This emergency contact will be deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('CANCEL')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('REMOVE',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _service.deleteContact(id);
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Emergency Contacts'),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : () => _addOrEdit(),
        backgroundColor: theme.primaryColor,
        foregroundColor: Colors.black,
        icon: const Icon(LucideIcons.plusCircle),
        label: const Text('ADD CONTACT',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                children: [
                  _sectionLabel('MY CONTACTS'),
                  const SizedBox(height: 12),
                  if (_personal.isEmpty)
                    _emptyPersonal(theme)
                  else
                    ..._personal.map((c) => _card(
                          context,
                          name: c.name,
                          phone: c.phone,
                          icon: LucideIcons.user,
                          color: theme.primaryColor,
                          onTap: () => _dial(c.phone),
                          onEdit: () => _addOrEdit(existing: c),
                          onDelete: () => _delete(c),
                        )),
                  const SizedBox(height: 28),
                  _sectionLabel('EMERGENCY SERVICES & CHURCH'),
                  const SizedBox(height: 12),
                  ..._shared.map((c) => _card(
                        context,
                        name: c.name,
                        phone: c.phone,
                        icon: _iconFor(c),
                        color: _colorFor(c, theme),
                        onTap: () => _dial(c.phone),
                      )),
                ],
              ),
            ),
    );
  }

  Widget _emptyPersonal(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.primaryColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.info, color: theme.primaryColor, size: 20),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Add your own emergency numbers (family, doctor, neighbour) so they are one tap away.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(EmergencyContact c) {
    switch (c.icon) {
      case 'shield':
        return LucideIcons.shield;
      case 'plus-circle':
        return LucideIcons.plusCircle;
      case 'flame':
        return LucideIcons.flame;
      case 'message-circle':
        return LucideIcons.messageCircle;
      case 'user':
        return LucideIcons.user;
      default:
        return LucideIcons.phone;
    }
  }

  Color _colorFor(EmergencyContact c, ThemeData theme) {
    switch (c.category) {
      case 'church':
        return theme.primaryColor;
      case 'medical':
        return Colors.red;
      case 'fire':
        return Colors.orange;
      case 'police':
        return Colors.blue;
      default:
        return Colors.teal;
    }
  }

  Widget _sectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: Colors.grey,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _card(
    BuildContext context, {
    required String name,
    required String phone,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    VoidCallback? onEdit,
    VoidCallback? onDelete,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Text(name,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        subtitle: Text(phone,
            style: TextStyle(
                color: color.withValues(alpha: 0.9),
                fontWeight: FontWeight.w600,
                fontSize: 13)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onEdit != null)
              IconButton(
                icon: const Icon(LucideIcons.pencil, size: 18),
                onPressed: onEdit,
                tooltip: 'Edit',
              ),
            if (onDelete != null)
              IconButton(
                icon: const Icon(LucideIcons.trash2, size: 18),
                onPressed: onDelete,
                color: Colors.red,
                tooltip: 'Remove',
              )
            else
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(LucideIcons.phone, color: color, size: 18),
              ),
          ],
        ),
      ),
    );
  }
}
