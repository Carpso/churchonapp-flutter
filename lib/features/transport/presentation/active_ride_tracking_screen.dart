import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import '../../../core/widgets/church_map.dart';
import 'package:church_on_app/features/connect/presentation/chat_messenger_screen.dart';
import '../data/transport_service.dart';
import '../data/ride_request_model.dart';

class ActiveRideTrackingScreen extends ConsumerStatefulWidget {
  final LatLng startPos;
  final LatLng destPos;
  final String? requestId;
  final String? deliveryId;
  final String type; // 'ride' or 'delivery'

  const ActiveRideTrackingScreen({
    super.key,
    required this.startPos,
    required this.destPos,
    this.requestId,
    this.deliveryId,
    this.type = 'ride',
  });

  @override
  ConsumerState<ActiveRideTrackingScreen> createState() => _ActiveRideTrackingScreenState();
}

class _ActiveRideTrackingScreenState extends ConsumerState<ActiveRideTrackingScreen> {
  LatLng _driverPos = const LatLng(-15.39, 28.33);
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _initTracking();
  }

  void _initTracking() async {
    // 1. Get driver ID from the request
    final service = ref.read(transportServiceProvider);
    String? driverId;
    
    if (widget.type == 'ride' && widget.requestId != null) {
      final rideStream = service.getMyRideRequestStream();
      _sub = rideStream.listen((ride) {
        if (ride?.driverId != null) {
          _listenToDriver(ride!.driverId!);
        }
      });
    } else if (widget.type == 'delivery' && widget.deliveryId != null) {
      final deliveryStream = service.getMyDeliveryStream();
      _sub = deliveryStream.listen((delivery) {
        if (delivery?.driverId != null) {
          _listenToDriver(delivery!.driverId!);
        }
      });
    }
  }

  void _listenToDriver(String driverId) {
    ref.read(transportServiceProvider).watchDriverLocation(driverId).listen((pos) {
      if (pos != null && mounted) {
        setState(() => _driverPos = pos);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          ChurchMap(
            center: widget.startPos,
            zoom: 15,
            markers: [
              buildUserMarker(point: widget.startPos),
              buildRideMarker(point: _driverPos, color: Theme.of(context).primaryColor),
              Marker(
                point: widget.destPos,
                width: 40,
                height: 40,
                child: const Icon(LucideIcons.mapPin, color: Colors.red, size: 40),
              )
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
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 20)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: Theme.of(context).primaryColor,
                        backgroundImage: const NetworkImage('https://i.pravatar.cc/150?img=11'),
                      ),
                      const SizedBox(width: 15),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Kingdom Driver", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                          Row(
                            children: const [
                              Icon(LucideIcons.star, color: Colors.orange, size: 14),
                              Text(" 4.9 (Brother John)", style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        ],
                      ),
                      const Spacer(),
                      CircleAvatar(
                        backgroundColor: Colors.green.withValues(alpha: 0.1),
                        child: IconButton(
                          icon: const Icon(LucideIcons.phone, color: Colors.green),
                          onPressed: () {},
                        ),
                      ),
                      const SizedBox(width: 8),
                      CircleAvatar(
                        backgroundColor: Colors.blue.withValues(alpha: 0.1),
                        child: IconButton(
                          icon: const Icon(LucideIcons.messageCircle, color: Colors.blue),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const ChatMessengerScreen(
                                  userName: "Kingdom Driver",
                                  userAvatar: "https://i.pravatar.cc/150?img=11",
                                  receiverId: "driver_id_mock", // Replace with real driver ID
                                ),
                              ),
                            );
                          },
                        ),
                      )
                    ],
                  ),
                  const Divider(height: 30),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text("Toyota Mark X", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          Text("BAZ 1450 (Silver)", style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor,
                          borderRadius: BorderRadius.circular(15)
                        ),
                        child: Text("3 min away", style: TextStyle(color: Theme.of(context).colorScheme.secondary, fontWeight: FontWeight.bold)),
                      )
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                       Expanded(
                         child: ElevatedButton.icon(
                            onPressed: () => _refuseRide(),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade100, foregroundColor: Colors.red),
                            icon: const Icon(LucideIcons.xCircle, size: 16),
                            label: const Text("Refuse Ride"),
                         )
                       ),
                       const SizedBox(width: 10),
                       Expanded(
                         child: ElevatedButton.icon(
                            onPressed: () => _finishRide(),
                            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).primaryColor, foregroundColor: Colors.white),
                            icon: const Icon(LucideIcons.checkCircle, size: 16),
                            label: Text(widget.type == 'ride' ? "Finish & Rate" : "Complete Mission"),
                         )
                       )
                    ]
                  )
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  void _refuseRide() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Cancel Ride?"),
        content: const Text("Are you sure you want to refuse this ride? Nothing happens if you cancel now."),
        actions: [
           TextButton(onPressed: () => Navigator.pop(context), child: const Text("BACK")),
           ElevatedButton(
              onPressed: () {
                 Navigator.pop(context); // close dialog
                 Navigator.pop(context); // close tracking
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: const Text("CANCEL RIDE"),
           )
        ]
      )
    );
  }

  void _finishRide() {
    int rating = 5;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text("Rate Your Driver", textAlign: TextAlign.center),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                 const CircleAvatar(
                    radius: 40,
                    backgroundImage: NetworkImage('https://i.pravatar.cc/150?img=11'),
                 ),
                 const SizedBox(height: 15),
                 const Text("How was your trip with Kingdom Driver?", textAlign: TextAlign.center),
                 const SizedBox(height: 20),
                 Row(
                   mainAxisAlignment: MainAxisAlignment.center,
                   children: List.generate(5, (index) => IconButton(
                      icon: Icon(LucideIcons.star, color: index < rating ? Colors.orange : Colors.grey.shade300, size: 30),
                      onPressed: () => setState(() => rating = index + 1),
                   )).toList(),
                 ),
                 const SizedBox(height: 15),
                 TextField(
                    decoration: InputDecoration(
                       hintText: "Leave a review...",
                       border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                    maxLines: 2,
                 )
              ]
            ),
             actions: [
               ElevatedButton(
                  onPressed: () async {
                     final service = ref.read(transportServiceProvider);
                     if (widget.type == 'ride' && widget.requestId != null) {
                        await service.updateRideStatus(widget.requestId!, 'completed');
                     } else if (widget.type == 'delivery' && widget.deliveryId != null) {
                        await service.updateDeliveryStatus(widget.deliveryId!, 'delivered');
                     }
                     
                     if (mounted) {
                       Navigator.pop(context); // close dialog
                       Navigator.pop(context); // close tracking
                       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Mission Accomplished! Coins settled.")));
                     }
                  },
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50), backgroundColor: Theme.of(context).primaryColor, foregroundColor: Colors.white),
                  child: const Text("SUBMIT & SETTLE"),
               )
            ]
          );
        }
      )
    );
  }
}
