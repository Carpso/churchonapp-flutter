import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../modules/media/data/radio_service.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import 'package:church_on_app/core/widgets/premium_toast.dart';
import 'package:church_on_app/core/widgets/empty_state_widget.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';

class RadioStationManagementScreen extends ConsumerStatefulWidget {
  const RadioStationManagementScreen({super.key});

  @override
  ConsumerState<RadioStationManagementScreen> createState() => _RadioStationManagementScreenState();
}

class _RadioStationManagementScreenState extends ConsumerState<RadioStationManagementScreen> {
  @override
  Widget build(BuildContext context) {
    final stationsAsync = ref.watch(radioStationsFutureProvider);
    final theme = Theme.of(context);
    final profile = ref.watch(profileProvider);

    return profile.when(
      data: (user) {
        if (user == null || (!user.isSuperadmin && !user.isEmployee)) {
          return Scaffold(
            appBar: AppBar(title: const Text("Radio Stations")),
            body: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.lock, size: 48, color: Colors.grey),
                  SizedBox(height: 12),
                  Text("Access restricted to COA team members.", style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: theme.colorScheme.surface,
          appBar: AppBar(
            title: const Text("Radio Stations", style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: theme.colorScheme.surface,
            elevation: 0,
            foregroundColor: theme.colorScheme.onSurface,
            leading: IconButton(
              icon: const Icon(LucideIcons.chevronLeft),
              onPressed: () => context.canPop() ? Navigator.pop(context) : context.go('/'),
            ),
            actions: [
              IconButton(
                icon: const Icon(LucideIcons.refreshCw),
                onPressed: () => ref.invalidate(radioStationsFutureProvider),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _showStationForm(),
            icon: const Icon(LucideIcons.plus, size: 20),
            label: const Text("Add Station"),
          ),
          body: stationsAsync.when(
            data: (stations) {
              if (stations.isEmpty) {
                return const EmptyStateWidget(
                  icon: LucideIcons.radio,
                  title: 'No Radio Stations',
                  subtitle: 'Tap + to add a radio station',
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                itemCount: stations.length,
                itemBuilder: (context, index) {
                  final station = stations[index];
                  return _StationCard(
                    station: station,
                    onTap: () => _showStationForm(station: station),
                    onDelete: () => _confirmDelete(station),
                    onPlay: () => _previewStation(station),
                  );
                },
              );
            },
            loading: () => const Center(child: ListSkeleton()),
            error: (err, stack) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.alertTriangle, size: 48, color: Colors.red.shade300),
                  const SizedBox(height: 12),
                  Text("Error: $err", style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => ref.invalidate(radioStationsFutureProvider),
                    child: const Text("Retry"),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text("Error: $e"))),
    );
  }

  void _showStationForm({RadioStation? station}) {
    final nameCtrl = TextEditingController(text: station?.name ?? '');
    final urlCtrl = TextEditingController(text: station?.streamUrl ?? '');
    final locCtrl = TextEditingController(text: station?.location ?? '');
    final imgUrlCtrl = TextEditingController(text: '');
    bool isPrivate = station?.isPrivate ?? false;
    final isEditing = station != null;
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(LucideIcons.radio, color: Theme.of(context).primaryColor),
                      const SizedBox(width: 12),
                      Text(
                        isEditing ? "Edit Station" : "Add Station",
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: nameCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: "Station Name",
                      labelStyle: const TextStyle(color: Colors.white60),
                      prefixIcon: const Icon(Icons.radio, color: Colors.white38, size: 20),
                      enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Theme.of(context).primaryColor)),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return "Station name is required";
                      if (val.trim().length < 2) return "Name too short";
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: urlCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: "Stream URL",
                      labelStyle: const TextStyle(color: Colors.white60),
                      prefixIcon: const Icon(Icons.link, color: Colors.white38, size: 20),
                      enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Theme.of(context).primaryColor)),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return "Stream URL is required";
                      final trimmed = val.trim().toLowerCase();
                      if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
                        return "URL must start with http:// or https://";
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: locCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: "Location / Country",
                      labelStyle: const TextStyle(color: Colors.white60),
                      prefixIcon: const Icon(Icons.location_on, color: Colors.white38, size: 20),
                      enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Theme.of(context).primaryColor)),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return "Location is required";
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: imgUrlCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: "Station Image URL (optional)",
                      labelStyle: const TextStyle(color: Colors.white60),
                      prefixIcon: const Icon(Icons.image, color: Colors.white38, size: 20),
                      enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Theme.of(context).primaryColor)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Theme(
                        data: ThemeData(unselectedWidgetColor: Colors.white60),
                        child: Checkbox(
                          value: isPrivate,
                          fillColor: WidgetStateProperty.resolveWith((states) => Colors.amber),
                          checkColor: Colors.black,
                          onChanged: (val) => setSheetState(() => isPrivate = val ?? false),
                        ),
                      ),
                      const Text("Private Station", style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () async {
                      if (!formKey.currentState!.validate()) return;
                      try {
                        final updateData = {
                          'name': nameCtrl.text.trim(),
                          'stream_url': urlCtrl.text.trim(),
                          'location': locCtrl.text.trim(),
                          'is_private': isPrivate,
                        };
                        if (imgUrlCtrl.text.trim().isNotEmpty) {
                          updateData['image_url'] = imgUrlCtrl.text.trim();
                        }
                        if (isEditing) {
                          await ref.read(radioServiceProvider).updateStation(station.id, updateData);
                        } else {
                          await ref.read(radioServiceProvider).addStation(
                            name: nameCtrl.text.trim(),
                            streamUrl: urlCtrl.text.trim(),
                            location: locCtrl.text.trim(),
                            isPrivate: isPrivate,
                          );
                        }
                        ref.invalidate(radioStationsFutureProvider);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          PremiumToast.showSuccess(context, isEditing ? "Station updated!" : "Station added!");
                        }
                      } catch (e) {
                        if (ctx.mounted) PremiumToast.showError(ctx, "Error: $e");
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(isEditing ? "UPDATE STATION" : "ADD STATION", style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(RadioStation station) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Station?"),
        content: Text("Are you sure you want to delete \"${station.name}\"? This cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("CANCEL")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text("DELETE"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ref.read(radioServiceProvider).deleteStation(station.id);
        ref.invalidate(radioStationsFutureProvider);
        if (mounted) PremiumToast.showSuccess(context, "${station.name} deleted");
      } catch (e) {
        if (mounted) PremiumToast.showError(context, "Delete failed: $e");
      }
    }
  }

  Future<void> _previewStation(RadioStation station) async {
    try {
      await ref.read(radioServiceProvider).playStation(station);
      if (mounted) PremiumToast.showInfo(context, "Playing ${station.name}");
    } catch (e) {
      if (mounted) PremiumToast.showError(context, "Could not play ${station.name}");
    }
  }
}

class _StationCard extends StatelessWidget {
  final RadioStation station;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onPlay;

  const _StationCard({
    required this.station,
    required this.onTap,
    required this.onDelete,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dismissible(
      key: ValueKey(station.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onDelete();
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: Colors.red.shade800,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(LucideIcons.trash2, color: Colors.white),
      ),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  station.isPrivate ? LucideIcons.lock : LucideIcons.radio,
                  color: station.isPrivate ? Colors.amber : theme.primaryColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            station.name,
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: theme.colorScheme.onSurface),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (station.isPrivate)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text("PRIVATE", style: TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      station.streamUrl,
                      style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.4), fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(LucideIcons.mapPin, size: 10, color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
                        const SizedBox(width: 4),
                        Text(
                          station.location,
                          style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onPlay,
                icon: Icon(LucideIcons.playCircle, color: theme.primaryColor, size: 28),
                tooltip: "Preview",
              ),
              Icon(LucideIcons.chevronRight, size: 16, color: theme.colorScheme.onSurface.withValues(alpha: 0.2)),
            ],
          ),
        ),
      ),
    );
  }
}
