import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

class ChurchOnboardingScreen extends ConsumerStatefulWidget {
  const ChurchOnboardingScreen({super.key});

  @override
  ConsumerState<ChurchOnboardingScreen> createState() => _ChurchOnboardingScreenState();
}

class _ChurchOnboardingScreenState extends ConsumerState<ChurchOnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;

  // Form Fields
  final _nameController = TextEditingController();
  final _pastorController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _treasurerPhoneController = TextEditingController();
  final _logoUrlController = TextEditingController(text: "https://churchonapp.com/churchonappicon.png");
  final _directionsController = TextEditingController();
  String _selectedThemeColor = "#8B5CF6";
  String _currentCountry = "Zambia";
  double? _lat;
  double? _lng;
  bool _isSubmitting = false;
  final _formKeys = [GlobalKey<FormState>(), GlobalKey<FormState>(), GlobalKey<FormState>()];

  @override
  void initState() {
    super.initState();
    _detectLocation();
  }

  Future<void> _detectLocation() async {
    try {
      final position = await _determinePosition();
      if (mounted) {
        setState(() {
          _lat = position.latitude;
          _lng = position.longitude;
          
          // Detect country based on longitude/latitude
          // Zambia approx: Lat -8 to -18, Lng 22 to 33
          // Zimbabwe approx: Lat -15.5 to -22.5, Lng 25 to 33
          if (position.latitude < -17.5 && position.longitude > 25.0) {
            _currentCountry = "Zimbabwe";
          } else {
            _currentCountry = "Zambia";
          }
        });
      }
    } catch (e) {
      debugPrint('Failed to determine position for country detection: $e');
    }
  }

  Future<dynamic> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return Future.error('Location services are disabled.');

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return Future.error('Location permissions are denied');
    }
    
    if (permission == LocationPermission.deniedForever) return Future.error('Location permissions are permanently denied'); 

    return await Geolocator.getCurrentPosition();
  }

  void _next() {
    if (!_formKeys[_currentStep].currentState!.validate()) return;

    if (_currentStep < 2) {
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      _submit();
    }
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Church Name cannot be empty"), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final supabase = Supabase.instance.client;
      final slug = name.toLowerCase().replaceAll(' ', '-').replaceAll(RegExp(r'[^a-z0-9-]'), '');
      
      final data = await supabase.from('churches').insert({
        'name': name,
        'slug': slug,
        'pastor_name': _pastorController.text,
        'contact_phone': _phoneController.text,
        'address': _addressController.text,
        'country': _currentCountry,
        'latitude': _lat,
        'longitude': _lng,
        'primary_color': _selectedThemeColor,
        'treasurer_phone': _treasurerPhoneController.text,
        'logo_url': _logoUrlController.text,
        'directions': _directionsController.text,
        'is_verified': true, // Auto-verify so trial is active instantly
        'subscription_ends_at': DateTime.now().add(const Duration(days: 30)).toIso8601String(),
      }).select().single();

      if (mounted) {
        _showSuccess(data);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showSuccess(Map<String, dynamic> church) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 80),
            const SizedBox(height: 20),
            const Text("Registration Successful!", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
            const SizedBox(height: 10),
            Text("Welcome to the Kingdom Ecosystem! ${_nameController.text} has been onboarded with a 30-day FREE trial.", textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context); // Close dialog
                context.go('/select-church');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              child: const Text("OK"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text("Church Onboarding", style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
      ),
      body: Column(
        children: [
          _buildProgressIndicator(),
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (i) => setState(() => _currentStep = i),
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildBasicInfoStep(),
                _buildLeaderInfoStep(),
                _buildBrandingStep(),
              ],
            ),
          ),
          _buildBottomNavigation(),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Padding(
      padding: const EdgeInsets.all(25),
      child: Row(
        children: List.generate(3, (index) {
          final active = index <= _currentStep;
          return Expanded(
            child: Container(
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: active ? Colors.amber : Colors.grey[200],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildBasicInfoStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(25),
      child: Form(
        key: _formKeys[0],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Church Identity", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const Text("Tell us about your congregation.", style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 30),
            _buildFormLabel("Church Registered Name"),
            _buildTextField(_nameController, "e.g. Grace Chapel International", Icons.church, (v) {
              if (v == null || v.trim().isEmpty) return 'Required';
              if (v.trim().length < 2) return 'Min 2 characters';
              return null;
            }),
            const SizedBox(height: 20),
            _buildFormLabel("Physical Address in $_currentCountry"),
            _buildTextField(_addressController, "e.g. Plot 123, Great East Road", Icons.map, (v) {
              if (v == null || v.trim().isEmpty) return 'Required';
              if (v.trim().length < 2) return 'Min 2 characters';
              return null;
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildLeaderInfoStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(25),
      child: Form(
        key: _formKeys[1],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Apostolic Oversight", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const Text("Who is the lead visionary?", style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 30),
            _buildFormLabel("Lead Pastor / Bishop Name"),
            _buildTextField(_pastorController, "e.g. Rev. John Banda", Icons.person, (v) {
              if (v == null || v.trim().isEmpty) return 'Required';
              if (v.trim().length < 2) return 'Min 2 characters';
              return null;
            }),
            const SizedBox(height: 20),
            _buildFormLabel("Administrative Phone Number"),
            _buildTextField(_phoneController, "e.g. +260 977 ...", Icons.phone, (v) {
              if (v == null || v.trim().isEmpty) return 'Required';
              if (v.replaceAll(RegExp(r'\D'), '').length < 10) return 'Min 10 digits';
              return null;
            }),
            const SizedBox(height: 20),
            _buildFormLabel("Treasurer Payout Phone Number"),
            _buildTextField(_treasurerPhoneController, "e.g. +260 966 ... (MTN/Airtel)", Icons.account_balance_wallet, (v) {
              if (v == null || v.trim().isEmpty) return 'Required';
              if (v.replaceAll(RegExp(r'\D'), '').length < 10) return 'Min 10 digits';
              return null;
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildBrandingStep() {
    final colors = ["#8B5CF6", "#F59E0B", "#10B981", "#EF4444", "#3B82F6", "#000000"];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(25),
      child: Form(
        key: _formKeys[2],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Kingdom Branding", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const Text("Customize your digital sanctuary.", style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 30),
            _buildFormLabel("Primary Theme Color"),
            const SizedBox(height: 15),
            Wrap(
              spacing: 15,
              runSpacing: 15,
              children: colors.map((col) {
                final isSelected = _selectedThemeColor == col;
                return GestureDetector(
                  onTap: () => setState(() => _selectedThemeColor = col),
                  child: Container(
                    width: 50, height: 50,
                    decoration: BoxDecoration(
                      color: Color(int.parse(col.replaceAll('#', '0xFF'))),
                      shape: BoxShape.circle,
                      border: isSelected ? Border.all(color: Colors.amber, width: 4) : null,
                    ),
                    child: isSelected ? const Icon(Icons.check, color: Colors.white) : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 30),
            _buildFormLabel("Church Logo URL (Optional)"),
            _buildTextField(_logoUrlController, "URL to church logo", Icons.image),
            const SizedBox(height: 20),
            _buildFormLabel("Directions (e.g. Next to Post Office)"),
            _buildTextField(_directionsController, "Simple directions for members", Icons.navigation),
            const SizedBox(height: 40),
            const Center(
              child: Column(
                children: [
                  Icon(Icons.verified_user, color: Colors.amber, size: 40),
                  SizedBox(height: 10),
                  Text("AUTO-VERIFICATION ENABLED", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
                  Text("Kingdom Cloud Multi-Tenant Isolation Secure", style: TextStyle(fontSize: 10, color: Colors.grey)),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavigation() {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, -10))],
      ),
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: () => _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 60),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: const Text("BACK"),
              ),
            ),
          if (_currentStep > 0) const SizedBox(width: 15),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _next,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black,
                minimumSize: const Size(0, 60),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                elevation: 0,
              ),
              child: _isSubmitting
                ? const CircularProgressIndicator(color: Colors.black)
                : Text(_currentStep == 2 ? "FINALIZE ONBOARDING" : "NEXT STEP", style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint, IconData icon, [String? Function(String?)? validator]) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey[200]!)),
      child: TextFormField(
        controller: controller,
        validator: validator,
        decoration: InputDecoration(
          icon: Icon(icon, size: 20, color: Colors.amber),
          border: InputBorder.none,
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey[300], fontSize: 14),
        ),
      ),
    );
  }
}

