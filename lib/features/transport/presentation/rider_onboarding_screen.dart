import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:lucide_icons/lucide_icons.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/providers/auth_provider.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/features/give/presentation/widgets/momo_phone_input_widget.dart';

class RiderOnboardingScreen extends ConsumerStatefulWidget {
  const RiderOnboardingScreen({super.key});

  @override
  ConsumerState<RiderOnboardingScreen> createState() => _RiderOnboardingScreenState();
}

class _RiderOnboardingScreenState extends ConsumerState<RiderOnboardingScreen> {
  int _step = 1;
  final _formKeys = List.generate(4, (_) => GlobalKey<FormState>());

  String _fullName = '';
  String _phone = '';
  String _email = '';
  String _payoutOperator = 'mtn';
  String _payoutNumber = '';
  String _vehicleType = 'motorbike';
  String _makeModel = '';
  String _licensePlate = '';
  String _color = '';
  String? _vehiclePhotoPath;
  String? _licensePhotoPath;
  String? _idPhotoPath;
  bool _vehicleUploaded = false;
  bool _licenseUploaded = false;
  bool _idUploaded = false;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(profileProvider).value;
    if (profile != null) {
      final name = profile.name;
      if (name.isNotEmpty) _fullName = name;
      final phone = profile.phoneNumber ?? '';
      if (phone.isNotEmpty) _phone = phone;
      final email = ref.read(authProvider).user?.email ?? '';
      if (email.isNotEmpty) _email = email;
      if (_phone.isNotEmpty) {
        _payoutNumber = _phone;
        _payoutOperator = _networkFromPhone(_phone);
      }
    }
  }

  String _networkFromPhone(String phone) {
    // Use confident detection only; fallback to current operator prevents premature MTN default on "09"
    final known = MomoPhoneInputWidget.detectNetworkIdIfKnown(phone);
    if (known != null) return known;
    // Fallback to legacy detect for complete numbers, else keep current
    final legacy = MomoPhoneInputWidget.detectNetwork(phone).toLowerCase();
    return legacy;
  }

  void _onPhoneChanged(String value) {
    _phone = value;
    final known = MomoPhoneInputWidget.detectNetworkIdIfKnown(value);
    if (known != null && known != _payoutOperator) {
      setState(() => _payoutOperator = known);
    } else if (value.replaceAll(RegExp(r'\D'), '').length >= 10) {
      final detected = _networkFromPhone(value);
      if (detected != _payoutOperator) {
        setState(() => _payoutOperator = detected);
      }
    }
  }

  void _onPayoutPhoneChanged(String value) {
    _payoutNumber = value;
    final known = MomoPhoneInputWidget.detectNetworkIdIfKnown(value);
    if (known != null && known != _payoutOperator) {
      setState(() => _payoutOperator = known);
    } else if (value.replaceAll(RegExp(r'\D'), '').length >= 10) {
      final detected = _networkFromPhone(value);
      if (detected != _payoutOperator) {
        setState(() => _payoutOperator = detected);
      }
    }
  }

  void _handleNext() {
    final key = _formKeys[_step - 1];
    if (key.currentState != null && !key.currentState!.validate()) return;
    if (_step == 2 && !_vehicleUploaded) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vehicle photo is required before continuing'), backgroundColor: Colors.orange),
        );
      }
      return;
    }
    if (_step == 3 && (!_licenseUploaded || !_idUploaded)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Driver's License and National ID are both required"), backgroundColor: Colors.orange),
        );
      }
      return;
    }
    if (_step < 4) {
      setState(() => _step++);
    }
  }

  void _handleSubmit() async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) throw Exception("Not logged in");

      final profile = ref.read(profileProvider).value;
      final tenantId = profile?.tenantId;

      // Upload documents to R2 storage
      String? vehiclePhotoUrl;
      String? licensePhotoUrl;
      String? idPhotoUrl;

      Future<String?> uploadToR2(String filePath, String folder) async {
        try {
          final file = File(filePath);
          final bytes = await file.readAsBytes();
          if (bytes.isEmpty) return null;

          final ext = filePath.split('.').last;
          final fileName = '$userId-${DateTime.now().millisecondsSinceEpoch}.$ext';
          final contentType = ext == 'pdf' ? 'application/pdf' : 'image/$ext';
          final key = '$folder/$userId/$fileName';

          final response = await client.functions.invoke('r2-sign', body: {
            'action': 'write',
            'folder': folder,
            'filename': '$userId/$fileName',
            'contentType': contentType,
          });

          if (response.data == null) return null;
          final data = response.data as Map<String, dynamic>;
          final uploadUrl = data['signedUrl'] as String?;
          if (uploadUrl == null) return null;

          final uploadResponse = await http.put(
            Uri.parse(uploadUrl),
            body: bytes,
            headers: {'Content-Type': contentType},
          );
          if (uploadResponse.statusCode != 200) {
            debugPrint('R2 upload PUT failed: ${uploadResponse.statusCode}');
            return null;
          }

          final publicUrl = data['publicUrl'] as String?;
          if (publicUrl != null && publicUrl.isNotEmpty) return publicUrl;
          return key;
        } catch (e) {
          debugPrint('R2 upload failed for $folder: $e');
          return null;
        }
      }

      if (_vehiclePhotoPath != null) {
        vehiclePhotoUrl = await uploadToR2(_vehiclePhotoPath!, 'driver-documents');
      }
      if (_licensePhotoPath != null) {
        licensePhotoUrl = await uploadToR2(_licensePhotoPath!, 'driver-documents');
      }
      if (_idPhotoPath != null) {
        idPhotoUrl = await uploadToR2(_idPhotoPath!, 'driver-documents');
      }

      if (vehiclePhotoUrl == null || licensePhotoUrl == null || idPhotoUrl == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Document upload failed. Please try again.'), backgroundColor: Colors.red),
          );
        }
        return;
      }

      await client.from('driver_applications').insert({
        'user_id': userId,
        'tenant_id': tenantId,
        'full_name': _fullName,
        'email': _email,
        'phone': _phone,
        'vehicle_type': _vehicleType,
        'license_plate': _licensePlate,
        'vehicle_make_model': _makeModel,
        'vehicle_color': _color,
        'vehicle_photo_url': vehiclePhotoUrl,
        'drivers_license_url': licensePhotoUrl,
        'national_id_url': idPhotoUrl,
        'payout_operator': _payoutOperator,
        'payout_number': _payoutNumber,
        'status': 'pending',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Application Submitted Successfully! You will be notified once verified.')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Submission failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _pickDocument(String type) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 1080, maxHeight: 1080);
      if (picked == null) return;

      setState(() {
        if (type == 'vehicle') {
          _vehiclePhotoPath = picked.path;
          _vehicleUploaded = true;
        } else if (type == 'license') {
          _licensePhotoPath = picked.path;
          _licenseUploaded = true;
        } else if (type == 'id') {
          _idPhotoPath = picked.path;
          _idUploaded = true;
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${type.toUpperCase()} document selected'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick document: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
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
    final stepKey = _formKeys[0];
    return ListView(
      padding: const EdgeInsets.all(25),
      children: [
        Form(
          key: stepKey,
          child: Column(
            children: [
              Center(
                child: CircleAvatar(
                  radius: 35,
                  backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.15),
                  child: Icon(LucideIcons.user, size: 35, color: Theme.of(context).primaryColor),
                ),
              ),
              const SizedBox(height: 15),
              const Text("Personal Details", textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const Text("Let's get to know you.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 30),
              _buildTextField("Full Legal Name", "e.g. John Banda", (val) => _fullName = val, validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                if (v.trim().length < 2) return 'Min 2 characters';
                return null;
              }),
              const SizedBox(height: 15),
              _buildTextField("Phone Number", "e.g. 0977 123 456", _onPhoneChanged, isNumber: true, validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                if (v.replaceAll(RegExp(r'\D'), '').length < 10) return 'Min 10 digits';
                return null;
              }),
              const SizedBox(height: 15),
              _buildTextField("Email Address", "e.g. john@example.com", (val) => _email = val, validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                if (!v.contains('@') || !v.contains('.')) return 'Enter a valid email';
                return null;
              }),
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
                    Text("Payout Settings", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade800)),
                    Text("Where we send your earnings — auto-detects Zambian network from your number", style: TextStyle(color: Colors.green.shade600, fontSize: 12)),
                    const SizedBox(height: 15),
                    _buildTextField("Mobile Money Number", "097XXXXXXX / 26097XXXXXXX", _onPayoutPhoneChanged, isNumber: true, validator: (v) {
                      final err = MomoPhoneInputWidget.validateZambianPhone(v);
                      if (err != null) return err;
                      // Cross-check: number prefix must match selected network chip
                      final known = MomoPhoneInputWidget.detectNetworkIdIfKnown(v ?? '');
                      if (known != null && known != _payoutOperator) {
                        return 'Number looks like ${known.toUpperCase()} but ${ _payoutOperator.toUpperCase()} is selected — tap the correct network or correct the number';
                      }
                      return null;
                    }),
                    Builder(builder: (context) {
                      final known = MomoPhoneInputWidget.detectNetworkIdIfKnown(_payoutNumber);
                      final display = known != null ? known.toUpperCase() : _payoutOperator.toUpperCase();
                      final isMatch = known == null || known == _payoutOperator;
                      final chipColor = display == 'MTN' ? Colors.amber : display == 'AIRTEL' ? Colors.red : Colors.green;
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            Icon(isMatch ? LucideIcons.checkCircle : LucideIcons.alertTriangle, size: 14, color: isMatch ? Colors.green : Colors.orange),
                            const SizedBox(width: 6),
                            Text(
                              known != null ? 'Auto-detected: $display' : 'Selected: $display — start typing to auto-detect',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isMatch ? Colors.green.shade700 : Colors.orange.shade800),
                            ),
                            if (known != null && !isMatch) ...[
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => setState(() => _payoutOperator = known),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(color: chipColor, borderRadius: BorderRadius.circular(8)),
                                  child: Text('Switch to $display', style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 15),
                    const Text("Mobile Network", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 6),
                    Text("Tap to override — but number must match the selected network's Zambian prefix (MTN: 096/076, Airtel: 097/077, Zamtel: 095/075)", style: TextStyle(color: Colors.grey, fontSize: 10)),
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
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNetworkBtn(String label, String id, Color activeColor) {
    bool isSelected = _payoutOperator == id;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _payoutOperator = id),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? activeColor : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isSelected ? activeColor : Colors.grey.shade200),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : Colors.grey.shade700,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep2() {
    final stepKey = _formKeys[1];
    return ListView(
      padding: const EdgeInsets.all(25),
      children: [
        Form(
          key: stepKey,
          child: Column(
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
                        color: isSelected ? Theme.of(context).primaryColor.withValues(alpha: 0.15) : Colors.white,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: isSelected ? Theme.of(context).primaryColor : Colors.grey.shade200, width: 2),
                      ),
                      child: Center(child: Text(type.toUpperCase(), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isSelected ? const Color(0xFF7A5C00) : Colors.grey))),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              _buildTextField("Make & Model", "e.g. Honda Ace 125", (val) => _makeModel = val, validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                if (v.trim().length < 2) return 'Min 2 characters';
                return null;
              }),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(child: _buildTextField("License Plate", "ABC 123", (val) => _licensePlate = val.toUpperCase(), isAllCaps: true, validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    return null;
                  })),
                  const SizedBox(width: 15),
                  Expanded(child: _buildTextField("Color", "Red", (val) => _color = val)),
                ],
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () => _pickDocument('vehicle'),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(30),
                  decoration: BoxDecoration(
                    color: _vehicleUploaded ? Colors.green.shade50 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _vehicleUploaded ? Colors.green.shade300 : Colors.grey.shade300,
                      style: BorderStyle.none,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        _vehicleUploaded ? LucideIcons.checkCircle : LucideIcons.camera,
                        size: 40,
                        color: _vehicleUploaded ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _vehicleUploaded ? "Vehicle photo selected" : "Tap to upload vehicle photo",
                        style: TextStyle(
                          color: _vehicleUploaded ? Colors.green.shade700 : Colors.grey,
                          fontSize: 12,
                          fontWeight: _vehicleUploaded ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
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
        _buildDocumentBox("Driver's License", "Valid Class C or Motorbike License", _licenseUploaded, () => _pickDocument('license')),
        const SizedBox(height: 15),
        _buildDocumentBox("National ID / Passport", "Proof of Identification", _idUploaded, () => _pickDocument('id')),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(color: Theme.of(context).primaryColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(15)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.shield, color: Theme.of(context).primaryColor, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "By proceeding, you verify that the information provided is accurate. We perform background checks on all riders to ensure community safety.",
                  style: TextStyle(color: const Color(0xFF7A5C00), fontSize: 11),
                ),
              )
            ],
          ),
        )
      ],
    );
  }

  Widget _buildDocumentBox(String title, String subtitle, bool isUploaded, VoidCallback onUpload) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isUploaded ? Colors.green.shade200 : Colors.grey.shade200),
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
          GestureDetector(
            onTap: onUpload,
            child: Container(
               width: double.infinity,
               padding: const EdgeInsets.symmetric(vertical: 12),
decoration: BoxDecoration(
                  color: isUploaded ? Colors.green.shade50 : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isUploaded ? Colors.green.shade200 : Theme.of(context).primaryColor.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isUploaded ? LucideIcons.check : LucideIcons.upload,
                      size: 16,
                      color: isUploaded ? Colors.green : Theme.of(context).primaryColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isUploaded ? "Uploaded" : "Upload Document",
                      style: TextStyle(
                        color: isUploaded ? Colors.green.shade700 : const Color(0xFF7A5C00),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
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

  Widget _buildTextField(String label, String hint, Function(String) onChanged, {bool isNumber = false, bool isAllCaps = false, String? Function(String?)? validator}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        const SizedBox(height: 8),
        TextFormField(
          onChanged: onChanged,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          textCapitalization: isAllCaps ? TextCapitalization.characters : TextCapitalization.none,
          validator: validator,
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
