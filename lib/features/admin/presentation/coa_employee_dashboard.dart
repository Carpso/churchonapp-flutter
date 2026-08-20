import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/profile_provider.dart';
import '../../../core/widgets/app_error_view.dart';
import '../../../core/services/coa_payment_service.dart';
import '../../../core/services/plan_service.dart';
import '../../../core/config/fee_config.dart';
import '../../../core/config/remote_config.dart';
import '../data/audit_service.dart';
import '../data/organization_service.dart';
import 'resolution_hub_screen.dart';

class CoaEmployeeDashboard extends ConsumerStatefulWidget {
  const CoaEmployeeDashboard({super.key});

  @override
  ConsumerState<CoaEmployeeDashboard> createState() => _CoaEmployeeDashboardState();
}

class _CoaEmployeeDashboardState extends ConsumerState<CoaEmployeeDashboard> {
  int _activeTenantsCount = 0;
  int _totalUsersCount = 0;
  double _totalPlatformRevenue = 0.0;
  List<Map<String, dynamic>> _pendingChurches = [];
  List<Map<String, dynamic>> _pendingPayments = [];
  List<CoaPayment> _pendingCoaPayments = [];
  bool _statsLoading = true;
  late final AuditService _audit;

  @override
  void initState() {
    super.initState();
    _audit = AuditService(Supabase.instance.client);
    _loadStats();
  }

  Future<void> _refresh() async {
    await _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final client = Supabase.instance.client;

      final activeChurchesRes = await client.from('churches').select('id').eq('is_verified', true);

      List<Map<String, dynamic>> pendingList = [];
      List<Map<String, dynamic>> paymentsList = [];
      List<CoaPayment> coaPayments = [];
      int usersCount = 0;
      double platformRevenue = 0.0;

      try {
        final pendingRes = await client.from('churches').select('id, name, email, contact_phone, location, is_verified, subscription_ends_at, logo_url').eq('is_verified', false);
        pendingList = List<Map<String, dynamic>>.from(pendingRes);
      } catch (e) {
        debugPrint("COA stats: pending churches query failed: $e");
      }

      try {
        final paymentsRes = await client.from('churches').select('id, name, email, contact_phone, location, payment_reference, payment_amount, is_verified').not('payment_reference', 'is', null);
        paymentsList = List<Map<String, dynamic>>.from(paymentsRes)
            .where((c) => (c['payment_reference'] as String?)?.isNotEmpty == true)
            .toList();
      } catch (e) {
        debugPrint("COA stats: payment churches query failed: $e");
      }

      try {
        final profilesRes = await client.from('profiles').select('id');
        usersCount = profilesRes.length;
      } catch (e) {
        debugPrint("COA stats: profiles query failed: $e");
      }

      try {
        final revenue = await ref
            .read(organizationServiceProvider)
            .getPlatformRevenueSummary();
        platformRevenue = (revenue['total_revenue'] as num?)?.toDouble() ?? 0.0;
      } catch (e) {
        debugPrint("COA stats: platform revenue RPC failed: $e");
      }

      try {
        coaPayments = await ref.read(coaPaymentServiceProvider).getPendingPayments();
      } catch (e) {
        debugPrint("COA stats: coa payments query failed: $e");
      }

      if (mounted) {
        setState(() {
          _activeTenantsCount = activeChurchesRes.length;
          _totalUsersCount = usersCount;
          _totalPlatformRevenue = platformRevenue;
          _pendingChurches = pendingList;
          _pendingPayments = paymentsList;
          _pendingCoaPayments = coaPayments;
          _statsLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading COA employee stats: $e");
      if (mounted) setState(() => _statsLoading = false);
    }
  }

  Future<void> _approveChurch(Map<String, dynamic> church) async {
    try {
      final client = Supabase.instance.client;
      // P3-39: Extend subscription from current end date (or now if expired)
      final currentEnds = church['subscription_ends_at'] != null
          ? DateTime.tryParse(church['subscription_ends_at'].toString())
          : null;
      final baseDate = (currentEnds != null && currentEnds.isAfter(DateTime.now()))
          ? currentEnds
          : DateTime.now();
      await client.from('churches').update({
        'is_verified': true,
        'subscription_ends_at': baseDate
            .add(Duration(days: widgetRemoteConfig(ref).trialDurationDays))
            .toIso8601String(),
        'plan': 'silver',
      }).eq('id', church['id']);

      final pastorData = church['pastor_name']?.toString() ?? '';
      if (pastorData.contains(':')) {
        final parts = pastorData.split(':');
        final pastorId = parts[0];
        final role = parts[1];
        await client.from('profiles').update({'tenant_id': church['id'], 'role': role}).eq('id', pastorId);

        // Notify the pastor about church approval
        try {
          await client.functions.invoke('push-notifications', body: {
            'userId': pastorId,
            'title': 'Church Approved!',
            'body': '${church['name']} has been approved and is now live on Church On App!',
            'data': {
              'type': 'church_approved',
              'reference_id': church['id'],
              'channel_id': 'coa_announcements',
            },
          });
        } catch (e) {
          debugPrint('[COA Employee] Church approval notification failed: $e');
        }
      }

      await _audit.logChurchAction(action: 'approve', churchId: church['id'], churchName: church['name']?.toString());

      if (mounted) {
        showAppSnackBar(
          context,
          "Approved ${church['name']}!",
          status: AppStatus.success,
        );
        _loadStats();
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          AppErrorView.friendlyMessage(e),
          status: AppStatus.error,
        );
      }
    }
  }

  Future<void> _rejectChurch(Map<String, dynamic> church) async {
    try {
      final client = Supabase.instance.client;
      await client.from('churches').delete().eq('id', church['id']);
      await _audit.logChurchAction(action: 'reject', churchId: church['id'], churchName: church['name']?.toString());
      if (mounted) {
        showAppSnackBar(
          context,
          "Rejected ${church['name']}",
          status: AppStatus.error,
        );
        _loadStats();
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          AppErrorView.friendlyMessage(e),
          status: AppStatus.error,
        );
      }
    }
  }

  Future<void> _approvePayment(Map<String, dynamic> church) async {
    try {
      final client = Supabase.instance.client;
      final rc = widgetRemoteConfig(ref);
      var platinumUntil = DateTime.now().add(Duration(days: rc.platinumPromoDays));
      if (platinumUntil.isAfter(PlanLimits.promotionEndDate)) {
        platinumUntil = PlanLimits.promotionEndDate;
      }
      // P3-39: Extend subscription from current end date (or now if expired)
      final currentEnds = church['subscription_ends_at'] != null
          ? DateTime.tryParse(church['subscription_ends_at'].toString())
          : null;
      final baseDate = (currentEnds != null && currentEnds.isAfter(DateTime.now()))
          ? currentEnds
          : DateTime.now();
      await client.from('churches').update({
        'onboarding_fee_paid': true,
        'onboarding_fee_paid_at': DateTime.now().toIso8601String(),
        'promotion_platinum_until': platinumUntil.toIso8601String(),
        'subscription_ends_at': baseDate
            .add(Duration(days: widgetRemoteConfig(ref).renewalDurationDays))
            .toIso8601String(),
        'payment_reference': null,
        'payment_submitted_at': null,
        'is_verified': true,
        'plan': 'platinum',
      }).eq('id', church['id']);
      await _audit.logPaymentAction(action: 'approve_payment', paymentId: church['id'], churchName: church['name']?.toString());
      if (mounted) {
        showAppSnackBar(
          context,
          "Approved payment for ${church['name']}",
          status: AppStatus.success,
        );
        _loadStats();
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          AppErrorView.friendlyMessage(e),
          status: AppStatus.error,
        );
      }
    }
  }

  Future<void> _rejectPayment(Map<String, dynamic> church) async {
    try {
      final client = Supabase.instance.client;
      await client.from('churches').update({'payment_reference': null, 'payment_submitted_at': null}).eq('id', church['id']);
      await _audit.logPaymentAction(action: 'reject_payment', paymentId: church['id'], churchName: church['name']?.toString());
      if (mounted) {
        showAppSnackBar(
          context,
          "Rejected payment for ${church['name']}",
          status: AppStatus.error,
        );
        _loadStats();
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          AppErrorView.friendlyMessage(e),
          status: AppStatus.error,
        );
      }
    }
  }

  Future<void> _approveCoaPayment(CoaPayment payment, UserProfile profile) async {
    try {
      final ok = await ref.read(coaPaymentServiceProvider).approvePayment(payment.id, profile.id);
      if (ok && mounted) {
        showAppSnackBar(
          context,
          "Approved ${payment.serviceType} payment",
          status: AppStatus.success,
        );
        _loadStats();
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          AppErrorView.friendlyMessage(e),
          status: AppStatus.error,
        );
      }
    }
  }

  Future<void> _rejectCoaPayment(CoaPayment payment) async {
    try {
      final ok = await ref.read(coaPaymentServiceProvider).rejectPayment(payment.id);
      if (ok && mounted) {
        showAppSnackBar(
          context,
          "Rejected ${payment.serviceType} payment",
          status: AppStatus.warning,
        );
        _loadStats();
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          AppErrorView.friendlyMessage(e),
          status: AppStatus.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);
    return profileAsync.when(
      data: (profile) {
        if (profile == null || !profile.isEmployee) {
          return const Scaffold(body: Center(child: Text("Unauthorized")));
        }
        return _buildScreen(profile);
      },
      loading: () => const Scaffold(body: Center(child: _CoaShimmerPlaceholder())),
      error: (e, st) => Scaffold(body: AppErrorView(error: e, onRetry: _loadStats)),
    );
  }

  Widget _buildWelcomeHeader(ThemeData theme, UserProfile profile) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.primary.withValues(alpha: 0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: theme.colorScheme.onPrimary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: CircleAvatar(
              radius: 28,
              backgroundColor: theme.colorScheme.onPrimary.withValues(alpha: 0.05),
              backgroundImage: profile.avatarUrl != null ? CachedNetworkImageProvider(profile.avatarUrl!) : null,
              child: profile.avatarUrl == null
                  ? Icon(LucideIcons.user, size: 24, color: theme.colorScheme.onPrimary)
                  : null,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Welcome back,",
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  profile.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.shieldCheck, color: Colors.amber, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        profile.role.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

Widget _buildScreen(UserProfile profile) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("COA Employee Console", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            Text(
              "COA TEAM",
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(LucideIcons.refreshCw), onPressed: _statsLoading ? null : _loadStats),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(25),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildWelcomeHeader(theme, profile),
              const SizedBox(height: 25),
              _buildStatCards(),
              const SizedBox(height: 35),
              const Text("Pending Church Registrations", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 15),
              _buildPendingApprovals(),
              const SizedBox(height: 35),
              const Text("Pending Subscription Payments", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 15),
              _buildPendingPayments(),
              const SizedBox(height: 35),
              const Text("Pending COA Service Payments", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 15),
              _buildPendingCoaPayments(profile),
              const SizedBox(height: 35),
              const Text("Platform Actions", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 15),
              _buildAction(LucideIcons.userCheck, "Role Approvals", "Approve or elevate user roles", theme.primaryColor, () {
                context.push('/role-approvals');
              }),
              _buildAction(LucideIcons.mapPin, "Expansion Leads", "Churches requesting to be added next", Colors.amber, () {
                context.push('/expansion-leads');
              }),
              _buildAction(LucideIcons.penTool, "Writer Approvals", "Approve writer applications", theme.primaryColor, () {
                context.push('/writer-approvals');
              }),
              _buildAction(LucideIcons.car, "Carpso Driver Approvals", "Approve driver applications for Carpso Ride", theme.primaryColor, () {
                context.push('/carpso-approval');
              }),
              _buildAction(LucideIcons.scrollText, "Audit Log", "View admin actions and changes", Colors.orange, () => _showAuditLog()),
              _buildAction(LucideIcons.lifeBuoy, "Resolution Hub", "Respond to tickets, disputes & error reports", Colors.redAccent, () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ResolutionHubScreen()));
              }),
const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCards() {
    final theme = Theme.of(context);
    if (_statsLoading) {
      return Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: const _CoaShimmerPlaceholder()));
    }
    return Column(
      children: [
        Row(
          children: [
            _buildStatItem("Active Tenants", _activeTenantsCount.toString(), LucideIcons.building, theme.primaryColor),
            const SizedBox(width: 15),
            _buildStatItem("Total Users", _totalUsersCount.toString(), LucideIcons.users, Colors.green),
          ],
        ),
        const SizedBox(height: 16),
        _buildFeeBreakdownCard(theme),
      ],
    );
  }

  Widget _buildFeeBreakdownCard(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.dividerColor),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "PLATFORM REVENUE BREAKDOWN",
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(LucideIcons.banknote, color: theme.colorScheme.primary, size: 28),
              const SizedBox(width: 12),
              Text("K ${_totalPlatformRevenue.toStringAsFixed(2)}", style: TextStyle(color: theme.colorScheme.primary, fontSize: 24, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: theme.dividerColor, height: 1),
          const SizedBox(height: 12),
          Consumer(
            builder: (context, ref, _) {
              final feeAsync = ref.watch(feeConfigProvider);
              return feeAsync.when(
                data: (fees) => Column(
                  children: [
                    _feeRow("COA Fee (${(fees.coaFeePercent * 100).toStringAsFixed(1)}%)", "1% of every transaction", Colors.greenAccent, theme),
                    const SizedBox(height: 8),
                    _feeRow("Lipila MoMo (${(fees.momoFeePercent * 100).toStringAsFixed(1)}%)", "Mobile money processing fee", theme.primaryColor.withValues(alpha: 0.8), theme),
                    const SizedBox(height: 8),
                    _feeRow("Lipila Card (${(fees.cardFeePercent * 100).toStringAsFixed(1)}%)", "Card processing fee", theme.primaryColor.withValues(alpha: 0.7), theme),
                    const SizedBox(height: 8),
                    _feeRow("Business Cut (${(fees.businessCutPercent * 100).toStringAsFixed(0)}%)", "Deducted from sellers/drivers at settlement", Colors.orangeAccent, theme),
                    const SizedBox(height: 8),
                    _feeRow("Lipila Disbursement (${(fees.lipilaDisbursementFeePercent * 100).toStringAsFixed(1)}%)", "Deducted from every payout (money out)", theme.primaryColor.withValues(alpha: 0.55), theme),
                    const SizedBox(height: 8),
                    _feeRow("COA Payout (${(fees.coaPayoutFeePercent * 100).toStringAsFixed(1)}%, min K${fees.minFeeKwacha.toStringAsFixed(0)})", "COA's cut on money out", Colors.amberAccent, theme),
                    const SizedBox(height: 8),
                    _feeRow("Min Fee", "K${fees.minFeeKwacha.toStringAsFixed(0)} floor on all platform fees", theme.primaryColor.withValues(alpha: 0.45), theme),
                  ],
                ),
                loading: () => Text("Loading fee config...", style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.4), fontSize: 11)),
                error: (_, __) => Text("Using default fee config", style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.4), fontSize: 11)),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _feeRow(String label, String description, Color color, ThemeData theme) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                description,
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: theme.dividerColor),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withValues(alpha: 0.03),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 16),
            Text(value, style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 22, fontWeight: FontWeight.w900)),
            Text(
              label,
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAction(IconData icon, String title, String sub, Color color, VoidCallback onTap) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.dividerColor),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withValues(alpha: 0.02),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface, fontSize: 14)),
                  Text(sub, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 11)),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, color: theme.colorScheme.onSurface.withValues(alpha: 0.3), size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingApprovals() {
    final theme = Theme.of(context);
    if (_pendingChurches.isEmpty) return _emptyCard(theme, "No pending church registrations.");
    return Column(
      children: _pendingChurches.map((church) {
        return Container(
          margin: const EdgeInsets.only(bottom: 15),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              CircleAvatar(radius: 24, backgroundColor: Colors.amber.withValues(alpha: 0.1), child: const Icon(LucideIcons.church, color: Colors.amber)),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(church['name'] ?? 'Unknown Church', style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                    const SizedBox(height: 4),
                    Text("Pastor: ${church['pastor_name'] ?? 'None'} • ${church['country'] ?? 'Zambia'}", style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 12)),
                    Text("Phone: ${church['contact_phone'] ?? 'None'}", style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.4), fontSize: 11)),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(icon: const Icon(LucideIcons.xCircle, color: Colors.redAccent, size: 24), tooltip: "Reject", onPressed: () => _rejectChurch(church)),
                  IconButton(icon: const Icon(LucideIcons.checkCircle, color: Colors.greenAccent, size: 24), tooltip: "Approve", onPressed: () => _approveChurch(church)),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPendingPayments() {
    final theme = Theme.of(context);
    if (_pendingPayments.isEmpty) return _emptyCard(theme, "No pending subscription payments.");
    return Column(
      children: _pendingPayments.map((church) {
        final date = church['payment_submitted_at'] != null ? DateTime.parse(church['payment_submitted_at']).toLocal() : DateTime.now();
        return Container(
          margin: const EdgeInsets.only(bottom: 15),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              CircleAvatar(radius: 24, backgroundColor: Colors.amber.withValues(alpha: 0.1), child: const Icon(LucideIcons.banknote, color: Colors.amber)),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(church['name'] ?? 'Unknown Church', style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                    const SizedBox(height: 4),
                    Text("TXID: ${church['payment_reference']}", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
                    Text("Submitted: ${date.day}/${date.month}/${date.year}", style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 11)),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(icon: const Icon(LucideIcons.xCircle, color: Colors.redAccent, size: 24), tooltip: "Reject", onPressed: () => _rejectPayment(church)),
                  IconButton(icon: const Icon(LucideIcons.checkCircle, color: Colors.greenAccent, size: 24), tooltip: "Approve", onPressed: () => _approvePayment(church)),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPendingCoaPayments(UserProfile profile) {
    final theme = Theme.of(context);
    if (_pendingCoaPayments.isEmpty) return _emptyCard(theme, "No pending COA service payments.");
    return Column(
      children: _pendingCoaPayments.map((payment) {
        final svcLabel = payment.serviceType.replaceAll('_', ' ').toUpperCase();
        return Container(
          margin: const EdgeInsets.only(bottom: 15),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              CircleAvatar(radius: 24, backgroundColor: theme.primaryColor.withValues(alpha: 0.1), child: Icon(LucideIcons.creditCard, color: theme.primaryColor)),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(svcLabel, style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                    const SizedBox(height: 4),
                    Text("TXID: ${payment.paymentRef}", style: TextStyle(color: theme.primaryColor, fontWeight: FontWeight.bold, fontSize: 12)),
                    Text("K${payment.amount.toStringAsFixed(2)} • ${payment.createdAt.day}/${payment.createdAt.month}/${payment.createdAt.year}", style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 11)),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(icon: const Icon(LucideIcons.xCircle, color: Colors.redAccent, size: 24), tooltip: "Reject", onPressed: () => _rejectCoaPayment(payment)),
                  IconButton(icon: const Icon(LucideIcons.checkCircle, color: Colors.greenAccent, size: 24), tooltip: "Approve", onPressed: () => _approveCoaPayment(payment, profile)),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _emptyCard(ThemeData theme, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.1)),
      ),
      child: Center(child: Text(message, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.4)))),
    );
  }

  void _showAuditLog() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const _EmployeeAuditLogScreen()));
  }
}

class _EmployeeAuditLogScreen extends ConsumerWidget {
  const _EmployeeAuditLogScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(auditLogStreamProvider);
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text("Audit Log", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
      ),
      body: logsAsync.when(
        data: (logs) {
          if (logs.isEmpty) return Center(child: Text("No audit logs yet.", style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.4))));
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: logs.length,
            itemBuilder: (context, i) {
              final log = logs[i];
              final action = (log['action']?.toString() ?? 'unknown').replaceAll('_', ' ').toUpperCase();
              final entity = log['entity_type']?.toString() ?? '';
              final createdAt = log['created_at']?.toString() ?? '';
              final adminEmail = log['admin_email']?.toString() ?? '';
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(action, style: TextStyle(color: theme.colorScheme.primary, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    const SizedBox(height: 4),
                    Text(entity, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 12)),
                    Text(
                      "$adminEmail • ${createdAt.isNotEmpty ? createdAt.substring(0, 19).replaceAll('T', ' ') : ''}",
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
        loading: () => const Center(child: _CoaShimmerPlaceholder()),
        error: (e, st) => AppErrorView(error: e, onRetry: () => ref.invalidate(auditLogStreamProvider)),
      ),
    );
  }
}

class _CoaShimmerPlaceholder extends StatelessWidget {
  const _CoaShimmerPlaceholder();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: isDark ? Colors.grey[800]! : Colors.grey[300]!,
      highlightColor: isDark ? Colors.grey[700]! : Colors.grey[100]!,
      child: Padding(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(6, (i) => Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Container(
              height: i == 0 ? 120 : 80,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          )),
        ),
      ),
    );
  }
}
