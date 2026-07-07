import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

class MinistryScheduleEntry {
  final String id;
  final String ministryName;
  final DateTime date;
  final TimeOfDay time;
  final String location;
  final String leader;

  MinistryScheduleEntry({
    required this.id,
    required this.ministryName,
    required this.date,
    required this.time,
    required this.location,
    required this.leader,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'ministry_name': ministryName,
    'date': date.toIso8601String(),
    'time_hour': time.hour,
    'time_minute': time.minute,
    'location': location,
    'leader': leader,
  };

  factory MinistryScheduleEntry.fromJson(Map<String, dynamic> json) => MinistryScheduleEntry(
    id: json['id'] as String,
    ministryName: json['ministry_name'] as String,
    date: DateTime.parse(json['date'] as String),
    time: TimeOfDay(hour: json['time_hour'] as int, minute: json['time_minute'] as int),
    location: json['location'] as String? ?? '',
    leader: json['leader'] as String? ?? '',
  );
}

class MinistryScheduleNotifier extends Notifier<List<MinistryScheduleEntry>> {
  @override
  List<MinistryScheduleEntry> build() => [];

  void addEntry(MinistryScheduleEntry entry) {
    state = [...state, entry];
  }

  void updateEntry(MinistryScheduleEntry entry) {
    state = state.map((e) => e.id == entry.id ? entry : e).toList();
  }

  void removeEntry(String id) {
    state = state.where((e) => e.id != id).toList();
  }
}

final ministryScheduleProvider = NotifierProvider<MinistryScheduleNotifier, List<MinistryScheduleEntry>>(
  MinistryScheduleNotifier.new,
);

class MinistryScheduleScreen extends ConsumerStatefulWidget {
  const MinistryScheduleScreen({super.key});

  @override
  ConsumerState<MinistryScheduleScreen> createState() => _MinistryScheduleScreenState();
}

class _MinistryScheduleScreenState extends ConsumerState<MinistryScheduleScreen> {
  DateTime _currentMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _selectedDay;

  @override
  Widget build(BuildContext context) {
    final schedules = ref.watch(ministryScheduleProvider);
    final schedulesForSelectedDay = _selectedDay != null
        ? schedules.where((s) =>
            s.date.year == _selectedDay!.year &&
            s.date.month == _selectedDay!.month &&
            s.date.day == _selectedDay!.day).toList()
        : <MinistryScheduleEntry>[];

    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text('Ministry Schedule'),
        backgroundColor: const Color(0xFFFFFAEB),
        elevation: 0,
        foregroundColor: Colors.black87,
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          _buildMonthNavigation(),
          Expanded(
            child: schedules.isEmpty
                ? _buildEmptyState()
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                    children: [
                      _buildCalendarGrid(schedules),
                      if (_selectedDay != null) ...[
                        const SizedBox(height: 20),
                        _buildSelectedDayHeader(),
                        if (schedulesForSelectedDay.isEmpty)
                          _buildNoScheduleForDay()
                        else
                          ...schedulesForSelectedDay.map(_buildScheduleCard),
                      ],
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showScheduleForm(null),
        backgroundColor: Colors.amber,
        child: const Icon(LucideIcons.plus, color: Colors.white),
      ),
    );
  }

  Widget _buildMonthNavigation() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(LucideIcons.chevronLeft),
            onPressed: () => setState(() {
              _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
              _selectedDay = null;
            }),
          ),
          Text(
            DateFormat('MMMM yyyy').format(_currentMonth),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          IconButton(
            icon: const Icon(LucideIcons.chevronRight),
            onPressed: () => setState(() {
              _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
              _selectedDay = null;
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarGrid(List<MinistryScheduleEntry> schedules) {
    final daysInMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 0).day;
    final firstWeekday = DateTime(_currentMonth.year, _currentMonth.month, 1).weekday % 7;

    final scheduledDates = schedules
        .where((s) => s.date.year == _currentMonth.year && s.date.month == _currentMonth.month)
        .map((s) => s.date.day)
        .toSet();

    final today = DateTime.now();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
                .map((d) => Expanded(
                      child: Center(
                        child: Text(d, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[500])),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 4),
          Wrap(
            children: List.generate(42, (index) {
              final day = index - firstWeekday + 1;
              if (day < 1 || day > daysInMonth) {
                return const SizedBox(width: 0, height: 0);
              }

              final isSelected = _selectedDay != null &&
                  _selectedDay!.day == day &&
                  _selectedDay!.month == _currentMonth.month;
              final isToday = today.year == _currentMonth.year &&
                  today.month == _currentMonth.month &&
                  today.day == day;
              final hasSchedule = scheduledDates.contains(day);

              return SizedBox(
                width: (MediaQuery.of(context).size.width - 64) / 7,
                height: 44,
                child: GestureDetector(
                  onTap: () => setState(() {
                    _selectedDay = DateTime(_currentMonth.year, _currentMonth.month, day);
                  }),
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.amber : null,
                      shape: BoxShape.circle,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$day',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected || isToday ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? Colors.white : (isToday ? Colors.amber : Colors.black87),
                          ),
                        ),
                        if (hasSchedule)
                          Container(
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(
                              color: Colors.amber,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedDayHeader() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(LucideIcons.calendar, size: 16, color: Colors.amber),
          ),
          const SizedBox(width: 12),
          Text(
            DateFormat('EEEE, MMMM d, yyyy').format(_selectedDay!),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildNoScheduleForDay() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
      ),
      child: Column(
        children: [
          Icon(LucideIcons.calendarX, size: 40, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text('No ministries scheduled for this day',
              style: TextStyle(color: Colors.grey[500], fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildScheduleCard(MinistryScheduleEntry entry) {
    final timeString = entry.time.format(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(LucideIcons.church, color: Colors.amber, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.ministryName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 6),
                _buildInfoRow(LucideIcons.clock, timeString),
                const SizedBox(height: 2),
                if (entry.location.isNotEmpty)
                  _buildInfoRow(LucideIcons.mapPin, entry.location),
                if (entry.leader.isNotEmpty)
                  _buildInfoRow(LucideIcons.user, entry.leader),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _confirmDelete(entry),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(LucideIcons.trash2, size: 18, color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 12, color: Colors.grey[500]),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.calendarDays, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 20),
          Text('No schedules yet', style: TextStyle(color: Colors.grey[500], fontSize: 16)),
          const SizedBox(height: 8),
          Text('Tap + to add a ministry schedule', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
        ],
      ),
    );
  }

  void _confirmDelete(MinistryScheduleEntry entry) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Schedule'),
        content: Text('Remove "${entry.ministryName}" from this schedule?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              ref.read(ministryScheduleProvider.notifier).removeEntry(entry.id);
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showScheduleForm(MinistryScheduleEntry? existing) {
    final isEditing = existing != null;
    final ministryNameController = TextEditingController(text: existing?.ministryName ?? '');
    final locationController = TextEditingController(text: existing?.location ?? '');
    final leaderController = TextEditingController(text: existing?.leader ?? '');
    final selectedDate = ValueNotifier<DateTime>(existing?.date ?? DateTime.now());
    final selectedTime = ValueNotifier<TimeOfDay>(existing?.time ?? const TimeOfDay(hour: 9, minute: 0));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              decoration: const BoxDecoration(
                color: Color(0xFFFFFAEB),
                borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            isEditing ? 'Edit Schedule' : 'New Schedule Entry',
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(LucideIcons.x),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFormField('Ministry Name', ministryNameController, LucideIcons.church),
                          const SizedBox(height: 16),
                          ValueListenableBuilder<DateTime>(
                            valueListenable: selectedDate,
                            builder: (context, date, _) => _buildDatePicker(date, (d) => selectedDate.value = d),
                          ),
                          const SizedBox(height: 16),
                          ValueListenableBuilder<TimeOfDay>(
                            valueListenable: selectedTime,
                            builder: (context, time, _) => _buildTimePicker(time, (t) => selectedTime.value = t),
                          ),
                          const SizedBox(height: 16),
                          _buildFormField('Location', locationController, LucideIcons.mapPin),
                          const SizedBox(height: 16),
                          _buildFormField('Leader', leaderController, LucideIcons.user),
                          const SizedBox(height: 30),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: () {
                                final name = ministryNameController.text.trim();
                                if (name.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Please enter a ministry name'), backgroundColor: Colors.red),
                                  );
                                  return;
                                }
                                final entry = MinistryScheduleEntry(
                                  id: existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
                                  ministryName: name,
                                  date: selectedDate.value,
                                  time: selectedTime.value,
                                  location: locationController.text.trim(),
                                  leader: leaderController.text.trim(),
                                );
                                if (isEditing) {
                                  ref.read(ministryScheduleProvider.notifier).updateEntry(entry);
                                } else {
                                  ref.read(ministryScheduleProvider.notifier).addEntry(entry);
                                }
                                Navigator.pop(ctx);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.amber,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                              ),
                              child: Text(
                                isEditing ? 'Update Schedule' : 'Save Schedule',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
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

  Widget _buildFormField(String label, TextEditingController controller, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 5)],
          ),
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              prefixIcon: Icon(icon, size: 18, color: Colors.grey),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDatePicker(DateTime date, ValueChanged<DateTime> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Date', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: date,
              firstDate: DateTime(2020),
              lastDate: DateTime(2035),
            );
            if (picked != null) onChanged(picked);
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 5)],
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.calendar, size: 18, color: Colors.grey),
                const SizedBox(width: 12),
                Text(
                  DateFormat('MMM d, yyyy').format(date),
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimePicker(TimeOfDay time, ValueChanged<TimeOfDay> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Time', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () async {
            final picked = await showTimePicker(context: context, initialTime: time);
            if (picked != null) onChanged(picked);
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 5)],
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.clock, size: 18, color: Colors.grey),
                const SizedBox(width: 12),
                Text(
                  time.format(context),
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
