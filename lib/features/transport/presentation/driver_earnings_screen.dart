import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/widgets/premium_toast.dart';
import 'package:church_on_app/features/finance/presentation/lipila_payment_gateway.dart';

class DriverEarningsScreen extends ConsumerStatefulWidget {
  const DriverEarningsScreen({super.key});

  @override
  ConsumerState<DriverEarningsScreen> createState() => _DriverEarningsScreenState();
}

class _DriverEarningsScreenState extends ConsumerState<DriverEarningsScreen> {
  bool _isLoading = true;
  double _totalEarnings = 0.0;
  double _weeklyEarnings = 0.0;
  int _completedRidesCount = 0;
  List<Map<String, dynamic>> _earningsHistory = [];

  @override
  void initState() {
    super.initState();
    _loadEarnings();
  }

  Future<void> _loadEarnings() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);
    try {
      final rides = await Supabase.instance.client
          .from('ride_requests')
          .select('id, offered_fare, fare, created_at, status')
          .eq('driver_id', user.id)
          .eq('status', 'completed')
          .order('created_at', ascending: false);

      final now = DateTime.now();
      final startOfWeek = now.subtract(Duration(days: now.weekday - 1));

      double total = 0.0;
      double weekly = 0.0;
      int completed = 0;

      for (var r in rides) {
        final fare = (r['offered_fare'] ?? r['fare'] ?? 0.0).toDouble();
        final netFare = fare * 0.90; // 90% goes to driver
        total += netFare;
        completed++;

        final date = DateTime.tryParse(r['created_at'] ?? '');
        if (date != null && date.isAfter(startOfWeek)) {
          weekly += netFare;
        }
      }

      if (mounted) {
        setState(() {
          _totalEarnings = total;
          _weeklyEarnings = weekly;
          _completedRidesCount = completed;
          _earningsHistory = List<Map<String, dynamic>>.from(rides);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading driver earnings: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _requestCashout() {
    if (_totalEarnings <= 0) {
      PremiumToast.showError(context, 'No balance available for cashout');
      return;
    }

    final user = Supabase.instance.client.auth.currentUser;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => LipilaPaymentGateway(
        amount: _totalEarnings,
        description: 'Driver Cashout Payout',
        category: 'payout',
        recipientName: user?.userMetadata?['full_name'] ?? 'Driver',
        recipientAccount: user?.email ?? 'Mobile Money Wallet',
        paymentReason: 'Driver Earnings Settlement',
        onComplete: (success, txId) {
          Navigator.pop(context);
          if (success) {
            PremiumToast.showSuccess(context, 'Cashout request submitted successfully!');
            _loadEarnings();
          } else {
            PremiumToast.showError(context, 'Cashout failed. Please try again.');
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Driver Earnings',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Summary Card
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [theme.primaryColor, theme.primaryColor.withValues(alpha: 0.8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: theme.primaryColor.withValues(alpha: 0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AVAILABLE BALANCE (NET 90%)',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'K${_totalEarnings.toStringAsFixed(2)}',
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'This Week',
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
                                ),
                                Text(
                                  'K${_weeklyEarnings.toStringAsFixed(2)}',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Completed Trips',
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
                                ),
                                Text(
                                  '$_completedRidesCount rides',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: _requestCashout,
                        icon: const Icon(LucideIcons.arrowUpRight, size: 18),
                        label: const Text('CASHOUT TO MOBILE MONEY', style: TextStyle(fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: theme.primaryColor,
                          minimumSize: const Size(double.infinity, 48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 30),
                Text(
                  'COMPLETED TRIPS HISTORY',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: theme.disabledColor,
                  ),
                ),
                const SizedBox(height: 12),

                if (_earningsHistory.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(LucideIcons.coins, size: 48, color: theme.disabledColor),
                          const SizedBox(height: 12),
                          Text('No completed trips recorded yet', style: TextStyle(color: theme.disabledColor)),
                        ],
                      ),
                    ),
                  )
                else
                  ..._earningsHistory.map((ride) {
                    final fare = (ride['offered_fare'] ?? ride['fare'] ?? 0.0).toDouble();
                    final net = fare * 0.90;
                    final date = ride['created_at'] != null ? ride['created_at'].toString().split('T')[0] : 'N/A';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.green.withValues(alpha: 0.15),
                          child: const Icon(LucideIcons.check, color: Colors.green, size: 18),
                        ),
                        title: Text('Trip Fare: K${fare.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Date: $date • Platform Fee: K${(fare * 0.10).toStringAsFixed(2)}'),
                        trailing: Text(
                          '+K${net.toStringAsFixed(2)}',
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w800,
                            color: Colors.green,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}
