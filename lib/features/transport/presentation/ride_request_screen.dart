import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/widgets/church_map.dart';
import 'active_ride_tracking_screen.dart';
import '../data/transport_service.dart';
import '../../finance/presentation/lipila_payment_gateway.dart';
import '../data/ride_request_model.dart';
import '../data/delivery_model.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_map/flutter_map.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/services/r2_service.dart';

class RideRequestScreen extends ConsumerStatefulWidget {
  final String mode; // 'ride' or 'delivery'
  const RideRequestScreen({super.key, this.mode = 'ride'});

  @override
  ConsumerState<RideRequestScreen> createState() => _RideRequestScreenState();
}

class _RideRequestScreenState extends ConsumerState<RideRequestScreen> {
  final _pickupController = TextEditingController();
  final _dropoffController = TextEditingController();
  final _itemDescController = TextEditingController();
  String _selectedCategory = 'people';
  String _selectedWeight = 'Light';
  bool _calculating = false;
  double? _estimatedPrice;
  double? _offeredFare;
  bool _isNegotiating = false;
  LatLng? _pickupLatLng;
  LatLng? _destLatLng;
  String? _pinModeFor; // 'pickup' or 'destination' or null
  final _mapKey = GlobalKey();

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
          if (_pinModeFor != null)
            _buildConfirmLocationOverlay()
          else
            _buildBottomSheet(),
        ],
      ),
    );
  }

  Widget _buildConfirmLocationOverlay() {
    final theme = Theme.of(context);
    final isPickup = _pinModeFor == 'pickup';
    final targetText = isPickup ? "Pickup Location" : "Destination";
    final point = isPickup ? _pickupLatLng : _destLatLng;
    final String coordText = point != null 
        ? '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}' 
        : 'Tap map to place pin...';

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  isPickup ? LucideIcons.mapPin : LucideIcons.flagTriangleRight,
                  color: isPickup ? Colors.green : Colors.red,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Set $targetText",
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        coordText,
                        style: const TextStyle(color: Colors.grey, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: point == null 
                  ? null 
                  : () {
                      setState(() {
                        _pinModeFor = null;
                        if (_pickupLatLng != null && _destLatLng != null) {
                          _simulateCalculation();
                        }
                      });
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primaryColor,
                foregroundColor: theme.colorScheme.secondary,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                elevation: 0,
              ),
              child: Text(
                "Confirm $targetText",
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMap() {
    final driversAsync = ref.watch(activeDriversStreamProvider);
    final markers = <Marker>[
      if (_pickupLatLng != null)
        Marker(
          point: _pickupLatLng!,
          width: 80,
          height: 80,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.mapPin, color: Colors.green, size: 32),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('Pickup', style: TextStyle(color: Colors.white, fontSize: 10)),
              ),
            ],
          ),
        ),
      if (_destLatLng != null)
        Marker(
          point: _destLatLng!,
          width: 80,
          height: 80,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.flagTriangleRight, color: Colors.red, size: 32),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('Dropoff', style: TextStyle(color: Colors.white, fontSize: 10)),
              ),
            ],
          ),
        ),
      buildUserMarker(point: const LatLng(-15.3875, 28.3228)),
      ...driversAsync.when(
        data: (drivers) => drivers.map((d) => buildRideMarker(
          point: LatLng(d.lat, d.lng),
          color: Theme.of(context).primaryColor,
        )),
        loading: () => [],
        error: (e, s) => [],
      ),
    ];

    return ChurchMap(
      key: _mapKey,
      showPin: _pinModeFor != null,
      initialPinPosition: _pinModeFor == 'pickup' ? _pickupLatLng : _destLatLng,
      onPinChanged: (point) {
        setState(() {
          if (_pinModeFor == 'pickup') {
            _pickupLatLng = point;
            _pickupController.text = '${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}';
          } else if (_pinModeFor == 'destination') {
            _destLatLng = point;
            _dropoffController.text = '${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}';
          }
        });
      },
      showAddressSearch: _pinModeFor != null,
      addressSearchHint: _pinModeFor == 'pickup' ? 'Search pickup address...' : 'Search destination address...',
      onAddressSelected: (address) {
        _searchAndSetLocation(address);
      },
      markers: markers,
      onMapTapped: (point) {
        if (_pinModeFor == null) {
          setState(() {
            _pinModeFor = 'pickup';
            _pickupLatLng = point;
            _pickupController.text = '${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}';
          });
        }
      },
    );
  }

  Future<void> _searchAndSetLocation(String address) async {
    try {
      final locations = await locationFromAddress(address);
      if (locations.isEmpty) return;
      final loc = locations.first;
      final point = LatLng(loc.latitude, loc.longitude);
      setState(() {
        if (_pinModeFor == 'pickup') {
          _pickupLatLng = point;
          _pickupController.text = address;
        } else if (_pinModeFor == 'destination') {
          _destLatLng = point;
          _dropoffController.text = address;
        }
        _pinModeFor = null;
        _simulateCalculation();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not find address: $e')),
        );
      }
    }
  }

  Widget _buildTopOverlay() {
    final categoryInfo = {
      'people': {'label': 'RIDE', 'desc': 'Personal Transport', 'icon': LucideIcons.car},
      'bus': {'label': 'BUS', 'desc': 'Find a Bus Route', 'icon': LucideIcons.bus},
      'marketplace': {'label': 'MARKET', 'desc': 'Deliver Goods', 'icon': LucideIcons.shoppingBag},
      'bookshop': {'label': 'BOOKS', 'desc': 'Book Delivery', 'icon': LucideIcons.bookOpen},
    };
    final info = categoryInfo[_selectedCategory] ?? categoryInfo['people']!;

    final theme = Theme.of(context);
    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 20,
      right: 20,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          CircleAvatar(
            backgroundColor: theme.colorScheme.surface,
            child: IconButton(
              icon: Icon(LucideIcons.arrowLeft, color: theme.colorScheme.onSurface),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10)],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  info['icon'] as IconData,
                  size: 14,
                  color: theme.primaryColor,
                ),
                const SizedBox(width: 6),
                Text(
                  info['label'] as String,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _showRiderProfile(),
            child: CircleAvatar(
              backgroundColor: theme.colorScheme.surface,
              child: Icon(LucideIcons.user, color: theme.colorScheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  void _showRiderProfile() {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Consumer(
          builder: (context, ref, child) {
            final user = Supabase.instance.client.auth.currentUser;
            final profileAsync = ref.watch(profileProvider);
            final profile = profileAsync.value;
            final userName = user?.userMetadata?['full_name'] ?? profile?.name ?? 'Kingdom Rider';
            final email = user?.email ?? '';
            final avatarUrl = profile?.avatarUrl ?? "https://i.pravatar.cc/300?u=${profile?.id ?? user?.id ?? '1'}";
            final isVerified = profile?.isVerified ?? false;
            
            return ListView(
              padding: const EdgeInsets.all(25),
              children: [
                Center(
                  child: Container(
                    width: 50,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(color: theme.colorScheme.onSurface.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                Center(child: Text("Carpso Ride Profile", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface))),
                const SizedBox(height: 25),
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 45,
                      backgroundColor: theme.primaryColor.withValues(alpha: 0.1),
                      backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                      child: avatarUrl.isEmpty
                          ? Text(userName.isNotEmpty ? userName[0].toUpperCase() : "R",
                              style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: theme.primaryColor))
                          : null,
                    ),
                    if (isVerified)
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFD700),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(Icons.verified, color: Colors.black, size: 16),
                        ),
                      ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      child: GestureDetector(
                        onTap: () => _pickCarpsoAvatar(),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: theme.primaryColor, shape: BoxShape.circle),
                          child: const Icon(LucideIcons.camera, color: Colors.white, size: 16),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(userName, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                      if (isVerified) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.verified, color: Color(0xFFFFD700), size: 18),
                      ],
                    ],
                  ),
                ),
                Center(child: Text(email, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 12))),
                const SizedBox(height: 10),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: isVerified ? const Color(0xFFFFD700).withValues(alpha: 0.1) : Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(isVerified ? Icons.verified : LucideIcons.star, size: 14, color: isVerified ? const Color(0xFFFFD700) : Colors.green),
                        const SizedBox(width: 6),
                        Text(isVerified ? "Verified" : "4.8 Rating", style: TextStyle(color: isVerified ? const Color(0xFFFFD700) : Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 25),
                _buildProfileStatRow("Total Carpso Rides", "12"),
                _buildProfileStatRow("Carpso Rides This Month", "3"),
                _buildProfileStatRow("Favorite Route", "Home → Church"),
                _buildProfileStatRow("Member Since", "2024"),
                _buildProfileStatRow("Carpso Prayer Rides", "5"),
                const SizedBox(height: 20),
                Divider(color: theme.colorScheme.onSurface.withValues(alpha: 0.1)),
                ListTile(
                  leading: Icon(LucideIcons.sliders, color: theme.primaryColor),
                  title: Text("Ride Preferences", style: TextStyle(color: theme.colorScheme.onSurface)),
                  trailing: Icon(LucideIcons.chevronRight, size: 18, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                  onTap: () {
                    Navigator.pop(context);
                    _showPreferencesSheet();
                  },
                ),
                ListTile(
                  leading: Icon(LucideIcons.shield, color: theme.primaryColor),
                  title: Text("Safety Settings", style: TextStyle(color: theme.colorScheme.onSurface)),
                  trailing: Icon(LucideIcons.chevronRight, size: 18, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                  onTap: () {
                    Navigator.pop(context);
                    _showSafetySettingsSheet();
                  },
                ),
                ListTile(
                  leading: Icon(LucideIcons.creditCard, color: theme.primaryColor),
                  title: Text("Payment Methods", style: TextStyle(color: theme.colorScheme.onSurface)),
                  trailing: Icon(LucideIcons.chevronRight, size: 18, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                  onTap: () {
                    Navigator.pop(context);
                    _showPaymentMethodsSheet();
                  },
                ),
                ListTile(
                  leading: Icon(LucideIcons.history, color: theme.primaryColor),
                  title: Text("Carpso Ride History", style: TextStyle(color: theme.colorScheme.onSurface)),
                  trailing: Icon(LucideIcons.chevronRight, size: 18, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                  onTap: () {
                    Navigator.pop(context);
                    _showRideHistorySheet();
                  },
                ),
                ListTile(
                  leading: Icon(LucideIcons.helpCircle, color: theme.primaryColor),
                  title: Text("Help & Support", style: TextStyle(color: theme.colorScheme.onSurface)),
                  trailing: Icon(LucideIcons.chevronRight, size: 18, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                  onTap: () {
                    Navigator.pop(context);
                    _showHelpSupportSheet();
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // Sub-State variables for preferences
  bool _prefGospelMusic = true;
  bool _prefQuietRide = false;
  bool _prefAcOn = false;

  // Sub-State variables for safety settings
  final _emergencyNameCtrl = TextEditingController(text: "Brother Emmanuel");
  final _emergencyPhoneCtrl = TextEditingController(text: "+260 977 123456");

  // Sub-State variables for payment methods
  final List<Map<String, String>> _linkedMomoWallets = [
    {"operator": "MTN", "phone": "+260 966 789123", "logo": "assets/logo_mtn.png"},
    {"operator": "Airtel", "phone": "+260 978 456123", "logo": "assets/logo_airtel.png"},
  ];

  void _showPreferencesSheet() {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          padding: const EdgeInsets.all(25),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 50, height: 5,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(color: theme.colorScheme.onSurface.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                ),
              ),
              Text("Carpso Ride Preferences", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
              const SizedBox(height: 10),
              Text("Customize your travel settings with drivers.", style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              const SizedBox(height: 20),
              SwitchListTile(
                activeThumbColor: theme.primaryColor,
                title: const Text("Prefer Gospel Music / Sermons"),
                subtitle: const Text("Drivers will try to play uplifting audio"),
                value: _prefGospelMusic,
                onChanged: (v) {
                  setState(() => _prefGospelMusic = v);
                  setSheetState(() => _prefGospelMusic = v);
                },
              ),
              SwitchListTile(
                activeThumbColor: theme.primaryColor,
                title: const Text("Quiet / Silent Ride"),
                subtitle: const Text("Drivers will minimize conversation"),
                value: _prefQuietRide,
                onChanged: (v) {
                  setState(() => _prefQuietRide = v);
                  setSheetState(() => _prefQuietRide = v);
                },
              ),
              SwitchListTile(
                activeThumbColor: theme.primaryColor,
                title: const Text("Air Conditioning (AC)"),
                subtitle: const Text("Request temperature control"),
                value: _prefAcOn,
                onChanged: (v) {
                  setState(() => _prefAcOn = v);
                  setSheetState(() => _prefAcOn = v);
                },
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primaryColor,
                  foregroundColor: theme.colorScheme.secondary,
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                child: const Text("SAVE PREFERENCES", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSafetySettingsSheet() {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(25),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 50, height: 5,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(color: theme.colorScheme.onSurface.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                ),
              ),
              Text("Safety Settings & SOS", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
              const SizedBox(height: 10),
              Text("Add a trusted contact to share ride tracking details automatically.", style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              const SizedBox(height: 20),
              TextField(
                controller: _emergencyNameCtrl,
                decoration: InputDecoration(
                  labelText: "Contact Name",
                  prefixIcon: const Icon(LucideIcons.user),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _emergencyPhoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: "Phone Number",
                  prefixIcon: const Icon(LucideIcons.phone),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                ),
              ),
              const SizedBox(height: 25),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Emergency Contact saved successfully!"), backgroundColor: Colors.green),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primaryColor,
                  foregroundColor: theme.colorScheme.secondary,
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                child: const Text("CONFIRM EMERGENCY CONTACT", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPaymentMethodsSheet() {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          padding: const EdgeInsets.all(25),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 50, height: 5,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(color: theme.colorScheme.onSurface.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Payment Methods", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                  TextButton(
                    onPressed: () => _addMomoWalletDialog(setSheetState),
                    child: Text("+ Add", style: TextStyle(color: theme.primaryColor, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text("Select or link mobile wallets for rides.", style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              const SizedBox(height: 15),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _linkedMomoWallets.length,
                  itemBuilder: (context, idx) {
                    final wallet = _linkedMomoWallets[idx];
                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Colors.grey.shade100)),
                      child: ListTile(
                        leading: Image.asset(wallet['logo']!, height: 28, width: 28, fit: BoxFit.contain),
                        title: Text(wallet['operator']!, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(wallet['phone']!),
                        trailing: IconButton(
                          icon: const Icon(LucideIcons.trash2, color: Colors.red, size: 18),
                          onPressed: () {
                            setSheetState(() {
                              _linkedMomoWallets.removeAt(idx);
                            });
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _addMomoWalletDialog(StateSetter setSheetState) {
    String selectedNet = 'MTN';
    final phoneCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("Link Mobile Wallet"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _dialogNetBtn("MTN", "assets/logo_mtn.png", selectedNet == 'MTN', () => setDlgState(() => selectedNet = 'MTN')),
                  _dialogNetBtn("Airtel", "assets/logo_airtel.png", selectedNet == 'Airtel', () => setDlgState(() => selectedNet = 'Airtel')),
                  _dialogNetBtn("Zamtel", "assets/logo_zamtel.png", selectedNet == 'Zamtel', () => setDlgState(() => selectedNet = 'Zamtel')),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: "Wallet Phone Number",
                  hintText: "096XXXXXXX",
                  prefixIcon: Icon(LucideIcons.phone),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
            TextButton(
              onPressed: () {
                final phone = phoneCtrl.text.trim();
                if (phone.isNotEmpty) {
                  setSheetState(() {
                    _linkedMomoWallets.add({
                      "operator": selectedNet,
                      "phone": phone,
                      "logo": "assets/logo_${selectedNet.toLowerCase()}.png",
                    });
                  });
                  Navigator.pop(ctx);
                }
              },
              child: const Text("Link", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dialogNetBtn(String label, String logo, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.amber.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? Colors.amber : Colors.grey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(logo, height: 16, width: 16, fit: BoxFit.contain),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  void _showRideHistorySheet() {
    final theme = Theme.of(context);
    final mockHistory = [
      {"route": "Home → Church Cathedral", "date": "July 7, 2026", "fare": "K45.00", "status": "Completed", "color": Colors.green},
      {"route": "Central Mall → Office Park", "date": "July 5, 2026", "fare": "K60.00", "status": "Completed", "color": Colors.green},
      {"route": "Church Cathedral → Home", "date": "June 30, 2026", "fare": "K45.00", "status": "Cancelled", "color": Colors.red},
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 50, height: 5,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(color: theme.colorScheme.onSurface.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
              ),
            ),
            Text("Carpso Ride History", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
            const SizedBox(height: 15),
            Expanded(
              child: ListView.builder(
                itemCount: mockHistory.length,
                itemBuilder: (context, idx) {
                  final ride = mockHistory[idx];
                  return Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Colors.grey.shade100)),
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.orange.withValues(alpha: 0.1),
                        child: const Icon(LucideIcons.car, color: Colors.orange),
                      ),
                      title: Text(ride['route'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: Text(ride['date'] as String, style: const TextStyle(fontSize: 12)),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(ride['fare'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          Text(
                            ride['status'] as String,
                            style: TextStyle(color: ride['color'] as Color, fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showHelpSupportSheet() {
    final theme = Theme.of(context);
    final faqs = [
      {"q": "What is Carpso?", "a": "Carpso is our secure, church-only ride-sharing network connecting verified drivers and riders from the parish."},
      {"q": "How does pricing work?", "a": "Pricing is based on distance with a recommended fair value. Drivers and riders can negotiate final coin amounts."},
      {"q": "Is it safe?", "a": "Yes! All drivers are verified church members vetted by the Bishop and leadership team."},
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 50, height: 5,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(color: theme.colorScheme.onSurface.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
              ),
            ),
            Text("Help & Support", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
            const SizedBox(height: 15),
            Expanded(
              child: ListView(
                children: [
                  ...faqs.map((faq) => Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Colors.grey.shade100)),
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ExpansionTile(
                      shape: const Border(),
                      title: Text(faq['q']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(faq['a']!, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                        )
                      ],
                    ),
                  )),
                  const SizedBox(height: 15),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Calling Support Bishop...+260 97000000"), backgroundColor: Colors.amber),
                      );
                    },
                    icon: const Icon(LucideIcons.phone),
                    label: const Text("CALL SUPPORT BISHOP"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primaryColor,
                      foregroundColor: theme.colorScheme.secondary,
                      minimumSize: const Size(double.infinity, 56),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileStatRow(String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
        ],
      ),
    );
  }


  Widget _buildBottomSheet() {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.65,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 20)],
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 15),
              width: 50,
              height: 5,
              decoration: BoxDecoration(color: theme.colorScheme.onSurface.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 25),
                child: Column(
                  children: [
                    _buildCategoryToggle(),
                    const SizedBox(height: 15),
                    Expanded(
                      child: SingleChildScrollView(
                        child: _buildInputFields(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_calculating)
                      CircularProgressIndicator(color: Theme.of(context).primaryColor)
                    else if (_estimatedPrice != null)
                      _buildPriceDetails()
                    else
                      _buildInitialState(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryToggle() {
    final theme = Theme.of(context);
    final categories = [
      {'id': 'people', 'label': 'Carpso Ride', 'desc': 'Personal Transport', 'icon': LucideIcons.car},
      {'id': 'bus', 'label': 'Bus', 'desc': 'Find a Bus Route', 'icon': LucideIcons.bus},
      {'id': 'marketplace', 'label': 'Market', 'desc': 'Deliver Goods', 'icon': LucideIcons.shoppingBag},
      {'id': 'bookshop', 'label': 'Books', 'desc': 'Book Delivery', 'icon': LucideIcons.bookOpen},
    ];

    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(color: theme.colorScheme.onSurface.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: categories.map((cat) {
          final isSelected = _selectedCategory == cat['id'];
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => _selectedCategory = cat['id'] as String);
                if (_pickupController.text.isNotEmpty && _dropoffController.text.isNotEmpty) {
                  _simulateCalculation();
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                decoration: BoxDecoration(
                  color: isSelected ? theme.colorScheme.secondary : Colors.transparent,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: isSelected
                      ? [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 6, offset: const Offset(0, 2))]
                      : [],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(cat['icon'] as IconData, color: isSelected ? theme.primaryColor : theme.colorScheme.onSurface.withValues(alpha: 0.5), size: 18),
                    const SizedBox(height: 3),
                    Text(
                      cat['label'] as String,
                      style: TextStyle(
                        color: isSelected ? theme.colorScheme.onSecondary : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (isSelected)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          cat['desc'] as String,
                          style: TextStyle(
                            color: theme.primaryColor.withValues(alpha: 0.8),
                            fontSize: 7,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
    final isDelivery = _selectedCategory == 'marketplace' || _selectedCategory == 'bookshop';
    return Column(
      children: [
        _buildTextField(_pickupController, LucideIcons.mapPin, "Pickup Location"),
        const SizedBox(height: 15),
        _buildTextField(_dropoffController, LucideIcons.navigation, "Destination"),
        if (isDelivery) ...[
          const SizedBox(height: 15),
          _buildTextField(_itemDescController, LucideIcons.package, "What are we delivering? (e.g. 5 Books, Bible Study Kit)"),
          const SizedBox(height: 15),
          _buildWeightSelector(),
        ],
      ],
    );
  }

  Widget _buildWeightSelector() {
    final weights = ["Light", "Medium", "Heavy"];
    return Row(
      children: weights.map((w) {
        final isSelected = _selectedWeight == w;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _selectedWeight = w),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isSelected ? Theme.of(context).primaryColor : Colors.grey[100],
                borderRadius: BorderRadius.circular(15),
              ),
              child: Center(
                child: Text(
                  w,
                  style: TextStyle(
                    color: isSelected ? Theme.of(context).colorScheme.secondary : Colors.grey,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTextField(TextEditingController controller, IconData icon, String hint) {
    final theme = Theme.of(context);
    final isPickup = hint.contains('Pickup');
    final field = isPickup ? 'pickup' : 'destination';
    return GestureDetector(
      onTap: () {
        setState(() => _pinModeFor = field);
      },
      child: Container(
        decoration: BoxDecoration(color: theme.colorScheme.onSurface.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(20)),
        child: AbsorbPointer(
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              prefixIcon: Icon(icon, color: theme.primaryColor, size: 20),
              hintText: _pinModeFor == field ? 'Tap map or search...' : hint,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 18),
            ),
          ),
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
        _offeredFare = null;
        _isNegotiating = false;
      });
    });
  }

  Widget _buildPriceDetails() {
    final theme = Theme.of(context);
    final desc = _selectedCategory == 'bus'
        ? 'Find a Bus Route'
        : (_selectedCategory == 'marketplace')
            ? 'Deliver Goods'
            : (_selectedCategory == 'bookshop')
                ? 'Book Delivery'
                : 'Personal Transport';
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.1)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("ESTIMATED FARE", style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 10, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 5),
                      Text(
                        _selectedCategory == 'bus' 
                            ? "Shared Bus Route Ride" 
                            : (_selectedCategory == 'marketplace' || _selectedCategory == 'bookshop') 
                                ? "Kingdom Cargo Delivery" 
                                : "Standard Carpso Ride",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: theme.colorScheme.onSurface),
                      ),
                      Text(desc, style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text("K ${_isNegotiating && _offeredFare != null ? _offeredFare!.toInt() : _estimatedPrice!.toInt()}", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: theme.colorScheme.secondary)),
                      Text("+ MoMo fee (max 5% or K3.00)", style: TextStyle(fontSize: 10, color: theme.primaryColor.withValues(alpha: 0.7))),
                    ]
                  )
                ],
              ),
              const SizedBox(height: 15),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                   GestureDetector(
                     onTap: () => _showNegotiateDialog(),
                     child: Text(
                        _isNegotiating ? "Change Offer" : "Negotiate Price",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: theme.primaryColor, decoration: TextDecoration.underline),
                     )
                   )
                ]
              ),
              Divider(height: 30, color: theme.colorScheme.onSurface.withValues(alpha: 0.1)),
              Row(
                children: [
                  Icon(LucideIcons.sparkles, color: theme.primaryColor, size: 14),
                  SizedBox(width: 8),
                  Text("Includes Prayer Mode & Security", style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 30),
        Consumer(builder: (context, ref, child) {
          final myRide = ref.watch(myRideRequestStreamProvider).value;
          final myDelivery = ref.watch(myDeliveryStreamProvider).value;
          
          final isWaiting = (myRide != null && myRide.status == 'pending') || (myDelivery != null && myDelivery.status == 'pending');
          final isRideAccepted = myRide != null && myRide.status == 'accepted' && myRide.status != 'confirmed';
          final isDeliveryAccepted = myDelivery != null && myDelivery.status == 'accepted' && myDelivery.status != 'confirmed';

          if (isRideAccepted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
               _confirmRideBooking(myRide);
            });
          } else if (isDeliveryAccepted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
               _confirmDeliveryBooking(myDelivery);
            });
          }

          return ElevatedButton(
            onPressed: isWaiting ? null : () => _handleRidePayment(),
            style: ElevatedButton.styleFrom(
              backgroundColor: isWaiting ? theme.colorScheme.onSurface.withValues(alpha: 0.3) : theme.primaryColor,
              minimumSize: const Size(double.infinity, 65),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
              elevation: 8,
              shadowColor: theme.primaryColor.withValues(alpha: 0.5),
            ),
            child: Text(
              isWaiting 
                  ? "SEARCHING FOR DRIVER..." 
                  : _selectedCategory == 'bus' 
                      ? "REQUEST SHUTTLE BUS" 
                      : (_selectedCategory == 'marketplace' || _selectedCategory == 'bookshop')
                          ? "REQUEST CARGO DELIVERY" 
                          : "REQUEST CARPSO RIDE",
              style: TextStyle(color: theme.colorScheme.onSecondary, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1.5),
            ),
          );
        }),
      ],
    );
  }

  void _pickCarpsoAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (picked == null) return;

    try {
      final file = File(picked.path);
      final fileName = "carpso_avatar_${DateTime.now().millisecondsSinceEpoch}.jpg";
      final r2 = R2Service(Supabase.instance.client);
      final url = await r2.uploadFile(file, "avatars/$fileName");

      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        await Supabase.instance.client.from('profiles').update({
          'avatar_url': url,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', user.id);
      }

      ref.invalidate(profileProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Profile picture updated!"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Upload failed: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _handleRidePayment() {
    final fare = _isNegotiating && _offeredFare != null ? _offeredFare! : _estimatedPrice!;
    final pickup = _pickupLatLng ?? const LatLng(-15.3875, 28.3228);
    final dest = _destLatLng ?? const LatLng(-15.395, 28.35);
    final isDelivery = _selectedCategory == 'marketplace' || _selectedCategory == 'bookshop';

    if (isDelivery) {
      ref.read(transportServiceProvider).requestDelivery(
        pickup: pickup,
        dest: dest,
        desc: _itemDescController.text,
        category: _selectedCategory,
        weight: _selectedWeight,
        fare: fare,
      );
      _showAvailableDrivers("Kingdom Courier");
    } else {
      ref.read(transportServiceProvider).requestRide(pickup, dest, fare);
      _showAvailableDrivers("Carpso Ride Driver");
    }
  }

  void _showAvailableDrivers(String driverType) {
    final driversAsync = ref.read(activeDriversStreamProvider);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DriverListSheet(
        driverType: driverType,
        driversAsync: driversAsync,
        pickupLatLng: _pickupLatLng ?? const LatLng(-15.3875, 28.3228),
        destLatLng: _destLatLng ?? const LatLng(-15.395, 28.35),
        onDriverSelected: (driverId) {
          Navigator.pop(ctx);
          _listenForAcceptance(driverId);
        },
      ),
    );
  }

  void _listenForAcceptance(String driverId) {
    final service = ref.read(transportServiceProvider);
    service.getMyRideRequestStream().listen((ride) {
      if (ride != null && ride.status == 'accepted' && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ActiveRideTrackingScreen(
              startPos: _pickupLatLng ?? const LatLng(-15.3875, 28.3228),
              destPos: _destLatLng ?? const LatLng(-15.395, 28.35),
              requestId: ride.id,
              type: 'ride',
            ),
          ),
        );
      }
    });
  }

  Future<void> _payForAcceptedRide(String requestId, double fare) async {
    final double fee = fare * 0.05 > 3.00 ? fare * 0.05 : 3.00;
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => LipilaPaymentGateway(
        amount: fare + fee,
        description: "Carpso Ride to: ${_dropoffController.text}",
        category: "ride",
        recipientName: "Church On App Global (Platform Owner)",
        recipientAccount: "PLATFORM-CARPSO-SETTLE",
        paymentReason: "Carpso Ride Fare",
        onComplete: (success, txId) async {
          Navigator.pop(context);
          if (success) {
            await ref.read(transportServiceProvider).confirmRidePayment(requestId, fare);
            if (!context.mounted) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ActiveRideTrackingScreen(
                  startPos: _pickupLatLng ?? const LatLng(-15.3875, 28.3228),
                  destPos: _destLatLng ?? const LatLng(-15.395, 28.35),
                  requestId: requestId,
                  type: 'ride',
                ),
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildInitialState() {
    final theme = Theme.of(context);
    return Column(
      children: [
        Icon(LucideIcons.info, color: theme.colorScheme.onSurface.withValues(alpha: 0.3), size: 40),
        const SizedBox(height: 10),
        Text(
          "Enter your pickup and dropoff to see prices",
          style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.4), fontSize: 12),
        ),
      ],
    );
  }

  void _showNegotiateDialog() {
    final TextEditingController offerCtrl = TextEditingController(text: _estimatedPrice?.toInt().toString());
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: const Text("Negotiate Fare"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Offer a different price to drivers nearby. Drivers can accept, refuse, or counter your offer.", style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
            const SizedBox(height: 15),
            TextField(
              controller: offerCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                prefixText: "K ",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")),
          ElevatedButton(
            onPressed: () {
              if (offerCtrl.text.isNotEmpty) {
                 setState(() {
                    _offeredFare = double.parse(offerCtrl.text);
                    _isNegotiating = true;
                 });
              }
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).primaryColor, foregroundColor: Theme.of(context).colorScheme.onSecondary),
            child: const Text("SET OFFER"),
          )
        ],
      )
    );
  }

  void _confirmRideBooking(RideRequest ride) {
    if (ModalRoute.of(context)?.isCurrent == false) return;
    _payForAcceptedRide(ride.id, ride.fare);
  }

  void _confirmDeliveryBooking(DeliveryRequest delivery) {
    if (ModalRoute.of(context)?.isCurrent == false) return;
    if (!mounted) return;
    _payForAcceptedRide(delivery.id, delivery.fare);
  }
}

class DriverListSheet extends ConsumerWidget {
  final String driverType;
  final AsyncValue<List<RideRegistration>> driversAsync;
  final LatLng pickupLatLng;
  final LatLng destLatLng;
  final ValueChanged<String> onDriverSelected;

  const DriverListSheet({
    super.key,
    required this.driverType,
    required this.driversAsync,
    required this.pickupLatLng,
    required this.destLatLng,
    required this.onDriverSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 15),
            width: 50, height: 5,
            decoration: BoxDecoration(color: theme.colorScheme.onSurface.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 25),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Available ${driverType}s", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                Text("Nearby", style: TextStyle(color: theme.primaryColor, fontWeight: FontWeight.bold, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Divider(),
          Expanded(
            child: driversAsync.when(
              data: (drivers) {
                if (drivers.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.car, size: 48, color: theme.colorScheme.onSurface.withValues(alpha: 0.2)),
                        const SizedBox(height: 12),
                        Text("No drivers available nearby", style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
                        const SizedBox(height: 8),
                        Text("Your request has been submitted.\nWaiting for a driver to accept...", textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.3), fontSize: 12)),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: drivers.length,
                  itemBuilder: (context, index) {
                    final driver = drivers[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(15),
                        leading: CircleAvatar(
                          backgroundColor: theme.primaryColor.withValues(alpha: 0.1),
                          child: Icon(LucideIcons.user, color: theme.primaryColor),
                        ),
                        title: Text("$driverType #${index + 1}", style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(driver.vehicleInfo ?? 'Standard Vehicle'),
                        trailing: ElevatedButton(
                          onPressed: () => onDriverSelected(driver.userId),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.primaryColor,
                            foregroundColor: theme.colorScheme.onSecondary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text("SELECT", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text("Error loading drivers: $e")),
            ),
          ),
        ],
      ),
    );
  }
}

