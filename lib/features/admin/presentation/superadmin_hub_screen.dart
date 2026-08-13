import 'dart:convert';
import 'package:universal_io/io.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/tenant_service.dart';
import '../../../core/providers/profile_provider.dart';
import '../../../core/widgets/app_error_view.dart';
import '../../../core/utils/db_seeder.dart';
import '../../../core/services/platform_settings_service.dart';
import '../../../core/services/plan_service.dart';
import '../../../core/config/fee_config.dart';
import '../../../core/config/remote_config.dart';
import '../data/admin_service.dart';
import '../data/role_hierarchy_service.dart';
import '../../events/data/event_service.dart';
import '../data/audit_service.dart';
import 'resolution_hub_screen.dart';
import 'emergency_shutdown_screen.dart';
import 'ad_management_screen.dart';
import 'role_approval_screen.dart';
import 'writer_approval_screen.dart';
import 'custom_role_management_screen.dart';
import 'order_tracking_screen.dart';
import 'manage_partners_screen.dart';
import 'whatsapp_config_screen.dart';
import '../../../features/profile/presentation/church_referral_screen.dart';

class SuperadminHubScreen extends ConsumerStatefulWidget {
  const SuperadminHubScreen({super.key});

  @override
  ConsumerState<SuperadminHubScreen> createState() => _SuperadminHubScreenState();
}

class _SuperadminHubScreenState extends ConsumerState<SuperadminHubScreen> {
  final _passController = TextEditingController();
  final _onboardingFeeController = TextEditingController();
  final _goldFeeController = TextEditingController();
  final _platinumFeeController = TextEditingController();
  final _coaMoMoNumberController = TextEditingController();
  final _coaMoMoNameController = TextEditingController();
  final _coaTreasuryPhoneController = TextEditingController();
  bool _isSavingRates = false;
  bool _isSavingMoMo = false;
  late final AuditService _audit;

  @override
  void dispose() {
    _passController.dispose();
    _onboardingFeeController.dispose();
    _goldFeeController.dispose();
    _platinumFeeController.dispose();
    _coaMoMoNumberController.dispose();
    _coaMoMoNameController.dispose();
    _coaTreasuryPhoneController.dispose();
    super.dispose();
  }

  int _activeTenantsCount = 0;
  int _totalUsersCount = 0;
  double _totalPlatformRevenue = 0.0;
  List<Map<String, dynamic>> _pendingChurches = [];
  List<Map<String, dynamic>> _pendingPayments = [];
  bool _statsLoading = true;

  @override
  void initState() {
    super.initState();
    _audit = AuditService(Supabase.instance.client);
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final client = Supabase.instance.client;
      
      // Active verified tenants count
      final activeChurchesRes = await client.from('churches').select('id').eq('is_verified', true);
      final tenantsCount = activeChurchesRes.length;

      // Pending registrations list
      final pendingRes = await client.from('churches').select('id, name, email, contact_phone, location, is_verified, subscription_ends_at, logo_url').eq('is_verified', false);
      final pendingList = List<Map<String, dynamic>>.from(pendingRes);

      // Pending subscription payments
      final paymentsRes = await client.from('churches').select('id, name, email, contact_phone, location, payment_reference, payment_amount, is_verified').not('payment_reference', 'is', null);
      final paymentsList = List<Map<String, dynamic>>.from(paymentsRes)
          .where((c) => (c['payment_reference'] as String?)?.isNotEmpty == true)
          .toList();

      final profilesRes = await client.from('profiles').select('id');
      final usersCount = profilesRes.length;

      final txsRes = await client.from('transactions').select('platform_fee');
      double rev1 = 0.0;
      for (var row in txsRes) {
        rev1 += (row['platform_fee'] as num?)?.toDouble() ?? 0.0;
      }

      final wTxsRes = await client.from('wallet_transactions').select('platform_fee');
      double rev2 = 0.0;
      for (var row in wTxsRes) {
        rev2 += (row['platform_fee'] as num?)?.toDouble() ?? 0.0;
      }

      final settings = await ref.read(platformSettingsServiceProvider).fetchSettings();
      _onboardingFeeController.text = settings.onboardingFee.toStringAsFixed(0);
      _goldFeeController.text = settings.goldMonthlyFee.toStringAsFixed(0);
      _platinumFeeController.text = settings.platinumMonthlyFee.toStringAsFixed(0);
      _coaMoMoNumberController.text = settings.coaMoMoNumber;
      _coaMoMoNameController.text = settings.coaMoMoName;
      _coaTreasuryPhoneController.text = settings.coaTreasuryPhone;

      if (mounted) {
        setState(() {
          _activeTenantsCount = tenantsCount;
          _totalUsersCount = usersCount;
          _totalPlatformRevenue = rev1 + rev2;
          _pendingChurches = pendingList;
          _pendingPayments = paymentsList;
          _statsLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading superadmin stats: $e");
      if (mounted) {
        setState(() => _statsLoading = false);
      }
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
        await client.from('profiles').update({
          'tenant_id': church['id'],
          'role': role,
        }).eq('id', pastorId);
      }

      await _audit.logChurchAction(
        action: 'approve',
        churchId: church['id'],
        churchName: church['name']?.toString(),
      );

      if (mounted) {
        showAppSnackBar(
          context,
          "Approved ${church['name']}! 30-day Silver trial started ✅",
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

      await _audit.logChurchAction(
        action: 'reject',
        churchId: church['id'],
        churchName: church['name']?.toString(),
      );

      if (mounted) {
        showAppSnackBar(
          context,
          "Rejected and deleted ${church['name']}",
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

  Widget _buildPendingApprovals() {
    if (_pendingChurches.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white10),
        ),
        child: const Center(
          child: Text(
            "No pending church registrations. ⛪",
            style: TextStyle(color: Colors.white60, fontSize: 14),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _pendingChurches.map((church) {
        return Container(
          margin: const EdgeInsets.only(bottom: 15),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Colors.amber.withValues(alpha: 0.1),
                child: const Icon(LucideIcons.church, color: Colors.amber),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      church['name'] ?? 'Unknown Church',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Pastor: ${church['pastor_name'] ?? 'None'} • ${church['country'] ?? 'Zambia'}",
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Phone: ${church['contact_phone'] ?? 'None'}",
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(LucideIcons.xCircle, color: Colors.redAccent, size: 24),
                    tooltip: "Reject Registration",
                    onPressed: () => _rejectChurch(church),
                  ),
                  const SizedBox(width: 5),
                  IconButton(
                    icon: const Icon(LucideIcons.checkCircle, color: Colors.greenAccent, size: 24),
                    tooltip: "Approve Registration",
                    onPressed: () => _approveChurch(church),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
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

      await _audit.logPaymentAction(
        action: 'approve_payment',
        paymentId: church['id'],
        churchName: church['name']?.toString(),
      );

      if (mounted) {
        showAppSnackBar(
          context,
          "Onboarding approved for ${church['name']}! Platinum active until ${platinumUntil.toLocal().toString().split(' ')[0]} 🚀",
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
      await client.from('churches').update({
        'payment_reference': null,
        'payment_submitted_at': null,
      }).eq('id', church['id']);

      await _audit.logPaymentAction(
        action: 'reject_payment',
        paymentId: church['id'],
        churchName: church['name']?.toString(),
      );

      if (mounted) {
        showAppSnackBar(
          context,
          "Rejected payment reference for ${church['name']}",
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

  Widget _buildPendingPayments() {
    if (_pendingPayments.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white10),
        ),
        child: const Center(
          child: Text(
            "No pending subscription payments. 💵",
            style: TextStyle(color: Colors.white60, fontSize: 14),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _pendingPayments.map((church) {
        final date = church['payment_submitted_at'] != null 
            ? DateTime.parse(church['payment_submitted_at']).toLocal() 
            : DateTime.now();
        return Container(
          margin: const EdgeInsets.only(bottom: 15),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Colors.amber.withValues(alpha: 0.1),
                child: const Icon(LucideIcons.banknote, color: Colors.amber),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      church['name'] ?? 'Unknown Church',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "TXID / Reference: ${church['payment_reference']}",
                      style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Submitted: ${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}",
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(LucideIcons.xCircle, color: Colors.redAccent, size: 24),
                    tooltip: "Reject Payment",
                    onPressed: () => _rejectPayment(church),
                  ),
                  const SizedBox(width: 5),
                  IconButton(
                    icon: const Icon(LucideIcons.checkCircle, color: Colors.greenAccent, size: 24),
                    tooltip: "Approve Payment",
                    onPressed: () => _approvePayment(church),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Future<void> _saveRates() async {
    final onboarding = double.tryParse(_onboardingFeeController.text) ?? PlanLimits.onboardingFeeKwacha;
    final gold = double.tryParse(_goldFeeController.text) ?? PlanLimits.forPlan(TenantPlan.gold).monthlyPriceKwacha;
    final platinum = double.tryParse(_platinumFeeController.text) ?? PlanLimits.forPlan(TenantPlan.platinum).monthlyPriceKwacha;

    setState(() => _isSavingRates = true);
    try {
      await ref.read(platformSettingsServiceProvider).updateSettings(
        onboardingFee: onboarding,
        goldMonthlyFee: gold,
        platinumMonthlyFee: platinum,
      );
      ref.invalidate(platformSettingsProvider);
      if (mounted) {
        showAppSnackBar(
          context,
          "Platform rates updated successfully! 🚀",
          status: AppStatus.success,
        );
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          AppErrorView.friendlyMessage(e),
          status: AppStatus.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingRates = false);
    }
  }

  Future<void> _saveMoMo() async {
    final momoNumber = _coaMoMoNumberController.text.trim();
    final momoName = _coaMoMoNameController.text.trim();
    final treasuryPhone = _coaTreasuryPhoneController.text.trim();

    setState(() => _isSavingMoMo = true);
    try {
      await ref.read(platformSettingsServiceProvider).updateSettings(
        onboardingFee: double.tryParse(_onboardingFeeController.text) ?? PlanLimits.onboardingFeeKwacha,
        goldMonthlyFee: double.tryParse(_goldFeeController.text) ?? PlanLimits.forPlan(TenantPlan.gold).monthlyPriceKwacha,
        platinumMonthlyFee: double.tryParse(_platinumFeeController.text) ?? PlanLimits.forPlan(TenantPlan.platinum).monthlyPriceKwacha,
        coaMoMoNumber: momoNumber,
        coaMoMoName: momoName,
        coaTreasuryPhone: treasuryPhone,
      );
      ref.invalidate(platformSettingsProvider);
      if (mounted) {
        showAppSnackBar(
          context,
          "COA MoMo numbers updated! ✅",
          status: AppStatus.success,
        );
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          AppErrorView.friendlyMessage(e),
          status: AppStatus.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingMoMo = false);
    }
  }

  Widget _buildMoMoEditor() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("These numbers receive coin purchase payments.", style: TextStyle(color: Colors.white38, fontSize: 12)),
          const SizedBox(height: 16),
          _buildRateInput("COA MoMo Number (e.g. 0977000000)", _coaMoMoNumberController),
          const SizedBox(height: 15),
          _buildRateInput("COA MoMo Name (e.g. Church On App)", _coaMoMoNameController),
          const SizedBox(height: 15),
          _buildRateInput("COA Treasury Phone (e.g. 260977000000)", _coaTreasuryPhoneController),
          const SizedBox(height: 25),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isSavingMoMo ? null : _saveMoMo,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              child: _isSavingMoMo
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text("UPDATE MOMO NUMBERS", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatesEditor() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRateInput("Onboarding Fee (K) — one-time", _onboardingFeeController),
          const SizedBox(height: 15),
          _buildRateInput("Gold Monthly Plan Fee (K/mo)", _goldFeeController),
          const SizedBox(height: 15),
          _buildRateInput("Platinum Monthly Plan Fee (K/mo)", _platinumFeeController),
          const SizedBox(height: 25),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isSavingRates ? null : _saveRates,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              child: _isSavingRates
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                  : const Text("UPDATE PLATFORM RATES", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRateInput(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }

  final List<String> _allFeatures = [
    'Radio',
    'Marketplace',
    'Klips',
    'Jobs Portal',
    'Logistics & Tracking',
    'Kids Zone',
    'Game Arena',
    'Events Management',
    'Giving & Tithes',
    'Bible Quiz',
    'Live Streaming',
    'Sermon Library',
    'Kingdom Klips',
    'Direct Chat',
    'Community Chat',
    'Audio/Video Calls',
    'SMS Broadcasts',
    'Carpso Ride',
    'Cargo Delivery',
    'Bible Reader',
    'Bible Study Plans',
    'Kael Bible Tools',
    'QR Check-in',
    'Event Ticketing',
    'Attendance Scanner',
    'Finance Dashboard',
    'Service Reports',
    'Data Import',
    'Bookshop',
    'Inter-Tenant Events',
  ];

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(currentTenantProvider);
    final profileAsync = ref.watch(profileProvider);

    return profileAsync.when(
      data: (profile) {
        if (profile == null || !profile.isSuperadmin) {
          return const Scaffold(
            backgroundColor: Color(0xFF0F172A),
            body: Center(
              child: Text(
                "Unauthorized Access\n(Superadmin Only)",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60, fontSize: 16),
              ),
            ),
          );
        }
        return _buildScreen(context, tenant, profile);
      },
      loading: () => const Scaffold(
        backgroundColor: Color(0xFF0F172A),
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: AppErrorView(error: e, onRetry: _loadStats),
      ),
    );
  }

  Widget _buildScreen(BuildContext context, Tenant? tenant, UserProfile profile) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Dark mode for superadmin
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Superadmin God-Mode", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
            const Text("SUPERADMIN", style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatCards(),
            const SizedBox(height: 35),
            const Text("Pending Church Registrations", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            _buildPendingApprovals(),
            const SizedBox(height: 35),
            const Text("Pending Subscription Payments", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            _buildPendingPayments(),
            const SizedBox(height: 35),
            Text("Tenant Management: ${tenant?.name ?? 'Global'}", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            _buildFeatureToggles(tenant),
            const SizedBox(height: 40),
            const Text("Platform Subscription Rates", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            _buildRatesEditor(),
            const SizedBox(height: 40),
            const Text("COA Treasury MoMo Numbers", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            _buildMoMoEditor(),
            const SizedBox(height: 40),
            const Text("Global Overrides", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            _buildGlobalAction(LucideIcons.refreshCw, "Force Data Sync", "Triggers re-fetch for all data", Colors.blue, () async {
              try {
                ref.invalidate(currentTenantProvider);
                ref.invalidate(membersProvider);
                ref.invalidate(eventsStreamProvider);
                if (!context.mounted) return;
                showAppSnackBar(context, "Data sync triggered!", status: AppStatus.success);
              } catch (e) {
                if (!context.mounted) return;
                showAppSnackBar(context, AppErrorView.friendlyMessage(e), status: AppStatus.error);
              }
            }),
            _buildGlobalAction(LucideIcons.shieldAlert, "Emergency Lockdown", "Instantly disable app for maintenance", Colors.red, () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const EmergencyShutdownScreen()));
            }),
            _buildGlobalAction(LucideIcons.database, "Clear Tenant Cache", "Wipe local storage for current church", Colors.amber, () async {
              try {
                final prefs = await SharedPreferences.getInstance();
                await prefs.clear();
                if (!context.mounted) return;
                showAppSnackBar(context, "Local cache cleared!", status: AppStatus.warning);
              } catch (e) {
                if (!context.mounted) return;
                showAppSnackBar(context, AppErrorView.friendlyMessage(e), status: AppStatus.error);
              }
            }),
            _buildGlobalAction(LucideIcons.sparkles, "Seed Mock Data", "Populate all tables with demo data", Colors.green, () async {
              try {
                await DbSeeder.seedAll();
                if (!context.mounted) return;
                showAppSnackBar(context, "Mock data seeded successfully! ✅", status: AppStatus.success);
              } catch (e) {
                if (!context.mounted) return;
                showAppSnackBar(context, AppErrorView.friendlyMessage(e), status: AppStatus.error);
              }
            }),
            _buildGlobalAction(LucideIcons.hardDrive, "Create System Backup", "Download snapshot of database schema and settings", Colors.purple, () => _performBackup()),
            _buildGlobalAction(LucideIcons.scrollText, "Audit Log", "View all admin actions and changes", Colors.orange, () => _showAuditLog()),
            _buildGlobalAction(LucideIcons.lifeBuoy, "Resolution Hub", "Respond to tickets, disputes & error reports", Colors.redAccent, () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ResolutionHubScreen()));
            }),
            _buildGlobalAction(LucideIcons.megaphone, "Sponsored Content", "Manage tenant ads and banners", Colors.cyan, () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AdManagementScreen()));
            }),
            _buildGlobalAction(LucideIcons.userCheck, "Role Approvals", "Approve or elevate user roles", Colors.teal, () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const RoleApprovalScreen()));
            }),
            _buildGlobalAction(LucideIcons.penTool, "Writer Approvals", "Approve writer applications", Colors.indigo, () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const WriterApprovalScreen()));
            }),
            _buildGlobalAction(LucideIcons.users, "Custom Roles", "Manage custom tenant roles", Colors.pink, () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomRoleManagementScreen()));
            }),
            _buildGlobalAction(LucideIcons.userPlus, "Quick Add Tenant Staff", "Create staff with department roles for any tenant", Colors.green, () async {
              final userCtrl = TextEditingController();
              final roleCtrl = TextEditingController(text: 'assistant');
              String staffRole = 'assistant';
              String selectedTenantId = '';

              // Load tenants
              final tenants = await Supabase.instance.client.from('tenants').select('id, name').order('name');
              final tenantList = tenants as List<dynamic>? ?? [];

              if (!context.mounted) return;
              final result = await showDialog<Map<String, String>>(
                context: context,
                builder: (ctx) => StatefulBuilder(
                  builder: (ctx, setDialogState) => AlertDialog(
                    title: const Text("Quick Add Tenant Staff"),
                    content: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        DropdownButtonFormField<String>(
                          initialValue: selectedTenantId.isNotEmpty ? selectedTenantId : null,
                          items: tenantList.map((t) => DropdownMenuItem(value: t['id'] as String, child: Text(t['name'] as String? ?? 'Unknown'))).toList(),
                          onChanged: (v) => setDialogState(() => selectedTenantId = v ?? ''),
                          decoration: const InputDecoration(labelText: "Tenant", hintText: "Select tenant"),
                        ),
                        const SizedBox(height: 12),
                        TextField(controller: userCtrl, decoration: const InputDecoration(labelText: "User ID (UUID)", hintText: "Paste the user's ID")),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: staffRole,
                          items: ['store_manager', 'assistant', 'cashier', 'department_leader', 'usher', 'treasurer', 'worship_leader'].map((r) => DropdownMenuItem(value: r, child: Text(r.replaceAll('_', ' ')))).toList(),
                          onChanged: (v) {
                            setDialogState(() => staffRole = v ?? 'assistant');
                            roleCtrl.text = v ?? 'assistant';
                          },
                          decoration: const InputDecoration(labelText: "Staff Role", hintText: "Select role"),
                        ),
                      ]),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
                      ElevatedButton(onPressed: () {
                        if (selectedTenantId.isEmpty) {
                          Navigator.pop(ctx);
                          return;
                        }
                        Navigator.pop(ctx, {'tenantId': selectedTenantId, 'userId': userCtrl.text.trim(), 'role': staffRole});
                      }, child: const Text("Add Staff")),
                    ],
                  ),
                ),
              );
              if (result != null) {
                final uid = result['userId'];
                final role = result['role'];
                final tenantId = result['tenantId'];
                if (uid != null && uid.isNotEmpty && role != null && role.isNotEmpty) {
                  final svc = ref.read(roleHierarchyServiceProvider);
                  try {
                    await svc.assignRole(userId: uid, roleName: role, tenantId: tenantId);
                    if (context.mounted) {
                      showAppSnackBar(
                        context,
                        "Staff role requested: $role for tenant $tenantId",
                        status: AppStatus.success,
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      showAppSnackBar(
                        context,
                        AppErrorView.friendlyMessage(e),
                        status: AppStatus.error,
                      );
                    }
                  }
                }
              }
            }),
            _buildGlobalAction(LucideIcons.package, "Orders & Deliveries", "Track marketplace orders", Colors.brown, () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const OrderTrackingScreen()));
            }),
            _buildGlobalAction(LucideIcons.phoneCall, "Church Leads", "Manage pastor referrals", Colors.deepOrange, () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ChurchReferralScreen()));
            }),
            _buildGlobalAction(LucideIcons.store, "Partner Tenants", "Manage coin redemption partners", Colors.teal, () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ManagePartnersScreen()));
            }),
            _buildGlobalAction(LucideIcons.messageCircle, "WhatsApp Config", "Configure WhatsApp Business API", const Color(0xFF1A1A1A), () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const WhatsAppConfigScreen()));
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _performBackup() async {
    final client = Supabase.instance.client;
    final tables = [
      'profiles', 'churches', 'transactions', 'wallet_transactions',
      'events', 'event_registrations', 'social_posts', 'prayers',
      'testimonies', 'klips', 'ride_requests', 'delivery_requests',
      'service_reports', 'notifications', 'platform_settings',
    ];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        backgroundColor: Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
        content: SizedBox(
          width: 200,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.purpleAccent),
              SizedBox(height: 20),
              Text("Backing up database...", style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      ),
    );

    try {
      final backup = <String, List<dynamic>>{};
      for (final table in tables) {
        final res = await client.from(table).select('*');
        backup[table] = List<dynamic>.from(res);
      }

      await _audit.logAction(
        action: 'system_backup',
        entityType: 'system',
        details: {'tables': tables, 'record_count': backup.values.fold(0, (s, t) => s + t.length)},
      );

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/churchonapp_backup_${DateTime.now().millisecondsSinceEpoch}.json');
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(backup));

      if (mounted) Navigator.pop(context);

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
            title: const Row(
              children: [
                Icon(LucideIcons.checkCircle, color: Colors.greenAccent),
                SizedBox(width: 10),
                Text("Backup Complete", style: TextStyle(color: Colors.white)),
              ],
            ),
            content: Text(
              "Database snapshot saved to:\n${file.path}\n\nTables backed up: ${backup.length}\nTotal records: ${backup.values.fold(0, (s, t) => s + t.length)}",
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("OK", style: TextStyle(color: Colors.purpleAccent)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        showAppSnackBar(
          context,
          AppErrorView.friendlyMessage(e),
          status: AppStatus.error,
        );
      }
    }
  }

  void _showAuditLog() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => _AuditLogScreen()));
  }

  Widget _buildStatCards() {
    if (_statsLoading) {
      return const Center(child: Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: CircularProgressIndicator(color: Colors.red),
      ));
    }

    return Column(
      children: [
        Row(
          children: [
            _buildStatItem("Active Tenants", _activeTenantsCount.toString(), LucideIcons.building, Colors.blue),
            const SizedBox(width: 15),
            _buildStatItem("Total Users", _totalUsersCount.toString(), LucideIcons.users, Colors.green),
          ],
        ),
        const SizedBox(height: 15),
        _buildFeeBreakdownCard(),
      ],
    );
  }

  Widget _buildFeeBreakdownCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "PLATFORM REVENUE BREAKDOWN",
            style: TextStyle(
              color: Colors.white60,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(LucideIcons.banknote, color: Colors.amber, size: 28),
              const SizedBox(width: 12),
              Text("K ${_totalPlatformRevenue.toStringAsFixed(2)}", style: const TextStyle(color: Colors.amber, fontSize: 24, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 12),
          Consumer(
            builder: (context, ref, _) {
              final feeAsync = ref.watch(feeConfigProvider);
              return feeAsync.when(
                data: (fees) => Column(
                  children: [
                    _feeBreakdownRow("COA Fee (${(fees.coaFeePercent * 100).toStringAsFixed(1)}%)", "1% of every transaction", Colors.greenAccent),
                    const SizedBox(height: 8),
                    _feeBreakdownRow("Lipila MoMo (${(fees.momoFeePercent * 100).toStringAsFixed(1)}%)", "Mobile money processing fee", Colors.blueAccent),
                    const SizedBox(height: 8),
                    _feeBreakdownRow("Lipila Card (${(fees.cardFeePercent * 100).toStringAsFixed(1)}%)", "Card processing fee", Colors.purpleAccent),
                    const SizedBox(height: 8),
                    _feeBreakdownRow("Business Cut (${(fees.businessCutPercent * 100).toStringAsFixed(0)}%)", "Deducted from sellers/drivers at settlement", Colors.orangeAccent),
                    const SizedBox(height: 8),
                    _feeBreakdownRow("Lipila Disbursement (${(fees.lipilaDisbursementFeePercent * 100).toStringAsFixed(1)}%)", "Deducted from every payout (money out)", Colors.pinkAccent),
                    const SizedBox(height: 8),
                    _feeBreakdownRow("COA Payout (${(fees.coaPayoutFeePercent * 100).toStringAsFixed(1)}%, min K${fees.minFeeKwacha.toStringAsFixed(0)})", "COA's cut on money out", Colors.amberAccent),
                    const SizedBox(height: 8),
                    _feeBreakdownRow("Min Fee", "K${fees.minFeeKwacha.toStringAsFixed(0)} floor on all platform fees", Colors.tealAccent),
                  ],
                ),
                loading: () => const Text("Loading fee config...", style: TextStyle(color: Colors.white38, fontSize: 11)),
                error: (_, __) => const Text("Using default fee config", style: TextStyle(color: Colors.white38, fontSize: 11)),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _feeBreakdownRow(String label, String description, Color color) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
              Text(description, style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 15),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
            Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureToggles(Tenant? tenant) {
    return Container(
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(25), border: Border.all(color: Colors.white10)),
      child: Column(
        children: _allFeatures.map((feature) {
          final key = feature.toLowerCase().replaceAll(' ', '_');
          final isEnabled = tenant?.settings?[key] ?? true;
          return SwitchListTile(
            title: Text(feature, style: const TextStyle(color: Colors.white, fontSize: 14)),
            value: isEnabled,
            activeThumbColor: Colors.greenAccent,
            subtitle: Text(
              "Enabled for ${tenant?.name ?? 'all'}",
              style: const TextStyle(color: Colors.white30, fontSize: 11),
            ),
            onChanged: (val) async {
              if (tenant == null) {
                showAppSnackBar(
                  context,
                  "No tenant selected to configure",
                  status: AppStatus.error,
                );
                return;
              }
              final client = Supabase.instance.client;
              final updatedSettings = Map<String, dynamic>.from(tenant.settings ?? {});
              updatedSettings[key] = val;
              
              try {
                await client.from('churches').update({
                  'settings': updatedSettings,
                }).eq('id', tenant.id);
                
                final updatedTenant = await ref.read(tenantServiceProvider).getTenantById(tenant.id);
                if (updatedTenant != null) {
                  await ref.read(currentTenantProvider.notifier).setTenant(updatedTenant);
                }
                
                if (mounted) {
                  showAppSnackBar(
                    context,
                    "$feature updated to ${val ? 'Enabled' : 'Disabled'}! ✅",
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
            },
          );
        }).toList(),
      ),
    );
  }

  Widget _buildGlobalAction(IconData icon, String title, String sub, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)),
      child: Row(
        children: [
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 20)),
          const SizedBox(width: 20),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              Text(sub, style: const TextStyle(color: Colors.white30, fontSize: 11)),
            ]),
          ),
          Icon(LucideIcons.chevronRight, color: Colors.white24, size: 16),
        ],
      ),
    ),
    );
  }
}

class _AuditLogScreen extends ConsumerStatefulWidget {
  @override
  ConsumerState<_AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends ConsumerState<_AuditLogScreen> {
  @override
  Widget build(BuildContext context) {
    final logsAsync = ref.watch(auditLogStreamProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text("Admin Audit Log", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
      ),
      body: logsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: Colors.amber)),
        error: (e, st) => AppErrorView(error: e, onRetry: () => ref.invalidate(auditLogStreamProvider)),
        data: (logs) {
          if (logs.isEmpty) {
            return const Center(child: Text("No audit logs yet.", style: TextStyle(color: Colors.white38)));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: logs.length,
            itemBuilder: (context, i) {
              final log = logs[i];
              final action = log['action']?.toString() ?? 'unknown';
              final entity = log['entity_type']?.toString() ?? '';
              final entityId = log['entity_id']?.toString() ?? '';
              final adminEmail = log['admin_email']?.toString() ?? '';
              final createdAt = log['created_at']?.toString() ?? '';
              final details = log['details'] is Map ? Map<String, dynamic>.from(log['details']) : <String, dynamic>{};

              IconData icon;
              Color color;
              switch (action) {
                case 'approve':
                  icon = LucideIcons.checkCircle; color = Colors.green;
                  break;
                case 'reject':
                  icon = LucideIcons.xCircle; color = Colors.red;
                  break;
                case 'approve_payment':
                  icon = LucideIcons.creditCard; color = Colors.greenAccent;
                  break;
                case 'reject_payment':
                  icon = LucideIcons.creditCard; color = Colors.orangeAccent;
                  break;
                case 'system_backup':
                  icon = LucideIcons.hardDrive; color = Colors.purpleAccent;
                  break;
                case 'role_change':
                  icon = LucideIcons.shield; color = Colors.amber;
                  break;
                default:
                  icon = LucideIcons.info; color = Colors.blueGrey;
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
                      child: Icon(icon, color: color, size: 16),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(action.replaceAll('_', ' ').toUpperCase(), style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                          const SizedBox(height: 4),
                          Text("$entity${entityId.isNotEmpty ? ': $entityId' : ''}", style: const TextStyle(color: Colors.white54, fontSize: 12)),
                          if (details.isNotEmpty)
                            Text(
                              details.toString(),
                              style: const TextStyle(color: Colors.white24, fontSize: 11),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          const SizedBox(height: 4),
                          Text(
                            "$adminEmail • ${createdAt.isNotEmpty ? createdAt.substring(0, 19).replaceAll('T', ' ') : ''}",
                            style: const TextStyle(color: Colors.white24, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

