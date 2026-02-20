import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/widgets/church_map.dart';
import '../../navigation/presentation/ride_on_scanner_screen.dart'; // Correct relative path
import '../../../core/widgets/kingdom_logo.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import '../../../core/theme/app_theme.dart';

class RideRequestScreen extends ConsumerStatefulWidget {
  final String mode; // 'ride' or 'delivery'
  const RideRequestScreen({super.key, this.mode = 'ride'});

  @override
  ConsumerState<RideRequestScreen> createState() => _RideRequestScreenState();
}

class _RideRequestScreenState extends ConsumerState<RideRequestScreen> {
  final _pickupController = TextEditingController();
  final _dropoffController = TextEditingController();
  String _selectedCategory = 'people';
  bool _calculating = false;
  double? _estimatedPrice;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.mode == 'delivery' ? 'marketplace' : 'people';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _buildMap(),
          _buildTopOverlay(),
          _buildBottomSheet(),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return ChurchMap(
      markers: [
        buildUserMarker(point: const LatLng(-15.3875, 28.3228)),
        buildRideMarker(
          point: const LatLng(-15.39, 28.33),
          color: Theme.of(context).primaryColor,
        ),
        buildRideMarker(
          point: const LatLng(-15.38, 28.31),
          color: Theme.of(context).primaryColor,
        ),
      ],
      path: const [
        LatLng(-15.3875, 28.3228),
        LatLng(-15.388, 28.325),
        LatLng(-15.39, 28.33),
      ],
    );
  }

  Widget _buildTopOverlay() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 20,
      right: 20,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          CircleAvatar(
            backgroundColor: Colors.white,
            child: IconButton(
              icon: const Icon(LucideIcons.arrowLeft, color: Colors.black),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
            ),
            child: Row(
              children: [
                Icon(
                  _selectedCategory == 'people' ? LucideIcons.user : LucideIcons.package,
                  size: 16,
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(width: 8),
                Text(
                  _selectedCategory.toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ],
            ),
          ),
          const CircleAvatar(
            backgroundColor: Colors.white,
            child: Icon(LucideIcons.user, color: Colors.black),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomSheet() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.55,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20)],
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 15),
              width: 50,
              height: 5,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 25),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildCategoryToggle(),
                      const SizedBox(height: 25),
                      _buildInputFields(),
                      const SizedBox(height: 30),
                      if (_calculating)
                        CircularProgressIndicator(color: Theme.of(context).primaryColor)
                      else if (_estimatedPrice != null)
                        _buildPriceDetails()
                      else
                        _buildInitialState(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryToggle() {
    final categories = [
      {'id': 'people', 'label': 'Ride', 'icon': LucideIcons.users},
      {'id': 'bus', 'label': 'Bus', 'icon': LucideIcons.truck},
      {'id': 'marketplace', 'label': 'Market', 'icon': LucideIcons.shoppingBag},
      {'id': 'bookshop', 'label': 'Books', 'icon': LucideIcons.book},
    ];

    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: categories.map((cat) {
          final isSelected = _selectedCategory == cat['id'];
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedCategory = cat['id'] as String),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected ? Theme.of(context).colorScheme.secondary : Colors.transparent,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Column(
                  children: [
                    Icon(cat['icon'] as IconData, color: isSelected ? Theme.of(context).primaryColor : Colors.grey, size: 18),
                    const SizedBox(height: 4),
                    Text(
                      cat['label'] as String,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.grey,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildInputFields() {
    return Column(
      children: [
        _buildTextField(_pickupController, LucideIcons.mapPin, "Pickup Location"),
        const SizedBox(height: 15),
        _buildTextField(_dropoffController, LucideIcons.navigation, "Destination"),
      ],
    );
  }

  Widget _buildTextField(TextEditingController controller, IconData icon, String hint) {
    return Container(
      decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(20)),
      child: TextField(
        controller: controller,
        onChanged: (val) {
          if (_pickupController.text.isNotEmpty && _dropoffController.text.isNotEmpty) {
            _simulateCalculation();
          }
        },
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: Theme.of(context).primaryColor, size: 20),
          hintText: hint,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 18),
        ),
      ),
    );
  }

  void _simulateCalculation() {
    setState(() => _calculating = true);
    Future.delayed(const Duration(seconds: 1), () {
      setState(() {
        _calculating = false;
        _estimatedPrice = 45.0 + (DateTime.now().second % 50);
      });
    });
  }

  Widget _buildPriceDetails() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: Colors.grey[200]!),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("ESTIMATED FARE", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                      SizedBox(height: 5),
                      Text("Standard Ride", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  Text("K ${_estimatedPrice!.toInt()}", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.secondary)),
                ],
              ),
              const Divider(height: 30),
              Row(
                children: [
                  Icon(LucideIcons.sparkles, color: Theme.of(context).primaryColor, size: 14),
                  SizedBox(width: 8),
                  const Text("Includes Prayer Mode & Security", style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 30),
        ElevatedButton(
          onPressed: () => _confirmBooking(),
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).primaryColor,
            minimumSize: const Size(double.infinity, 65),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
            elevation: 8,
            shadowColor: Theme.of(context).primaryColor.withOpacity(0.5),
          ),
          child: Text(
            "REQUEST RIDE ON APP",
            style: TextStyle(color: Theme.of(context).colorScheme.secondary, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.5),
          ),
        ),
      ],
    );
  }

  Widget _buildInitialState() {
    return Column(
      children: [
        Icon(LucideIcons.info, color: Colors.grey[300], size: 40),
        const SizedBox(height: 10),
        Text(
          "Enter your pickup and dropoff to see prices",
          style: TextStyle(color: Colors.grey[400], fontSize: 12),
        ),
      ],
    );
  }

  void _confirmBooking() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.checkCircle, color: Colors.green, size: 60),
            const SizedBox(height: 20),
            const Text("Connecting...", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text("Finding your nearest Kingdom Driver", style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }
}
