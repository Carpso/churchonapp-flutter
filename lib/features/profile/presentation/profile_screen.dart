import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/widgets/qr_code_with_logo.dart';
import '../../finance/presentation/giving_screen.dart';
import '../../finance/presentation/giving_history_screen.dart';
import '../../marketplace/presentation/my_library_screen.dart';
import 'referral_system_screen.dart';
import 'package:church_on_app/features/admin/presentation/admin_hub_screen.dart';
import 'account_settings_screen.dart';
import 'kyc_verification_screen.dart';
import 'package:church_on_app/features/admin/presentation/superadmin_hub_screen.dart';
import '../../auth/presentation/register_church_screen.dart';
import 'package:church_on_app/features/admin/presentation/service_report_screen.dart';
import 'package:church_on_app/features/admin/presentation/ledger_screen.dart';
import 'package:church_on_app/features/admin/presentation/bishop_hub_screen.dart';
import 'package:church_on_app/features/admin/presentation/year_planner_screen.dart';
import 'package:church_on_app/features/admin/presentation/pastor_bishop_report_screen.dart';
import 'package:church_on_app/features/admin/presentation/attendance_scanner_screen.dart';
import '../../modules/events/presentation/events_screen.dart';
import '../../connect/presentation/prayer_wall_screen.dart';
import '../../support/presentation/support_hub_screen.dart';

import '../../../core/providers/profile_provider.dart';
import '../../../core/providers/auth_provider.dart';
import '../../auth/presentation/login_screen.dart';
import '../../auth/presentation/two_factor_setup_screen.dart';
import '../../../core/services/coins_service.dart';
import '../../../core/services/r2_service.dart';
import '../../connect/data/user_activity_service.dart';
import '../../modules/bible_quiz/data/bible_quiz_service.dart';
import '../../transport/presentation/driver_portal_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'security_screen.dart';
import 'role_onboarding_screen.dart';
import 'writer_application_screen.dart';
import 'church_referral_screen.dart';
import 'package:church_on_app/features/admin/presentation/order_tracking_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);
    final tenant = ref.watch(currentTenantProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F), // Deep premium black
      body: profileAsync.when(
        data: (profile) {
          if (profile == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(LucideIcons.userX, size: 80, color: Colors.white24),
                  const SizedBox(height: 24),
                  const Text("PROFILE NOT FOUND", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white, letterSpacing: 1.5)),
                  const SizedBox(height: 12),
                  const Text("Please sign in to access your Kingdom account.", style: TextStyle(color: Colors.white38, fontSize: 13)),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD700),
                      foregroundColor: Colors.black,
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
                      _buildSectionHeader(context, "ACCOUNT & TRUST"),
                      _buildAccountList(context, ref, profile),
                      const SizedBox(height: 40),
                      _buildSectionHeader(context, "DIGITAL ASSETS"),
                      _buildAssetGrid(context, ref),
                      const SizedBox(height: 120),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: Colors.amber)),
        error: (e, st) => Center(child: Text("Error: $e", style: const TextStyle(color: Colors.red))),
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
                            backgroundImage: NetworkImage(profile.avatarUrl ?? "https://i.pravatar.cc/300?u=${profile.id}"),
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
                          child: const Icon(Icons.verified, color: Colors.black, size: 20),
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
                        const Icon(Icons.verified, color: Color(0xFFFFD700), size: 22),
                      ],
                    ],
                  ),
                ),
                Text(tenant?.name ?? "Global Member", style: const TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                  ),
                  child: Text(profile.role.toUpperCase(), style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 2)),
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
    final String safeId = profile.id.length >= 8 ? profile.id.substring(0, 8).toUpperCase() : profile.id.toUpperCase();
    final walletId = "COA-$safeId";

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("KINGDOM WALLET", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white24, letterSpacing: 2)),
                    const SizedBox(height: 8),
                    Text("$coins CC", style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.amber)),
                    const SizedBox(height: 4),
                    Text(walletId, style: const TextStyle(fontSize: 11, color: Colors.white10, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              if (profile.canWork) _buildWorkModeToggle(context, ref, profile),
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                child: QrCodeWithLogo(
                  data: profile.id,
                  size: 50,
                  logoSize: 14,
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildWalletAction(context, LucideIcons.send, "GIVE", () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GivingScreen()))),
        _buildWalletAction(context, LucideIcons.history, "RECORDS", () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GivingHistoryScreen()))),
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
        _buildWalletAction(context, LucideIcons.gift, "REWARDS", () => _showRewardsDialog(context, profile)),
        _buildWalletAction(context, LucideIcons.shieldCheck, "IDENTITY", () => Navigator.push(context, MaterialPageRoute(builder: (_) => const KycVerificationScreen()))),
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
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white38, letterSpacing: 1)),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20.0),
      child: Row(
        children: [
          Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white70, letterSpacing: 2.5)),
          const Spacer(),
          const Icon(LucideIcons.chevronRight, size: 14, color: Colors.white24),
        ],
      ),
    );
  }

  Widget _buildMinistryActions(BuildContext context, WidgetRef ref, UserProfile profile, Tenant? tenant) {
    return Column(
      children: [
        _buildPremiumItem(context, LucideIcons.plusCircle, "Register Your Church", isHighlighted: true, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterChurchScreen()))),
        if (profile.isExecutiveOffice) ...[
          _buildPremiumItem(context, LucideIcons.crown, "BISHOP COMMAND HUB", isHighlighted: true, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BishopHubScreen()))),
        ],
        _buildPremiumItem(context, LucideIcons.calendar, "Yearly Program Planner", onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const YearPlannerScreen()))),
        if (profile.isPastor) ...[
          _buildPremiumItem(context, LucideIcons.clipboardCheck, "Submit Report to Bishop", onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PastorBishopReportScreen()))),
        ],
        if (profile.isLedgerManager) ...[
          _buildPremiumItem(context, LucideIcons.qrCode, "Scan Attendance", onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AttendanceScannerScreen()))),
          _buildPremiumItem(context, LucideIcons.barChart3, "Ministry Reports", onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ServiceReportScreen()))),
          _buildPremiumItem(context, LucideIcons.bookOpen, "Financial Ledger", onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LedgerScreen()))),
        ],
        if (profile.isAdminOrHigher) ...[
          _buildPremiumItem(context, LucideIcons.settings, "SYSTEM ADMIN HUB", onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminHubScreen()))),
        ],
        if (profile.isSuperadmin) ...[
          _buildPremiumItem(context, LucideIcons.zap, "SUPERADMIN CONSOLE", isHighlighted: true, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SuperadminHubScreen()))),
        ],
      ],
    );
  }

  Widget _buildAccountList(BuildContext context, WidgetRef ref, UserProfile profile) {
    return Column(
      children: [
        _buildPremiumItem(context, LucideIcons.user, "Personal Information", onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountSettingsScreen()))),
        _buildPremiumItem(context, LucideIcons.shield, "Security & Privacy", onTap: () => _showSecuritySettings(context)),
        _buildPremiumItem(context, LucideIcons.fileCheck, "KYC Verification", trailing: "UNVERIFIED", onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const KycVerificationScreen()))),
        _buildPremiumItem(context, LucideIcons.trendingUp, "Role Onboarding", onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RoleOnboardingScreen(role: profile.role)))),
        if (profile.role != 'writer')
          _buildPremiumItem(context, LucideIcons.penTool, "Apply as Writer", onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WriterApplicationScreen()))),
        _buildPremiumItem(context, LucideIcons.package, "My Orders", onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OrderTrackingScreen()))),
        _buildPremiumItem(context, LucideIcons.gift, "Referral Program", onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReferralSystemScreen()))),
        _buildPremiumItem(context, LucideIcons.church, "Can't Find Your Church?", onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChurchReferralScreen()))),
        _buildPremiumItem(context, LucideIcons.helpCircle, "Help & Support", onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportHubScreen()))),
        _buildPremiumItem(context, LucideIcons.logOut, "Logout", isDestructive: true, onTap: () => _showLogoutConfirmation(context, ref)),
      ],
    );
  }

  Widget _buildPremiumItem(BuildContext context, IconData icon, String title, {bool isDestructive = false, bool isHighlighted = false, String? trailing, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isHighlighted ? Colors.amber.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: isHighlighted ? Colors.amber.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05)),
        ),
        child: Row(
          children: [
            Icon(icon, color: isDestructive ? Colors.redAccent : (isHighlighted ? Colors.amber : Colors.white70), size: 20),
            const SizedBox(width: 16),
            Expanded(
              child: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isDestructive ? Colors.redAccent : Colors.white)),
            ),
            if (trailing != null) 
              Text(trailing, style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1))
            else
              const Icon(LucideIcons.chevronRight, size: 16, color: Colors.white12),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkModeToggle(BuildContext context, WidgetRef ref, UserProfile profile) {
    final mode = profile.isWorkMode;
    return GestureDetector(
      onTap: () => ref.read(profileProvider.notifier).toggleWorkMode(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: mode ? Colors.green.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: mode ? Colors.green.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.1)),
        ),
        child: Column(
          children: [
            Icon(mode ? LucideIcons.zap : LucideIcons.zapOff, color: mode ? Colors.green : Colors.white24, size: 22),
            const SizedBox(height: 6),
            Text(mode ? "ON DUTY" : "OFF DUTY", style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: mode ? Colors.green : Colors.white24)),
            if (mode) ...[
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const DriverPortalScreen())),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("COMMAND", style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.black)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAssetGrid(BuildContext context, WidgetRef ref) {
    final assets = [
      {"icon": LucideIcons.book, "title": "My Library", "count": "156 items", "action": "library"},
      {"icon": LucideIcons.calendar, "title": "Events", "count": "3 upcoming", "action": "events"},
      {"icon": LucideIcons.flame, "title": "Prayer Wall", "count": "12 entries", "action": "prayer"},
      {"icon": LucideIcons.award, "title": "Certificates", "count": "4 earned", "action": "certs"},
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 1.5),
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
              case 'prayer':
                Navigator.push(context, MaterialPageRoute(builder: (_) => const PrayerWallScreen()));
                break;
              case 'certs':
                _showCertificatesDialog(context);
                break;
            }
          },
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(assets[index]['icon'] as IconData, color: Colors.amber, size: 24),
                const SizedBox(height: 12),
                Text(assets[index]['title'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                Text(assets[index]['count'] as String, style: const TextStyle(color: Colors.white38, fontSize: 10)),
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
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(32),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildDashboardMetric("Attendance", "85%", LucideIcons.calendarCheck, Colors.blueAccent),
              quizRankAsync.when(
                data: (rank) => _buildDashboardMetric("Quiz Rank", rank, LucideIcons.trophy, Colors.amber),
                loading: () => _buildDashboardMetric("Quiz Rank", "#--", LucideIcons.trophy, Colors.amber),
                error: (e, st) => _buildDashboardMetric("Quiz Rank", "#--", LucideIcons.trophy, Colors.amber),
              ),
              _buildDashboardMetric("Tokens", "${profile.coins}", LucideIcons.zap, Colors.purpleAccent),
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
                    color: Colors.amber,
                    barWidth: 4,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(show: true, color: Colors.amber.withValues(alpha: 0.1)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text("SPIRITUAL GROWTH INDEX", style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.white10, letterSpacing: 3)),
        ],
      ),
    );
  }

  Widget _buildDashboardMetric(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.white)),
        Text(label.toUpperCase(), style: const TextStyle(fontSize: 8, color: Colors.white24, fontWeight: FontWeight.bold, letterSpacing: 1)),
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
          Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
        ],
      ),
    );
  }

  void _showLogoutConfirmation(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: const Text("SIGN OUT?", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        content: const Text("Are you sure you want to exit your session?", style: TextStyle(color: Colors.white60)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL", style: TextStyle(color: Colors.white24))),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(authProvider.notifier).signOut();
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
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

  void _showRewardsDialog(BuildContext context, UserProfile profile) {
    showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
          title: const Row(children: [Icon(LucideIcons.gift, color: Colors.amber), SizedBox(width: 10), Text("Kingdom Rewards", style: TextStyle(color: Colors.white))]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(leading: Icon(LucideIcons.star, color: Colors.amber), title: Text("Welcome Bonus", style: TextStyle(color: Colors.white)), subtitle: Text("500 Kingdom Coins", style: TextStyle(color: Colors.white38)), dense: true),
              ListTile(leading: const Icon(LucideIcons.flame, color: Colors.red), title: Text("${profile.streakCount}-Day Streak", style: const TextStyle(color: Colors.white)), subtitle: const Text("100 Kingdom Coins", style: TextStyle(color: Colors.white38)), dense: true),
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text("CLOSE"))],
        ));
  }

  void _showSecuritySettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("SECURITY", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 2)),
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
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
    final passwordCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: const Text("Change Password", style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: passwordCtrl,
          obscureText: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "Enter new password...",
            hintStyle: TextStyle(color: Colors.white30),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL", style: TextStyle(color: Colors.white24))),
          ElevatedButton(
            onPressed: () async {
              if (passwordCtrl.text.length < 6) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Password must be at least 6 characters"), backgroundColor: Colors.red));
                return;
              }
              try {
                await Supabase.instance.client.auth.updateUser(UserAttributes(password: passwordCtrl.text));
                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Password updated successfully!"), backgroundColor: Colors.green));
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
            child: const Text("UPDATE"),
          ),
        ],
      ),
    );
  }

  void _showPrivacyModeDialog(BuildContext context) {
    bool isPrivacyEnabled = false;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
            title: const Text("Privacy Mode", style: TextStyle(color: Colors.white)),
            content: SwitchListTile(
              title: const Text("Go Anonymous", style: TextStyle(color: Colors.white, fontSize: 14)),
              subtitle: const Text("Hide your presence status in communities", style: TextStyle(color: Colors.white54, fontSize: 11)),
              activeThumbColor: Colors.amber,
              value: isPrivacyEnabled,
              onChanged: (val) {
                setDialogState(() => isPrivacyEnabled = val);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(val ? "Presence set to Anonymous!" : "Presence set to Public!"),
                  backgroundColor: val ? Colors.indigo : Colors.grey,
                ));
              },
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("CLOSE", style: TextStyle(color: Colors.amber))),
            ],
          );
        }
      ),
    );
  }

  Widget _buildActionItem(IconData icon, String title, {VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70),
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      trailing: const Icon(LucideIcons.chevronRight, color: Colors.white10),
      onTap: onTap,
    );
  }

  void _showCertificatesDialog(BuildContext context) {
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
          title: const Row(children: [Icon(LucideIcons.award, color: Colors.amber), SizedBox(width: 10), Text("Certificates", style: TextStyle(color: Colors.white))]),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(leading: Icon(LucideIcons.bookOpen, color: Colors.blue), title: Text("Bible Completion", style: TextStyle(color: Colors.white)), dense: true),
              ListTile(leading: Icon(LucideIcons.award, color: Colors.amber), title: Text("Quiz Champion", style: TextStyle(color: Colors.white)), dense: true),
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("CLOSE"))],
        ));
  }

  void _pickAvatar(BuildContext context, WidgetRef ref, UserProfile profile) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (picked == null) return;

    try {
      final file = File(picked.path);
      final fileName = "avatar_${DateTime.now().millisecondsSinceEpoch}.jpg";
      final r2 = R2Service(Supabase.instance.client);
      final url = await r2.uploadFile(file, "avatars/$fileName");

      await Supabase.instance.client.from('profiles').update({
        'avatar_url': url,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', profile.id);

      ref.invalidate(profileProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Profile picture updated!"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Upload failed: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }
}
