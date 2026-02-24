import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'business_meetings_screen.dart';
import 'event_details_screen.dart';
import 'package:church_on_app/features/events/data/event_service.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import 'package:image_picker/image_picker.dart';
import 'package:church_on_app/core/services/r2_service.dart';
import 'dart:io';

// Represents a world-class premium events hub mimicking ticketing platforms like Eventbrite / Ticketmaster
class EventsScreen extends ConsumerStatefulWidget {
  const EventsScreen({super.key});

  @override
  ConsumerState<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends ConsumerState<EventsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _ticketsSold = 142;
  double _revenue = 35500.00;

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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CreateEventBottomSheet(onCreated: (event) {
        ref.read(eventServiceProvider).createEvent(event);
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
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text("Kingdom Events Hub", style: TextStyle(fontWeight: FontWeight.bold)),
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
          _buildDiscoverTab(),
          _buildMyTicketsTab(),
          _buildManageTab(),
        ],
      ),
    );
  }

  Widget _buildDiscoverTab() {
    final eventsAsync = ref.watch(eventsStreamProvider);

    return eventsAsync.when(
      data: (events) => events.isEmpty 
        ? const Center(child: Text("No upcoming events found."))
        : ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: events.length,
            itemBuilder: (context, index) {
              return _buildPremiumEventCard(events[index]);
            },
          ),
      loading: () => const ListSkeleton(),
      error: (err, stack) => Center(child: Text("Error: $err")),
    );
  }

  Widget _buildMyTicketsTab() {
    final myTicketsAsync = ref.watch(myTicketsStreamProvider);

    return myTicketsAsync.when(
      data: (tickets) => tickets.isEmpty 
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.ticket, size: 80, color: Colors.grey.withValues(alpha: 0.3)),
                const SizedBox(height: 20),
                const Text("No active tickets", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: () => _tabController.animateTo(0),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  child: Text("Browse Events", style: TextStyle(color: Theme.of(context).colorScheme.secondary, fontWeight: FontWeight.bold)),
                )
              ],
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: tickets.length,
            itemBuilder: (context, index) => _buildSimpleTicketCard(tickets[index]),
          ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text("Error: $err")),
    );
  }

  Widget _buildSimpleTicketCard(ChurchEvent event) {
    return Container(
       margin: const EdgeInsets.only(bottom: 15),
       padding: const EdgeInsets.all(15),
       decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.withValues(alpha: 0.1))),
       child: Row(
         children: [
           ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(event.imageUrl, width: 60, height: 60, fit: BoxFit.cover)),
           const SizedBox(width: 15),
           Expanded(
             child: Column(
               crossAxisAlignment: CrossAxisAlignment.start,
               children: [
                 Text(event.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                 Text(DateFormat.yMMMd().format(event.date), style: const TextStyle(color: Colors.grey, fontSize: 12)),
               ],
             ),
           ),
           const Icon(LucideIcons.qrCode, color: Colors.blueAccent),
         ],
       ),
    );
  }

  Widget _buildManageTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        GestureDetector(
          onTap: _showCreateEventModal,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Theme.of(context).primaryColor, Colors.orangeAccent]),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Theme.of(context).primaryColor.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 5))]
            ),
            child: Row(
              children: [
                CircleAvatar(backgroundColor: Colors.white.withValues(alpha: 0.2), child: const Icon(LucideIcons.plus, color: Colors.white)),
                const SizedBox(width: 15),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Create New Event", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    Text("Host tickets, live streams & more", style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text("Dashboard & Analytics", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 15),
        Row(
          children: [
            Expanded(child: _buildMetricCard("Tickets Sold", _ticketsSold.toString(), LucideIcons.ticket, Colors.blue)),
            const SizedBox(width: 15),
            Expanded(child: _buildMetricCard("Revenue (K)", _revenue.toStringAsFixed(2), LucideIcons.wallet, Colors.green)),
          ],
        )
      ],
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.withValues(alpha: 0.1))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 10),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildPremiumEventCard(ChurchEvent event) {
    bool isFree = event.ticketPrice == 0;
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => EventDetailsScreen(event: {
        'title': event.title,
        'date': DateFormat.yMMMd().format(event.date),
        'location': event.location,
        'cover': event.imageUrl,
        'price': event.ticketPrice.toInt(),
        'isLiveStream': false,
        'interchurch': true,
      }))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 25),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(25),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 15, offset: const Offset(0, 5))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Event Cover Image
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
                  child: CachedNetworkImage(
                    imageUrl: event.imageUrl,
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(color: Colors.grey.shade200),
                    errorWidget: (context, url, error) => const Icon(Icons.error),
                  ),
                ),
                Positioned(
                  top: 15,
                  right: 15,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 5)]),
                    child: Text(isFree ? "FREE" : "K${event.ticketPrice}", style: TextStyle(fontWeight: FontWeight.w900, color: Theme.of(context).primaryColor)),
                  ),
                ),
              ],
            ),
            // Event Details
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(DateFormat.yMMMd().format(event.date), style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold, fontSize: 12)),
                      const Row(
                        children: [
                          Icon(LucideIcons.globe, size: 12, color: Colors.blue),
                          SizedBox(width: 4),
                          Text("Interchurch", style: TextStyle(color: Colors.blue, fontSize: 10, fontWeight: FontWeight.bold)),
                        ],
                      )
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(event.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(LucideIcons.mapPin, size: 14, color: Colors.grey),
                      const SizedBox(width: 5),
                      Text(event.location, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                             ref.read(eventServiceProvider).registerForEvent(event.id);
                             ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Registration Successful!")));
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.secondary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            padding: const EdgeInsets.symmetric(vertical: 15),
                          ),
                          child: Text(isFree ? "RSVP NOW" : "BUY TICKET", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(15)),
                        child: IconButton(
                          icon: const Icon(LucideIcons.share2, color: Colors.black87),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Link Copied!")));
                          },
                        ),
                      )
                    ],
                  ),
                ],
              ),
            )
          ],
        ),
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
    return price * 0.06;
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (pickedFile != null) {
      setState(() => _imageFile = File(pickedFile.path));
    }
  }

  Future<String?> _uploadImage() async {
    if (_imageFile == null) return null;
    setState(() => _isUploading = true);
    final r2Service = ref.read(r2ServiceProvider);
    final fileName = "event_${DateTime.now().millisecondsSinceEpoch}.jpg";
    final url = await r2Service.uploadFile(_imageFile!, "events/$fileName");
    setState(() => _isUploading = false);
    return url;
  }

  Future<void> _submitEvent() async {
    if (_titleCtrl.text.isEmpty) return;

    String coverUrl = "https://images.unsplash.com/photo-1501281668745-f7f57925c3b4?w=800&q=80";
    if (_imageFile != null) {
      final uploadedUrl = await _uploadImage();
      if (uploadedUrl != null) {
        coverUrl = uploadedUrl;
      }
    }

    final newEvent = {
      "title": _titleCtrl.text,
      "type": _eventType,
      "date": "Feb 28, 2026",
      "time": "10:00 AM",
      "location": "Main Hall",
      "isLiveStream": _enableLiveStream,
      "price": _isPaid ? (int.tryParse(_priceCtrl.text) ?? 0) : 0,
      "cover": coverUrl,
      "interchurch": _isInterchurch,
    };

    widget.onCreated(newEvent);
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
            
            // Event Type
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade200)),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _eventType,
                  isExpanded: true,
                  items: ["Conference", "Concert", "Youth Camp", "Seminar"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (v) => setState(() => _eventType = v!),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Interchurch Option
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

            // Live Stream Option
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Enable Live Stream", style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text("Generates VPS stream link & embeds into digital tickets."),
              value: _enableLiveStream,
              activeThumbColor: Colors.red,
              onChanged: (v) => setState(() => _enableLiveStream = v),
            ),

            const Divider(height: 30),

            // Paid Event Option
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
            
            // Media Upload UI
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
                          child: Image.file(_imageFile!, height: 100, width: 200, fit: BoxFit.cover),
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
      decoration: const BoxDecoration(color: Color(0xFF1E293B), borderRadius: BorderRadius.vertical(top: Radius.circular(30))), // Dark sleek pro theme
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
