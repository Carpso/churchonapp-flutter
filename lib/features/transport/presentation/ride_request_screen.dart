import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/widgets/church_map.dart';
import '../../../core/theme/app_theme.dart';
import 'active_ride_tracking_screen.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import '../data/transport_service.dart';
import '../../finance/presentation/lenco_payment_gateway.dart';
import '../data/ride_request_model.dart';
import '../data/delivery_model.dart';

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
    final driversAsync = ref.watch(activeDriversStreamProvider);

    return ChurchMap(
      markers: [
        buildUserMarker(point: const LatLng(-15.3875, 28.3228)),
        ...driversAsync.when(
          data: (drivers) => drivers.map((d) => buildRideMarker(
            point: LatLng(d.lat, d.lng),
            color: Theme.of(context).primaryColor,
          )),
          loading: () => [],
          error: (e, s) => [],
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
    final categoryInfo = {
      'people': {'label': 'RIDE', 'desc': 'Personal Transport', 'icon': LucideIcons.car},
      'bus': {'label': 'BUS', 'desc': 'Find a Bus Route', 'icon': LucideIcons.bus},
      'marketplace': {'label': 'MARKET', 'desc': 'Deliver Goods', 'icon': LucideIcons.shoppingBag},
      'bookshop': {'label': 'BOOKS', 'desc': 'Book Delivery', 'icon': LucideIcons.bookOpen},
    };
    final info = categoryInfo[_selectedCategory] ?? categoryInfo['people']!;

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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  info['icon'] as IconData,
                  size: 16,
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      info['label'] as String,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    Text(
                      info['desc'] as String,
                      style: TextStyle(fontSize: 9, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _showRiderProfile(),
            child: const CircleAvatar(
              backgroundColor: Colors.white,
              child: Icon(LucideIcons.user, color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }

  void _showRiderProfile() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Consumer(
          builder: (context, ref, child) {
            final user = Supabase.instance.client.auth.currentUser;
            final userName = user?.userMetadata?['full_name'] ?? 'Kingdom Rider';
            final email = user?.email ?? '';
            
            return ListView(
              padding: const EdgeInsets.all(25),
              children: [
                Center(
                  child: Container(
                    width: 50,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const Center(child: Text("Ride On Profile", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
                const SizedBox(height: 25),
                Center(
                  child: CircleAvatar(
                    radius: 45,
                    backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                    child: Text(
                      userName.isNotEmpty ? userName[0].toUpperCase() : "R",
                      style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor),
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                Center(child: Text(userName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                Center(child: Text(email, style: const TextStyle(color: Colors.grey, fontSize: 12))),
                const SizedBox(height: 10),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.star, size: 14, color: Colors.green),
                        SizedBox(width: 6),
                        Text("4.8 Rating", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 25),
                _buildProfileStatRow("Total Rides", "12"),
                _buildProfileStatRow("Rides This Month", "3"),
                _buildProfileStatRow("Favorite Route", "Home → Church"),
                _buildProfileStatRow("Member Since", "2024"),
                _buildProfileStatRow("Prayer Rides", "5"),
                const SizedBox(height: 20),
                const Divider(),
                ListTile(
                  leading: Icon(LucideIcons.shield, color: Theme.of(context).primaryColor),
                  title: const Text("Safety Settings"),
                  trailing: const Icon(LucideIcons.chevronRight, size: 18),
                  onTap: () {},
                ),
                ListTile(
                  leading: Icon(LucideIcons.creditCard, color: Theme.of(context).primaryColor),
                  title: const Text("Payment Methods"),
                  trailing: const Icon(LucideIcons.chevronRight, size: 18),
                  onTap: () {},
                ),
                ListTile(
                  leading: Icon(LucideIcons.history, color: Theme.of(context).primaryColor),
                  title: const Text("Ride History"),
                  trailing: const Icon(LucideIcons.chevronRight, size: 18),
                  onTap: () {},
                ),
                ListTile(
                  leading: Icon(LucideIcons.helpCircle, color: Theme.of(context).primaryColor),
                  title: const Text("Help & Support"),
                  trailing: const Icon(LucideIcons.chevronRight, size: 18),
                  onTap: () {},
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildProfileStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
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
      {'id': 'people', 'label': 'Ride', 'desc': 'Personal Transport', 'icon': LucideIcons.car},
      {'id': 'bus', 'label': 'Bus', 'desc': 'Find a Bus Route', 'icon': LucideIcons.bus},
      {'id': 'marketplace', 'label': 'Market', 'desc': 'Deliver Goods', 'icon': LucideIcons.shoppingBag},
      {'id': 'bookshop', 'label': 'Books', 'desc': 'Book Delivery', 'icon': LucideIcons.bookOpen},
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
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                decoration: BoxDecoration(
                  color: isSelected ? Theme.of(context).colorScheme.secondary : Colors.transparent,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: isSelected
                      ? [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 6, offset: const Offset(0, 2))]
                      : [],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(cat['icon'] as IconData, color: isSelected ? Theme.of(context).primaryColor : Colors.grey, size: 18),
                    const SizedBox(height: 3),
                    Text(
                      cat['label'] as String,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.grey,
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
                            color: Theme.of(context).primaryColor.withOpacity(0.8),
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
        _offeredFare = null;
        _isNegotiating = false;
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text("K ${_isNegotiating && _offeredFare != null ? _offeredFare!.toInt() : _estimatedPrice!.toInt()}", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.secondary)),
                      const Text("inc 6% platform fee", style: TextStyle(fontSize: 10, color: Colors.blue)),
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
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Theme.of(context).primaryColor, decoration: TextDecoration.underline),
                     )
                   )
                ]
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
        Consumer(builder: (context, ref, child) {
          final myRide = ref.watch(myRideRequestStreamProvider).value;
          final myDelivery = ref.watch(myDeliveryStreamProvider).value;
          
          final isWaiting = (myRide != null && myRide.status == 'pending') || (myDelivery != null && myDelivery.status == 'pending');
          final isRideAccepted = myRide != null && myRide.status == 'accepted';
          final isDeliveryAccepted = myDelivery != null && myDelivery.status == 'accepted';

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
              backgroundColor: isWaiting ? Colors.grey : Theme.of(context).primaryColor,
              minimumSize: const Size(double.infinity, 65),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
              elevation: 8,
              shadowColor: Theme.of(context).primaryColor.withOpacity(0.5),
            ),
            child: Text(
              isWaiting ? "SEARCHING FOR DRIVER..." : "PAY & REQUEST RIDE",
              style: TextStyle(color: Theme.of(context).colorScheme.secondary, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.5),
            ),
          );
        }),
      ],
    );
  }

  void _handleRidePayment() {
    final fare = _isNegotiating && _offeredFare != null ? _offeredFare! : _estimatedPrice!;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => LencoPaymentGateway(
        amount: fare + (fare * 0.06),
        description: "Ride to: ${_dropoffController.text}",
        category: "ride",
        recipientName: "Kingdom Driver (John D.)",
        recipientAccount: "DRIVER-SETTLE-8899",
        paymentReason: "Ride On App Fare",
        onComplete: (success, txId) async {
          Navigator.pop(context); // Close gateway
          if (success) {
            final fare = _isNegotiating && _offeredFare != null ? _offeredFare! : _estimatedPrice!;
            final isDelivery = _selectedCategory == 'marketplace' || _selectedCategory == 'bookshop';
            
            if (isDelivery) {
              await ref.read(transportServiceProvider).requestDelivery(
                pickup: const LatLng(-15.3875, 28.3228),
                dest: const LatLng(-15.395, 28.35),
                desc: _itemDescController.text,
                category: _selectedCategory,
                weight: _selectedWeight,
                fare: fare,
              );
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Delivery request sent to Kingdom Couriers!")));
            } else {
              await ref.read(transportServiceProvider).requestRide(
                const LatLng(-15.3875, 28.3228), 
                const LatLng(-15.395, 28.35), 
                fare
              );
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Request sent to Kingdom Drivers!")));
            }
          }
        },
      ),
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
            const Text("Offer a different price to drivers nearby. Drivers can accept, refuse, or counter your offer.", style: TextStyle(fontSize: 12, color: Colors.grey)),
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
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).primaryColor, foregroundColor: Colors.white),
            child: const Text("SET OFFER"),
          )
        ],
      )
    );
  }

  void _confirmRideBooking(RideRequest ride) {
    if (ModalRoute.of(context)?.isCurrent == false) return;
    _showBookingDialog(
      title: "DRIVER FOUND!",
      icon: LucideIcons.checkCircle,
      onConfirm: () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ActiveRideTrackingScreen(
              startPos: ride.pickup,
              destPos: ride.destination,
              requestId: ride.id,
              type: 'ride',
            ),
          ),
        );
      },
    );
  }

  void _confirmDeliveryBooking(DeliveryRequest delivery) {
    if (ModalRoute.of(context)?.isCurrent == false) return;
    _showBookingDialog(
      title: "COURIER FOUND!",
      icon: LucideIcons.package,
      onConfirm: () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ActiveRideTrackingScreen(
              startPos: delivery.pickup,
              destPos: delivery.destination,
              deliveryId: delivery.id,
              type: 'delivery',
            ),
          ),
        );
      },
    );
  }

  void _showBookingDialog({required String title, required IconData icon, required VoidCallback onConfirm}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.green, size: 60),
            const SizedBox(height: 20),
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const Text("Your Kingdom partner is on the way. You can now track their live GPS heartbeat.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: onConfirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Theme.of(context).colorScheme.secondary,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              child: const Text("TRACK MISSION", style: TextStyle(fontWeight: FontWeight.bold)),
            )
          ],
        ),
      ),
    );
  }
}

