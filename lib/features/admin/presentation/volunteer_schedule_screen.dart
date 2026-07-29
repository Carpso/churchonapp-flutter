import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/widgets/premium_toast.dart';

class VolunteerScheduleScreen extends ConsumerStatefulWidget {
  const VolunteerScheduleScreen({super.key});

  @override
  ConsumerState<VolunteerScheduleScreen> createState() =>
      _VolunteerScheduleScreenState();
}

class _VolunteerScheduleScreenState
    extends ConsumerState<VolunteerScheduleScreen> {
  DateTime _selectedWeek = _startOfWeek(DateTime.now());
  List<Map<String, dynamic>> _schedules = [];
  bool _isLoading = true;

  static DateTime _startOfWeek(DateTime dt) {
    final diff = dt.weekday - DateTime.monday;
    return DateTime(dt.year, dt.month, dt.day - diff);
  }

  final List<Map<String, dynamic>> _ministries = [
    {'value': 'ushering', 'label': 'Ushering', 'icon': LucideIcons.doorOpen, 'color': Colors.blue},
    {'value': 'worship', 'label': 'Worship Team', 'icon': LucideIcons.music, 'color': Colors.purple},
    {'value': 'media', 'label': 'Media/AV', 'icon': LucideIcons.monitor, 'color': Colors.teal},
    {'value': 'children', 'label': "Children's Church", 'icon': LucideIcons.baby, 'color': Colors.orange},
    {'value': 'parking', 'label': 'Parking/Security', 'icon': LucideIcons.shield, 'color': Colors.red},
    {'value': 'cleaning', 'label': 'Cleaning', 'icon': LucideIcons.sparkles, 'color': Colors.green},
    {'value': 'prayer', 'label': 'Prayer Team', 'icon': LucideIcons.heart, 'color': Colors.pink},
    {'value': 'hospitality', 'label': 'Hospitality', 'icon': LucideIcons.coffee, 'color': Colors.amber},
  ];

  @override
  void initState() {
    super.initState();
    _loadSchedules();
  }

  Future<void> _loadSchedules() async {
    final tenant = ref.read(currentTenantProvider);
    if (tenant == null) return;

    setState(() => _isLoading = true);
    try {
      final weekEnd = _selectedWeek.add(const Duration(days: 7));
      final data = await Supabase.instance.client
          .from('volunteer_schedules')
          .select('*, profiles!volunteer_schedules_volunteer_id_fkey(full_name, avatar_url)')
          .eq('tenant_id', tenant.id)
          .gte('schedule_date', _selectedWeek.toIso8601String().split('T')[0])
          .lt('schedule_date', weekEnd.toIso8601String().split('T')[0])
          .order('schedule_date', ascending: true);

      if (mounted) {
        setState(() {
          _schedules = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading volunteer schedules: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _changeWeek(int offset) {
    setState(() {
      _selectedWeek = _selectedWeek.add(Duration(days: 7 * offset));
    });
    _loadSchedules();
  }

  Future<void> _addShift() async {
    final tenant = ref.read(currentTenantProvider);
    if (tenant == null) return;

    DateTime shiftDate = DateTime.now();
    String ministry = 'ushering';
    String role = 'Volunteer';
    String? selectedVolunteerId;
    String? volunteerName;
    TimeOfDay startTime = const TimeOfDay(hour: 8, minute: 0);
    TimeOfDay endTime = const TimeOfDay(hour: 12, minute: 0);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.75,
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.all(24),
            child: ListView(
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[400],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Add Volunteer Shift',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),

                // Date picker
                ListTile(
                  leading: const Icon(LucideIcons.calendar),
                  title: const Text('Date'),
                  subtitle: Text(DateFormat('EEEE, MMM d').format(shiftDate)),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: shiftDate,
                      firstDate: DateTime.now().subtract(const Duration(days: 7)),
                      lastDate: DateTime.now().add(const Duration(days: 90)),
                    );
                    if (picked != null) {
                      setSheetState(() => shiftDate = picked);
                    }
                  },
                ),

                // Time range
                Row(
                  children: [
                    Expanded(
                      child: ListTile(
                        leading: const Icon(LucideIcons.clock, size: 18),
                        title: const Text('Start', style: TextStyle(fontSize: 13)),
                        subtitle: Text(startTime.format(context)),
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: startTime,
                          );
                          if (picked != null) {
                            setSheetState(() => startTime = picked);
                          }
                        },
                      ),
                    ),
                    Expanded(
                      child: ListTile(
                        leading: const Icon(LucideIcons.clock, size: 18),
                        title: const Text('End', style: TextStyle(fontSize: 13)),
                        subtitle: Text(endTime.format(context)),
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: endTime,
                          );
                          if (picked != null) {
                            setSheetState(() => endTime = picked);
                          }
                        },
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Ministry selector
                const Text('Ministry', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _ministries.map((m) {
                    final isSelected = ministry == m['value'];
                    return GestureDetector(
                      onTap: () => setSheetState(() => ministry = m['value'] as String),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? (m['color'] as Color).withValues(alpha: 0.15)
                              : Colors.grey.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected ? m['color'] as Color : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(m['icon'] as IconData, size: 14, color: m['color'] as Color),
                            const SizedBox(width: 6),
                            Text(
                              m['label'] as String,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 16),

                // Volunteer picker
                ListTile(
                  leading: const Icon(LucideIcons.user),
                  title: const Text('Assign Volunteer'),
                  subtitle: Text(volunteerName ?? 'Tap to select'),
                  onTap: () async {
                    final result = await _showVolunteerPicker(context, tenant.id);
                    if (result != null) {
                      setSheetState(() {
                        selectedVolunteerId = result['id'];
                        volunteerName = result['full_name'];
                      });
                    }
                  },
                ),

                // Role
                TextFormField(
                  initialValue: role,
                  decoration: const InputDecoration(
                    labelText: 'Role / Position',
                    hintText: 'e.g., Lead Usher, Drummer',
                  ),
                  onChanged: (v) => role = v,
                ),

                const SizedBox(height: 24),

                // Submit
                ElevatedButton(
                  onPressed: () async {
                    if (selectedVolunteerId == null) {
                      PremiumToast.showError(context, 'Please select a volunteer');
                      return;
                    }
                    try {
                      await Supabase.instance.client.from('volunteer_schedules').insert({
                        'tenant_id': tenant.id,
                        'volunteer_id': selectedVolunteerId,
                        'ministry': ministry,
                        'role': role,
                        'schedule_date': shiftDate.toIso8601String().split('T')[0],
                        'start_time': '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}',
                        'end_time': '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}',
                      });
                      if (context.mounted) Navigator.pop(context);
                      _loadSchedules();
                    } catch (e) {
                      if (context.mounted) {
                        PremiumToast.showError(context, 'Failed to add shift: $e');
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('ADD SHIFT', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<Map<String, dynamic>?> _showVolunteerPicker(
      BuildContext context, String tenantId) async {
    final members = await Supabase.instance.client
        .from('profiles')
        .select('id, full_name, avatar_url, role')
        .eq('tenant_id', tenantId)
        .order('full_name', ascending: true);

    if (!context.mounted) return null;

    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        String query = '';
        return StatefulBuilder(
          builder: (context, setPickerState) {
            final filtered = (members as List).where((m) {
              final name = (m['full_name'] ?? '').toString().toLowerCase();
              return query.isEmpty || name.contains(query.toLowerCase());
            }).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.6,
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Search members...',
                        prefixIcon: const Icon(LucideIcons.search, size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onChanged: (v) => setPickerState(() => query = v),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final m = filtered[index];
                        return ListTile(
                          leading: CircleAvatar(
                            child: Text(
                              ((m['full_name'] ?? '?') as String).isNotEmpty
                                  ? (m['full_name'] as String)[0].toUpperCase()
                                  : '?',
                            ),
                          ),
                          title: Text(m['full_name'] ?? 'Unknown'),
                          subtitle: Text(m['role'] ?? 'Member', style: const TextStyle(fontSize: 12)),
                          onTap: () => Navigator.pop(context, m),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Color _ministryColor(String ministry) {
    final match = _ministries.firstWhere(
      (m) => m['value'] == ministry,
      orElse: () => {'color': Colors.grey},
    );
    return match['color'] as Color;
  }

  IconData _ministryIcon(String ministry) {
    final match = _ministries.firstWhere(
      (m) => m['value'] == ministry,
      orElse: () => {'icon': LucideIcons.user},
    );
    return match['icon'] as IconData;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weekEnd = _selectedWeek.add(const Duration(days: 6));
    final weekLabel =
        '${DateFormat('MMM d').format(_selectedWeek)} – ${DateFormat('MMM d').format(weekEnd)}';

    // Group schedules by day
    final Map<String, List<Map<String, dynamic>>> byDay = {};
    for (final s in _schedules) {
      final date = (s['schedule_date'] ?? '').toString().split('T')[0];
      byDay.putIfAbsent(date, () => []).add(s);
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Volunteer Schedule',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addShift,
        icon: const Icon(LucideIcons.plus),
        label: const Text('Add Shift'),
        backgroundColor: theme.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // ── Week Navigator ─────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: theme.colorScheme.surface,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(LucideIcons.chevronLeft),
                  onPressed: () => _changeWeek(-1),
                ),
                Column(
                  children: [
                    Text(
                      weekLabel,
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      '${_schedules.length} shift${_schedules.length == 1 ? '' : 's'} this week',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(LucideIcons.chevronRight),
                  onPressed: () => _changeWeek(1),
                ),
              ],
            ),
          ),

          // ── Schedule List ──────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _schedules.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.calendarOff,
                                size: 48,
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.2)),
                            const SizedBox(height: 12),
                            Text(
                              'No shifts scheduled this week',
                              style: TextStyle(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: _addShift,
                              icon: const Icon(LucideIcons.plus, size: 16),
                              label: const Text('Add a shift'),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadSchedules,
                        child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: byDay.entries.map((entry) {
                            final date = DateTime.parse(entry.key);
                            final shifts = entry.value;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: Text(
                                    DateFormat('EEEE, MMM d').format(date),
                                    style: GoogleFonts.plusJakartaSans(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                    ),
                                  ),
                                ),
                                ...shifts.map((s) => _buildShiftCard(s, theme)),
                                const SizedBox(height: 8),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildShiftCard(Map<String, dynamic> shift, ThemeData theme) {
    final ministry = shift['ministry'] ?? 'unknown';
    final role = shift['role'] ?? 'Volunteer';
    final profile = shift['profiles'] as Map<String, dynamic>?;
    final name = profile?['full_name'] ?? 'Unassigned';
    final startTime = shift['start_time'] ?? '';
    final endTime = shift['end_time'] ?? '';
    final color = _ministryColor(ministry);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border(
          left: BorderSide(color: color, width: 4),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(_ministryIcon(ministry), size: 18, color: color),
        ),
        title: Text(
          name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              role,
              style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
            ),
            if (startTime.isNotEmpty)
              Text(
                '$startTime – $endTime',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
          ],
        ),
        trailing: IconButton(
          icon: Icon(LucideIcons.trash2,
              size: 16, color: Colors.red.withValues(alpha: 0.5)),
          onPressed: () async {
            try {
              await Supabase.instance.client
                  .from('volunteer_schedules')
                  .delete()
                  .eq('id', shift['id']);
              _loadSchedules();
              if (mounted) {
                PremiumToast.showSuccess(context, 'Shift removed');
              }
            } catch (e) {
              if (mounted) {
                PremiumToast.showError(context, 'Failed to delete shift');
              }
            }
          },
        ),
      ),
    );
  }
}
