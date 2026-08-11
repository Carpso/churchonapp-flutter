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
import '../../auth/presentation/two_factor_setup_screen.dart';
import '../../../core/services/coins_service.dart';
import '../../../core/services/r2_service.dart';
import '../../connect/data/user_activity_service.dart';
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
            _buildWalletAction(context, canCollect ? LucideIcons.coins : LucideIcons.checkCircle, canCollect ? "COLLECT" : "DONE", () async {
              if (!canCollect) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Already collected today! Come back tomorrow."), backgroundColor: Colors.orange));
                }
                return;
              }
              final service = ref.read(coinsServiceProvider);
              final activity = ref.read(userActivityServiceProvider);
              final earned = await service.collectDailyCoins();
              if (earned > 0) {
                await activity.logActivity(type: ActivityType.coinCollected, description: "Daily coin reward", coinsEarned: earned);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("+$earned coins collected!"), backgroundColor: Colors.green));
                }
              }
            }),
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
        _buildPremiumItem(context, LucideIcons.plusCircle, "Register Your Church", isHighlighted: true, onTap: () => context.push('/register-church')),
        if (profile.isExecutiveOffice) ...[
          _buildPremiumItem(context, LucideIcons.crown, "BISHOP COMMAND HUB", isHighlighted: true, onTap: () => context.push('/bishop-hub')),
        ],
        _buildPremiumItem(context, LucideIcons.calendar, "Yearly Program Planner", onTap: () => context.push('/year-planner')),
        if (profile.isPastor) ...[
          _buildPremiumItem(context, LucideIcons.layoutDashboard, "Pastor Dashboard", isHighlighted: true, onTap: () => context.push('/pastor-dashboard')),
          _buildPremiumItem(context, LucideIcons.clipboardCheck, "Submit Report to Bishop", onTap: () => context.push('/pastor-bishop-report')),
        ],
        if (profile.isLedgerManager) ...[
          _buildPremiumItem(context, LucideIcons.qrCode, "Scan Attendance", onTap: () => context.push('/attendance-scanner')),
          _buildPremiumItem(context, LucideIcons.barChart3, "Ministry Reports", onTap: () => context.push('/service-report')),
          _buildPremiumItem(context, LucideIcons.bookOpen, "Financial Ledger", onTap: () => context.push('/ledger')),
        ],
        if (profile.isAdminOrHigher) ...[
          _buildPremiumItem(context, LucideIcons.settings, "SYSTEM ADMIN HUB", onTap: () => context.push('/admin-hub')),
        ],
        if (profile.role == 'apostle') ...[
          _buildPremiumItem(context, LucideIcons.globe, "APOSTLE DASHBOARD", isHighlighted: true, onTap: () => context.push('/apostle-dashboard')),
        ],
        if (profile.isSuperadmin) ...[
          _buildPremiumItem(context, LucideIcons.zap, "SUPERADMIN CONSOLE", isHighlighted: true, onTap: () => context.push('/superadmin-hub')),
        ],
        if (profile.role == 'vendor' || profile.role == 'merchant' || profile.role == 'bookshop_owner') ...[
          _buildPremiumItem(context, LucideIcons.store, "VENDOR DASHBOARD", isHighlighted: true, onTap: () => context.push('/vendor-dashboard')),
        ],
        if (profile.role == 'bookshop_owner')
          _buildPremiumItem(context, LucideIcons.store, "Set Up Bookshop", onTap: () => context.push('/bookshop-onboarding')),
      ],
    );
  }

  Widget _buildAccountList(BuildContext context, WidgetRef ref, UserProfile profile) {
    return Column(
      children: [
        _buildPremiumItem(context, LucideIcons.user, "Personal Information", onTap: () => context.push('/account-settings')),
        _buildPremiumItem(context, LucideIcons.shield, "Security & Privacy", onTap: () => _showSecuritySettings(context)),
        _buildPremiumItem(context, LucideIcons.fileCheck, "KYC Verification", trailing: "UNVERIFIED", onTap: () => context.push('/kyc-verification')),
        if (!profile.isVerified)
          _buildPremiumItem(context, LucideIcons.badgeCheck, "Request Verification", isHighlighted: true, onTap: () => context.push('/request-verification')),
        _buildPremiumItem(context, LucideIcons.trendingUp, "Role Onboarding", onTap: () => context.push('/onboarding/${profile.role}')),
        if (profile.role != 'writer')
          _buildPremiumItem(context, LucideIcons.penTool, "Apply as Writer", onTap: () => context.push('/apply-writer')),
        _buildPremiumItem(context, LucideIcons.package, "My Orders", onTap: () => context.push('/orders')),
        _buildPremiumItem(context, LucideIcons.gift, "Referral Program", onTap: () => context.push('/referral-program')),
        _buildPremiumItem(context, LucideIcons.church, "Can't Find Your Church?", onTap: () => context.push('/refer-church')),
        _buildPremiumItem(context, LucideIcons.heart, "COA Missions Donate", isHighlighted: true, onTap: () => context.push('/missions-donate')),
        _buildPremiumItem(context, LucideIcons.helpCircle, "Help & Support", onTap: () => context.push('/support')),
        _buildPremiumItem(context, LucideIcons.logOut, "Logout", isDestructive: true, onTap: () => _showLogoutConfirmation(context, ref)),
      ],
    );
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

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 1.2),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildDashboardMetric(context, "Church", (profile.tenantId ?? '').isNotEmpty ? 'Active' : '--', LucideIcons.building, Colors.blueAccent),
              quizRankAsync.when(
                data: (rank) => _buildDashboardMetric(context, "Quiz Rank", rank, LucideIcons.trophy, Colors.amber),
                loading: () => _buildDashboardMetric(context, "Quiz Rank", "#--", LucideIcons.trophy, Colors.amber),
                error: (e, st) => _buildDashboardMetric(context, "Quiz Rank", "#--", LucideIcons.trophy, Colors.amber),
              ),
              _buildDashboardMetric(context, "Tokens", "${profile.coins}", LucideIcons.zap, Colors.purpleAccent),
            ],
          ),
          const SizedBox(height: 32),
          SizedBox(
            height: 120,
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: [
                      const FlSpot(0, 3), const FlSpot(1, 1), const FlSpot(2, 4), const FlSpot(3, 2), const FlSpot(4, 5), const FlSpot(5, 3), const FlSpot(6, 4),
                    ],
                    isCurved: true,
                    color: Theme.of(context).primaryColor,
                    barWidth: 4,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(show: true, color: Theme.of(context).primaryColor.withValues(alpha: 0.1)),
                  ),
                ],
              ),
            ),
          ),
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
          if (profile.isBishop) _buildBadge(LucideIcons.crown, "BISHOP", Colors.amber),
          if (profile.isPastor) _buildBadge(LucideIcons.scroll, "PASTOR", Colors.blueAccent),
          if (profile.isUsher) _buildBadge(LucideIcons.shieldCheck, "USHER", Colors.greenAccent),
          if (profile.role == 'writer') _buildBadge(LucideIcons.penTool, "WRITER", Colors.purpleAccent),
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

  // ignore: unused_element
  void _showComingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("$feature — Coming Soon!"), backgroundColor: Colors.amber, duration: const Duration(seconds: 2)),
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
                      backgroundColor: val ? Colors.indigo : Colors.grey,
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
