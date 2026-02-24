import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../data/transport_service.dart';

class RiderOnboardingScreen extends ConsumerStatefulWidget {
  const RiderOnboardingScreen({super.key});

  @override
  ConsumerState<RiderOnboardingScreen> createState() => _RiderOnboardingScreenState();
}

class _RiderOnboardingScreenState extends ConsumerState<RiderOnboardingScreen> {
  int _step = 1;

  // Form Data
  String _fullName = '';
  String _phone = '';
  String _email = '';
  String _payoutOperator = 'mtn';
  String _vehicleType = 'motorbike';
  String _makeModel = '';
  String _licensePlate = '';
  String _color = '';

  void _handleNext() {
    if (_step == 1) {
      if (_fullName.isEmpty || _phone.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill required fields')));
        return;
      }
    } else if (_step == 2) {
      if (_makeModel.isEmpty || _licensePlate.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vehicle details required')));
        return;
      }
    }
    setState(() => _step++);
  }

  void _handleSubmit() async {
    // In a real app, we would insert into a 'driver_applications' table.
    // Here we simulate going live immediately for the task.
    await ref.read(transportServiceProvider).updateLocation(-15.39, 28.33);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Application Submitted & You are now LIVE!')));
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB), // gray-50
      appBar: AppBar(
        title: const Text("Driver Application", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0c2d48),
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(40),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: List.generate(4, (index) => Expanded(
                child: Container(
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: _step >= index + 1 ? Colors.amber : Colors.grey.shade600,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              )),
            ),
          ),
        ),
      ),
      body: _buildCurrentStep(),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.black12)),
        ),
        child: _step < 4 ? Row(
          children: [
            if (_step > 1) 
              TextButton(
                onPressed: () => setState(() => _step--),
                child: const Text("Back", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
              )
            else const Spacer(),
            ElevatedButton.icon(
              onPressed: _handleNext,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0c2d48),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              icon: const Text("Next"),
              label: Icon(LucideIcons.chevronRight, size: 18),
            )
          ],
        ) : ElevatedButton.icon(
           onPressed: _handleSubmit,
           style: ElevatedButton.styleFrom(
             backgroundColor: Colors.green.shade600,
             foregroundColor: Colors.white,
             padding: const EdgeInsets.symmetric(vertical: 18),
             shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
           ),
           icon: const Text("SUBMIT APPLICATION"),
           label: Icon(LucideIcons.checkCircle, size: 18),
        ),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_step) {
      case 1: return _buildStep1();
      case 2: return _buildStep2();
      case 3: return _buildStep3();
      case 4: return _buildStep4();
      default: return const SizedBox.shrink();
    }
  }

  Widget _buildStep1() {
    return ListView(
      padding: const EdgeInsets.all(25),
      children: [
        Center(
          child: CircleAvatar(
            radius: 35,
            backgroundColor: Colors.blue.shade100,
            child: Icon(LucideIcons.user, size: 35, color: Colors.blue.shade600),
          ),
        ),
        const SizedBox(height: 15),
        const Text("Personal Details", textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const Text("Let's get to know you.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 30),
        _buildTextField("Full Legal Name", "e.g. John Banda", (val) => _fullName = val),
        const SizedBox(height: 15),
        _buildTextField("Phone Number", "e.g. 0977 123 456", (val) => _phone = val, isNumber: true),
        const SizedBox(height: 15),
        _buildTextField("Email Address", "e.g. john@example.com", (val) => _email = val),
        const SizedBox(height: 30),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.green.shade100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("💰 Payout Settings", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade800)),
              Text("Where we send your earnings", style: TextStyle(color: Colors.green.shade600, fontSize: 12)),
              const SizedBox(height: 15),
              _buildTextField("Mobile Money Number", "097XXXXXXX", (val) {}, isNumber: true),
              const SizedBox(height: 15),
              const Text("Mobile Network", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 10),
              Row(
                children: [
                  _buildNetworkBtn("MTN", "mtn", Colors.amber),
                  const SizedBox(width: 8),
                  _buildNetworkBtn("Airtel", "airtel", Colors.red),
                  const SizedBox(width: 8),
                  _buildNetworkBtn("Zamtel", "zamtel", Colors.green),
                ],
              )
            ],
          ),
        )
      ],
    );
  }

  Widget _buildNetworkBtn(String label, String id, Color activeColor) {
    bool isSelected = _payoutOperator == id;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _payoutOperator = id),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? activeColor : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isSelected ? activeColor : Colors.grey.shade200),
          ),
          child: Center(
            child: Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.grey.shade700, fontSize: 12)),
          ),
        ),
      ),
    );
  }

  Widget _buildStep2() {
    return ListView(
      padding: const EdgeInsets.all(25),
      children: [
        Center(
          child: CircleAvatar(
            radius: 35,
            backgroundColor: Colors.green.shade100,
            child: Icon(LucideIcons.truck, size: 35, color: Colors.green.shade600),
          ),
        ),
        const SizedBox(height: 15),
        const Text("Vehicle Information", textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const Text("What will you be driving?", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 30),
        GridView.count(
          shrinkWrap: true,
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 3,
          physics: const NeverScrollableScrollPhysics(),
          children: ['motorbike', 'bicycle', 'car', 'van'].map((type) {
            bool isSelected = _vehicleType == type;
            return GestureDetector(
              onTap: () => setState(() => _vehicleType = type),
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? Colors.blue.shade50 : Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: isSelected ? Colors.blue.shade600 : Colors.grey.shade200, width: 2),
                ),
                child: Center(child: Text(type.toUpperCase(), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isSelected ? Colors.blue.shade800 : Colors.grey))),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        _buildTextField("Make & Model", "e.g. Honda Ace 125", (val) => _makeModel = val),
        const SizedBox(height: 15),
        Row(
          children: [
            Expanded(child: _buildTextField("License Plate", "ABC 123", (val) => _licensePlate = val)),
            const SizedBox(width: 15),
            Expanded(child: _buildTextField("Color", "Red", (val) => _color = val)),
          ],
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(30),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade300, style: BorderStyle.none),
          ),
          child: const Column(
            children: [
              Icon(LucideIcons.camera, size: 40, color: Colors.grey),
              SizedBox(height: 10),
              Text("Tap to upload vehicle photo", style: TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildStep3() {
    return ListView(
      padding: const EdgeInsets.all(25),
      children: [
        Center(
          child: CircleAvatar(
            radius: 35,
            backgroundColor: Colors.amber.shade100,
            child: Icon(LucideIcons.fileText, size: 35, color: Colors.amber.shade600),
          ),
        ),
        const SizedBox(height: 15),
        const Text("Documents & KYC", textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const Text("Verify your identity.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 30),
        _buildDocumentBox("Driver's License", "Valid Class C or Motorbike License", false),
        const SizedBox(height: 15),
        _buildDocumentBox("National ID / Passport", "Proof of Identification", false),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(15)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.shield, color: Colors.blue.shade600, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "By proceeding, you verify that the information provided is accurate. We perform background checks on all riders to ensure community safety.",
                  style: TextStyle(color: Colors.blue.shade800, fontSize: 11),
                ),
              )
            ],
          ),
        )
      ],
    );
  }

  Widget _buildDocumentBox(String title, String subtitle, bool isUploaded) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
               Column(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                   Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                   Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                 ],
               ),
               Icon(LucideIcons.checkCircle, color: isUploaded ? Colors.green : Colors.grey.shade300),
            ],
          ),
          const SizedBox(height: 15),
          Container(
             width: double.infinity,
             padding: const EdgeInsets.symmetric(vertical: 12),
             decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.blue.shade100)),
             child: const Row(
               mainAxisAlignment: MainAxisAlignment.center,
               children: [
                 Icon(LucideIcons.upload, size: 16, color: Colors.blue),
                 SizedBox(width: 8),
                 Text("Upload Document", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12)),
               ],
             ),
          )
        ],
      ),
    );
  }

  Widget _buildStep4() {
    return ListView(
      padding: const EdgeInsets.all(25),
      children: [
        const SizedBox(height: 30),
        Center(
          child: CircleAvatar(
            radius: 50,
            backgroundColor: Colors.green.shade100,
            child: Icon(LucideIcons.shield, size: 50, color: Colors.green.shade600),
          ),
        ),
        const SizedBox(height: 20),
        const Text("You're All Set!", textAlign: TextAlign.center, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        const Text("Your application has been received. We will notify you via SMS once your documents are verified (usually within 24 hours).", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 40),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(20)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Review Details", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Divider(height: 20),
              _buildReviewRow("Name", _fullName.isEmpty ? "John Doe" : _fullName),
              _buildReviewRow("Vehicle", _vehicleType.toUpperCase()),
              _buildReviewRow("Plate", _licensePlate.isEmpty ? "ABC 123" : _licensePlate),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildReviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, String hint, Function(String) onChanged, {bool isNumber = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        const SizedBox(height: 8),
        TextField(
          onChanged: onChanged,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.all(20),
          ),
        ),
      ],
    );
  }
}
