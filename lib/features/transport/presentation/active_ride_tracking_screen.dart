import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/widgets/church_map.dart';
import 'package:church_on_app/core/widgets/live_tracking_sheet.dart';
import 'package:church_on_app/features/connect/presentation/chat_messenger_screen.dart';
import 'package:church_on_app/features/connect/presentation/audio_call_screen.dart';
import '../data/transport_service.dart';

class ActiveRideTrackingScreen extends ConsumerStatefulWidget {
  final LatLng startPos;
  final LatLng destPos;
  final String? requestId;
  final String? deliveryId;
  final String type;
  final String? driverName;
  final String? driverId;

  const ActiveRideTrackingScreen({
    super.key,
    required this.startPos,
    required this.destPos,
    this.requestId,
    this.deliveryId,
    this.type = 'ride',
    this.driverName,
    this.driverId,
  });

  @override
  ConsumerState<ActiveRideTrackingScreen> createState() =>
      _ActiveRideTrackingScreenState();
}

class _ActiveRideTrackingScreenState
    extends ConsumerState<ActiveRideTrackingScreen>
    with SingleTickerProviderStateMixin {
  String _driverName = "";
  String _driverId = "";
  LatLng _driverPos = const LatLng(-15.39, 28.33);
  LatLng? _prevDriverPos;
  StreamSubscription? _statusSub;
  StreamSubscription? _locationSub;
  String? _vehicleInfo;
  final bool _followDriver = true;
  late AnimationController _animController;
  Animation<LatLng>? _driverAnim;

  @override
  void initState() {
    super.initState();
    _driverName = widget.driverName ?? "Driver";
    _driverId = widget.driverId ?? "";
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..addListener(() {
        if (_driverAnim != null && mounted) {
          setState(() => _driverPos = _driverAnim!.value);
        }
      });
    _initTracking();
  }

  void _initTracking() {
    final service = ref.read(transportServiceProvider);

    if (widget.type == 'ride' && widget.requestId != null) {
      _statusSub = service.getMyRideRequestStream().listen((ride) {
        if (ride?.driverId != null && mounted) {
          _listenToDriver(ride!.driverId!);
          _fetchDriverProfile(ride.driverId!);
        }
      });
    } else if (widget.type == 'delivery' && widget.deliveryId != null) {
      _statusSub = service.getMyDeliveryStream().listen((delivery) {
        if (delivery?.driverId != null && mounted) {
          _listenToDriver(delivery!.driverId!);
          _fetchDriverProfile(delivery.driverId!);
        }
      });
    }
  }

  void _listenToDriver(String driverId) {
    _locationSub?.cancel();
    _locationSub =
        ref.read(transportServiceProvider).watchDriverLocation(driverId).listen(
      (pos) {
        if (pos != null && mounted) {
          _prevDriverPos = _driverPos;
          _driverAnim = Tween<LatLng>(begin: _prevDriverPos, end: pos).animate(
            CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
          );
          _animController.forward(from: 0.0);
        }
      },
    );
  }

  Future<void> _fetchDriverProfile(String driverId) async {
    try {
      final client = Supabase.instance.client;
      final profile = await client
          .from('profiles')
          .select('full_name, avatar_url, vehicle_info')
          .eq('id', driverId)
          .maybeSingle();
      if (profile != null && mounted) {
        setState(() {
          _driverName = profile['full_name'] ?? _driverName;
          _vehicleInfo = profile['vehicle_info'];
          _driverId = driverId;
        });
      }
    } catch (e) {
      debugPrint('Error fetching driver info: $e');
    }
  }

  void _showLiveTrackingSheet() {
    final steps = [
      LiveTrackingStep(title: 'Driver Assigned', description: '$_driverName is on the way', isCompleted: true, isCurrent: false),
      LiveTrackingStep(title: 'Pickup', description: 'Driver arriving at pickup point', isCompleted: false, isCurrent: true),
      LiveTrackingStep(title: 'En Route', description: 'Heading to destination', isCompleted: false, isCurrent: false),
      LiveTrackingStep(title: 'Arrived', description: 'Reached destination', isCompleted: false, isCurrent: false),
    ];
    LiveTrackingSheet.show(
      context,
      title: widget.type == 'ride' ? 'Ride Tracking' : 'Delivery Tracking',
      subtitle: 'From pickup to destination',
      statusText: 'Active',
      statusColor: Colors.green,
      driverName: _driverName,
      vehicleInfo: _vehicleInfo,
      etaText: '12 min',
      steps: steps,
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    _statusSub?.cancel();
    _locationSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Stack(
        children: [
          ChurchMap(
            center: _followDriver ? _driverPos : widget.startPos,
            zoom: 16,
            markers: [
              // User pickup marker with label
              Marker(
                point: widget.startPos,
                width: 100,
                height: 70,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                      ),
                      child: const Text('Pickup', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 2),
                    const Icon(LucideIcons.mapPin, color: Colors.green, size: 28),
                  ],
                ),
              ),
              // Driver marker with vehicle label
              Marker(
                point: _driverPos,
                width: 120,
                height: 80,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: theme.primaryColor,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                      ),
                      child: Text(
                        _vehicleInfo ?? _driverName,
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: theme.primaryColor,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: theme.primaryColor.withValues(alpha: 0.4), blurRadius: 12)],
                      ),
                      child: const Icon(LucideIcons.car, color: Colors.white, size: 18),
                    ),
                  ],
                ),
              ),
              // Destination marker with label
              Marker(
                point: widget.destPos,
                width: 100,
                height: 70,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.flag, color: Colors.red, size: 28),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                      ),
                      child: const Text('Destination', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ],
            path: [widget.startPos, _driverPos, widget.destPos],
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 20,
            child: CircleAvatar(
              backgroundColor: Colors.white,
              child: IconButton(
                icon: const Icon(LucideIcons.arrowLeft, color: Colors.black),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 20)
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor:
                            Theme.of(context).primaryColor.withValues(alpha: 0.1),
                        child: Text(
                          _driverName.isNotEmpty
                              ? _driverName[0].toUpperCase()
                              : "D",
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_driverName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 18)),
                            if (_vehicleInfo != null)
                              Text(_vehicleInfo!,
                                  style: const TextStyle(
                                      color: Colors.grey, fontSize: 12)),
                          ],
                        ),
                      ),
                      CircleAvatar(
                        backgroundColor:
                            Colors.green.withValues(alpha: 0.1),
                        child: IconButton(
                          icon: const Icon(LucideIcons.phone,
                              color: Colors.green),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AudioCallScreen(
                                  userName: _driverName,
                                  userAvatar: '',
                                  recipientId: _driverId,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      CircleAvatar(
                        backgroundColor:
                            Colors.blue.withValues(alpha: 0.1),
                        child: IconButton(
                          icon: const Icon(LucideIcons.messageCircle,
                              color: Colors.blue),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ChatMessengerScreen(
                                  userName: _driverName,
                                  userAvatar: '',
                                  receiverId: _driverId,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      CircleAvatar(
                        backgroundColor:
                            Colors.indigo.withValues(alpha: 0.1),
                        child: IconButton(
                          icon: const Icon(LucideIcons.info,
                              color: Colors.indigo),
                          onPressed: () => _showLiveTrackingSheet(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      CircleAvatar(
                        backgroundColor:
                            Colors.amber.withValues(alpha: 0.1),
                        child: IconButton(
                          icon: const Icon(LucideIcons.share2,
                              color: Colors.amber),
                          onPressed: () async {
                            final String tripUrl =
                                "https://carpso.churchonapp.com/track/${widget.requestId ?? widget.deliveryId}";
                            await Clipboard.setData(
                                ClipboardData(text: tripUrl));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        "Secure Share Link copied to clipboard!")),
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 30),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _vehicleInfo ?? "Standard Vehicle",
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Text(
                          "En Route",
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.secondary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _refuseRide(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade100,
                            foregroundColor: Colors.red,
                          ),
                          icon:
                              const Icon(LucideIcons.xCircle, size: 16),
                          label: const Text("Refuse Carpso Ride"),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _finishRide(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                Theme.of(context).primaryColor,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(LucideIcons.checkCircle,
                              size: 16),
                          label: Text(widget.type == 'ride'
                              ? "Finish & Rate"
                              : "Complete Mission"),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _refuseRide() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Cancel Carpso Ride?"),
        content: const Text(
            "Are you sure you want to refuse this Carpso Ride? Nothing happens if you cancel now."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("BACK")),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white),
            child: const Text("CANCEL CARPSO RIDE"),
          ),
        ],
      ),
    );
  }

  void _finishRide() {
    int rating = 5;
    final reviewCtrl = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: const Text("Rate Your Driver",
                textAlign: TextAlign.center),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor:
                      Theme.of(context).primaryColor.withValues(alpha: 0.1),
                  child: Text(
                    _driverName.isNotEmpty
                        ? _driverName[0].toUpperCase()
                        : "D",
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                Text(
                  "How was your trip with $_driverName?",
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    5,
                    (index) => IconButton(
                      icon: Icon(
                        LucideIcons.star,
                        color: index < rating
                            ? Colors.orange
                            : Colors.grey.shade300,
                        size: 30,
                      ),
                      onPressed: () =>
                          setDialogState(() => rating = index + 1),
                    ),
                  ).toList(),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: reviewCtrl,
                  decoration: InputDecoration(
                    hintText: "Leave a review...",
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15)),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () async {
                  final service = ref.read(transportServiceProvider);
                  if (widget.type == 'ride' && widget.requestId != null) {
                    await service.updateRideStatus(
                        widget.requestId!, 'completed');
                  } else if (widget.type == 'delivery' &&
                      widget.deliveryId != null) {
                    await service.updateDeliveryStatus(
                        widget.deliveryId!, 'delivered');
                  }

                  // Save rating to service_ratings
                  try {
                    final user = Supabase.instance.client.auth.currentUser;
                    if (user != null && widget.driverId != null) {
                      await Supabase.instance.client.from('service_ratings').upsert({
                        'rater_id': user.id,
                        'rated_id': widget.driverId,
                        'rating': rating,
                        'review': reviewCtrl.text.trim().isNotEmpty ? reviewCtrl.text.trim() : null,
                        'context': widget.type,
                        'context_id': widget.requestId ?? widget.deliveryId,
                      }, onConflict: 'rater_id,context,context_id');
                    }
                  } catch (e) {
                    debugPrint('Rating save failed: $e');
                  }

                  if (!context.mounted) return;
                  Navigator.pop(context);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            "Mission Accomplished! Coins settled.")),
                  );
                },
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: const Text("SUBMIT & SETTLE"),
              ),
            ],
          );
        },
      ),
    );
  }
}
