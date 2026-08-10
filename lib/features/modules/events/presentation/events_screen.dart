import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'business_meetings_screen.dart';
import 'package:church_on_app/features/events/data/event_service.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/services/r2_service.dart';
import 'package:church_on_app/core/config/remote_config.dart';
import 'package:image_picker/image_picker.dart';
import 'package:universal_io/io.dart';

import 'widgets/discover_tab.dart';
import 'widgets/my_tickets_tab.dart';
import 'widgets/manage_tab.dart';

class EventsScreen extends ConsumerStatefulWidget {
  const EventsScreen({super.key});

  @override
  ConsumerState<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends ConsumerState<EventsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showCreateEventModal() {
    final tenantId = ref.read(currentTenantProvider)?.id;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CreateEventBottomSheet(onCreated: (event) async {
        final eventWithTenant = {...event, 'tenant_id': tenantId};
        try {
          await ref.read(eventServiceProvider).createEvent(eventWithTenant);
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Event creation failed: $e"), backgroundColor: Colors.red),
            );
          }
        }
      }),
    );
  }

  void _showBusinessMeetingModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const HostBusinessMeetingSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Events Hub", style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Theme.of(context).primaryColor,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Theme.of(context).primaryColor,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(text: "DISCOVER"),
            Tab(text: "MY TICKETS"),
            Tab(text: "MANAGE"),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.briefcase, color: Colors.blueGrey),
            tooltip: "Pro Business Meetings",
            onPressed: _showBusinessMeetingModal,
          ),
          IconButton(
            icon: const Icon(LucideIcons.plusCircle),
            onPressed: _showCreateEventModal,
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          const DiscoverTab(),
          MyTicketsTab(onBrowseEvents: () => _tabController.animateTo(0)),
          ManageTab(onCreateEvent: _showCreateEventModal),
        ],
      ),
    );
  }
}

// ==========================================
// BOTTOM SHEET FOR CREATING EVENTS
// ==========================================
class CreateEventBottomSheet extends ConsumerStatefulWidget {
  final Function(Map<String, dynamic>) onCreated;
  const CreateEventBottomSheet({super.key, required this.onCreated});

  @override
  ConsumerState<CreateEventBottomSheet> createState() => _CreateEventBottomSheetState();
}

class _CreateEventBottomSheetState extends ConsumerState<CreateEventBottomSheet> {
  final _titleCtrl = TextEditingController();
  final _priceCtrl = TextEditingController(text: "0");
  final _descriptionCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _speakersCtrl = TextEditingController();
  final _momoNameCtrl = TextEditingController();
  final _momoPhoneCtrl = TextEditingController();
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 7));
  TimeOfDay _selectedTime = const TimeOfDay(hour: 10, minute: 0);
  DateTime _endDate = DateTime.now().add(const Duration(days: 7, hours: 2));
  TimeOfDay _endTime = const TimeOfDay(hour: 12, minute: 0);
  String _eventType = "Conference";
  bool _isPaid = false;
  bool _isInterchurch = false;
  bool _enableLiveStream = false;
  File? _imageFile;
  bool _isUploading = false;

  double get platformCommission {
    if (!_isPaid) return 0.0;
    if (_eventType == "Conference") return 0.0;
    final price = double.tryParse(_priceCtrl.text) ?? 0.0;
    final percent =
        widgetRemoteConfig(ref).getDouble('event_commission_percent', 0.10);
    return price * percent;
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70, maxWidth: 1080, maxHeight: 1080);
    if (pickedFile != null) {
      setState(() => _imageFile = File(pickedFile.path));
    }
  }

  Future<String?> _uploadImage() async {
    if (_imageFile == null) return null;
    setState(() => _isUploading = true);
    try {
      final r2Service = ref.read(r2ServiceProvider);
      final fileName = "event_${DateTime.now().millisecondsSinceEpoch}.jpg";
      final url = await r2Service.uploadFile(_imageFile!, "events/$fileName");
      return url;
    } catch (e) {
      debugPrint('Event image upload failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Image upload failed: $e'), backgroundColor: Colors.red),
        );
      }
      return null;
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _submitEvent() async {
    if (_titleCtrl.text.isEmpty) return;

    String coverUrl = "";
    if (_imageFile != null) {
      final uploadedUrl = await _uploadImage();
      if (uploadedUrl != null) {
        coverUrl = uploadedUrl;
      }
    }

    final combinedDateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );

    final combinedEndDateTime = DateTime(
      _endDate.year,
      _endDate.month,
      _endDate.day,
      _endTime.hour,
      _endTime.minute,
    );

    final newEvent = {
      "title": _titleCtrl.text,
      "description": _descriptionCtrl.text.isEmpty ? "No description provided." : _descriptionCtrl.text,
      "type": _eventType,
      "date": combinedDateTime.toIso8601String(),
      "time": "${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}",
      "end_date": combinedEndDateTime.toIso8601String(),
      "speakers": _speakersCtrl.text,
      "organizer_momo_phone": _momoPhoneCtrl.text,
      "organizer_momo_name": _momoNameCtrl.text,
      "location": _locationCtrl.text.isEmpty ? "Main Hall" : _locationCtrl.text,
      "isLiveStream": _enableLiveStream,
      "price": _isPaid ? (int.tryParse(_priceCtrl.text) ?? 0) : 0,
      "cover": coverUrl,
      "interchurch": _isInterchurch,
    };

    widget.onCreated(newEvent);
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Event Created! Banner uploaded securely to Cloudflare R2."), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      padding: EdgeInsets.only(left: 25, right: 25, top: 30, bottom: MediaQuery.of(context).viewInsets.bottom + 30),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Host an Event", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
            const Text("Concerts, Conferences, Church Meetings", style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 25),
            
            _buildTextField("Event Title", _titleCtrl, LucideIcons.type),
            const SizedBox(height: 15),
            _buildTextField("Event Description", _descriptionCtrl, LucideIcons.fileText),
            const SizedBox(height: 15),
            _buildTextField("Event Location", _locationCtrl, LucideIcons.mapPin),
            const SizedBox(height: 15),
            _buildTextField("Guest Speakers (e.g. Pastor John, Singer Sarah)", _speakersCtrl, LucideIcons.mic),
            const SizedBox(height: 20),
            
            const Text("Event Starts", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime.now(),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) {
                        setState(() => _selectedDate = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(LucideIcons.calendar, size: 18, color: Colors.grey),
                          const SizedBox(width: 8),
                          Text(
                            "${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}",
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: _selectedTime,
                      );
                      if (picked != null) {
                        setState(() => _selectedTime = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(LucideIcons.clock, size: 18, color: Colors.grey),
                          const SizedBox(width: 8),
                          Text(
                            _selectedTime.format(context),
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),

            const Text("Event Ends", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _endDate,
                        firstDate: DateTime.now(),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) {
                        setState(() => _endDate = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(LucideIcons.calendar, size: 18, color: Colors.grey),
                          const SizedBox(width: 8),
                          Text(
                            "${_endDate.day}/${_endDate.month}/${_endDate.year}",
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: _endTime,
                      );
                      if (picked != null) {
                        setState(() => _endTime = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(LucideIcons.clock, size: 18, color: Colors.grey),
                          const SizedBox(width: 8),
                          Text(
                            _endTime.format(context),
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade200)),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _eventType,
                  isExpanded: true,
                  items: [
                    "Conference", 
                    "Concert", 
                    "Youth Camp", 
                    "Seminar",
                    "Crusade",
                    "Revival",
                    "Prayer Meeting",
                    "Bible Study",
                    "Worship Night",
                    "Youth Rally",
                    "Men's Conference",
                    "Women's Conference",
                    "Children's Program",
                    "Marriage Seminar",
                    "Leadership Training",
                    "Missions Conference",
                    "Anniversary Celebration",
                    "Christmas Program",
                    "Easter Service",
                    "New Year Service",
                    "Other"
                  ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (v) => setState(() => _eventType = v!),
                ),
              ),
            ),
            const SizedBox(height: 15),
            const Text("MoMo Payout Details", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            _buildTextField("MoMo Recipient Name (e.g. Pastor John Payout)", _momoNameCtrl, LucideIcons.userCheck),
            const SizedBox(height: 10),
            _buildTextField("Settlement Account Phone (e.g. 097xxxxxxx)", _momoPhoneCtrl, LucideIcons.smartphone),
            const SizedBox(height: 20),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Interchurch Event", style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text("Allow members from other COA churches to search and attend globally."),
              value: _isInterchurch,
              activeThumbColor: Theme.of(context).primaryColor,
              onChanged: (v) {
                setState(() => _isInterchurch = v);
                if (v) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Global COA Church Directory Unlocked!")));
                }
              },
            ),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Enable Live Stream", style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text("Generates live stream link & embeds into digital tickets."),
              value: _enableLiveStream,
              activeThumbColor: Colors.red,
              onChanged: (v) => setState(() => _enableLiveStream = v),
            ),

            const Divider(height: 30),

            Row(
              children: [
                const Text("Ticketing", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                ChoiceChip(label: const Text("Free"), selected: !_isPaid, onSelected: (v) => setState(() => _isPaid = false)),
                const SizedBox(width: 10),
                ChoiceChip(label: const Text("Paid"), selected: _isPaid, onSelected: (v) => setState(() => _isPaid = true)),
              ],
            ),
            
            if (_isPaid) ...[
              const SizedBox(height: 15),
              TextField(
                controller: _priceCtrl,
                keyboardType: TextInputType.number,
                onChanged: (v) => setState(() {}),
                decoration: InputDecoration(
                  labelText: "Ticket Price (K)",
                  prefixIcon: const Icon(LucideIcons.banknote),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    const Icon(LucideIcons.info, color: Colors.blue, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _eventType == "Conference" 
                          ? "Platform Commission: K0.00 (Conferences are fee-free!)"
                          : "Platform Commission: K${platformCommission.toStringAsFixed(2)} per ticket",
                        style: const TextStyle(color: Colors.blue, fontSize: 12),
                      ),
                    )
                  ],
                ),
              )
            ],

            const SizedBox(height: 30),
            
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50, 
                  borderRadius: BorderRadius.circular(20), 
                  border: Border.all(color: Colors.grey.shade300, style: BorderStyle.none)
                ),
                child: _imageFile != null 
                  ? Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          // cacheWidth downsamples at decode (camera photos are
                          // huge) — Google Play flags full-size decodes.
                          child: Image.file(
                            _imageFile!,
                            height: 100,
                            width: 200,
                            fit: BoxFit.cover,
                            cacheWidth:
                                (200 * MediaQuery.devicePixelRatioOf(context))
                                    .round(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text("Change Banner", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    )
                  : const Column(
                      children: [
                        Icon(LucideIcons.uploadCloud, size: 40, color: Colors.grey),
                        SizedBox(height: 10),
                        Text("Upload Event Banner (Saves to R2)", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                      ],
                    ),
              ),
            ),
            
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: _isUploading ? null : _submitEvent,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                minimumSize: const Size(double.infinity, 60),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              child: _isUploading 
                ? const CircularProgressIndicator(color: Colors.white)
                : Text("PUBLISH EVENT", style: TextStyle(color: Theme.of(context).colorScheme.secondary, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(String hint, TextEditingController controller, IconData icon) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: Colors.grey),
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
      ),
    );
  }
}

// ==========================================
// PRO BUSINESS MEETING BOTTOM SHEET
// ==========================================
class HostBusinessMeetingSheet extends StatelessWidget {
  const HostBusinessMeetingSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Color(0xFF1E293B), borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      padding: EdgeInsets.only(left: 25, right: 25, top: 30, bottom: MediaQuery.of(context).viewInsets.bottom + 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.blueAccent.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
                child: const Icon(LucideIcons.video, color: Colors.blueAccent),
              ),
              const SizedBox(width: 15),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Pro Business Meeting", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  Text("Admin & Leadership VoIP/Video", style: TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              )
            ],
          ),
          const SizedBox(height: 30),

          _buildMeetingOption(context, "Start Instant Meeting", "Generates secure link immediately", LucideIcons.zap, Colors.orange, () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (context) => const BusinessMeetingsScreen(meetingTitle: "Instant Session X1")));
          }),
          const SizedBox(height: 15),
          _buildMeetingOption(context, "Schedule Meeting", "Set date and send calendar invites", LucideIcons.calendar, Colors.green, () {}),
          const SizedBox(height: 15),
          _buildMeetingOption(context, "Join with Code", "Enter meeting ID or alias", LucideIcons.logIn, Colors.white70, () {}),
          const SizedBox(height: 15),
          _buildMeetingOption(context, "Whiteboard & Blueprint", "Interactive canvas for structural plans", LucideIcons.mousePointerClick, Colors.pinkAccent, () {}),
          const SizedBox(height: 15),
          _buildMeetingOption(context, "Digital Voting System", "Secure anonymous polls for leadership", LucideIcons.barChart3, Colors.blue, () {}),
          const SizedBox(height: 30),
          
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (context) => const BusinessMeetingsScreen()));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              minimumSize: const Size(double.infinity, 60),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
            child: const Text("START SECURE SESSION", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildMeetingOption(BuildContext context, String title, String subtitle, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white10)),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
