import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:church_on_app/features/transport/data/ride_history_service.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import 'package:church_on_app/core/config/fee_config.dart';

class RideHistoryScreen extends ConsumerStatefulWidget {
  const RideHistoryScreen({super.key});

  @override
  ConsumerState<RideHistoryScreen> createState() => _RideHistoryScreenState();
}

class _RideHistoryScreenState extends ConsumerState<RideHistoryScreen> {
  String _filterStatus = 'all'; // 'all', 'completed', 'cancelled', 'in_progress'
  List<Map<String, dynamic>> _rides = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(rideHistoryServiceProvider);
    });
    _loadRideHistory();
  }

  Future<void> _loadRideHistory() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);
    try {
      final data = await Supabase.instance.client
          .from('ride_requests')
          .select('*')
          .or('rider_id.eq.${user.id},driver_id.eq.${user.id}')
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _rides = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading ride history: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredRides {
    if (_filterStatus == 'all') return _rides;
    return _rides.where((r) => r['status'] == _filterStatus).toList();
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'accepted':
      case 'in_progress':
        return Theme.of(context).primaryColor;
      case 'pending':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  String _formatStatus(String status) {
    return status.replaceAll('_', ' ').toUpperCase();
  }

  void _showReceiptSheet(Map<String, dynamic> ride) {
    final fare = (ride['offered_fare'] ?? ride['fare'] ?? 0.0).toDouble();
    final cut = ref.read(feeConfigProvider).value?.businessCutPercent ?? 0.10;
    final pickup = ride['pickup_address'] ?? 'Pickup Point';
    final dest = ride['destination_address'] ?? 'Destination';
    final date = ride['created_at'] != null
        ? DateFormat('MMM d, yyyy • h:mm a').format(DateTime.parse(ride['created_at']))
        : 'N/A';
    final status = ride['status'] ?? 'completed';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Ride Receipt',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(status).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _formatStatus(status),
                    style: TextStyle(
                      color: _statusColor(status),
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              date,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const Divider(height: 32),

            // Route details
            Row(
              children: [
                const Icon(LucideIcons.circleDot, size: 16, color: Colors.green),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    pickup,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ],
            ),
            Container(
              margin: const EdgeInsets.only(left: 7),
              height: 20,
              width: 2,
              color: Colors.grey[300],
            ),
            Row(
              children: [
                const Icon(LucideIcons.mapPin, size: 16, color: Colors.red),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    dest,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ],
            ),

            const Divider(height: 32),

            // Fare breakdown
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Base Fare', style: TextStyle(color: Colors.grey)),
                Text('K${fare.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Platform Fee (${(cut * 100).toStringAsFixed(0)}%)', style: const TextStyle(color: Colors.grey)),
                Text('K${(fare * cut).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total Paid', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.bold)),
                Text(
                  'K${fare.toStringAsFixed(2)}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('CLOSE RECEIPT', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filteredRides;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Carpso Ride History',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          // Filter Chips
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _buildFilterChip('all', 'All Rides'),
                _buildFilterChip('completed', 'Completed'),
                _buildFilterChip('in_progress', 'Active'),
                _buildFilterChip('cancelled', 'Cancelled'),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // List
          Expanded(
            child: _isLoading
                ? ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: 4,
                    itemBuilder: (context, index) => const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: ShimmerLoader.rectangular(height: 96),
                    ),
                  )
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(LucideIcons.car, size: 48, color: theme.disabledColor),
                            const SizedBox(height: 12),
                            Text('No rides found', style: TextStyle(color: theme.disabledColor)),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadRideHistory,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final ride = filtered[index];
                            final status = ride['status'] ?? 'pending';
                            final fare = (ride['offered_fare'] ?? ride['fare'] ?? 0.0).toDouble();
                            final date = ride['created_at'] != null
                                ? DateFormat('MMM d, h:mm a').format(DateTime.parse(ride['created_at']))
                                : 'N/A';

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                leading: CircleAvatar(
                                  backgroundColor: _statusColor(status).withValues(alpha: 0.15),
                                  child: Icon(LucideIcons.car, color: _statusColor(status), size: 20),
                                ),
                                title: Text(
                                  'K${fare.toStringAsFixed(2)}',
                                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                subtitle: Text(
                                  date,
                                  style: TextStyle(fontSize: 12, color: theme.disabledColor),
                                ),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _statusColor(status).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _formatStatus(status),
                                    style: TextStyle(
                                      color: _statusColor(status),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                onTap: () => _showReceiptSheet(ride),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    final isSelected = _filterStatus == value;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) {
          setState(() => _filterStatus = value);
        },
        selectedColor: theme.primaryColor.withValues(alpha: 0.2),
        checkmarkColor: theme.primaryColor,
      ),
    );
  }
}
