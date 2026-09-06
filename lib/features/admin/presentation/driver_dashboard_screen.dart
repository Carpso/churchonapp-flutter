import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import 'package:church_on_app/features/transport/presentation/driver_portal_screen.dart';
import 'package:church_on_app/features/transport/presentation/driver_earnings_screen.dart';

class DriverDashboardScreen extends ConsumerStatefulWidget {
  const DriverDashboardScreen({super.key});

  @override
  ConsumerState<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends ConsumerState<DriverDashboardScreen> {
  bool _isLoading = true;
  String? _error;
  bool _isOnline = false;
  int _totalRides = 0;
  int _totalDeliveries = 0;
  double _totalEarnings = 0;
  double _monthEarnings = 0;
  double _rating = 0;
  int _pendingRequests = 0;

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

    final now = DateTime.now();
    final firstOfMonth = DateTime(now.year, now.month, 1);

    try {
      // NOTE: `avg_rating` is not a profiles column — ratings come from the
      // get_user_avg_rating() RPC. Selecting a missing column made the whole
      // dashboard fail to load.
      final profileRes = await Supabase.instance.client
          .from('profiles')
          .select('driver_status')
          .eq('id', userId)
          .maybeSingle();

      double rating = 0;
      try {
        rating = ((await Supabase.instance.client
                    .rpc('get_user_avg_rating', params: {'target_user_id': userId})) as num?)
                ?.toDouble() ??
            0;
      } catch (e) {
        debugPrint('DriverDashboard: rating lookup failed (non-fatal): $e');
      }

      // `ride_bookings` / `deliveries.fee` do not exist. Carpso rides live in
      // ride_requests and deliveries in delivery_requests, both keyed by
      // driver_id, with negotiated_fare ?? offered_fare as the fare.
      final ridesRes = await Supabase.instance.client
          .from('ride_requests')
          .select('id, offered_fare, negotiated_fare, status, created_at')
          .eq('driver_id', userId);

      final deliveriesRes = await Supabase.instance.client
          .from('delivery_requests')
          .select('id, offered_fare, negotiated_fare, status, created_at')
          .eq('driver_id', userId);

      final pendingRides = await Supabase.instance.client
          .from('ride_requests')
          .select('id')
          .eq('driver_id', userId)
          .eq('status', 'pending');

      final rides = List<Map<String, dynamic>>.from(ridesRes);
      final deliveries = List<Map<String, dynamic>>.from(deliveriesRes);

      final completedRides = rides.where((r) => r['status'] == 'completed').length;
      final completedDeliveries = deliveries.where((d) => d['status'] == 'delivered').length;

      double fareOf(Map<String, dynamic> row) =>
          ((row['negotiated_fare'] ?? row['offered_fare'] ?? row['fare'] ?? row['fee'])
                  as num?)
              ?.toDouble() ??
          0;

      double totalEarn = 0, monthEarn = 0;
      for (final r in rides) {
        final fare = fareOf(r);
        totalEarn += fare;
        final created = r['created_at']?.toString() ?? '';
        final dt = DateTime.tryParse(created);
        if (dt != null && dt.isAfter(firstOfMonth)) monthEarn += fare;
      }
      for (final d in deliveries) {
        final fee = fareOf(d);
        totalEarn += fee;
        final created = d['created_at']?.toString() ?? '';
        final dt = DateTime.tryParse(created);
        if (dt != null && dt.isAfter(firstOfMonth)) monthEarn += fee;
      }

      if (mounted) {
        setState(() {
          _isOnline = profileRes?['driver_status'] == 'online';
          _rating = rating;
          _totalRides = completedRides;
          _totalDeliveries = completedDeliveries;
          _totalEarnings = totalEarn;
          _monthEarnings = monthEarn;
          _pendingRequests = (pendingRides as List).length;
          _isLoading = false; _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _error = e.toString(); });
    }
  }

  Future<void> _toggleOnline() async {
    final newStatus = !_isOnline;
    try {
      await Supabase.instance.client.from('profiles')
          .update({'driver_status': newStatus ? 'online' : 'offline'})
          .eq('id', ref.read(profileProvider).value?.id ?? '');
      setState(() => _isOnline = newStatus);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Driver Dashboard", style: TextStyle(fontWeight: FontWeight.bold)),
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
                  const SizedBox(height: 30), _buildEarningsSection(theme),
                  const SizedBox(height: 30),
                  Text("Quick Actions", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                  const SizedBox(height: 15),
                  _actionBtn(theme, LucideIcons.map, "View Rides", "Browse available ride requests near you", theme.primaryColor, () => Navigator.push(context, MaterialPageRoute(builder: (context) => const DriverPortalScreen()))),
                  _actionBtn(theme, LucideIcons.package, "Deliveries", "Available cargo and package deliveries", Colors.orange, () => Navigator.push(context, MaterialPageRoute(builder: (context) => const DriverPortalScreen()))),
                  _actionBtn(theme, LucideIcons.barChart3, "Earnings Report", "Detailed payout and earnings history", Colors.green, () => Navigator.push(context, MaterialPageRoute(builder: (context) => const DriverEarningsScreen()))),
                ]),
              ),
            ),
    );
  }

  Widget _buildShimmer() => SingleChildScrollView(
    padding: const EdgeInsets.all(25),
    child: Column(children: [
      ShimmerLoader.rectangular(height: 150, width: double.infinity),
      const SizedBox(height: 20), Row(children: [Expanded(child: ShimmerLoader.rectangular(height: 100)), const SizedBox(width: 12), Expanded(child: ShimmerLoader.rectangular(height: 100))]),
      const SizedBox(height: 12), Row(children: [Expanded(child: ShimmerLoader.rectangular(height: 100)), const SizedBox(width: 12), Expanded(child: ShimmerLoader.rectangular(height: 100))]),
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
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
            child: const Icon(LucideIcons.truck, color: Colors.black, size: 28)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("Driver Dashboard", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 20)),
            Text("${_rating > 0 ? '${_rating.toStringAsFixed(1)} ★' : 'No ratings yet'} • $_totalRides rides", style: TextStyle(color: Colors.black.withValues(alpha: 0.55), fontSize: 12)),
          ])),
          GestureDetector(
            onTap: _toggleOnline,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _isOnline ? Colors.greenAccent : Colors.black.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(_isOnline ? "ONLINE" : "OFFLINE", style: TextStyle(
                color: _isOnline ? Colors.black87 : Colors.black87, fontWeight: FontWeight.bold, fontSize: 11)),
            ),
          ),
        ]),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _bannerStat(currency.format(_monthEarnings), "This Month"),
          _bannerStat("$_totalRides", "Rides"),
          _bannerStat("$_pendingRequests", "Pending"),
        ]),
      ]),
    );
  }

  Widget _bannerStat(String value, String label) => Column(children: [
    Text(value, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 18)),
    Text(label, style: TextStyle(color: Colors.black.withValues(alpha: 0.55), fontSize: 11)),
  ]);

  Widget _buildStatsGrid(ThemeData theme) => GridView.count(
    physics: const NeverScrollableScrollPhysics(),
    crossAxisCount: 2, mainAxisSpacing: 15, crossAxisSpacing: 15, childAspectRatio: 1.2,
    children: [
      _statCard("Total Rides", "$_totalRides", LucideIcons.car, theme.primaryColor.withValues(alpha: 0.7)),
      _statCard("Deliveries", "$_totalDeliveries", LucideIcons.package, Colors.orange),
      _statCard("Rating", _rating > 0 ? _rating.toStringAsFixed(1) : "--", LucideIcons.star, Colors.amber),
      _statCard("Pending Requests", "$_pendingRequests", LucideIcons.clock, Colors.red),
    ],
  );

  Widget _buildEarningsSection(ThemeData theme) {
    final currency = NumberFormat.currency(symbol: 'K ', decimalDigits: 0);
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("Earnings Overview", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          Column(children: [Icon(LucideIcons.wallet, color: Colors.green), const SizedBox(height: 6),
            Text(currency.format(_totalEarnings), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
            Text("Total Earned", style: TextStyle(color: Colors.grey.shade500, fontSize: 11))]),
          Column(children: [Icon(LucideIcons.calendar, color: theme.primaryColor), const SizedBox(height: 6),
            Text(currency.format(_monthEarnings), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
            Text("This Month", style: TextStyle(color: Colors.grey.shade500, fontSize: 11))]),
        ]),
      ]),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12)]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, color: color, size: 20), const Spacer(),
      Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
      Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
    ]),
  );

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
}
