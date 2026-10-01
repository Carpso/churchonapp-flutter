import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/widgets/app_image.dart';
import '../data/map_live_models.dart';
import '../data/map_live_service.dart';

/// Church fleet management â€” the missing piece that makes bus tracking real.
///
/// Before this, `church_buses` rows existed but nothing could create one, and
/// `driver_id` was never set, so the bus GPS heartbeat in
/// `LocationTrackerService` could never fire. Without a driver on a bus, the
/// fleet map is permanently empty.
class FleetManagementScreen extends ConsumerWidget {
  const FleetManagementScreen({super.key, required this.tenantId});

  final String tenantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final busesAsync = ref.watch(liveBusesProvider(tenantId));

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Church Fleet',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: theme.scaffoldBackgroundColor,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editBus(context, ref),
        icon: const Icon(LucideIcons.bus),
        label: const Text('ADD BUS'),
      ),
      body: busesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load the fleet: $e')),
        data: (buses) {
          if (buses.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.bus,
                        size: 56, color: Colors.grey.withValues(alpha: 0.35)),
                    const SizedBox(height: 14),
                    const Text('No buses yet',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    const Text(
                      'Add a bus, assign a driver, and its live position will '
                      'appear on the Live Map while they are on duty.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final b in buses)
                _busCard(context, ref, theme, b),
            ],
          );
        },
      ),
    );
  }

  Widget _busCard(
      BuildContext context, WidgetRef ref, ThemeData theme, LiveBus bus) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: bus.hasLiveFix
                ? Colors.green.withValues(alpha: 0.35)
                : Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.bus,
                  color: bus.hasLiveFix ? Colors.green : Colors.grey),
              const SizedBox(width: 10),
              Expanded(
                child: Text(bus.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (bus.hasLiveFix ? Colors.green : Colors.grey)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(bus.statusLabel,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: bus.hasLiveFix ? Colors.green : Colors.grey)),
              ),
            ],
          ),
          if (bus.route != null && bus.route!.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text('Route: ${bus.route}',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
          if (bus.recordedAt != null)
            Text('Last ping ${DateFormat.Hm().format(bus.recordedAt!.toLocal())}'
                '${bus.speedKmh != null ? ' Â· ${bus.speedKmh!.toStringAsFixed(0)} km/h' : ''}',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _assignDriver(context, ref, bus),
                icon: const Icon(LucideIcons.userPlus, size: 15),
                label: const Text('Assign driver', style: TextStyle(fontSize: 12)),
              ),
              TextButton.icon(
                onPressed: () => _editBus(context, ref, bus: bus),
                icon: const Icon(LucideIcons.pencil, size: 15),
                label: const Text('Edit', style: TextStyle(fontSize: 12)),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _reportNow(context, ref, bus),
                icon: const Icon(LucideIcons.mapPin, size: 15),
                label: const Text('Ping now', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Create or edit a bus.
  Future<void> _editBus(BuildContext context, WidgetRef ref,
      {LiveBus? bus}) async {
    final nameCtl = TextEditingController(text: bus?.name ?? '');
    final routeCtl = TextEditingController(text: bus?.route ?? '');
    final client = Supabase.instance.client;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(bus == null ? 'Add a bus' : 'Edit bus'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtl,
              decoration: const InputDecoration(labelText: 'Bus name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: routeCtl,
              decoration: const InputDecoration(
                  labelText: 'Route / description'),
            ),
          ],
        ),
        actions: [
          if (bus != null)
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx, false);
                await client
                    .from('church_buses')
                    .update({'is_active': false}).eq('id', bus.busId);
                ref.invalidate(liveBusesProvider(tenantId));
              },
              child: const Text('RETIRE',
                  style: TextStyle(color: Colors.red)),
            ),
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCEL')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('SAVE')),
        ],
      ),
    );
    if (saved != true || !context.mounted) return;
    final name = nameCtl.text.trim();
    if (name.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (bus == null) {
        await client.from('church_buses').insert({
          'tenant_id': tenantId,
          'name': name,
          'route': routeCtl.text.trim(),
          'is_active': true,
        });
      } else {
        await client.from('church_buses').update({
          'name': name,
          'route': routeCtl.text.trim(),
        }).eq('id', bus.busId);
      }
      ref.invalidate(liveBusesProvider(tenantId));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('Could not save: $e'), backgroundColor: Colors.red));
    }
  }

  /// Pick a tenant member and write them onto `driver_id`. This is the link
  /// that lets `LocationTrackerService` recognise them as a bus driver.
  Future<void> _assignDriver(
      BuildContext context, WidgetRef ref, LiveBus bus) async {
    final messenger = ScaffoldMessenger.of(context);
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: _MemberPicker(tenantId: tenantId),
      ),
    );
    if (picked == null || !context.mounted) return;
    try {
      await Supabase.instance.client
          .from('church_buses')
          .update({'driver_id': picked})
          .eq('id', bus.busId);
      ref.invalidate(liveBusesProvider(tenantId));
      messenger.showSnackBar(
          const SnackBar(content: Text('Driver assigned â€” they now feed live position.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('Could not assign: $e'), backgroundColor: Colors.red));
    }
  }

  /// Manual ping â€” useful when a driver has no app, or to test the pipeline.
  Future<void> _reportNow(
      BuildContext context, WidgetRef ref, LiveBus bus) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      await ref.read(mapLiveServiceProvider).reportBusPosition(
            busId: bus.busId,
            tenantId: tenantId,
            lat: p.latitude,
            lng: p.longitude,
            heading: p.heading >= 0 ? p.heading : null,
            speedKmh: p.speed >= 0 ? p.speed * 3.6 : null,
          );
      ref.invalidate(liveBusesProvider(tenantId));
      messenger.showSnackBar(const SnackBar(
          content: Text('Position reported â€” the map will update shortly.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('Could not get a GPS fix: $e'),
          backgroundColor: Colors.red));
    }
  }
}

/// Search this church's members to pick a driver.
class _MemberPicker extends ConsumerStatefulWidget {
  const _MemberPicker({required this.tenantId});

  final String tenantId;

  @override
  ConsumerState<_MemberPicker> createState() => _MemberPickerState();
}

class _MemberPickerState extends ConsumerState<_MemberPicker> {
  final _ctl = TextEditingController();
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    try {
      var sel = Supabase.instance.client
          .from('profiles')
          .select('id, full_name, role, avatar_url')
          .eq('tenant_id', widget.tenantId)
          .filter('deleted_at', 'is', 'null');
      if (q.trim().isNotEmpty) {
        sel = sel.or('full_name.ilike.%${q.trim()}%');
      }
      final res = await sel.order('full_name').limit(30);
      if (mounted) {
        setState(() {
          _rows = (res as List).map((e) => Map<String, dynamic>.from(e)).toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: TextField(
              controller: _ctl,
              onChanged: _search,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search a memberâ€¦',
                prefixIcon: Icon(LucideIcons.search, size: 20),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _rows.length,
                    itemBuilder: (context, i) {
                      final m = _rows[i];
                      final avatar = m['avatar_url']?.toString();
                      return ListTile(
                        leading: ClipOval(
                          child: (avatar != null && avatar.isNotEmpty)
                              ? AppImage(avatar, width: 36, height: 36)
                              : const CircleAvatar(
                                  radius: 18,
                                  child: Icon(LucideIcons.user, size: 18)),
                        ),
                        title: Text(m['full_name']?.toString() ?? 'Member',
                            style: const TextStyle(fontSize: 13)),
                        subtitle: Text(m['role']?.toString() ?? '',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey)),
                        onTap: () => Navigator.pop(context, m['id'].toString()),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
