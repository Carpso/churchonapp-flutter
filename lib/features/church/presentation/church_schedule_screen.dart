import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/services/tenant_service.dart';

import '../data/church_schedule_service.dart';
import '../data/church_service_time.dart';

class ChurchScheduleScreen extends ConsumerStatefulWidget {
  const ChurchScheduleScreen({super.key});

  @override
  ConsumerState<ChurchScheduleScreen> createState() => _ChurchScheduleScreenState();
}

class _ChurchScheduleScreenState extends ConsumerState<ChurchScheduleScreen> {
  List<ChurchServiceTime> _items = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tenant = ref.read(currentTenantProvider);
    if (tenant == null) {
      setState(() { _loading = false; _error = 'No church selected'; });
      return;
    }
    try {
      final schedule = await ref.read(churchScheduleServiceProvider).fetchSchedule(tenant.id);
      if (mounted) setState(() { _items = schedule; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _save() async {
    final tenant = ref.read(currentTenantProvider);
    if (tenant == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(churchScheduleServiceProvider).saveSchedule(tenant.id, _items);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Service schedule saved'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _addService() {
    setState(() {
      _items.add(const ChurchServiceTime(
        dayOfWeek: 7, // Sunday
        title: 'Sunday Main Service',
        startTime: TimeOfDay(hour: 9, minute: 0),
        endTime: TimeOfDay(hour: 11, minute: 30),
        enableCarpso: true,
      ));
    });
  }

  void _removeAt(int index) => setState(() => _items.removeAt(index));

  void _update(int index, ChurchServiceTime updated) => setState(() => _items[index] = updated);

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).value;
    final canEdit = profile?.isAdminOrHigher ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Church Service Schedule'),
        actions: [
          if (canEdit && !_loading)
            TextButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(LucideIcons.save, size: 18),
              label: const Text('SAVE'),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Set the days and times your church meets. Carpso Ride cards will automatically appear on these days.',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    ..._items.asMap().entries.map((e) => _ServiceEditorCard(
                          key: ValueKey(e.key),
                          service: e.value,
                          onChanged: (s) => _update(e.key, s),
                          onDelete: () => _removeAt(e.key),
                          editable: canEdit,
                        )),
                    if (_items.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Text('No services scheduled yet.', style: TextStyle(color: Colors.grey.shade600)),
                        ),
                      ),
                    const SizedBox(height: 20),
                    if (canEdit)
                      ElevatedButton.icon(
                        onPressed: _addService,
                        icon: const Icon(LucideIcons.plus),
                        label: const Text('ADD SERVICE'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    if (!canEdit)
                      const Card(
                        color: Color(0xFFFFF8E1),
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Icon(LucideIcons.info, color: Colors.orange),
                              SizedBox(width: 10),
                              Expanded(child: Text('Only pastors, bishops, admins or assigned leaders can edit the schedule.', style: TextStyle(fontSize: 12))),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}

class _ServiceEditorCard extends StatelessWidget {
  final ChurchServiceTime service;
  final ValueChanged<ChurchServiceTime> onChanged;
  final VoidCallback onDelete;
  final bool editable;

  const _ServiceEditorCard({
    super.key,
    required this.service,
    required this.onChanged,
    required this.onDelete,
    required this.editable,
  });

  static const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: service.title,
                    enabled: editable,
                    decoration: const InputDecoration(labelText: 'Service Title', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                    onChanged: (v) => onChanged(service.copyWith(title: v)),
                  ),
                ),
                if (editable) ...[
                  const SizedBox(width: 8),
                  IconButton(icon: const Icon(LucideIcons.trash2, color: Colors.red), onPressed: onDelete),
                ],
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: service.dayOfWeek,
              decoration: const InputDecoration(labelText: 'Day of Week', border: OutlineInputBorder()),
              items: List.generate(7, (i) => DropdownMenuItem(value: i + 1, child: Text(_days[i]))),
              onChanged: editable ? (v) { if (v != null) onChanged(service.copyWith(dayOfWeek: v)); } : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _TimePickerField(
                    label: 'Start Time',
                    time: service.startTime,
                    enabled: editable,
                    onChanged: (t) => onChanged(service.copyWith(startTime: t)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TimePickerField(
                    label: 'End Time (optional)',
                    time: service.endTime,
                    enabled: editable,
                    nullable: true,
                    onChanged: (t) => onChanged(service.copyWith(endTime: t)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: service.description ?? '',
              enabled: editable,
              decoration: const InputDecoration(labelText: 'Description (optional)', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
              maxLines: 2,
              onChanged: (v) => onChanged(service.copyWith(description: v)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(LucideIcons.info, size: 14, color: Colors.grey),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Carpso Ride cards appear automatically on service days (managed by COA).',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TimePickerField extends StatelessWidget {
  final String label;
  final TimeOfDay? time;
  final bool enabled;
  final bool nullable;
  final ValueChanged<TimeOfDay?> onChanged;

  const _TimePickerField({required this.label, required this.time, required this.enabled, this.nullable = false, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final display = time == null ? '--:--' : time!.format(context);
    return InputDecorator(
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      child: InkWell(
        onTap: enabled
            ? () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: time ?? const TimeOfDay(hour: 9, minute: 0),
                );
                if (nullable && picked == null) {
                  onChanged(null);
                } else if (picked != null) {
                  onChanged(picked);
                }
              }
            : null,
        child: Text(display, style: const TextStyle(fontSize: 14)),
      ),
    );
  }
}

extension _CopyChurchServiceTime on ChurchServiceTime {
  ChurchServiceTime copyWith({
    int? dayOfWeek,
    String? title,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    String? description,
    bool? enableCarpso,
  }) {
    return ChurchServiceTime(
      dayOfWeek: dayOfWeek ?? this.dayOfWeek,
      title: title ?? this.title,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      description: description ?? this.description,
      enableCarpso: enableCarpso ?? this.enableCarpso,
    );
  }
}
