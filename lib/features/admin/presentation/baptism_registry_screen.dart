import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/features/baptism/data/baptism_service.dart';

class BaptismRecord {
  final String id;
  final String name;
  final DateTime date;
  final String minister;
  final String location;
  final String status;

  BaptismRecord({
    required this.id,
    required this.name,
    required this.date,
    required this.minister,
    required this.location,
    required this.status,
  });
}

class BaptismRegistryScreen extends ConsumerStatefulWidget {
  const BaptismRegistryScreen({super.key});

  @override
  ConsumerState<BaptismRegistryScreen> createState() => _BaptismRegistryScreenState();
}

class _BaptismRegistryScreenState extends ConsumerState<BaptismRegistryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(baptismServiceProvider);
    });
  }
  final List<BaptismRecord> _records = [
    BaptismRecord(id: "B-101", name: "Mwansa Chilufya", date: DateTime(2026, 4, 12), minister: "Pastor Abel Banda", location: "St. Peters Lusaka", status: "Verified"),
    BaptismRecord(id: "B-102", name: "Chipo Moyo", date: DateTime(2026, 5, 20), minister: "Pastor Abel Banda", location: "Bread of Life Church", status: "Verified"),
    BaptismRecord(id: "B-103", name: "Katongo Mulenga", date: DateTime(2026, 6, 1), minister: "Apostle Joseph Phiri", location: "Mount Zion Centre", status: "Pending Verification"),
  ];

  final _nameCtrl = TextEditingController();
  final _ministerCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();

  void _addRecord() {
    if (_nameCtrl.text.isEmpty || _ministerCtrl.text.isEmpty || _locationCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please fill all fields")));
      return;
    }
    setState(() {
      _records.add(BaptismRecord(
        id: "B-${101 + _records.length}",
        name: _nameCtrl.text,
        date: DateTime.now(),
        minister: _ministerCtrl.text,
        location: _locationCtrl.text,
        status: "Pending Verification",
      ));
    });
    _nameCtrl.clear();
    _ministerCtrl.clear();
    _locationCtrl.clear();
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Baptism record added for verification!"), backgroundColor: Colors.green));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Baptism Registry", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.black,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() {});
          await Future.delayed(const Duration(seconds: 1));
        },
        child: ListView.builder(
          padding: const EdgeInsets.all(25),
          itemCount: _records.length,
          itemBuilder: (context, index) => _buildRecordCard(_records[index]),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.black,
        icon: const Icon(LucideIcons.plus),
        label: const Text("Register Baptism"),
      ),
    );
  }

  Widget _buildRecordCard(BaptismRecord record) {
    final isVerified = record.status == "Verified";
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Theme.of(context).primaryColor.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(record.id, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF7A5C00), fontSize: 13)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isVerified ? Colors.green.withValues(alpha: 0.1) : Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  record.status.toUpperCase(),
                  style: TextStyle(color: isVerified ? Colors.green : Colors.amber.shade900, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Text(record.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 5),
          Text("Baptized on ${record.date.day}/${record.date.month}/${record.date.year}", style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 15),
          const Divider(),
          const SizedBox(height: 15),
          Row(
            children: [
              const Icon(LucideIcons.user, size: 16, color: Colors.grey),
              const SizedBox(width: 8),
              Text("Minister: ${record.minister}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(LucideIcons.mapPin, size: 16, color: Colors.grey),
              const SizedBox(width: 8),
              Text("Branch: ${record.location}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          if (isVerified) ...[
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => _viewCertificate(record),
              icon: const Icon(LucideIcons.award, size: 16),
              label: const Text("VIEW CERTIFICATE"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                foregroundColor: const Color(0xFF7A5C00),
                elevation: 0,
                minimumSize: const Size(double.infinity, 45),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
            )
          ]
        ],
      ),
    );
  }

  void _viewCertificate(BaptismRecord record) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFFFAF0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30), side: const BorderSide(color: Colors.amber, width: 2)),
        content: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.award, color: Colors.amber, size: 70),
              const SizedBox(height: 20),
              const Text("CERTIFICATE OF BAPTISM", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF7A5C00))),
              const SizedBox(height: 20),
              const Text("This is to certify that", style: TextStyle(fontStyle: FontStyle.italic, fontSize: 13)),
              const SizedBox(height: 10),
              Text(record.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22, fontStyle: FontStyle.normal)),
              const SizedBox(height: 10),
              const Text("has been baptized in the name of the Father, and of the Son, and of the Holy Spirit.", textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
              const SizedBox(height: 25),
              const Divider(color: Colors.amber),
              const SizedBox(height: 15),
              Text("Officiated by: ${record.minister}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              Text("Location: ${record.location}", style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
          padding: const EdgeInsets.all(25),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Register New Baptism", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 25),
              TextField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: "Baptist's Full Name",
                  fillColor: Colors.white,
                  filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _ministerCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: "Officiating Minister",
                  fillColor: Colors.white,
                  filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _locationCtrl,
                decoration: InputDecoration(
                  labelText: "Church Branch/Location",
                  fillColor: Colors.white,
                  filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: _addRecord,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 60),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: const Text("SUBMIT RECORD", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
