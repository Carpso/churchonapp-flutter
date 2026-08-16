import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:church_on_app/features/marketplace/data/marketplace_service.dart';
import 'package:church_on_app/features/admin/data/order_service.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/config/env.dart';
import 'package:church_on_app/core/config/fee_config.dart';
import 'package:church_on_app/core/config/remote_config.dart';
import 'package:church_on_app/features/give/presentation/widgets/momo_phone_input_widget.dart';
import 'package:church_on_app/features/transport/data/transport_service.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;

enum _PaymentPhase { idle, initiating, awaitingPin, succeeded, failed }

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _phoneCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _carpsoAddressCtrl = TextEditingController();
  String _selectedNetwork = "MTN";
  String _paymentMethod = "mobile_money";
  String _deliveryMethod = "delivery";

  bool _isProcessing = false;
  bool _isSuccess = false;
  bool _isError = false;
  String? _errorMessage;
  String? _orderReference;

  _PaymentPhase _paymentPhase = _PaymentPhase.idle;
  String _paymentStatusMessage = '';
  Timer? _pollTimer;
  Timer? _geocodeTimer;

  // Pickup churches for cart items (sellers may belong to different tenants).
  final Set<String> _pickupChurchNames = {};

  // Carpso delivery: geocoded destination + distance-based fare.
  LatLng? _geocodedDest;
  bool _geocoding = false;
  String? _geocodeError;

  final List<Map<String, dynamic>> _networks = [
    {"name": "MTN", "color": Colors.yellow, "id": "mtn", "logo": "assets/logo_mtn.png"},
    {"name": "Airtel", "color": Colors.red, "id": "airtel", "logo": "assets/logo_airtel.png"},
    {"name": "Zamtel", "color": Colors.green, "id": "zamtel", "logo": "assets/logo_zamtel.png"},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final profile = ref.read(profileProvider).value;
      if (profile?.phoneNumber != null && profile!.phoneNumber!.isNotEmpty) {
        _phoneCtrl.text = profile.phoneNumber!;
      }
      if (profile != null) {
        _firstNameCtrl.text = profile.name.split(' ').first;
        _lastNameCtrl.text = profile.name.split(' ').skip(1).join(' ');
        final user = Supabase.instance.client.auth.currentUser;
        _emailCtrl.text = user?.email ?? '';
      }
      _loadPickupChurches();
      _carpsoAddressCtrl.addListener(_onAddressChanged);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _geocodeTimer?.cancel();
    _phoneCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _carpsoAddressCtrl.dispose();
    super.dispose();
  }

  /// Resolve which church(es) the cart items are picked up from, so the
  /// "Pickup at Church" option is never ambiguous when sellers belong to
  /// different tenants.
  Future<void> _loadPickupChurches() async {
    final items = ref.read(cartProvider);
    final tenantIds = items
        .map((item) => item.product.tenantId)
        .whereType<String>()
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList();
    if (tenantIds.isEmpty) return;
    try {
      final supabase = Supabase.instance.client;
      final rows = await supabase
          .from('tenants')
          .select('id, name')
          .inFilter('id', tenantIds);
      if (!mounted) return;
      final names = (rows as List)
          .map((r) => (r['name'] ?? '').toString())
          .where((n) => n.isNotEmpty)
          .toSet();
      setState(() {
        _pickupChurchNames.addAll(names);
      });
    } catch (e) {
      debugPrint('Checkout: failed to load pickup churches: $e');
    }
  }

  void _onAddressChanged() {
    _geocodeTimer?.cancel();
    _geocodeTimer = Timer(const Duration(milliseconds: 900), _geocodeAddress);
  }

  /// Geocode the delivery address via OpenStreetMap Nominatim (free, no key).
  Future<void> _geocodeAddress() async {
    final address = _carpsoAddressCtrl.text.trim();
    if (address.isEmpty) {
      if (mounted) {
        setState(() {
          _geocodedDest = null;
          _geocoding = false;
          _geocodeError = null;
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _geocoding = true;
        _geocodeError = null;
      });
    }
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': '$address, Zambia',
        'format': 'json',
        'limit': '1',
      });
      final res = await http.get(uri, headers: {
        'User-Agent': 'ChurchOnApp/1.0 (church management app)',
      });
      final data = jsonDecode(res.body) as List;
      if (data.isEmpty) {
        if (mounted) {
          setState(() {
            _geocoding = false;
            _geocodedDest = null;
            _geocodeError = 'Address not found. Add a landmark or area name.';
          });
        }
        return;
      }
      final lat = double.tryParse(data[0]['lat']?.toString() ?? '');
      final lng = double.tryParse(data[0]['lon']?.toString() ?? '');
      if (lat == null || lng == null) {
        if (mounted) {
          setState(() {
            _geocoding = false;
            _geocodedDest = null;
            _geocodeError = 'Could not locate that address.';
          });
        }
        return;
      }
      if (mounted) {
        setState(() {
          _geocoding = false;
          _geocodedDest = LatLng(lat, lng);
          _geocodeError = null;
        });
      }
    } catch (e) {
      debugPrint('Checkout: geocoding failed: $e');
      if (mounted) {
        setState(() {
          _geocoding = false;
          _geocodedDest = null;
          _geocodeError = 'Could not verify the address. Check your connection.';
        });
      }
    }
  }

  /// Distance (km) between the pickup church and the geocoded destination.
  double? get _deliveryDistanceKm {
    final dest = _geocodedDest;
    final tenant = ref.read(currentTenantProvider);
    final lat = tenant?.latitude;
    final lng = tenant?.longitude;
    if (dest == null || lat == null || lng == null) return null;
    return const Distance()
        .as(LengthUnit.Kilometer, LatLng(lat, lng), dest);
  }

  // Platform fee = 1% COA + Lipila fees (buyer pays this)
  FeeConfig get _fees => ref.read(feeConfigProvider).value ?? FeeConfig.defaults;
  double get _platformFee => _fees.platformFee(ref.read(cartProvider.notifier).total);

  double get _deliveryFee {
    if (_deliveryMethod == 'carpso') {
      final km = _deliveryDistanceKm;
      if (km == null) return 0.0;
      // Distance-based engine: base + per-km, never below the minimum fare.
      final price = _fees.rideDeliveryBaseFareKwacha +
          km * _fees.rideDeliveryPerKmKwacha;
      final minFare =
          widgetRemoteConfig(ref).getDouble('ride_delivery_min_fare_kwacha', 20.0);
      return price < minFare ? minFare : price;
    }
    return _deliveryMethod == 'delivery'
        ? widgetRemoteConfig(ref).getDouble('marketplace_delivery_fee_kwacha', 15.0)
        : 0.0;
  }

  double get _total {
    final subtotal = ref.read(cartProvider.notifier).total;
    return subtotal + _platformFee + _deliveryFee;
  }

  Future<void> _disburseToSeller(List<CartItem> items, double subtotal, double fee, String? tenantId, String? paymentReference) async {
    try {
      final supabase = Supabase.instance.client;

      final vendorIds = items
          .where((item) => item.product.vendorId != null && item.product.vendorId!.isNotEmpty)
          .map((item) => item.product.vendorId!)
          .toSet()
          .toList();

      if (vendorIds.isEmpty) return;

      for (final vendorId in vendorIds) {
        String? sellerPhone;
        try {
          final profile = await supabase
              .from('profiles')
              .select('phone_number')
              .eq('id', vendorId)
              .maybeSingle();
          sellerPhone = profile?['phone_number'] as String?;
        } catch (e) {
          debugPrint('Error fetching seller phone: $e');
        }

        if (sellerPhone == null || sellerPhone.isEmpty) {
          try {
            final church = await supabase
                .from('churches')
                .select('treasurer_phone')
                .eq('id', tenantId ?? '')
                .maybeSingle();
            sellerPhone = church?['treasurer_phone'] as String?;
          } catch (e) {
            debugPrint('Error fetching treasurer phone: $e');
          }
        }

        if (sellerPhone == null || sellerPhone.isEmpty) {
          sellerPhone = Env.coaMoMoNumber;
        }

        final vendorItemTotal = items
            .where((item) => item.product.vendorId == vendorId)
            .fold(0.0, (sum, item) => sum + (item.product.price * item.quantity));
        if (vendorItemTotal <= 0) continue;

        final payoutRef = paymentReference ?? 'MKT-${DateTime.now().millisecondsSinceEpoch}-$vendorId';
        // ── Server-side settlement ──────────────────────────────────────
        // Enqueue a payout task anchored to the confirmed Lipila collection.
        // The settlement engine (webhook/cron) pays the seller's profile phone
        // and applies the COA business cut + payout fees SERVER-SIDE. We pass
        // the uncut item total so the cut can never be bypassed client-side.
        try {
          await supabase.rpc('enqueue_payout_task', params: {
            'p_source': 'order',
            'p_source_ref': null,
            'p_payment_ref': payoutRef,
            'p_recipient_user_id': vendorId,
            'p_recipient_phone': sellerPhone,
            'p_gross_amount': vendorItemTotal,
          });
          debugPrint('[Marketplace] Enqueued seller settlement for $vendorId (ref $payoutRef)');
        } catch (e) {
          debugPrint('[Marketplace] Seller settlement enqueue failed (non-blocking): $e');
        }
      }
    } catch (e) {
      debugPrint('[Marketplace] Seller disbursement failed (non-blocking): $e');
    }
  }

  Future<void> _placeOrder() async {
    final items = ref.read(cartProvider);
    if (items.isEmpty) return;

    if (_paymentMethod == "mobile_money" && _phoneCtrl.text.isEmpty) {
      setState(() {
        _isError = true;
        _errorMessage = "Phone number is required";
      });
      return;
    }

    if (_paymentMethod == "card" && (_firstNameCtrl.text.isEmpty || _lastNameCtrl.text.isEmpty)) {
      setState(() {
        _isError = true;
        _errorMessage = "First and last name are required for card payment";
      });
      return;
    }

    if (_deliveryMethod == "carpso" && _carpsoAddressCtrl.text.trim().isEmpty) {
      setState(() {
        _isError = true;
        _errorMessage = "Delivery address is required for Carpso Delivery";
      });
      return;
    }

    if (_deliveryMethod == "carpso" && _geocodedDest == null) {
      setState(() {
        _isError = true;
        _errorMessage =
            _geocodeError ?? "Please wait for the delivery address to be verified.";
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _isError = false;
      _errorMessage = null;
    });

    try {
      final subtotal = ref.read(cartProvider.notifier).total;
      final fee = _platformFee;
      final total = subtotal + fee;

      if (_paymentMethod == "card") {
        final supabase = Supabase.instance.client;
        final referenceId = const Uuid().v4();

        setState(() {
          _paymentPhase = _PaymentPhase.initiating;
          _paymentStatusMessage = "Connecting to card payment gateway...";
        });

        final response = await supabase.functions.invoke('lipila-card-collect', body: {
          "amount": total,
          "narration": "Marketplace Order",
          "reference": referenceId,
          "firstName": _firstNameCtrl.text.trim(),
          "lastName": _lastNameCtrl.text.trim(),
          "email": _emailCtrl.text.trim(),
          "phone": _phoneCtrl.text.isNotEmpty ? _phoneCtrl.text : "",
        });

        if (response.data == null) {
          throw Exception("Card payment initiation failed");
        }

        final data = response.data is Map
            ? Map<String, dynamic>.from(response.data as Map)
            : {};
        final cardUrl = data['url'] as String?;

        if (cardUrl != null && cardUrl.isNotEmpty) {
          final uri = Uri.parse(cardUrl);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.inAppWebView);
          }
        }

        setState(() {
          _paymentPhase = _PaymentPhase.awaitingPin;
          _paymentStatusMessage = "Complete card payment in the secure page, then return here.";
        });

        await _pollPaymentStatus(referenceId);
        return;
      }

      // Mobile Money: initiate → poll → then create order
      final supabase = Supabase.instance.client;
      String phone = MomoPhoneInputWidget.formatPhone(_phoneCtrl.text);

      final referenceId = const Uuid().v4();

      setState(() {
        _paymentPhase = _PaymentPhase.initiating;
        _paymentStatusMessage = "Connecting to Lipila Gateway...";
      });

      final response = await supabase.functions.invoke('lipila-collect', body: {
        "action": "initiate",
        "accountNumber": phone,
        "amount": total,
        "narration": "Marketplace Order",
        "reference": referenceId,
      });

      if (response.data == null) {
        throw Exception("Payment initiation failed");
      }

      setState(() {
        _paymentPhase = _PaymentPhase.awaitingPin;
        _paymentStatusMessage = "Pushing PIN prompt to ${_phoneCtrl.text}...";
      });

      await _pollPaymentStatus(referenceId);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _paymentPhase = _PaymentPhase.failed;
          _paymentStatusMessage = e.toString().replaceFirst("Exception: ", "");
          _errorMessage = e.toString().replaceFirst("Exception: ", "");
          _isError = true;
        });
      }
    }
  }

  Future<void> _pollPaymentStatus(String referenceId) async {
    const maxAttempts = 20;
    int attempts = 0;
    final completer = Completer<void>();

    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      attempts++;

      final supabase = Supabase.instance.client;

      // Check DB first (fastest path via webhook)
      try {
        final localPayment = await supabase
            .from('coa_payments')
            .select('status')
            .eq('payment_ref', referenceId)
            .maybeSingle();

        if (localPayment != null) {
          final dbStatus = (localPayment['status'] ?? '').toString().toLowerCase();
          if (['approved', 'completed', 'confirmed', 'settled'].contains(dbStatus)) {
            timer.cancel();
            if (mounted) {
              setState(() {
                _paymentPhase = _PaymentPhase.succeeded;
                _paymentStatusMessage = "Payment confirmed. Creating order...";
              });
            }
            if (!completer.isCompleted) completer.complete();
            return;
          } else if (['rejected', 'failed', 'cancelled'].contains(dbStatus)) {
            timer.cancel();
            if (mounted) {
              setState(() {
                _paymentPhase = _PaymentPhase.failed;
                _paymentStatusMessage = "Payment was $dbStatus.";
                _errorMessage = "Payment was $dbStatus.";
                _isError = true;
                _isProcessing = false;
              });
            }
            if (!completer.isCompleted) completer.complete();
            return;
          }
        }
      } catch (e) {
        debugPrint('Checkout: Error parsing payment status: $e');
      }

      // Check Lipila API status
      try {
        final statusResponse = await supabase.functions.invoke('lipila-collect', body: {
          "action": "status",
          "reference": referenceId,
        });

        if (statusResponse.data != null) {
          final statusData = statusResponse.data is Map
              ? Map<String, dynamic>.from(statusResponse.data as Map)
              : jsonDecode(jsonEncode(statusResponse.data)) as Map<String, dynamic>;

          String status = '';
          try {
            status = (statusData['data']?['status'] ??
                    statusData['data']?['data']?['status'] ??
                    statusData['data']?['transaction']?['status'] ??
                    statusData['status'] ??
                    statusData['transaction']?['status'] ??
                    '')
                .toString()
                .toLowerCase()
                .trim();
          } catch (e) {
            debugPrint('Checkout: Error parsing payment status: $e');
          }

          if (['successful', 'paid', 'completed', 'settled', 'success', 'approved', 'accepted', 'confirmed'].contains(status)) {
            timer.cancel();
            if (mounted) {
              setState(() {
                _paymentPhase = _PaymentPhase.succeeded;
                _paymentStatusMessage = "Payment confirmed. Creating order...";
              });
            }
            if (!completer.isCompleted) completer.complete();
            return;
          } else if (['failed', 'cancelled', 'rejected', 'declined', 'error', 'timeout'].contains(status)) {
            timer.cancel();
            if (mounted) {
              setState(() {
                _paymentPhase = _PaymentPhase.failed;
                _paymentStatusMessage = "Transaction was $status.";
                _errorMessage = "Transaction was $status.";
                _isError = true;
                _isProcessing = false;
              });
            }
            if (!completer.isCompleted) completer.complete();
            return;
          }
        }
      } catch (e) {
        debugPrint("Error polling payment status (attempt $attempts): $e");
      }

      if (attempts >= maxAttempts) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _paymentPhase = _PaymentPhase.failed;
            _paymentStatusMessage = "Payment verification timed out. Reference: ${referenceId.substring(0, 8)}";
            _errorMessage = "Payment could not be verified. Your money is safe — check with your provider. Ref: ${referenceId.substring(0, 8)}";
            _isError = true;
            _isProcessing = false;
          });
        }
        if (!completer.isCompleted) completer.complete();
      }
    });

    await completer.future;

    // If payment succeeded, create the order now
    if (_paymentPhase == _PaymentPhase.succeeded) {
      final subtotal = ref.read(cartProvider.notifier).total;
      final fee = _platformFee;
      final tenant = ref.read(currentTenantProvider);
      final items = ref.read(cartProvider);
      await _createOrderAndDisburse(items, subtotal, fee, tenant?.id, referenceId);
    }
  }

  Future<void> _createOrderAndDisburse(
    List<CartItem> items,
    double subtotal,
    double fee,
    String? tenantId,
    String? paymentReference,
  ) async {
    try {
      final orderService = ref.read(orderServiceProvider);

      final orderId = await orderService.createOrder(
        items: items.map((item) => {
          'item_id': item.product.id,
          'item_name': item.product.name,
          'quantity': item.quantity,
          'unit_price': item.product.price,
          'total_price': item.product.price * item.quantity,
          'vendor_id': item.product.vendorId,
        }).toList(),
        totalAmount: subtotal,
        deliveryFee: _deliveryFee,
        platformFee: fee,
        paymentReference: paymentReference,
        tenantId: tenantId,
        shippingAddress: _deliveryMethod == 'carpso' ? _carpsoAddressCtrl.text.trim() : null,
        contactPhone: _phoneCtrl.text.trim().isNotEmpty ? _phoneCtrl.text.trim() : null,
        notes: _deliveryMethod == 'carpso'
            ? 'Carpso Delivery to: ${_carpsoAddressCtrl.text.trim()}'
            : null,
      );

      // Disburse to seller only AFTER order is confirmed
      if (_paymentMethod == "mobile_money") {
        await _disburseToSeller(items, subtotal, fee, tenantId, paymentReference);
      }

      // Optional Carpso Delivery: create a courier request for drivers
      if (_deliveryMethod == "carpso") {
        await _triggerCarpsoDelivery(orderId, items);
      }

      ref.read(cartProvider.notifier).clear();

      if (mounted) {
        setState(() {
          _isSuccess = true;
          _isProcessing = false;
          _orderReference = orderId;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _isError = true;
          _errorMessage = "Order creation failed: ${e.toString().replaceFirst('Exception: ', '')}";
        });
      }
    }
  }

  /// Creates a Carpso courier request so a driver can deliver the order.
  /// Pickup is the seller church; the destination is the geocoded customer
  /// address; the fare is the engine-calculated delivery price.
  /// Non-blocking — the order is already placed and paid for.
  Future<void> _triggerCarpsoDelivery(String orderId, List<CartItem> items) async {
    try {
      final tenant = ref.read(currentTenantProvider);
      final lat = tenant?.latitude ?? -15.4190;
      final lng = tenant?.longitude ?? 28.3490;
      final dest = _geocodedDest ?? LatLng(lat, lng);
      final address = _carpsoAddressCtrl.text.trim();

      final itemNames = items.map((i) => '${i.quantity}x ${i.product.name}').join(', ');
      await ref.read(transportServiceProvider).requestDelivery(
        pickup: LatLng(lat, lng),
        dest: dest,
        desc: 'Marketplace order #${orderId.substring(0, 8).toUpperCase()}: $itemNames. Deliver to: $address',
        category: 'marketplace',
        weight: 'Light',
        fare: _deliveryFee,
      );
      debugPrint('[Marketplace] Carpso delivery request created for order $orderId');
    } catch (e) {
      debugPrint('[Marketplace] Carpso delivery request failed (non-blocking): $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(cartProvider);
    final subtotal = ref.read(cartProvider.notifier).total;

    return PopScope(
      canPop: !_isProcessing,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isProcessing) {
          _showCancelDialog();
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text("Checkout", style: TextStyle(fontWeight: FontWeight.bold)),
          leading: IconButton(
            icon: const Icon(LucideIcons.arrowLeft),
            onPressed: _isProcessing ? null : () => context.pop(),
          ),
        ),
        body: _isSuccess
            ? _buildSuccessState()
            : _paymentPhase != _PaymentPhase.idle && _paymentPhase != _PaymentPhase.failed
                ? _buildPaymentStatus()
                : _buildCheckoutContent(items, subtotal),
      ),
    );
  }

  Widget _buildPaymentStatus() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_paymentPhase == _PaymentPhase.initiating || _paymentPhase == _PaymentPhase.awaitingPin) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: SizedBox(
                  width: 50,
                  height: 50,
                  child: CircularProgressIndicator(strokeWidth: 4, color: Theme.of(context).primaryColor),
                ),
              ),
              const SizedBox(height: 25),
              Text(
                _paymentStatusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A), fontSize: 16),
              ),
              const SizedBox(height: 10),
              Text(
                _paymentPhase == _PaymentPhase.awaitingPin
                    ? "Please check your phone for the PIN request pop-up."
                    : "Initializing secure payment channel...",
                style: const TextStyle(color: Colors.grey, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              if (_paymentPhase == _PaymentPhase.awaitingPin) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(LucideIcons.shieldCheck, size: 16, color: Color(0xFFD97706)),
                      SizedBox(width: 8),
                      Text(
                        "Do NOT share your PIN with anyone",
                        style: TextStyle(color: Color(0xFFD97706), fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    _pollTimer?.cancel();
                    setState(() {
                      _paymentPhase = _PaymentPhase.idle;
                      _isProcessing = false;
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.grey),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  child: const Text("CANCEL", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCheckoutContent(List<CartItem> items, double subtotal) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildOrderSummary(items),
                const SizedBox(height: 24),
                _buildDeliveryMethodSelector(),
                const SizedBox(height: 24),
                _buildPaymentMethodSection(),
                const SizedBox(height: 24),
                _buildOrderTotal(subtotal),
                if (_isError && _errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(LucideIcons.alertCircle, color: Colors.red, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        _buildBottomButton(),
      ],
    );
  }

  void _showCancelDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(LucideIcons.alertTriangle, color: Colors.orange),
            SizedBox(width: 10),
            Text("Payment Active"),
          ],
        ),
        content: const Text(
          "Your mobile money payment is being processed. "
          "Leaving now may disrupt payment verification.\n\n"
          "Are you sure you want to cancel?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CONTINUE PAYMENT"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _pollTimer?.cancel();
              setState(() {
                _paymentPhase = _PaymentPhase.idle;
                _isProcessing = false;
              });
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text("CANCEL PAYMENT"),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderSummary(List<CartItem> items) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Order Summary", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text("${items.length} ${items.length == 1 ? 'item' : 'items'}", style: const TextStyle(color: Colors.grey)),
            ],
          ),
          const Divider(height: 24),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text("No items in cart", style: TextStyle(color: Colors.grey))),
            )
          else
            ...items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(LucideIcons.package, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.product.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        Text("Qty: ${item.quantity}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  ),
                  Text(
                    "K ${(item.product.price * item.quantity).toStringAsFixed(2)}",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            )),
        ],
      ),
    );
  }

  Widget _buildDeliveryMethodSelector() {
    final carpsoFee = _deliveryFee;
    final pickupLabel = _pickupChurchNames.isEmpty
        ? "FREE"
        : "FREE • ${_pickupChurchNames.join(', ')}";
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Delivery Method", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _deliveryMethod = 'delivery'),
                  child: Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: _deliveryMethod == 'delivery' ? Theme.of(context).primaryColor.withValues(alpha: 0.1) : Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: _deliveryMethod == 'delivery' ? Theme.of(context).primaryColor : Colors.grey.withValues(alpha: 0.2),
                        width: _deliveryMethod == 'delivery' ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(LucideIcons.truck, color: _deliveryMethod == 'delivery' ? Theme.of(context).primaryColor : Colors.grey),
                        const SizedBox(height: 8),
                        const Text("Express Delivery", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text("K15.00", style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _deliveryMethod = 'carpso'),
                  child: Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: _deliveryMethod == 'carpso' ? Theme.of(context).primaryColor.withValues(alpha: 0.1) : Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: _deliveryMethod == 'carpso' ? Theme.of(context).primaryColor : Colors.grey.withValues(alpha: 0.2),
                        width: _deliveryMethod == 'carpso' ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(LucideIcons.car, color: _deliveryMethod == 'carpso' ? Theme.of(context).primaryColor : Colors.grey),
                        const SizedBox(height: 8),
                        const Text("Carpso Delivery", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text(
                          _deliveryMethod == 'carpso' && carpsoFee > 0
                              ? "K${carpsoFee.toStringAsFixed(2)}"
                              : "By distance",
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _deliveryMethod = 'pickup'),
                  child: Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: _deliveryMethod == 'pickup' ? Theme.of(context).primaryColor.withValues(alpha: 0.1) : Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: _deliveryMethod == 'pickup' ? Theme.of(context).primaryColor : Colors.grey.withValues(alpha: 0.2),
                        width: _deliveryMethod == 'pickup' ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(LucideIcons.mapPin, color: _deliveryMethod == 'pickup' ? Theme.of(context).primaryColor : Colors.grey),
                        const SizedBox(height: 8),
                        const Text("Pickup at Church", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text(
                          pickupLabel,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_deliveryMethod == 'pickup' && _pickupChurchNames.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(LucideIcons.church, size: 16, color: Theme.of(context).primaryColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Collect your items from: ${_pickupChurchNames.join(', ')}",
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_deliveryMethod == 'carpso') ...[
            const SizedBox(height: 16),
            TextField(
              controller: _carpsoAddressCtrl,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: "Enter delivery address (home, office, landmark...)",
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(bottom: 40),
                  child: Icon(LucideIcons.mapPin, size: 20),
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (_geocoding)
              Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "Locating address...",
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              )
            else if (_geocodeError != null)
              Row(
                children: [
                  Icon(LucideIcons.alertCircle, size: 14, color: Colors.red.shade400),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _geocodeError!,
                      style: TextStyle(color: Colors.red.shade400, fontSize: 12),
                    ),
                  ),
                ],
              )
            else if (_geocodedDest != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(LucideIcons.mapPin, size: 14, color: Colors.green.shade600),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          "Address verified • ${(_deliveryDistanceKm ?? 0).toStringAsFixed(1)} km from ${ref.read(currentTenantProvider)?.name ?? 'church'} • K${_deliveryFee.toStringAsFixed(2)}",
                          style: TextStyle(color: Colors.green.shade700, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(LucideIcons.car, size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          "Delivery price is calculated from the pickup church to your address.",
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              )
            else
              Row(
                children: [
                  Icon(LucideIcons.car, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      "A Carpso courier picks up your order from the church and delivers to your address. Price is calculated by distance.",
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildPaymentMethodSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Payment Method", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _buildPaymentOption(
            icon: LucideIcons.smartphone,
            title: "Mobile Money",
            subtitle: "MTN / Airtel / Zamtel",
            value: "mobile_money",
          ),
          const SizedBox(height: 8),
          _buildPaymentOption(
            icon: LucideIcons.creditCard,
            title: "Card",
            subtitle: "Visa / Mastercard",
            value: "card",
          ),
          if (_paymentMethod == "mobile_money") ...[
            const SizedBox(height: 20),
            const Text("Select Network", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _networks.map((n) {
                final isSelected = _selectedNetwork == n['name'];
                return GestureDetector(
                  onTap: () => setState(() => _selectedNetwork = n['name']),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? (n['color'] as Color).withValues(alpha: 0.1) : Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? n['color'] as Color : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12),
                        width: 2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(n['logo'] as String, height: 18, width: 18, fit: BoxFit.contain),
                        const SizedBox(width: 6),
                        Text(
                          n['name'] as String,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: isSelected
                                ? (n['color'] == Colors.yellow ? Colors.black87 : n['color'] as Color)
                                : const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                hintText: "Enter Mobile Money number",
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(LucideIcons.phone, size: 20),
              ),
            ),
          ],
          if (_paymentMethod == "card") ...[
            const SizedBox(height: 16),
            TextField(
              controller: _firstNameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: "First Name",
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(LucideIcons.user, size: 20),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _lastNameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: "Last Name",
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(LucideIcons.user, size: 20),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                hintText: "Email (optional)",
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(LucideIcons.mail, size: 20),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPaymentOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required String value,
  }) {
    final isSelected = _paymentMethod == value;
    return GestureDetector(
      onTap: () => setState(() => _paymentMethod = value),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).primaryColor.withValues(alpha: 0.05) : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Theme.of(context).primaryColor : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? Theme.of(context).primaryColor : Colors.grey, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? Theme.of(context).primaryColor : Theme.of(context).colorScheme.onSurface)),
                  Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
            if (isSelected)
              Icon(LucideIcons.checkCircle, color: Theme.of(context).primaryColor, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderTotal(double subtotal) {
    final fee = _platformFee;
    final delivery = _deliveryFee;
    final total = _total;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Order Total", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Divider(height: 24),
          _buildTotalRow("Subtotal", "K ${subtotal.toStringAsFixed(2)}"),
          if (fee > 0) ...[
            const SizedBox(height: 8),
            _buildTotalRow("Platform Fee", "K ${fee.toStringAsFixed(2)}"),
          ],
          if (delivery > 0) ...[
            const SizedBox(height: 8),
            _buildTotalRow(
              _deliveryMethod == 'carpso' ? 'Carpso Delivery' : 'Express Delivery',
              "K ${delivery.toStringAsFixed(2)}",
            ),
          ],
          if (_deliveryMethod == 'pickup') ...[
            const SizedBox(height: 8),
            _buildTotalRow(
              _pickupChurchNames.isEmpty
                  ? "Pickup at Church"
                  : "Pickup at ${_pickupChurchNames.join(', ')}",
              "FREE",
              isTotal: false,
            ),
          ],
          const Divider(height: 24),
          _buildTotalRow("Total", "K ${total.toStringAsFixed(2)}", isTotal: true),
        ],
      ),
    );
  }

  Widget _buildTotalRow(String label, String value, {bool isTotal = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isTotal ? Theme.of(context).colorScheme.onSurface : Colors.grey,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              fontSize: isTotal ? 16 : 14,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: isTotal ? FontWeight.w900 : FontWeight.bold,
            fontSize: isTotal ? 18 : 14,
            color: isTotal ? Theme.of(context).primaryColor : Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomButton() {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewPadding.bottom + 20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, -5))],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: _isProcessing ? null : _placeOrder,
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.secondary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: _isProcessing
              ? const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                )
              : const Text(
                  "PLACE ORDER",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
        ),
      ),
    );
  }

  Widget _buildSuccessState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.checkCircle, color: Colors.green, size: 64),
            ),
            const SizedBox(height: 24),
            const Text("Order Placed!", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(
              "Your order #${_orderReference?.substring(0, 8).toUpperCase() ?? 'N/A'} has been placed successfully.",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
            if (_deliveryMethod == 'carpso') ...[
              const SizedBox(height: 8),
              Text(
                "A Carpso courier has been requested to deliver to: ${_carpsoAddressCtrl.text.trim()}",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
            if (_deliveryMethod == 'pickup' && _pickupChurchNames.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                "Collect your items from: ${_pickupChurchNames.join(', ')}",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
            if (_orderReference != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Reference: ", style: TextStyle(color: Colors.grey, fontSize: 12)),
                    Text(
                      _orderReference!,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () => context.go('/'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text(
                  "Back to Marketplace",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
