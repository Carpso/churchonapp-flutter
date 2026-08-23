import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import 'package:church_on_app/features/admin/data/organization_service.dart';
import 'package:church_on_app/features/transport/presentation/ride_request_screen.dart';
import 'package:church_on_app/features/transport/presentation/saved_places_sheet.dart';

class RiderDashboardScreen extends ConsumerStatefulWidget {
  const RiderDashboardScreen({super.key});

  @override
  ConsumerState<RiderDashboardScreen> createState() => _RiderDashboardScreenState();
}

class _RiderDashboardScreenState extends ConsumerState<RiderDashboardScreen> {
  bool _isLoading = true;
  String? _error;
  int _totalTrips = 0;
  double _totalSpent = 0;
  double _totalDistance = 0;
  Map<String, dynamic>? _activeRide;
  List<Map<String, dynamic>> _recentTrips = [];

  @override
  void initState() {
    super.initState();
    ref.listen(profileProvider, (prev, next) {
      if (next.hasValue && next.value != null) _loadDashboard();
      if (next.hasError) {
        setState(() {
          _isLoading = false;
          _error = next.error.toString();
        });
      }
    });
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    setState(() => _isLoading = true);
    final profile = ref.read(profileProvider).value;
    if (profile == null) {
      setState(() => _isLoading = false);
      return;
    }
    final userId = profile.id;

    try {
      final summary = await ref.read(organizationServiceProvider).getRiderSummary(userId);
      _totalTrips = (summary['completed_trips'] as num?)?.toInt() ?? 0;
      _totalSpent = (summary['total_fare'] as num?)?.toDouble() ?? 0;
      _totalDistance = (summary['total_distance_km'] as num?)?.toDouble() ?? 0;
      _activeRide = summary['active_ride'] is Map
          ? Map<String, dynamic>.from(summary['active_ride'] as Map)
          : null;

      final ridesRes = await Supabase.instance.client
          .from('ride_bookings')
          .select('id, pickup_location, dropoff_location, fare, distance_km, status, created_at')
          .eq('rider_id', userId)
          .order('created_at', ascending: false)
          .limit(20);

      final trips = List<Map<String, dynamic>>.from(ridesRes);

      if (mounted) {
        setState(() {
          _recentTrips = trips.take(10).toList();
          _isLoading = false; _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Rider Dashboard", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor, foregroundColor: Colors.black87, elevation: 0,
        actions: [IconButton(icon: const Icon(LucideIcons.refreshCw), onPressed: _isLoading ? null : _loadDashboard)],
      ),
      body: _isLoading ? _buildShimmer() : _error != null ? _buildError()
          : RefreshIndicator(
              onRefresh: _loadDashboard,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(25),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _buildHeader(theme),
                  const SizedBox(height: 25), _buildStatsGrid(theme),
                  const SizedBox(height: 30),
                  Text("Quick Actions", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                  const SizedBox(height: 15),
                  _actionBtn(theme, LucideIcons.map, "Book a Ride", "Request a Carpso Ride", theme.primaryColor, () => Navigator.push(context, MaterialPageRoute(builder: (context) => const RideRequestScreen()))),
                  _actionBtn(theme, LucideIcons.bookmark, "Saved Places", "Quick-select frequent locations", Colors.teal, () async {
                    final place = await showSavedPlacesPicker(context);
                    if (!mounted) return;
                    if (place != null) {
                      // ignore: use_build_context_synchronously
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Selected: ${place.address}')),
                      );
                    }
                  }),
                  _actionBtn(theme, LucideIcons.navigation, "Active Ride", _activeRide != null ? "Track your current trip" : "No active ride — book one first", Colors.amber, () {
                    final active = _activeRide;
                    if (active == null) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No active ride — book one first")));
                      return;
                    }
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const RideRequestScreen()),
                    );
                  }),
                  const SizedBox(height: 35),
                  Text("Recent Trips", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                  const SizedBox(height: 15),
                  ..._recentTrips.isNotEmpty ? _recentTrips.map((t) => _tripRow(theme, t)) : [_emptyCard(theme, "No trips yet. Book a Carpso Ride!")],
                ]),
              ),
            ),
    );
  }

  Widget _buildShimmer() => SingleChildScrollView(
    padding: const EdgeInsets.all(25),
    child: Column(children: [
      ShimmerLoader.rectangular(height: 120, width: double.infinity),
      const SizedBox(height: 20), Row(children: [Expanded(child: ShimmerLoader.rectangular(height: 90)), const SizedBox(width: 12), Expanded(child: ShimmerLoader.rectangular(height: 90))]),
      const SizedBox(height: 25), ShimmerLoader.rectangular(height: 18, width: 100),
      const SizedBox(height: 15), ...List.generate(3, (_) => Padding(padding: const EdgeInsets.only(bottom: 10), child: ShimmerLoader.rectangular(height: 65))),
    ]),
  );

  Widget _buildError() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(LucideIcons.wifiOff, size: 48, color: Colors.grey.shade300),
    const SizedBox(height: 12), Text("Could not load", style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
    const SizedBox(height: 20), ElevatedButton.icon(onPressed: _loadDashboard, icon: const Icon(LucideIcons.refreshCw, size: 16), label: const Text("Retry")),
  ]));

  Widget _buildHeader(ThemeData theme) {
    final currency = NumberFormat.currency(symbol: 'K ', decimalDigits: 0);
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [theme.primaryColor, theme.primaryColor.withValues(alpha: 0.7)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: theme.primaryColor.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
          child: const Icon(LucideIcons.map, color: Colors.black, size: 28)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text("Rider Dashboard", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 20)),
          Text("$_totalTrips trips • ${currency.format(_totalSpent)} spent", style: TextStyle(color: Colors.black.withValues(alpha: 0.55), fontSize: 12)),
        ])),
      ]),
    );
  }

  Widget _buildStatsGrid(ThemeData theme) {
    final currency = NumberFormat.currency(symbol: 'K ', decimalDigits: 0);
    return GridView.count(
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2, mainAxisSpacing: 15, crossAxisSpacing: 15, childAspectRatio: 1.2,
      children: [
        _statCard("Total Trips", "$_totalTrips", LucideIcons.car, theme.primaryColor.withValues(alpha: 0.7)),
        _statCard("Total Spent", currency.format(_totalSpent), LucideIcons.wallet, Colors.green),
        _statCard("Distance", _totalDistance > 0 ? '${_totalDistance.toStringAsFixed(0)} km' : '--', LucideIcons.mapPin, Colors.amber),
        _statCard(_activeRide != null ? "Active Ride" : "Rides This Month", _activeRide != null ? (NumberFormat.currency(symbol: 'K ', decimalDigits: 0).format((_activeRide!['fare'] as num?)?.toDouble() ?? 0)) : '$_totalTrips', _activeRide != null ? LucideIcons.navigation : LucideIcons.clock, _activeRide != null ? Colors.orange : Colors.red),
      ],
    );
  }

  Widget _tripRow(ThemeData theme, Map<String, dynamic> trip) {
    final pickup = trip['pickup_location'] as String? ?? 'Unknown';
    final dropoff = trip['dropoff_location'] as String? ?? 'Unknown';
    final fare = (trip['fare'] as num?)?.toDouble() ?? 0;
    final status = trip['status'] as String? ?? 'unknown';
    return Container(
      margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: theme.primaryColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
          child: Icon(LucideIcons.mapPin, color: theme.primaryColor, size: 16)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("$pickup → $dropoff", style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          Text("K ${NumberFormat.decimalPattern().format(fare)} • $status", style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
        ])),
      ]),
    );
  }

  Widget _actionBtn(ThemeData theme, IconData icon, String title, String subtitle, Color color, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)]),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: color, size: 22)),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
        ])),
        Icon(LucideIcons.chevronRight, size: 18, color: Colors.grey.shade300),
      ]),
    ),
  );

  Widget _statCard(String label, String value, IconData icon, Color color) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12)]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, color: color, size: 20), const Spacer(),
      Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
      Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
    ]),
  );

  Widget _emptyCard(ThemeData theme, String msg) => Container(
    width: double.infinity, padding: const EdgeInsets.all(25),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
    child: Center(child: Text(msg, style: TextStyle(color: Colors.grey.shade400))),
  );
}
