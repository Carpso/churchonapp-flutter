import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

class EventSchedulerScreen extends StatefulWidget {
  const EventSchedulerScreen({super.key});

  @override
  State<EventSchedulerScreen> createState() => _EventSchedulerScreenState();
}

class _EventSchedulerScreenState extends State<EventSchedulerScreen> {
  final _titleController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  String _eventType = "Service";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text("Kingdom Event Scheduler", style: TextStyle(fontWeight: FontWeight.bold)),
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
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: _buildDatePicker()),
                const SizedBox(width: 15),
                Expanded(child: _buildTimePicker()),
              ],
            ),
            const SizedBox(height: 20),
            _buildEventTypeDropdown(),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Event Scheduled & Synced with Global Hub!"), backgroundColor: Colors.green),
                );
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
        const SizedBox(height: 10),
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
        const SizedBox(height: 10),
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
        const SizedBox(height: 10),
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
        const SizedBox(height: 10),
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
