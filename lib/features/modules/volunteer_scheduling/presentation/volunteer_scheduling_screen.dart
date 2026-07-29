import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:church_on_app/core/widgets/premium_toast.dart';

/// Volunteer scheduling service
class VolunteerService {
  final SupabaseClient _client;

  VolunteerService(this._client);

  /// Get volunteer schedules for a church
  Future<List<Map<String, dynamic>>> getSchedules(String tenantId) async {
    final result = await _client
        .from('volunteer_schedules')
        .select('*, profiles!volunteer_id(full_name, avatar_url)')
        .eq('church_id', tenantId)
        .gte('date', DateTime.now().subtract(Duration(days: 1)).toIso8601String())
        .order('date');

    return List<Map<String, dynamic>>.from(result);
  }

  /// Get available slots
  Future<List<Map<String, dynamic>>> getAvailableSlots(String tenantId) async {
    final result = await _client
        .from('volunteer_slots')
        .select()
        .eq('church_id', tenantId)
        .eq('is_active', true)
        .order('date');

    return List<Map<String, dynamic>>.from(result);
  }

  /// Sign up for a slot
  Future<void> signUpForSlot({
    required String slotId,
    required String userId,
    String? notes,
  }) async {
    await _client.from('volunteer_signups').insert({
      'slot_id': slotId,
      'user_id': userId,
      'notes': notes,
      'status': 'confirmed',
    });
  }

  /// Cancel sign-up
  Future<void> cancelSignUp(String signupId) async {
    await _client
        .from('volunteer_signups')
        .update({'status': 'cancelled'})
        .eq('id', signupId);
  }

  /// Create a volunteer slot (admin)
  Future<Map<String, dynamic>> createSlot({
    required String tenantId,
    required String title,
    required DateTime date,
    required TimeOfDay startTime,
    required TimeOfDay endTime,
    required int spotsNeeded,
    String? description,
    String? ministry,
  }) async {
    final startDateTime = DateTime(
      date.year, date.month, date.day, startTime.hour, startTime.minute,
    );
    final endDateTime = DateTime(
      date.year, date.month, date.day, endTime.hour, endTime.minute,
    );

    final result = await _client
        .from('volunteer_slots')
        .insert({
          'church_id': tenantId,
          'title': title,
          'description': description,
          'ministry': ministry,
          'date': date.toIso8601String(),
          'start_time': startDateTime.toIso8601String(),
          'end_time': endDateTime.toIso8601String(),
          'spots_needed': spotsNeeded,
          'created_by': _client.auth.currentUser?.id,
        })
        .select()
        .single();

    return result;
  }

  /// Get user's sign-ups
  Future<List<Map<String, dynamic>>> getMySignUps(String userId) async {
    final result = await _client
        .from('volunteer_signups')
        .select('*, volunteer_slots!slot_id(*)')
        .eq('user_id', userId)
        .eq('status', 'confirmed')
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(result);
  }

  /// Send reminder notifications for upcoming slots
  Future<void> sendReminders(String tenantId) async {
    final tomorrow = DateTime.now().add(Duration(days: 1));
    final slots = await _client
        .from('volunteer_slots')
        .select('*, volunteer_signups!slot_id(user_id)')
        .eq('church_id', tenantId)
        .eq('date', DateFormat('yyyy-MM-dd').format(tomorrow));

    // Send reminders to each signed-up volunteer
    for (final slot in slots) {
      final signups = slot['volunteer_signups'] as List? ?? [];
      for (final signup in signups) {
        if (signup['user_id'] != null) {
          await _client.from('notifications').insert({
            'user_id': signup['user_id'],
            'title': 'Volunteer Reminder',
            'body': 'You\'re scheduled for "${slot['title']}" tomorrow!',
            'type': 'volunteer_reminder',
            'reference_id': slot['id'],
          });
        }
      }
    }
  }
}

final volunteerServiceProvider = Provider<VolunteerService>((ref) {
  return VolunteerService(Supabase.instance.client);
});

final volunteerSlotsProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, tenantId) async {
  final service = ref.watch(volunteerServiceProvider);
  return service.getAvailableSlots(tenantId);
});

final myVolunteerSignUpsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final service = ref.watch(volunteerServiceProvider);
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) return [];
  return service.getMySignUps(userId);
});

/// Volunteer scheduling screen
class VolunteerSchedulingScreen extends ConsumerStatefulWidget {
  final String tenantId;

  const VolunteerSchedulingScreen({super.key, required this.tenantId});

  @override
  ConsumerState<VolunteerSchedulingScreen> createState() =>
      _VolunteerSchedulingScreenState();
}

class _VolunteerSchedulingScreenState
    extends ConsumerState<VolunteerSchedulingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Volunteer Scheduling'),
        bottom: TabBar(
          controller: _tabController,
          tabAlignment: TabAlignment.start,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Available Slots'),
            Tab(text: 'My Sign-ups'),
          ],
        ),
        actions: [
          // Create slot button (admin only)
          IconButton(
            icon: Icon(Icons.add),
            onPressed: () => _showCreateSlotSheet(context),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _AvailableSlotsTab(tenantId: widget.tenantId),
          _MySignUpsTab(),
        ],
      ),
    );
  }

  void _showCreateSlotSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateSlotSheet(tenantId: widget.tenantId),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}

class _AvailableSlotsTab extends ConsumerWidget {
  final String tenantId;

  const _AvailableSlotsTab({required this.tenantId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slotsAsync = ref.watch(volunteerSlotsProvider(tenantId));

    return slotsAsync.when(
      data: (slots) {
        if (slots.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.event_available, size: 64, color: Colors.grey[400]),
                SizedBox(height: 16),
                Text(
                  'No volunteer slots available',
                  style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                ),
                SizedBox(height: 8),
                Text(
                  'Check back later or create a new slot',
                  style: TextStyle(color: Colors.grey[500]),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: EdgeInsets.all(16),
          itemCount: slots.length,
          itemBuilder: (context, index) => _SlotCard(slot: slots[index]),
        );
      },
      loading: () => Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

class _SlotCard extends ConsumerWidget {
  final Map<String, dynamic> slot;

  const _SlotCard({required this.slot});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = DateTime.parse(slot['date']);
    final startTime = slot['start_time'] != null
        ? DateTime.parse(slot['start_time'])
        : null;
    final endTime = slot['end_time'] != null
        ? DateTime.parse(slot['end_time'])
        : null;
    final signedUp = slot['signed_up_count'] ?? 0;
    final needed = slot['spots_needed'] ?? 1;
    final spotsLeft = needed - signedUp;

    return Container(
      margin: EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Date badge
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Text(
                        DateFormat('MMM').format(date),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                      Text(
                        DateFormat('dd').format(date),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        slot['title'] ?? 'Volunteer Needed',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (slot['ministry'] != null)
                        Text(
                          slot['ministry'],
                          style: TextStyle(color: Colors.grey[600], fontSize: 13),
                        ),
                      if (startTime != null && endTime != null)
                        Text(
                          '${DateFormat('HH:mm').format(startTime)} - ${DateFormat('HH:mm').format(endTime)}',
                          style: TextStyle(color: Colors.grey[600], fontSize: 13),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (slot['description'] != null) ...[
              SizedBox(height: 12),
              Text(
                slot['description'],
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
            SizedBox(height: 12),
            Row(
              children: [
                // Spots indicator
                Icon(Icons.people, size: 16, color: Colors.grey[500]),
                SizedBox(width: 4),
                Text(
                  '$signedUp/$needed spots filled',
                  style: TextStyle(
                    color: spotsLeft > 0 ? Colors.orange : Colors.green,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Spacer(),
                if (spotsLeft > 0)
                  ElevatedButton(
                    onPressed: () => _signUp(context, ref),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                    ),
                    child: Text('Sign Up'),
                  )
                else
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      'Full',
                      style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _signUp(BuildContext context, WidgetRef ref) async {
    final service = ref.read(volunteerServiceProvider);
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await service.signUpForSlot(slotId: slot['id'], userId: userId);
      ref.invalidate(volunteerSlotsProvider(slot['church_id']));
      ref.invalidate(myVolunteerSignUpsProvider);

      if (context.mounted) {
        PremiumToast.showSuccess(context, 'Signed up successfully!');
      }
    } catch (e) {
      if (context.mounted) {
        PremiumToast.showError(context, 'Error: $e');
      }
    }
  }
}

class _MySignUpsTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signUpsAsync = ref.watch(myVolunteerSignUpsProvider);

    return signUpsAsync.when(
      data: (signUps) {
        if (signUps.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.how_to_reg, size: 64, color: Colors.grey[400]),
                SizedBox(height: 16),
                Text(
                  'No volunteer sign-ups yet',
                  style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: EdgeInsets.all(16),
          itemCount: signUps.length,
          itemBuilder: (context, index) {
            final signup = signUps[index];
            final slot = signup['volunteer_slots'] as Map<String, dynamic>?;
            if (slot == null) return SizedBox.shrink();

            final date = DateTime.parse(slot['date']);

            return Container(
              margin: EdgeInsets.only(bottom: 12),
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      DateFormat('MMM dd').format(date),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          slot['title'] ?? 'Volunteer',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        if (slot['ministry'] != null)
                          Text(
                            slot['ministry'],
                            style: TextStyle(color: Colors.grey[600], fontSize: 13),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.cancel, color: Colors.red),
                    onPressed: () => _cancelSignUp(context, ref, signup['id']),
                  ),
                ],
              ),
            );
          },
        );
      },
      loading: () => Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  void _cancelSignUp(BuildContext context, WidgetRef ref, String signupId) async {
    final service = ref.read(volunteerServiceProvider);
    await service.cancelSignUp(signupId);
    ref.invalidate(myVolunteerSignUpsProvider);

    if (context.mounted) {
      PremiumToast.showInfo(context, 'Sign-up cancelled');
    }
  }
}

class _CreateSlotSheet extends ConsumerStatefulWidget {
  final String tenantId;

  const _CreateSlotSheet({required this.tenantId});

  @override
  ConsumerState<_CreateSlotSheet> createState() => _CreateSlotSheetState();
}

class _CreateSlotSheetState extends ConsumerState<_CreateSlotSheet> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _spotsController = TextEditingController(text: '5');
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _startTime = TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = TimeOfDay(hour: 12, minute: 0);
  String? _selectedMinistry;
  bool _saving = false;

  final List<String> _ministries = [
    'Worship',
    'Security',
    'Hospitality',
    'Children\'s Ministry',
    'Media/AV',
    'Prayer',
    'Outreach',
    'Cleanliness',
    'Other',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            margin: EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[400],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.all(24),
              children: [
                Text(
                  'Create Volunteer Slot',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 20),
                // Title
                TextField(
                  controller: _titleController,
                  decoration: InputDecoration(
                    labelText: 'Title',
                    hintText: 'e.g. Sound Technician',
                    border: OutlineInputBorder(),
                  ),
                ),
                SizedBox(height: 16),
                // Ministry dropdown
                DropdownButtonFormField<String>(
                  initialValue: _selectedMinistry,
                  decoration: InputDecoration(
                    labelText: 'Ministry',
                    border: OutlineInputBorder(),
                  ),
                  items: _ministries.map((m) {
                    return DropdownMenuItem(value: m, child: Text(m));
                  }).toList(),
                  onChanged: (value) => setState(() => _selectedMinistry = value),
                ),
                SizedBox(height: 16),
                // Date
                ListTile(
                  leading: Icon(Icons.calendar_today),
                  title: Text('Date'),
                  subtitle: Text(DateFormat('EEEE, MMMM d, yyyy').format(_selectedDate)),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(Duration(days: 90)),
                    );
                    if (date != null) setState(() => _selectedDate = date);
                  },
                ),
                // Times
                Row(
                  children: [
                    Expanded(
                      child: ListTile(
                        leading: Icon(Icons.access_time),
                        title: Text('Start'),
                        subtitle: Text(_startTime.format(context)),
                        onTap: () async {
                          final time = await showTimePicker(
                            context: context,
                            initialTime: _startTime,
                          );
                          if (time != null) setState(() => _startTime = time);
                        },
                      ),
                    ),
                    Expanded(
                      child: ListTile(
                        leading: Icon(Icons.access_time_filled),
                        title: Text('End'),
                        subtitle: Text(_endTime.format(context)),
                        onTap: () async {
                          final time = await showTimePicker(
                            context: context,
                            initialTime: _endTime,
                          );
                          if (time != null) setState(() => _endTime = time);
                        },
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                // Spots needed
                TextField(
                  controller: _spotsController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Spots Needed',
                    border: OutlineInputBorder(),
                  ),
                ),
                SizedBox(height: 16),
                // Description
                TextField(
                  controller: _descriptionController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Description (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                SizedBox(height: 24),
                // Save button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _saving
                        ? CircularProgressIndicator(color: Colors.white)
                        : Text('Create Slot', style: TextStyle(fontSize: 16, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      PremiumToast.showError(context, 'Please enter a title');
      return;
    }

    setState(() => _saving = true);

    try {
      final service = ref.read(volunteerServiceProvider);
      await service.createSlot(
        tenantId: widget.tenantId,
        title: _titleController.text.trim(),
        date: _selectedDate,
        startTime: _startTime,
        endTime: _endTime,
        spotsNeeded: int.tryParse(_spotsController.text) ?? 5,
        description: _descriptionController.text.trim(),
        ministry: _selectedMinistry,
      );

      ref.invalidate(volunteerSlotsProvider(widget.tenantId));

      if (mounted) {
        Navigator.pop(context);
        PremiumToast.showSuccess(context, 'Slot created!');
      }
    } catch (e) {
      if (mounted) {
        PremiumToast.showError(context, 'Error: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _spotsController.dispose();
    super.dispose();
  }
}
