import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EventHostDashboardScreen extends StatefulWidget {
  final String eventId;
  final String eventTitle;

  const EventHostDashboardScreen({
    super.key,
    required this.eventId,
    required this.eventTitle,
  });

  @override
  State<EventHostDashboardScreen> createState() => _EventHostDashboardScreenState();
}

class _EventHostDashboardScreenState extends State<EventHostDashboardScreen> {
  late Future<List<Map<String, dynamic>>> _registrationsFuture;
  late Future<List<Map<String, dynamic>>> _resourcesFuture;
  late Future<Map<String, dynamic>> _eventDetailsFuture;

  final _resourceTitleController = TextEditingController();
  final _resourceUrlController = TextEditingController();
  String _resourceType = "document";

  // Edit Event Form Controllers
  final _editTitleController = TextEditingController();
  final _editDescriptionController = TextEditingController();
  final _editLocationController = TextEditingController();
  final _editCategoryController = TextEditingController();
  final _editPriceController = TextEditingController();
  final _editMomoController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  void _refreshData() {
    setState(() {
      _registrationsFuture = Supabase.instance.client
          .from('event_registrations')
          .select('id, check_in_status, user_id, profiles (full_name, avatar_url, phone_number)')
          .eq('event_id', widget.eventId)
          .then((data) => List<Map<String, dynamic>>.from(data))
          .catchError((_) => <Map<String, dynamic>>[]);

      _resourcesFuture = Supabase.instance.client
          .from('event_resources')
          .select('id, title, resource_url, resource_type, event_id')
          .eq('event_id', widget.eventId)
          .then((data) => List<Map<String, dynamic>>.from(data))
          .catchError((_) => <Map<String, dynamic>>[]);

      _eventDetailsFuture = Supabase.instance.client
          .from('events')
          .select('id, title, description, location, category, ticket_price, organizer_momo_phone, created_by, date, time, end_date, cover, speakers, type, price')
          .eq('id', widget.eventId)
          .single()
          .then((data) {
            final map = Map<String, dynamic>.from(data);
            _editTitleController.text = map['title'] ?? '';
            _editDescriptionController.text = map['description'] ?? '';
            _editLocationController.text = map['location'] ?? '';
            _editCategoryController.text = map['category'] ?? '';
            _editPriceController.text = (map['ticket_price'] ?? 0.0).toString();
            _editMomoController.text = map['organizer_momo_phone'] ?? '';
            return map;
          });
    });
  }

  @override
  void dispose() {
    _resourceTitleController.dispose();
    _resourceUrlController.dispose();
    _editTitleController.dispose();
    _editDescriptionController.dispose();
    _editLocationController.dispose();
    _editCategoryController.dispose();
    _editPriceController.dispose();
    _editMomoController.dispose();
    super.dispose();
  }

  // Toggle check in status
  void _toggleCheckIn(String registrationId, bool currentStatus) async {
    try {
      await Supabase.instance.client
          .from('event_registrations')
          .update({'check_in_status': !currentStatus})
          .eq('id', registrationId);

      _refreshData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(!currentStatus ? "Attendee Checked In!" : "Check-in Undone"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: ${e.toString()}"), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Add Shared Resource
  void _addResource() async {
    final title = _resourceTitleController.text.trim();
    final url = _resourceUrlController.text.trim();

    if (title.isEmpty || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill in all resource fields"), backgroundColor: Colors.orange),
      );
      return;
    }

    try {
      await Supabase.instance.client.from('event_resources').insert({
        'event_id': widget.eventId,
        'title': title,
        'resource_url': url,
        'resource_type': _resourceType,
      });

      _resourceTitleController.clear();
      _resourceUrlController.clear();
      if (!mounted) return;
      Navigator.pop(context);
      _refreshData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Resource uploaded & shared successfully!"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: ${e.toString()}"), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Save Event Edit Details
  void _saveEventDetails() async {
    try {
      await Supabase.instance.client.from('events').update({
        'title': _editTitleController.text.trim(),
        'description': _editDescriptionController.text.trim(),
        'location': _editLocationController.text.trim(),
        'category': _editCategoryController.text.trim(),
        'ticket_price': double.tryParse(_editPriceController.text) ?? 0.0,
        'organizer_momo_phone': _editMomoController.text.trim().isEmpty ? null : _editMomoController.text.trim(),
      }).eq('id', widget.eventId);

      _refreshData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Event parameters updated successfully!"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to update event: ${e.toString()}"), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showAddResourceSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 25,
          right: 25,
          top: 25,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Share Conference Resource", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Text("Upload documents, slide booklets or guides.", style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 20),
            TextField(
              controller: _resourceTitleController,
              decoration: const InputDecoration(labelText: "Material Title (e.g. Program Booklet)"),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _resourceUrlController,
              decoration: const InputDecoration(labelText: "Resource Link / PDF URL"),
            ),
            const SizedBox(height: 15),
            DropdownButtonFormField<String>(
              initialValue: _resourceType,
              items: ["document", "media", "link"].map((type) {
                return DropdownMenuItem(value: type, child: Text(type.toUpperCase()));
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _resourceType = val);
              },
              decoration: const InputDecoration(labelText: "Format Type"),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: _addResource,
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 55)),
              child: const Text("SHARE WITH PARTICIPANTS"),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text("${widget.eventTitle} Host Console", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          bottom: const TabBar(
            tabs: [
              Tab(text: "ATTENDEES", icon: Icon(LucideIcons.users)),
              Tab(text: "MATERIALS", icon: Icon(LucideIcons.fileText)),
              Tab(text: "EDIT EVENT", icon: Icon(LucideIcons.edit3)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Attendees Tab
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _registrationsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final list = snapshot.data ?? [];
                if (list.isEmpty) {
                  return const Center(
                    child: Text("No member registrations yet for this event.", style: TextStyle(color: Colors.grey)),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final reg = list[index];
                    final profile = reg['profiles'] as Map<String, dynamic>?;
                    final name = profile?['full_name'] ?? 'Anonymous Member';
                    final phone = profile?['phone_number'] ?? 'No contact';
                    final isCheckedIn = reg['check_in_status'] == true;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundImage: profile?['avatar_url'] != null
                              ? NetworkImage(profile!['avatar_url'])
                              : null,
                          child: profile?['avatar_url'] == null
                              ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?')
                              : null,
                        ),
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("Phone: $phone", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text("Gate Pass", style: TextStyle(fontSize: 11, color: Colors.grey)),
                            Checkbox(
                              value: isCheckedIn,
                              activeColor: Colors.green,
                              onChanged: (_) => _toggleCheckIn(reg['id'], isCheckedIn),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),

            // Resources Tab
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _resourcesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final list = snapshot.data ?? [];
                return Scaffold(
                  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                  body: list.isEmpty
                      ? const Center(
                          child: Text("No shared materials yet. Upload one below!", style: TextStyle(color: Colors.grey)),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(20),
                          itemCount: list.length,
                          itemBuilder: (context, index) {
                            final res = list[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                              child: ListTile(
                                leading: Icon(
                                  res['resource_type'] == 'media' ? LucideIcons.video : LucideIcons.fileText,
                                  color: Colors.amber,
                                ),
                                title: Text(res['title'] ?? 'Booklet', style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text(res['resource_url'] ?? '', style: const TextStyle(fontSize: 11, color: Colors.blue)),
                                trailing: const Icon(LucideIcons.share2, size: 18),
                              ),
                            );
                          },
                        ),
                  floatingActionButton: FloatingActionButton.extended(
                    onPressed: _showAddResourceSheet,
                    icon: const Icon(LucideIcons.upload),
                    label: const Text("SHARE NEW FILE"),
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                  ),
                );
              },
            ),

            // Edit Details Tab
            FutureBuilder<Map<String, dynamic>>(
              future: _eventDetailsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(25),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Modify Interchurch Event Settings", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const Text("Customize event types, categories, or payout parameters.", style: TextStyle(color: Colors.grey, fontSize: 12)),
                      const SizedBox(height: 25),
                      _buildTextField("Event Title / Name", _editTitleController),
                      const SizedBox(height: 15),
                      _buildTextField("Description", _editDescriptionController, maxLines: 3),
                      const SizedBox(height: 15),
                      _buildTextField("Event Location / Venue", _editLocationController),
                      const SizedBox(height: 15),
                      
                      // Custom Event Type Category Input
                      _buildTextField(
                        "Event Type / Custom Category (e.g. Crusade, Youth Conference, Quiz Event)", 
                        _editCategoryController,
                        hint: "Enter custom category..."
                      ),
                      const SizedBox(height: 15),
                      Row(
                        children: [
                          Expanded(child: _buildTextField("Ticket Price (ZMW)", _editPriceController)),
                          const SizedBox(width: 15),
                          Expanded(child: _buildTextField("MoMo Account Number", _editMomoController)),
                        ],
                      ),
                      const SizedBox(height: 40),
                      ElevatedButton(
                        onPressed: _saveEventDetails,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          minimumSize: const Size(double.infinity, 60),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        child: const Text("SAVE CHANGES & SYNC", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {int maxLines = 1, String? hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: TextField(
            controller: controller,
            maxLines: maxLines,
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: hint ?? "Enter $label...",
            ),
          ),
        ),
      ],
    );
  }
}
