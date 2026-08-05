import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:latlong2/latlong.dart';
import 'package:church_on_app/core/config/fee_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:async';
import 'package:universal_io/io.dart';
import 'package:image_picker/image_picker.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/services/r2_service.dart';
import 'package:geolocator/geolocator.dart';
import '../data/transport_service.dart';
import '../data/ride_pricing_provider.dart';
import 'active_ride_tracking_screen.dart';
import 'widgets/ride_map_view.dart';
import 'widgets/pickup_dropoff_inputs.dart';
import 'widgets/vehicle_selection_sheet.dart';

class RideRequestScreen extends ConsumerStatefulWidget {
  final String mode;
  const RideRequestScreen({super.key, this.mode = 'ride'});

  @override
  ConsumerState<RideRequestScreen> createState() => _RideRequestScreenState();
}

class _RideRequestScreenState extends ConsumerState<RideRequestScreen> {
  final _pickupController = TextEditingController();
  final _dropoffController = TextEditingController();
  final _itemDescController = TextEditingController();
  String? _pinModeFor = 'pickup';
  LatLng? _pickupLatLng;
  LatLng? _destLatLng;
  StreamSubscription? _acceptanceSub;
  bool _isLocating = false;

  @override
  void initState() {
    super.initState();
    final initialCategory = widget.mode == 'delivery' ? 'marketplace' : 'people';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(ridePricingProvider.notifier).setCategory(initialCategory);
      _loadPreferences();
      _detectCurrentLocation();
    });
  }

  /// Smart pickup: auto-detect the rider's GPS location and reverse-geocode
  /// it into a readable address so the pickup is pre-filled.
  Future<void> _detectCurrentLocation() async {
    if (_pickupLatLng != null || _isLocating) return;
    setState(() => _isLocating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (!mounted) return;
      final point = LatLng(pos.latitude, pos.longitude);
      var label = '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';
      try {
        final places = await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (places.isNotEmpty) {
          final p = places.first;
          final street = [p.street, p.subLocality].where((s) => s != null && s.isNotEmpty).join(', ');
          final area = [p.locality, p.subAdministrativeArea].where((s) => s != null && s.isNotEmpty).join(', ');
          label = [street, area].where((s) => s.isNotEmpty).join(', ');
          if (label.isEmpty) {
            label = p.name ?? label;
          }
        }
      } catch (e) {
        debugPrint('Reverse geocode failed (using coords): $e');
      }
      if (!mounted) return;
      setState(() {
        _pickupLatLng = point;
        _pickupController.text = label;
        if (_pinModeFor == 'pickup') _pinModeFor = null;
      });
      if (_pickupLatLng != null && _destLatLng != null) {
        ref.read(ridePricingProvider.notifier).calculatePrice(_pickupLatLng!, _destLatLng!);
      }
    } catch (e) {
      debugPrint('Location detection failed: $e');
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _loadPreferences() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      final data = await Supabase.instance.client
          .from('ride_preferences')
          .select('gospel_music, quiet_ride, ac_on')
          .eq('user_id', user.id)
          .maybeSingle();
      if (data != null && mounted) {
        setState(() {
          _prefGospelMusic = data['gospel_music'] ?? true;
          _prefQuietRide = data['quiet_ride'] ?? false;
          _prefAcOn = data['ac_on'] ?? false;
        });
      }
    } catch (e) {
      debugPrint('Error loading ride preferences: $e');
    }
  }

  Future<void> _savePreferences() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      await Supabase.instance.client.from('ride_preferences').upsert({
        'user_id': user.id,
        'gospel_music': _prefGospelMusic,
        'quiet_ride': _prefQuietRide,
        'ac_on': _prefAcOn,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Failed to save ride preferences: $e');
    }
  }

  @override
  void dispose() {
    _pickupController.dispose();
    _dropoffController.dispose();
    _itemDescController.dispose();
    _acceptanceSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pricing = ref.watch(ridePricingProvider);

    return Scaffold(
      body: Stack(
        children: [
          RideMapView(
            pickupLatLng: _pickupLatLng,
            destLatLng: _destLatLng,
            pinModeFor: _pinModeFor,
            onPinChanged: (point) {
              setState(() {
                if (_pinModeFor == 'pickup') {
                  _pickupLatLng = point;
                  _pickupController.text =
                      '${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}';
                } else if (_pinModeFor == 'destination') {
                  _destLatLng = point;
                  _dropoffController.text =
                      '${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}';
                }
              });
            },
            onMapTapped: (point) {
              if (_pinModeFor == null) {
                setState(() {
                  _pinModeFor = 'pickup';
                  _pickupLatLng = point;
                  _pickupController.text =
                      '${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}';
                });
              }
            },
            onAddressSelected: _searchAndSetLocation,
          ),
          if (_pinModeFor == null) _buildTopOverlay(pricing),
          if (_pinModeFor != null)
            _buildConfirmLocationOverlay()
          else
            _buildBottomSheet(pricing),
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
                      Text("Set $targetText",
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: theme.colorScheme.onSurface)),
                      const SizedBox(height: 4),
                      Text(coordText,
                          style: TextStyle(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.5),
                              fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
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
                          ref
                              .read(ridePricingProvider.notifier)
                              .calculatePrice(_pickupLatLng!, _destLatLng!);
                        }
                      });
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primaryColor,
                foregroundColor: theme.colorScheme.onPrimary,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
                elevation: 0,
              ),
              child: Text("Confirm $targetText",
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopOverlay(RidePricingState pricing) {
    final categoryInfo = {
      'people': {'label': 'RIDE', 'icon': LucideIcons.car},
      'bus': {'label': 'BUS', 'icon': LucideIcons.bus},
      'marketplace': {'label': 'MARKET', 'icon': LucideIcons.shoppingBag},
      'bookshop': {'label': 'BOOKS', 'icon': LucideIcons.bookOpen},
    };
    final info =
        categoryInfo[pricing.selectedCategory] ?? categoryInfo['people']!;
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
              icon: Icon(LucideIcons.arrowLeft,
                  color: theme.colorScheme.onSurface),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10)
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(info['icon'] as IconData,
                    size: 14, color: theme.primaryColor),
                const SizedBox(width: 6),
                Text(info['label'] as String,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 11)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _showRiderProfile(),
            child: CircleAvatar(
              backgroundColor: theme.colorScheme.surface,
              child: Icon(LucideIcons.user,
                  color: theme.colorScheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomSheet(RidePricingState pricing) {
    final theme = Theme.of(context);
    final screenH = MediaQuery.of(context).size.height;
    final sheetH = (screenH * 0.65).clamp(400.0, screenH - 120.0);
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        height: sheetH,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(40)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 20)
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 15),
                width: 50,
                height: 5,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 25),
                  child: Column(
                    children: [
                      _buildCategoryToggle(pricing),
                      const SizedBox(height: 15),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              PickupDropoffInputs(
                                pickupController: _pickupController,
                                dropoffController: _dropoffController,
                                itemDescController: _itemDescController,
                                selectedCategory: pricing.selectedCategory,
                                selectedWeight: pricing.selectedWeight,
                                pinModeFor: _pinModeFor,
                                onWeightChanged: (w) => ref
                                    .read(ridePricingProvider.notifier)
                                    .setWeight(w),
                                onPickupTap: () =>
                                    setState(() => _pinModeFor = 'pickup'),
                                onDropoffTap: () =>
                                    setState(() => _pinModeFor = 'destination'),
                                onUseMyLocation: _detectCurrentLocation,
                                isLocating: _isLocating,
                              ),
                              const SizedBox(height: 10),
                              if (pricing.estimatedPrice != null)
                                VehicleSelectionSheet(
                                  pickupLatLng:
                                      _pickupLatLng ?? const LatLng(-15.3875, 28.3228),
                                  destLatLng:
                                      _destLatLng ?? const LatLng(-15.395, 28.35),
                                  onRequestRide: () => _handleRidePayment(),
                                  onDriverSelected: (driverId) =>
                                      _listenForAcceptance(driverId),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryToggle(RidePricingState pricing) {
    final theme = Theme.of(context);
    final categories = [
      {'id': 'people', 'label': 'Ride', 'icon': LucideIcons.car},
      {'id': 'bus', 'label': 'Bus', 'icon': LucideIcons.bus},
      {'id': 'marketplace', 'label': 'Market', 'icon': LucideIcons.shoppingBag},
      {'id': 'bookshop', 'label': 'Books', 'icon': LucideIcons.bookOpen},
    ];

    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: categories.map((cat) {
          final isSelected = pricing.selectedCategory == cat['id'];
          return Expanded(
            child: GestureDetector(
              onTap: () {
                ref
                    .read(ridePricingProvider.notifier)
                    .setCategory(cat['id'] as String);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                decoration: BoxDecoration(
                  color: isSelected
                      ? theme.colorScheme.secondary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      cat['icon'] as IconData,
                      color: isSelected
                          ? theme.primaryColor
                          : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      size: 18,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      cat['label'] as String,
                      style: TextStyle(
                        color: isSelected
                            ? theme.colorScheme.onSecondary
                            : theme.colorScheme.onSurface
                                .withValues(alpha: 0.5),
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

  bool _isRequesting = false;

  Future<void> _handleRidePayment() async {
    final pricing = ref.read(ridePricingProvider);
    if (pricing.estimatedPrice == null || _isRequesting) return;

    final fare = pricing.totalPayable(ref.read(feeConfigProvider).value ?? FeeConfig.defaults);
    final pickup = _pickupLatLng ?? const LatLng(-15.3875, 28.3228);
    final dest = _destLatLng ?? const LatLng(-15.395, 28.35);
    final isDelivery = pricing.selectedCategory == 'marketplace' ||
        pricing.selectedCategory == 'bookshop';

    setState(() => _isRequesting = true);
    try {
      String? requestId;
      if (isDelivery) {
        requestId = await ref.read(transportServiceProvider).requestDelivery(
              pickup: pickup,
              dest: dest,
              desc: _itemDescController.text,
              category: pricing.selectedCategory,
              weight: pricing.selectedWeight,
              fare: fare,
            );
      } else {
        requestId = await ref.read(transportServiceProvider).requestRide(pickup, dest, fare);
      }

      if (!mounted) return;
      if (requestId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Could not request a ride. Please sign in and try again."),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      _listenForAcceptance(requestId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isDelivery
                ? "Delivery requested! Waiting for a courier to confirm..."
                : "Ride requested! Waiting for a driver to confirm...",
          ),
          backgroundColor: Theme.of(context).primaryColor,
        ),
      );
    } catch (e) {
      debugPrint('Ride request failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to request ride: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isRequesting = false);
    }
  }

  void _listenForAcceptance([String? expectedRequestId]) {
    _acceptanceSub?.cancel();
    final service = ref.read(transportServiceProvider);
    _acceptanceSub = service.getMyRideRequestStream().listen((ride) {
      final matches = expectedRequestId == null || ride?.id == expectedRequestId;
      if (ride != null && matches && ride.status == 'accepted' && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ActiveRideTrackingScreen(
              startPos:
                  _pickupLatLng ?? const LatLng(-15.3875, 28.3228),
              destPos: _destLatLng ?? const LatLng(-15.395, 28.35),
              requestId: ride.id,
              type: 'ride',
            ),
          ),
        );
      }
    });
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
        if (_pickupLatLng != null && _destLatLng != null) {
          ref
              .read(ridePricingProvider.notifier)
              .calculatePrice(_pickupLatLng!, _destLatLng!);
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not find address: $e')),
        );
      }
    }
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
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Consumer(
          builder: (context, ref, child) {
            final user = Supabase.instance.client.auth.currentUser;
            final profileAsync = ref.watch(profileProvider);
            final profile = profileAsync.value;
            final userName = user?.userMetadata?['full_name'] ??
                profile?.name ??
                'Rider';
            final email = user?.email ?? '';
            final avatarUrl = profile?.avatarUrl ?? '';
            final isVerified = profile?.isVerified ?? false;

            return ListView(
              padding: const EdgeInsets.all(25),
              children: [
                Center(
                  child: Container(
                    width: 50,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                Center(
                  child: Text("Carpso Ride Profile",
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface)),
                ),
                const SizedBox(height: 25),
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 45,
                      backgroundColor:
                          theme.primaryColor.withValues(alpha: 0.1),
                      backgroundImage: avatarUrl.isNotEmpty
                          ? NetworkImage(avatarUrl)
                          : null,
                      child: avatarUrl.isEmpty
                          ? Text(
                              userName.isNotEmpty
                                  ? userName[0].toUpperCase()
                                  : "R",
                              style: TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.bold,
                                  color: theme.primaryColor),
                            )
                          : null,
                    ),
                    if (isVerified)
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: theme.primaryColor,
                            shape: BoxShape.circle,
                            border: Border.fromBorderSide(BorderSide(
                                color: theme.colorScheme.onPrimary, width: 2)),
                          ),
                          child: Icon(Icons.verified,
                              color: theme.colorScheme.onPrimary, size: 16),
                        ),
                      ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      child: GestureDetector(
                        onTap: () => _pickCarpsoAvatar(),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: theme.primaryColor,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(LucideIcons.camera,
                              color: theme.colorScheme.onPrimary, size: 16),
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
                      Text(userName,
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface)),
                      if (isVerified) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.verified,
                            color: theme.primaryColor, size: 18),
                      ],
                    ],
                  ),
                ),
                Center(
                    child: Text(email,
                        style: TextStyle(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6),
                            fontSize: 12))),
                const SizedBox(height: 10),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                            isVerified
                                ? Icons.verified
                                : LucideIcons.shieldCheck,
                            size: 14,
                            color: theme.primaryColor),
                        const SizedBox(width: 6),
                        Text(
                            isVerified ? "Verified Rider" : "Church Member",
                            style: TextStyle(
                                color: theme.primaryColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 12)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 25),
                FutureBuilder<Map<String, String>>(
                  future: _loadRiderStats(),
                  builder: (context, snapshot) {
                    final stats = snapshot.data ?? const {};
                    return Column(
                      children: [
                        _buildProfileStatRow("Total Carpso Rides",
                            stats['total'] ?? "--"),
                        _buildProfileStatRow("Carpso Rides This Month",
                            stats['month'] ?? "--"),
                        _buildProfileStatRow("Favorite Route",
                            stats['route'] ?? "--"),
                        _buildProfileStatRow("Member Since",
                            stats['since'] ?? "--"),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20),
                Divider(
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.1)),
                ListTile(
                  leading: Icon(LucideIcons.sliders,
                      color: theme.primaryColor),
                  title: Text("Ride Preferences",
                      style: TextStyle(
                          color: theme.colorScheme.onSurface)),
                  trailing: Icon(LucideIcons.chevronRight,
                      size: 18,
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.5)),
                  onTap: () {
                    Navigator.pop(context);
                    _showPreferencesSheet();
                  },
                ),
                ListTile(
                  leading: Icon(LucideIcons.shield,
                      color: theme.primaryColor),
                  title: Text("Safety Settings",
                      style: TextStyle(
                          color: theme.colorScheme.onSurface)),
                  trailing: Icon(LucideIcons.chevronRight,
                      size: 18,
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.5)),
                  onTap: () {
                    Navigator.pop(context);
                    _showSafetySettingsSheet();
                  },
                ),
                ListTile(
                  leading: Icon(LucideIcons.helpCircle,
                      color: theme.primaryColor),
                  title: Text("Help & Support",
                      style: TextStyle(
                          color: theme.colorScheme.onSurface)),
                  trailing: Icon(LucideIcons.chevronRight,
                      size: 18,
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.5)),
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

  Widget _buildProfileStatRow(String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  color: theme.colorScheme.onSurface
                      .withValues(alpha: 0.6))),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface)),
        ],
      ),
    );
  }

  Future<Map<String, String>> _loadRiderStats() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return const {};
    try {
      final client = Supabase.instance.client;
      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1).toIso8601String();

      final completed = await client
          .from('ride_requests')
          .select('id')
          .eq('rider_id', user.id)
          .eq('status', 'completed');
      final month = await client
          .from('ride_requests')
          .select('id')
          .eq('rider_id', user.id)
          .gte('created_at', monthStart);

      final profile = await client
          .from('profiles')
          .select('created_at')
          .eq('id', user.id)
          .maybeSingle();
      final created = DateTime.tryParse(profile?['created_at']?.toString() ?? '');
      final since = created != null
          ? '${created.month}/${created.year}'
          : '--';

      return {
        'total': completed.length.toString(),
        'month': month.length.toString(),
        'route': '--',
        'since': since,
      };
    } catch (e) {
      debugPrint('Error loading rider stats: $e');
      return const {};
    }
  }

  bool _prefGospelMusic = true;
  bool _prefQuietRide = false;
  bool _prefAcOn = false;
  final _emergencyNameCtrl = TextEditingController();
  final _emergencyPhoneCtrl = TextEditingController();

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
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 50,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              Text("Carpso Ride Preferences",
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface)),
              const SizedBox(height: 10),
              Text("Customize your travel settings with drivers.",
                  style: TextStyle(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.6),
                      fontSize: 13)),
              const SizedBox(height: 20),
              SwitchListTile(
                activeThumbColor: theme.primaryColor,
                title: Text("Prefer Gospel Music / Sermons",
                    style: TextStyle(color: theme.colorScheme.onSurface)),
                subtitle: Text("Drivers will try to play uplifting audio",
                    style: TextStyle(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.5))),
                value: _prefGospelMusic,
                onChanged: (v) {
                  setSheetState(() => _prefGospelMusic = v);
                },
              ),
              SwitchListTile(
                activeThumbColor: theme.primaryColor,
                title: Text("Quiet / Silent Ride",
                    style: TextStyle(color: theme.colorScheme.onSurface)),
                subtitle: Text("Drivers will minimize conversation",
                    style: TextStyle(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.5))),
                value: _prefQuietRide,
                onChanged: (v) {
                  setSheetState(() => _prefQuietRide = v);
                },
              ),
              SwitchListTile(
                activeThumbColor: theme.primaryColor,
                title: Text("Air Conditioning (AC)",
                    style: TextStyle(color: theme.colorScheme.onSurface)),
                subtitle: Text("Request temperature control",
                    style: TextStyle(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.5))),
                value: _prefAcOn,
                onChanged: (v) {
                  setSheetState(() => _prefAcOn = v);
                },
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  _savePreferences();
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primaryColor,
                  foregroundColor: theme.colorScheme.onPrimary,
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                ),
                child: const Text("SAVE PREFERENCES",
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSafetySettingsSheet() async {
    final theme = Theme.of(context);
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        final data = await Supabase.instance.client
            .from('profiles')
            .select('emergency_contact_name, emergency_contact_phone')
            .eq('id', user.id)
            .maybeSingle();
        if (data != null && mounted) {
          _emergencyNameCtrl.text =
              data['emergency_contact_name']?.toString() ?? '';
          _emergencyPhoneCtrl.text =
              data['emergency_contact_phone']?.toString() ?? '';
        }
      } catch (e) {
        debugPrint('Error loading emergency contact: $e');
      }
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(25),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 50,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              Text("Safety Settings & SOS",
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface)),
              const SizedBox(height: 10),
              Text(
                  "Add a trusted contact to share ride tracking details automatically.",
                  style: TextStyle(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.6),
                      fontSize: 13)),
              const SizedBox(height: 20),
              TextField(
                controller: _emergencyNameCtrl,
                decoration: InputDecoration(
                  labelText: "Contact Name",
                  prefixIcon: const Icon(LucideIcons.user),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15)),
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _emergencyPhoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: "Phone Number",
                  prefixIcon: const Icon(LucideIcons.phone),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15)),
                ),
              ),
              const SizedBox(height: 25),
              ElevatedButton(
                onPressed: _saveEmergencyContact,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primaryColor,
                  foregroundColor: theme.colorScheme.onPrimary,
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                ),
                child: const Text("CONFIRM EMERGENCY CONTACT",
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveEmergencyContact() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      await Supabase.instance.client.from('profiles').update({
        'emergency_contact_name': _emergencyNameCtrl.text.trim(),
        'emergency_contact_phone': _emergencyPhoneCtrl.text.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', user.id);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Emergency Contact saved successfully!"),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint('Failed to save emergency contact: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to save: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showHelpSupportSheet() {
    final theme = Theme.of(context);
    final faqs = [
      {
        "q": "What is Carpso?",
        "a": "Carpso is our secure, church-only ride-sharing network connecting verified drivers and riders from the parish."
      },
      {
        "q": "How does pricing work?",
        "a": "Rides: K10 base + K5/km — you can negotiate the final fare with your driver. Deliveries: fixed Yango-comparable rate (K15 base + K8/km) — no negotiation, the price shown is final."
      },
      {
        "q": "Is it safe?",
        "a": "Yes! All drivers are verified church members vetted by the Bishop and leadership team."
      },
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 50,
                height: 5,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface
                      .withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            Text("Help & Support",
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface)),
            const SizedBox(height: 15),
            Expanded(
              child: ListView(
                children: [
                  ...faqs.map((faq) => Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                          side: BorderSide(
                              color: theme.colorScheme.outlineVariant),
                        ),
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ExpansionTile(
                          shape: const Border(),
                          title: Text(faq['q']?.toString() ?? 'Question',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: theme.colorScheme.onSurface)),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Text(faq['a']?.toString() ?? '',
                                  style: TextStyle(
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.6),
                                      fontSize: 12)),
                            )
                          ],
                        ),
                      )),
                  const SizedBox(height: 15),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      // Navigate to support hub for COA Team contact
                      context.push('/support');
                    },
                    icon: const Icon(LucideIcons.headphones),
                    label: const Text("CONTACT COA TEAM"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primaryColor,
                      foregroundColor: theme.colorScheme.onPrimary,
                      minimumSize: const Size(double.infinity, 56),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18)),
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

  void _pickCarpsoAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: ImageSource.gallery, imageQuality: 70, maxWidth: 512, maxHeight: 512);
    if (picked == null) return;

    try {
      final file = File(picked.path);
      final fileName =
          "carpso_avatar_${DateTime.now().millisecondsSinceEpoch}.jpg";
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
          const SnackBar(
              content: Text("Profile picture updated!"),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("Upload failed: $e"),
              backgroundColor: Colors.red),
        );
      }
    }
  }
}
