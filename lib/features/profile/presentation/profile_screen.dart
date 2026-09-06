import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/services/prediction_service.dart';
import 'package:church_on_app/core/widgets/qr_code_with_logo.dart';
import 'package:church_on_app/core/widgets/error_retry_widget.dart';
import 'package:church_on_app/core/widgets/verification_badge.dart';
import 'package:church_on_app/features/profile/presentation/membership_card_screen.dart';
import '../../marketplace/presentation/my_library_screen.dart';
import '../../modules/events/presentation/events_screen.dart';

import '../../../core/providers/profile_provider.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/utils/money.dart';
import '../../auth/presentation/two_factor_setup_screen.dart';
import '../../../core/services/coins_service.dart';
import '../../../core/services/rating_service.dart';
import '../../../core/services/r2_service.dart';
import '../../finance/data/finance_service.dart';
import '../../modules/bible_quiz/data/bible_quiz_service.dart';
import '../../transport/presentation/driver_portal_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'security_screen.dart';
import 'camera_settings_screen.dart';
import 'emergency_contacts_screen.dart';
import 'rewards_screen.dart';
import 'certificates_screen.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  final String? userId;
  const ProfileScreen({super.key, this.userId});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final profileAsync = ref.watch(profileProvider);
    final tenant = ref.watch(currentTenantProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: profileAsync.when(
        data: (profile) {
          if (profile == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.userX, size: 80, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.25)),
                  const SizedBox(height: 24),
                  Text("PROFILE NOT FOUND", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Theme.of(context).colorScheme.onSurface, letterSpacing: 1.5)),
                  const SizedBox(height: 12),
                  Text("Please sign in to access your account.", style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 13)),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: () => context.push('/login'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      minimumSize: const Size(200, 56),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                    ),
                    child: const Text("LOGIN / SIGNUP", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );
          }
          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              _buildAppBar(context, ref, profile, tenant),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 30),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildCredentialsRow(profile),
                      const SizedBox(height: 24),
                      _buildActivityCard(context, ref),
                      const SizedBox(height: 24),
                      _buildPremiumWallet(context, profile, ref),
                      const SizedBox(height: 40),
                      _buildSectionHeader(context, "FAITH METRICS"),
                      _buildFaithDashboard(context, profile, ref),
                      const SizedBox(height: 40),
                      _buildSectionHeader(context, "MINISTRY & COMMAND"),
                      _buildMinistryActions(context, ref, profile, tenant),
                      const SizedBox(height: 40),
                      _buildSectionHeader(context, "DIGITAL ASSETS"),
                      _buildAssetGrid(context, ref),
                      const SizedBox(height: 40),
                      _buildSectionHeader(context, "ACCOUNT & TRUST"),
                      _buildAccountList(context, ref, profile),
                      const SizedBox(height: 120),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => Center(child: CircularProgressIndicator(color: Theme.of(context).primaryColor)),
        error: (e, st) => ErrorRetryWidget(
          message: "Failed to load profile",
          onRetry: () => ref.invalidate(profileProvider),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, WidgetRef ref, UserProfile profile, Tenant? tenant) {
    return SliverAppBar(
      expandedHeight: 320,
      pinned: true,
      stretch: true,
      backgroundColor: Colors.black,
      title: Text(
        profile.name,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [StretchMode.zoomBackground, StretchMode.blurBackground],
        background: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black, Colors.amber.withValues(alpha: 0.2), Colors.black],
                  ),
                ),
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 60),
                Stack(
                  children: [
                    GestureDetector(
                      onTap: () => _pickAvatar(context, ref, profile),
                      child: Hero(
                        tag: 'profile_avatar',
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.amber, width: 2),
                          ),
                          child: CircleAvatar(
                            radius: 56,
                            backgroundColor: Colors.white10,
                            backgroundImage: (profile.avatarUrl != null && profile.avatarUrl!.isNotEmpty)
                                ? NetworkImage(profile.avatarUrl!)
                                : null,
                            child: (profile.avatarUrl == null || profile.avatarUrl!.isEmpty)
                                ? const Icon(LucideIcons.user, color: Colors.white54, size: 40)
                                : null,
                          ),
                        ),
                      ),
                    ),
                    if (profile.isVerified)
                      Positioned(
                        bottom: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: Color(0xFFFFD700),
                            shape: BoxShape.circle,
                          ),
                          child: const VerificationBadge(size: 20),
                        ),
                      ),
                    Positioned(
                      bottom: 4,
                      left: 4,
                      child: GestureDetector(
                        onTap: () => _pickAvatar(context, ref, profile),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.amber,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(LucideIcons.camera, color: Colors.black, size: 16),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          profile.name.toUpperCase(),
                          style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 2),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      if (profile.isVerified) ...[
                        const SizedBox(width: 8),
                        const VerificationBadge(size: 22),
                      ],
                    ],
                  ),
                ),
                Text(tenant?.name ?? "Church On App Member", style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                  ),
                  child: Text(profile.role.toUpperCase(), style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 2)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPremiumWallet(BuildContext context, UserProfile profile, WidgetRef ref) {
    final coins = profile.coins;
    final canCollectAsync = ref.watch(canCollectDailyProvider);
    final walletId = profile.walletId ?? "COA-PENDING";

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("WALLET", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5), letterSpacing: 2)),
                    const SizedBox(height: 8),
                    Text("$coins CC", style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Theme.of(context).primaryColor)),
                    const SizedBox(height: 4),
                    Text(walletId, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4), fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              if (profile.canWork) _buildWorkModeToggle(context, ref, profile),
              const SizedBox(width: 16),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MembershipCardScreen()),
                ),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: QrCodeWithLogo(
                    data: profile.id,
                    size: 50,
                    logoSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          canCollectAsync.when(
            data: (canCollectValue) => _buildWalletActionsRow(context, profile, ref, canCollectValue),
            loading: () => _buildWalletActionsRow(context, profile, ref, false),
            error: (e, st) => _buildWalletActionsRow(context, profile, ref, false),
          ),
        ],
      ),
    );
  }

  Widget _buildWalletActionsRow(BuildContext context, UserProfile profile, WidgetRef ref, bool canCollect) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildWalletAction(context, LucideIcons.send, "GIVE", () => context.push('/giving')),
            _buildWalletAction(context, LucideIcons.coins, "MY CC", () => context.push('/payout-request')),
            _buildWalletAction(context, LucideIcons.shieldCheck, "IDENTITY", () => context.push('/kyc-verification')),
          ],
        ),
      ],
    );
  }

  Widget _buildWalletAction(BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Theme.of(context).colorScheme.onSurface, size: 20),
          ),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55), letterSpacing: 1)),
        ],
      ),
    );
  }

  // ignore: unused_element
  String _formatTimeAgo(DateTime time) {
    final diff = DateTime.now().difference(time.toLocal());
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${time.day}/${time.month}/${time.year}';
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20.0),
      child: Row(
        children: [
          Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7), letterSpacing: 2.5)),
          const Spacer(),
          Icon(LucideIcons.chevronRight, size: 14, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)),
        ],
      ),
    );
  }

  Widget _buildMinistryActions(BuildContext context, WidgetRef ref, UserProfile profile, Tenant? tenant) {
    return Column(
      children: [
        _buildPremiumItem(context, LucideIcons.plusCircle, "Register Your Church", onTap: () => context.push('/register-church')),
        if (profile.isBishopOrHigher) ...[
          _buildPremiumItem(context, LucideIcons.crown, "Bishop Dashboard", isHighlighted: true, onTap: () => context.push('/bishop-hub')),
        ],
        _buildPremiumItem(context, LucideIcons.calendar, "Yearly Program Planner", onTap: () => context.push('/year-planner')),
if (profile.isPastorOrHigher) ...[
_buildPremiumItem(context, LucideIcons.layoutDashboard, "Pastor Dashboard", isHighlighted: true, onTap: () => context.push('/pastor-dashboard')),
],
        if (profile.isLedgerManager) ...[
          _buildPremiumItem(context, LucideIcons.qrCode, "Scan Attendance", onTap: () => context.push('/attendance-scanner')),
          _buildPremiumItem(context, LucideIcons.wallet, "Finance Dashboard", isHighlighted: true, onTap: () => context.push('/finance-dashboard')),
          // Church Ledger consolidated into Finance Dashboard (single source
          // for trends, distribution, payouts & HQ remittance) — /ledger
          // redirects there, so no separate entry here.
        ],
        if (profile.role == 'driver') ...[
          _buildPremiumItem(context, LucideIcons.car, "Driver Portal", isHighlighted: true, onTap: () => context.push('/driver-portal')),
        ],
        if (profile.role == 'rider') ...[
          _buildPremiumItem(context, LucideIcons.bike, "Rider Dashboard", isHighlighted: true, onTap: () => context.push('/rider-dashboard')),
        ],
        if (profile.role == 'writer') ...[
          _buildPremiumItem(context, LucideIcons.penTool, "Writer Dashboard", isHighlighted: true, onTap: () => context.push('/writer-dashboard')),
        ],
        if (profile.isAdminOrHigher) ...[
          _buildPremiumItem(context, LucideIcons.settings, "SYSTEM ADMIN HUB", onTap: () => context.push('/admin-hub')),
        ],
        if (profile.role == 'apostle') ...[
          _buildPremiumItem(context, LucideIcons.globe, "APOSTLE DASHBOARD", isHighlighted: true, onTap: () => context.push('/apostle-dashboard')),
        ],
        if (profile.isEmployee) ...[
          _buildPremiumItem(context, LucideIcons.briefcase, "COA EMPLOYEE DASHBOARD", isHighlighted: true, onTap: () => context.push('/coa-employee-dashboard')),
        ],
        if (profile.isSuperadmin) ...[
          _buildPremiumItem(context, LucideIcons.zap, "SUPERADMIN CONSOLE", isHighlighted: true, onTap: () => context.push('/superadmin-hub')),
        ],
        if (profile.role == 'vendor' || profile.role == 'merchant') ...[
          _buildPremiumItem(context, LucideIcons.store, "VENDOR DASHBOARD", isHighlighted: true, onTap: () => context.push('/vendor-dashboard')),
        ],
        if (profile.isBookshopStaff) ...[
          _buildPremiumItem(context, LucideIcons.bookOpen, "BOOKSHOP DASHBOARD", isHighlighted: true, onTap: () => context.push('/bookshop-dashboard')),
        ],
        if (profile.role == 'bookshop_owner')
          _buildPremiumItem(context, LucideIcons.store, "Set Up Bookshop", onTap: () => context.push('/bookshop-onboarding')),
      ],
    );
  }

  Widget _buildAccountList(BuildContext context, WidgetRef ref, UserProfile profile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildGroupHeader(context, "PROFILE & IDENTITY"),
        _buildPremiumItem(context, LucideIcons.user, "Personal Information", onTap: () => context.push('/account-settings')),
        _buildPremiumItem(context, LucideIcons.shield, "Security & Privacy", onTap: () => _showSecuritySettings(context)),
        _buildPremiumItem(context, LucideIcons.fileCheck, "KYC Verification", trailing: "UNVERIFIED", onTap: () => context.push('/kyc-verification')),
        if (!profile.isVerified)
          _buildPremiumItem(context, LucideIcons.badgeCheck, "Request Verification", onTap: () => context.push('/request-verification')),
        _buildPremiumItem(context, LucideIcons.trendingUp, "Role Onboarding", onTap: () => context.push('/onboarding/${profile.role}')),
        if (profile.role != 'writer')
          _buildPremiumItem(context, LucideIcons.penTool, "Apply as Writer", onTap: () => context.push('/apply-writer')),
        const SizedBox(height: 8),
        _buildGroupHeader(context, "PAYMENTS & ORDERS"),
        if (profile.isAdminOrHigher)
          _buildPremiumItem(context, LucideIcons.crown, "My Subscription", onTap: () => context.push('/subscription')),
        _buildPremiumItem(context, LucideIcons.package, "My Orders", onTap: () => context.push('/orders')),
        _buildPremiumItem(context, LucideIcons.gift, "Referral Program", onTap: () => context.push('/referral-program')),
        _buildPremiumItem(context, LucideIcons.heart, "COA Missions Donate", onTap: () => context.push('/missions-donate')),
        const SizedBox(height: 8),
        _buildGroupHeader(context, "COMMUNITY & SUPPORT"),
        _buildPremiumItem(context, LucideIcons.bell, "Notification Preferences", onTap: () => context.push('/notification-preferences')),
        _buildPremiumItem(context, LucideIcons.lightbulb, "Request a Feature", onTap: () => context.push('/feature-request')),
        _buildPremiumItem(context, LucideIcons.church, "Can't Find Your Church?", onTap: () => context.push('/refer-church')),
        _buildPremiumItem(context, LucideIcons.helpCircle, "Help & Support", onTap: () => context.push('/support')),
        _buildPremiumItem(context, LucideIcons.star, "Rate the App", onTap: () => RatingService.openStoreListing()),
        _buildPremiumItem(context, LucideIcons.logOut, "Logout", isDestructive: true, onTap: () => _showLogoutConfirmation(context, ref)),
      ],
    );
  }

  Widget _buildGroupHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12, top: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 2,
          color: Theme.of(context).primaryColor.withValues(alpha: 0.8),
        ),
      ),
    );
  }

  Widget _buildActivityCard(BuildContext context, WidgetRef ref) {
    final txAsync = ref.watch(transactionsStreamProvider);
    final scheme = Theme.of(context).colorScheme;
    final (icon, label) = txAsync.when(
      data: (txs) {
        final completed = txs.where((t) => t.status == 'completed').toList();
        return (completed, "RECENT ACTIVITY");
      },
      loading: () => (const <Transaction>[], "RECENT ACTIVITY"),
      error: (e, st) => (const <Transaction>[], "RECENT ACTIVITY"),
    );
    final txs = icon;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.activity, size: 16, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (txs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                "No giving yet — start your giving journey from the Give tab.",
                style: TextStyle(
                  color: scheme.onSurface.withValues(alpha: 0.45),
                  fontSize: 12,
                ),
              ),
            )
          else
            ...txs.take(4).map((t) {
              final (tIcon, tColor) = _activityStyle(t.category);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: tColor.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(tIcon, color: tColor, size: 15),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _capitalize(t.category),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            "${_relativeDate(t.createdAt)} · ${t.reference.isEmpty ? 'CoA' : t.reference}",
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurface.withValues(alpha: 0.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      "+${formatKwacha(t.amount)}",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
              );
            }),
          const Divider(height: 8),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => context.push('/giving-history'),
            child: Row(
              children: [
                Text(
                  "VIEW ALL HISTORY",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(LucideIcons.chevronRight, size: 14, color: scheme.primary),
              ],
            ),
          ),
        ],
      ),
    );
  }

  (IconData, Color) _activityStyle(String category) {
    final brand = Theme.of(context).primaryColor;
    switch (category.toLowerCase()) {
      case 'tithe':
        return (LucideIcons.scrollText, brand);
      case 'offering':
        return (LucideIcons.heartHandshake, Colors.green);
      case 'mission':
        return (LucideIcons.globe, brand.withValues(alpha: 0.8));
      case 'building fund':
        return (LucideIcons.building2, brand.withValues(alpha: 0.6));
      default:
        return (LucideIcons.banknote, brand.withValues(alpha: 0.45));
    }
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  String _relativeDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return '$diff days ago';
  }

  Widget _buildPremiumItem(BuildContext context, IconData icon, String title, {bool isDestructive = false, bool isHighlighted = false, String? trailing, VoidCallback? onTap}) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isHighlighted ? scheme.primary.withValues(alpha: 0.08) : scheme.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: isHighlighted ? scheme.primary.withValues(alpha: 0.3) : scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Icon(icon, color: isDestructive ? scheme.error : (isHighlighted ? scheme.primary : scheme.onSurface.withValues(alpha: 0.7)), size: 20),
            const SizedBox(width: 16),
            Expanded(
              child: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isDestructive ? scheme.error : scheme.onSurface)),
            ),
            if (trailing != null)
              Text(trailing, style: TextStyle(color: scheme.primary, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1))
            else
              Icon(LucideIcons.chevronRight, size: 16, color: scheme.onSurface.withValues(alpha: 0.15)),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkModeToggle(BuildContext context, WidgetRef ref, UserProfile profile) {
    final mode = profile.isWorkMode;
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => ref.read(profileProvider.notifier).toggleWorkMode(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: mode ? Colors.green.withValues(alpha: 0.1) : scheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: mode ? Colors.green.withValues(alpha: 0.4) : scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Column(
          children: [
            Icon(mode ? LucideIcons.zap : LucideIcons.zapOff, color: mode ? Colors.green : scheme.onSurface.withValues(alpha: 0.3), size: 22),
            const SizedBox(height: 6),
            Text(mode ? "ON DUTY" : "OFF DUTY", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: mode ? Colors.green : scheme.onSurface.withValues(alpha: 0.3))),
            if (mode) ...[
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const DriverPortalScreen())),
                style: ElevatedButton.styleFrom(
                  backgroundColor: scheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("COMMAND", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.black)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAssetGrid(BuildContext context, WidgetRef ref) {
    final assets = [
      {"icon": LucideIcons.book, "title": "My Library", "count": "Digital books & content", "action": "library"},
      {"icon": LucideIcons.award, "title": "Certificates", "count": "Faith milestones", "action": "certs"},
      {"icon": LucideIcons.gift, "title": "Rewards", "count": "Coins & achievements", "action": "rewards"},
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = (constraints.maxWidth / 300).floor().clamp(2, 3);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 1.2),
          itemCount: assets.length,
          itemBuilder: (context, index) {
            return GestureDetector(
              onTap: () {
                final action = assets[index]['action'] as String;
                switch (action) {
                  case 'library':
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const MyLibraryScreen()));
                    break;
                  case 'events':
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const EventsScreen()));
                    break;
                  case 'rewards':
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const RewardsScreen()));
                    break;
                  case 'certs':
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const CertificatesScreen()));
                    break;
                }
              },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(assets[index]['icon'] as IconData, color: Theme.of(context).primaryColor, size: 24),
                const SizedBox(height: 10),
                Text(assets[index]['title'] as String, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Theme.of(context).colorScheme.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(assets[index]['count'] as String, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4), fontSize: 11, height: 1.3), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        );
          },
        );
      },
    );
  }

  Widget _buildFaithDashboard(BuildContext context, UserProfile profile, WidgetRef ref) {
    final quizRankAsync = ref.watch(myQuizRankProvider);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(32),
      ),
      child: Column(
        children: [
          Wrap(
            spacing: 18,
            runSpacing: 18,
            alignment: WrapAlignment.center,
            children: [
              _buildDashboardMetric(context, "Church", (profile.tenantId ?? '').isNotEmpty ? 'Active' : '--', LucideIcons.building, Theme.of(context).primaryColor),
              _buildDashboardMetric(context, "Streak", "${profile.streakCount}d", LucideIcons.flame, Colors.orange),
              quizRankAsync.when(
                data: (rank) => _buildDashboardMetric(context, "Quiz Rank", rank, LucideIcons.trophy, Theme.of(context).primaryColor),
                loading: () => _buildDashboardMetric(context, "Quiz Rank", "#--", LucideIcons.trophy, Theme.of(context).primaryColor),
                error: (e, st) => _buildDashboardMetric(context, "Quiz Rank", "#--", LucideIcons.trophy, Theme.of(context).primaryColor),
              ),
              _buildDashboardMetric(context, "Tokens", "${profile.coins}", LucideIcons.zap, Theme.of(context).primaryColor.withValues(alpha: 0.7)),
              _buildDashboardMetric(context, "Giving", "K${profile.balanceZmw.toInt()}", LucideIcons.banknote, Colors.greenAccent),
            ],
          ),
          const SizedBox(height: 32),
          _GrowthIndexChart(),
          const SizedBox(height: 16),
          Text("SPIRITUAL GROWTH INDEX", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5), letterSpacing: 3)),
          const SizedBox(height: 24),
          const SpiritualPredictorCard(),
        ],
      ),
    );
  }

  Widget _buildDashboardMetric(BuildContext context, String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Theme.of(context).colorScheme.onSurface)),
        Text(label.toUpperCase(), style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5), fontWeight: FontWeight.bold, letterSpacing: 1)),
      ],
    );
  }

  Widget _buildCredentialsRow(UserProfile profile) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          // Role badges — most-specific first; apostle must not render as BISHOP.
          if (profile.role == 'apostle')
            _buildBadge(LucideIcons.globe, "APOSTLE", Colors.deepPurple)
          else if (profile.role == 'bishop')
            _buildBadge(LucideIcons.crown, "BISHOP", Colors.amber)
          else if (profile.isPastor)
            _buildBadge(LucideIcons.scroll, "PASTOR", Theme.of(context).primaryColor),
          if (profile.role == 'treasurer' || profile.role == 'general_treasurer')
            _buildBadge(LucideIcons.wallet, "TREASURER", Colors.green),
          if (profile.role == 'driver') _buildBadge(LucideIcons.car, "DRIVER", Colors.teal),
          if (profile.role == 'rider') _buildBadge(LucideIcons.bike, "RIDER", Colors.cyan),
          if (profile.role == 'vendor' || profile.role == 'merchant')
            _buildBadge(LucideIcons.store, "VENDOR", Colors.indigo),
          if (profile.isBookshopStaff)
            _buildBadge(LucideIcons.bookOpen, "BOOKSHOP", Colors.blue),
          if (profile.isUsher) _buildBadge(LucideIcons.shieldCheck, "USHER", Colors.greenAccent),
          if (profile.role == 'writer') _buildBadge(LucideIcons.penTool, "WRITER", Theme.of(context).primaryColor.withValues(alpha: 0.7)),
          if (profile.isSuperadmin) _buildBadge(LucideIcons.zap, "COA TEAM", Colors.redAccent),
          if (profile.coins > 1000) _buildBadge(LucideIcons.star, "STEWARD", Colors.orangeAccent),
        ],
      ),
    );
  }

  Widget _buildBadge(IconData icon, String label, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
        ],
      ),
    );
  }

  void _showLogoutConfirmation(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text("SIGN OUT?", style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w900)),
        content: Text("Are you sure you want to exit your session?", style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6))),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text("CANCEL", style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.3)))),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await ref.read(authProvider.notifier).signOut();
            },
            style: ElevatedButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError),
            child: const Text("LOGOUT"),
          ),
        ],
      ),
    );
  }

  void _showSecuritySettings(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("SECURITY", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: scheme.onSurface, letterSpacing: 2)),
            const SizedBox(height: 24),
            _buildActionItem(LucideIcons.lock, "Change Password", onTap: () {
              Navigator.pop(context);
              _showChangePasswordDialog(context);
            }),
            _buildActionItem(LucideIcons.smartphone, "Two-Factor Auth", onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const TwoFactorSetupScreen()));
            }),
            _buildActionItem(LucideIcons.eye, "Privacy Mode", onTap: () {
              Navigator.pop(context);
              _showPrivacyModeDialog(context);
            }),
            _buildActionItem(LucideIcons.shield, "Full Security Dashboard", onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SecurityScreen()));
            }),
            _buildActionItem(LucideIcons.camera, "Camera Settings", onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const CameraSettingsScreen()));
            }),
            _buildActionItem(LucideIcons.phone, "Emergency Contacts", onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const EmergencyContactsScreen()));
            }),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const _ChangePasswordDialog(),
    );
  }

  void _showPrivacyModeDialog(BuildContext context) {
    final profileAsync = ref.read(profileProvider);
    final currentPrivacy = profileAsync.value?.isWorkMode ?? false;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final scheme = Theme.of(context).colorScheme;
          return AlertDialog(
            backgroundColor: scheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
            title: Text("Privacy Mode", style: TextStyle(color: scheme.onSurface)),
            content: SwitchListTile(
              title: Text("Go Anonymous", style: TextStyle(color: scheme.onSurface, fontSize: 14)),
              subtitle: Text("Hide your presence status in communities", style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5), fontSize: 11)),
              activeThumbColor: scheme.primary,
              value: currentPrivacy,
              onChanged: (val) async {
                try {
                  final user = Supabase.instance.client.auth.currentUser;
                  if (user == null) return;
                  await Supabase.instance.client.from('profiles').update({
                    'is_work_mode': val,
                  }).eq('id', user.id);
                  ref.invalidate(profileProvider);
                  setDialogState(() {});
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(val ? "Presence set to Anonymous!" : "Presence set to Public!"),
                      backgroundColor: val ? Theme.of(context).primaryColor : Colors.grey,
                    ));
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text("Failed to update: $e"), backgroundColor: Colors.red,
                    ));
                  }
                }
              },
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text("CLOSE", style: TextStyle(color: scheme.primary))),
            ],
          );
        }
      ),
    );
  }

  Widget _buildActionItem(IconData icon, String title, {VoidCallback? onTap}) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: scheme.onSurface.withValues(alpha: 0.7)),
      title: Text(title, style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.bold)),
      trailing: Icon(LucideIcons.chevronRight, color: scheme.onSurface.withValues(alpha: 0.15)),
      onTap: onTap,
    );
  }

  void _pickAvatar(BuildContext context, WidgetRef ref, UserProfile profile) async {
    try {
      final r2 = R2Service(Supabase.instance.client);
      final url = await r2.uploadAvatar(ImageSource.gallery);
      if (url == null) return;

      ref.invalidate(profileProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Profile picture updated!"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to update: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _passwordCtrl = TextEditingController();

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      backgroundColor: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
      title: Text("Change Password", style: TextStyle(color: scheme.onSurface)),
      content: TextField(
        controller: _passwordCtrl,
        obscureText: true,
        style: TextStyle(color: scheme.onSurface),
        decoration: InputDecoration(
          hintText: "Enter new password...",
          hintStyle: TextStyle(color: scheme.onSurface.withValues(alpha: 0.3)),
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: scheme.onSurface.withValues(alpha: 0.24))),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text("CANCEL", style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.3)))),
        ElevatedButton(
          onPressed: () async {
            if (_passwordCtrl.text.length < 6) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Password must be at least 6 characters"), backgroundColor: Colors.red));
              return;
            }
            try {
              await Supabase.instance.client.auth.updateUser(UserAttributes(password: _passwordCtrl.text));
              if (!context.mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Password updated successfully!"), backgroundColor: Colors.green));
            } catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
            }
          },
          style: ElevatedButton.styleFrom(backgroundColor: scheme.primary, foregroundColor: scheme.onPrimary),
          child: const Text("UPDATE"),
        ),
      ],
    );
  }
}

/// Real 7-day spiritual engagement line (notes + quiz + attendance per day)
/// from `PredictionService` — replaces the old hardcoded fake FlSpots.
/// Renders an honest empty state when there is no activity yet.
class _GrowthIndexChart extends ConsumerWidget {
  const _GrowthIndexChart();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final predictionAsync = ref.watch(spiritualPredictionProvider);

    return predictionAsync.when(
      data: (prediction) {
        final series = prediction.weeklyEngagement;
        final hasData = series.any((v) => v > 0);
        if (!hasData) {
          return SizedBox(
            height: 120,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.show_chart, size: 28, color: theme.primaryColor.withValues(alpha: 0.25)),
                  const SizedBox(height: 8),
                  Text(
                    'Read a chapter or join a quiz to start your growth line',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.45), fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          );
        }
        final spots = List<FlSpot>.generate(series.length, (i) => FlSpot(i.toDouble(), series[i]));
        return SizedBox(
          height: 120,
          child: LineChart(
            LineChartData(
              gridData: const FlGridData(show: false),
              titlesData: const FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
              minY: 0,
              maxY: (series.fold<double>(0, (m, v) => v > m ? v : m) + 1).clamp(3, 20),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  curveSmoothness: 0.25,
                  color: theme.primaryColor,
                  barWidth: 3,
                  isStrokeCapRound: true,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (s, p, b, i) => FlDotCirclePainter(radius: 2.6, color: theme.primaryColor, strokeWidth: 0),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      colors: [theme.primaryColor.withValues(alpha: 0.16), theme.primaryColor.withValues(alpha: 0.0)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ],
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => const Color(0xFF0F172A),
                  getTooltipItems: (touched) => touched.map((t) {
                    const days = ['6d ago', '5d ago', '4d ago', '3d ago', '2d ago', 'Yesterday', 'Today'];
                    final label = (t.x.toInt() >= 0 && t.x.toInt() < days.length) ? days[t.x.toInt()] : '';
                    return LineTooltipItem(
                      '$label • ${t.y.toStringAsFixed(0)} activities',
                      const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11),
                    );
                  }).toList(),
                ),
              ),
            ),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
          ),
        );
      },
      loading: () => SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: theme.primaryColor)),
      ),
      error: (_, __) => SizedBox(
        height: 120,
        child: Center(child: Icon(Icons.show_chart, size: 28, color: theme.colorScheme.onSurface.withValues(alpha: 0.15))),
      ),
    );
  }
}
