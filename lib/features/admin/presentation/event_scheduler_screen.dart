import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/features/events/data/event_service.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/features/admin/data/event_pass_service.dart';
import 'package:church_on_app/features/events/data/event_rsvp_service.dart';

class EventSchedulerScreen extends ConsumerStatefulWidget {
  const EventSchedulerScreen({super.key});

  @override
  ConsumerState<EventSchedulerScreen> createState() => _EventSchedulerScreenState();
}

class _EventSchedulerScreenState extends ConsumerState<EventSchedulerScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController(text: "Interchurch Conference");
  final _locationController = TextEditingController(text: "Main Sanctuary");
  final _priceController = TextEditingController(text: "0.0");
  final _momoPhoneController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  String _eventType = "Conference";

  late Future<List<Map<String, dynamic>>> _churchesFuture;
  final Set<String> _selectedChurchIds = {};

  @override
  void initState() {
    super.initState();
    _churchesFuture = Supabase.instance.client
        .from('churches')
        .select('id, name')
        .then((data) => List<Map<String, dynamic>>.from(data))
        .catchError((_) => <Map<String, dynamic>>[]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(eventPassServiceProvider);
      ref.read(eventRsvpServiceProvider);
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _priceController.dispose();
    _momoPhoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text("Event Scheduler", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Service & Mission Planning", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const Text("Coordinate your church calendar globally.", style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 30),
            
            _buildInput("Event Title", _titleController, LucideIcons.type),
            const SizedBox(height: 15),
            _buildInput("Description", _descriptionController, LucideIcons.fileText),
            const SizedBox(height: 15),
            _buildInput("Location / Venue", _locationController, LucideIcons.mapPin),
            const SizedBox(height: 15),
            
            Row(
              children: [
                Expanded(child: _buildDatePicker()),
                const SizedBox(width: 15),
                Expanded(child: _buildTimePicker()),
              ],
            ),
            const SizedBox(height: 15),
            
            Row(
              children: [
                Expanded(child: _buildInput("Ticket Price (ZMW)", _priceController, LucideIcons.dollarSign)),
                const SizedBox(width: 15),
                Expanded(child: _buildEventTypeDropdown()),
              ],
            ),
            const SizedBox(height: 15),
            
            _buildInput("Direct Organizer MoMo Phone (For Ticket Payouts)", _momoPhoneController, LucideIcons.phone),
            const SizedBox(height: 25),
            
            const Text("Link Participating Churches", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const Text("Select other churches participating in this interchurch event.", style: TextStyle(color: Colors.grey, fontSize: 11)),
            const SizedBox(height: 10),
            
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _churchesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final list = snapshot.data ?? [];
                if (list.isEmpty) {
                  return const Text("No other churches registered on the platform.");
                }
                return Container(
                  height: 150,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (context, idx) {
                      final ch = list[idx];
                      final name = ch['name'] ?? '';
                      final id = ch['id'] ?? '';
                      final isChecked = _selectedChurchIds.contains(id);
                      return CheckboxListTile(
                        title: Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        value: isChecked,
                        activeColor: Theme.of(context).primaryColor,
                        onChanged: (bool? value) {
                          setState(() {
                            if (value == true) {
                              _selectedChurchIds.add(id);
                            } else {
                              _selectedChurchIds.remove(id);
                            }
                          });
                        },
                      );
                    },
                  ),
                );
              },
            ),
            const SizedBox(height: 40),
            
            ElevatedButton(
              onPressed: () async {
                if (_titleController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Please enter a title"), backgroundColor: Colors.red),
                  );
                  return;
                }
                
                final tenant = ref.read(currentTenantProvider);
                final combinedDateTime = DateTime(
                  _selectedDate.year,
                  _selectedDate.month,
                  _selectedDate.day,
                  _selectedTime.hour,
                  _selectedTime.minute,
                );

                try {
                  final eventResponse = await ref.read(eventServiceProvider).createEvent({
                    "title": _titleController.text,
                    "description": _descriptionController.text,
                    "type": _eventType,
                    "date": combinedDateTime.toIso8601String(),
                    "location": _locationController.text,
                    "price": double.tryParse(_priceController.text) ?? 0.0,
                    "tenant_id": tenant?.id,
                    "organizer_momo_phone": _momoPhoneController.text.trim().isEmpty ? null : _momoPhoneController.text.trim(),
                  });

                  final eventId = eventResponse['id'];
                  if (eventId != null && _selectedChurchIds.isNotEmpty) {
                    final participatingChurchesInserts = _selectedChurchIds.map((churchId) => {
                      "event_id": eventId,
                      "church_id": churchId,
                    }).toList();
                    await Supabase.instance.client
                        .from('event_participating_churches')
                        .insert(participatingChurchesInserts);
                  }

                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Event Scheduled & Synced with Global Hub!"), backgroundColor: Colors.green),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Failed to publish event: ${e.toString().replaceAll("Exception: ", "")}"), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 60),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: const Text("PUBLISH TO CHURCH HUB", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInput(String label, TextEditingController controller, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade200)),
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              icon: Icon(icon, size: 18, color: Colors.grey),
              border: InputBorder.none,
              hintText: "Enter $label...",
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDatePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Date", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: _selectedDate,
              firstDate: DateTime.now(),
              lastDate: DateTime(2030),
            );
            if (date != null) setState(() => _selectedDate = date);
          },
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade200)),
            child: Row(
              children: [
                const Icon(LucideIcons.calendar, size: 18, color: Colors.grey),
                const SizedBox(width: 10),
                Text("${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}", style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Time", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () async {
            final time = await showTimePicker(context: context, initialTime: _selectedTime);
            if (time != null) setState(() => _selectedTime = time);
          },
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade200)),
            child: Row(
              children: [
                const Icon(LucideIcons.clock, size: 18, color: Colors.grey),
                const SizedBox(width: 10),
                Text(_selectedTime.format(context), style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEventTypeDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Event Type", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade200)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _eventType,
              isExpanded: true,
              items: ["Service", "Mission", "Conference", "Youth Hub", "Bible Study"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (v) => setState(() => _eventType = v!),
            ),
          ),
        ),
      ],
    );
  }
}
