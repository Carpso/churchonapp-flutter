import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import '../../finance/presentation/giving_screen.dart';
import '../../marketplace/presentation/my_library_screen.dart';
import '../../auth/presentation/select_church_screen.dart';
import '../../../core/services/supabase_service.dart';
import 'package:church_on_app/features/admin/presentation/admin_hub_screen.dart';
import 'account_settings_screen.dart';
import '../../finance/presentation/giving_history_screen.dart';
import 'membership_card_screen.dart';
import '../../finance/presentation/wallet_screen.dart';
import 'package:church_on_app/features/admin/presentation/superadmin_hub_screen.dart';
import '../../auth/presentation/register_church_screen.dart';
import 'package:church_on_app/features/admin/presentation/service_report_screen.dart';
import 'package:church_on_app/features/admin/presentation/ledger_screen.dart';
import 'package:church_on_app/features/admin/presentation/onboarding_manager_screen.dart';
import 'package:church_on_app/features/admin/presentation/bishop_hub_screen.dart';
import 'package:church_on_app/features/admin/presentation/year_planner_screen.dart';
import 'package:church_on_app/features/admin/presentation/pastor_bishop_report_screen.dart';
import 'package:church_on_app/features/admin/presentation/attendance_scanner_screen.dart';
import 'package:church_on_app/features/admin/presentation/writers_studio_screen.dart';
import '../../modules/events/presentation/events_screen.dart';
import '../../connect/presentation/prayer_wall_screen.dart';

import '../../../core/providers/profile_provider.dart';
import '../../../core/providers/auth_provider.dart';
import '../../auth/presentation/login_screen.dart';
import '../../modules/bible_quiz/data/bible_quiz_service.dart';
import '../../transport/presentation/driver_portal_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);
    final tenant = ref.watch(currentTenantProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      body: profileAsync.when(
        data: (profile) => CustomScrollView(
          slivers: [
            _buildAppBar(context, profile, tenant),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(25.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCredentialsRow(profile),
                    const SizedBox(height: 15),
                    _buildWalletCard(context, profile, ref),
                    const SizedBox(height: 30),
                    _buildSection(context, "Faith Dashboard"),
                    _buildFaithDashboard(context, profile, ref),
                    const SizedBox(height: 30),
                    _buildSection(context, "Ministry & Admin"),
                    const SizedBox(height: 10),
                    _buildMinistryActions(context, ref, profile, tenant),
                    const SizedBox(height: 30),
                    _buildSection(context, "Personal Assets"),
                    _buildAssetGrid(context, ref),
                    const SizedBox(height: 30),
                    _buildSection(context, "Account Settings"),
                    _buildSettingsList(context, ref, profile),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator(color: Colors.amber)),
        error: (e, st) => Center(child: Text("Error: $e")),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, UserProfile? profile, Tenant? tenant) {
    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      backgroundColor: Theme.of(context).primaryColor,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Theme.of(context).primaryColor, Theme.of(context).primaryColor.withValues(alpha: 0.8)],
                  ),
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 40),
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: ClipOval(
                        child: Image.network(
                          "https://i.pravatar.cc/300?u=${profile?.id ?? '1'}",
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  Text(profile?.name ?? "Believer", style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                  Text(tenant?.name ?? "Global Member", style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 14)),
                  const SizedBox(height: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
                    child: Text(profile?.role?.toUpperCase() ?? "MEMBER", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWalletCard(BuildContext context, UserProfile? profile, WidgetRef ref) {
    final coins = profile?.coins ?? 0;
    final walletId = "COA-${profile?.id.substring(0, 8).toUpperCase() ?? 'WALLET'}";

    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("KINGDOM COINS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.1)),
                    const SizedBox(height: 5),
                    Text("$coins CC", style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.secondary)),
                    const SizedBox(height: 5),
                    Text(walletId, style: const TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              if (profile?.canWork ?? false) ...[
                _buildWorkModeToggle(context, ref, profile!),
                const SizedBox(width: 15),
              ],
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(15)),
                child: QrImageView(data: walletId, version: QrVersions.auto, size: 60.0, foregroundColor: Theme.of(context).colorScheme.secondary),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Divider(color: Colors.grey.withValues(alpha: 0.1)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStewardAction(context, LucideIcons.arrowUpRight, "Give", () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const GivingScreen()));
              }),
              _buildStewardAction(context, LucideIcons.history, "History", () {
                _showComingSoon(context, "History");
              }),
              _buildStewardAction(context, LucideIcons.gift, "Rewards", () {
                _showRewardsDialog(context);
              }),
              _buildStewardAction(context, LucideIcons.users, "Tithes", () {
                _showTithesDialog(context);
              }),
            ],
          ),
        ],
      ),
    );
  }

  void _showRewardsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: const Row(children: [Icon(LucideIcons.gift, color: Colors.amber), SizedBox(width: 10), Text("Kingdom Rewards")]),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Your Rewards", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            SizedBox(height: 10),
            ListTile(leading: Icon(LucideIcons.star, color: Colors.amber), title: Text("Welcome Bonus"), subtitle: Text("500 Kingdom Coins"), dense: true),
            ListTile(leading: Icon(LucideIcons.flame, color: Colors.red), title: Text("7-Day Streak"), subtitle: Text("100 Kingdom Coins"), dense: true),
            ListTile(leading: Icon(LucideIcons.book, color: Colors.blue), title: Text("Bible Reader"), subtitle: Text("50 Kingdom Coins"), dense: true),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("CLOSE"))],
      ),
    );
  }

  void _showTithesDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: const Row(children: [Icon(LucideIcons.users, color: Colors.blue), SizedBox(width: 10), Text("Tithes & Offerings")]),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Your tithe records are managed by your church administration.", style: TextStyle(color: Colors.grey)),
            SizedBox(height: 15),
            ListTile(leading: Icon(LucideIcons.calendar, color: Colors.green), title: Text("This Month"), subtitle: Text("K 0.00"), dense: true),
            ListTile(leading: Icon(LucideIcons.trendingUp, color: Colors.blue), title: Text("Year Total"), subtitle: Text("K 0.00"), dense: true),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CLOSE")),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const GivingScreen()));
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
            child: const Text("GIVE NOW"),
          ),
        ],
      ),
    );
  }

  Widget _buildStewardAction(BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Theme.of(context).primaryColor.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(icon, color: Theme.of(context).primaryColor, size: 22),
          ),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.secondary)),
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15.0),
      child: Row(
        children: [
          Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.secondary)),
          const Spacer(),
          const Icon(LucideIcons.chevronRight, size: 16, color: Colors.grey),
        ],
      ),
    );
  }

  Widget _buildMinistryActions(BuildContext context, WidgetRef ref, UserProfile? profile, Tenant? tenant) {
    return Column(
      children: [
        _buildSettingItem(context, ref, LucideIcons.plusCircle, "Register Your Church", 
          isPremium: true,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterChurchScreen()))
        ),
        if (profile?.isExecutiveOffice ?? false) ...[
          _buildSettingItem(context, ref, LucideIcons.layoutDashboard, "BISHOP COMMAND HUB", 
            isPremium: true,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BishopHubScreen()))
          ),
        ],
        _buildSettingItem(context, ref, LucideIcons.calendar, "Yearly Program Planner", onTap: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const YearPlannerScreen()));
        }),
        if (profile?.role == 'pastor') ...[
          _buildSettingItem(context, ref, LucideIcons.clipboardCheck, "Submit Report to Bishop", onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const PastorBishopReportScreen()));
          }),
        ],
        if (profile?.isLedgerManager ?? false) ...[
          _buildSettingItem(context, ref, LucideIcons.barChart3, "Ministry Reports", onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const ServiceReportScreen()));
          }),
          _buildSettingItem(context, ref, LucideIcons.qrCode, "Scan Attendance", onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const AttendanceScannerScreen()));
          }),
          _buildSettingItem(context, ref, LucideIcons.bookOpen, "Financial Ledger", onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const LedgerScreen()));
          }),
        ],
        if (profile?.isAdminOrHigher ?? false) ...[
          _buildSettingItem(context, ref, LucideIcons.shieldCheck, "KINGDOM ADMIN HUB", onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminHubScreen()));
          }),
        ],
        if (profile?.isOnboardingOfficer ?? false) ...[
          _buildSettingItem(context, ref, LucideIcons.userPlus, "Onboarding Manager", onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const OnboardingManagerScreen()));
          }),
        ],
        if (profile?.isSuperadmin ?? false) ...[
          _buildSettingItem(context, ref, LucideIcons.zap, "SUPERADMIN HUB", 
            isPremium: true,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SuperadminHubScreen()))
          ),
        ],
        if (profile?.role == 'writer') ...[
           _buildSettingItem(context, ref, LucideIcons.penTool, "Writer Studio", onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const WriterStudioScreen()));
          }),
        ],
      ],
    );
  }

  Widget _buildWorkModeToggle(BuildContext context, WidgetRef ref, UserProfile profile) {
    final mode = profile.isWorkMode;
    return GestureDetector(
      onTap: () => ref.read(profileProvider.notifier).toggleWorkMode(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        decoration: BoxDecoration(
          color: mode ? Colors.green.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: mode ? Colors.green : Colors.grey.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(mode ? LucideIcons.zap : LucideIcons.zapOff, color: mode ? Colors.green : Colors.grey, size: 20),
            const SizedBox(height: 4),
            Text(mode ? "ON DUTY" : "OFF DUTY", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: mode ? Colors.green : Colors.grey)),
            if (mode) ...[
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const DriverPortalScreen())),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text("DRIVER COMMAND", style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.black)),
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
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 15, mainAxisSpacing: 15, childAspectRatio: 1.4),
      itemCount: assets.length,
      itemBuilder: (context, index) {
        return GestureDetector(
          onTap: () {
            final action = assets[index]['action'] as String;
            switch (action) {
              case 'library':
                Navigator.push(context, MaterialPageRoute(builder: (_) => const MyLibraryScreen()));
              case 'events':
                Navigator.push(context, MaterialPageRoute(builder: (_) => const EventsScreen()));
              case 'prayer':
                Navigator.push(context, MaterialPageRoute(builder: (_) => const PrayerWallScreen()));
              case 'certs':
                _showCertificatesDialog(context);
            }
          },
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.05)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(assets[index]['icon'] as IconData, color: Theme.of(context).primaryColor, size: 24),
                const SizedBox(height: 10),
                Text(assets[index]['title'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                Text(assets[index]['count'] as String, style: const TextStyle(color: Colors.grey, fontSize: 10)),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCertificatesDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: const Row(children: [Icon(LucideIcons.award, color: Colors.amber), SizedBox(width: 10), Text("My Certificates")]),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: Icon(LucideIcons.bookOpen, color: Colors.blue), title: Text("Bible Completion"), subtitle: Text("New Testament"), dense: true),
            ListTile(leading: Icon(LucideIcons.sword, color: Colors.orange), title: Text("Quiz Champion"), subtitle: Text("Season 1"), dense: true),
            ListTile(leading: Icon(LucideIcons.flame, color: Colors.red), title: Text("30-Day Streak"), subtitle: Text("Daily Reading"), dense: true),
            ListTile(leading: Icon(LucideIcons.users, color: Colors.green), title: Text("Community Leader"), subtitle: Text("Youth Ministry"), dense: true),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("CLOSE"))],
      ),
    );
  }

  Widget _buildSettingsList(BuildContext context, WidgetRef ref, UserProfile? profile) {
    return Column(
      children: [
        _buildSettingItem(context, ref, LucideIcons.user, "Personal Information", onTap: () {
          _showComingSoon(context, "Edit Profile");
        }),
        _buildSettingItem(context, ref, LucideIcons.bell, "Notification Settings", onTap: () {
          _showNotificationSettings(context);
        }),
        _buildSettingItem(context, ref, LucideIcons.shield, "Security & Privacy", onTap: () {
          _showSecuritySettings(context);
        }),
        _buildSettingItem(context, ref, LucideIcons.helpCircle, "Help Center", onTap: () {
          _showHelpCenter(context);
        }),
        _buildSettingItem(context, ref, LucideIcons.logOut, "Logout", isDestructive: true, onTap: () {
          _showLogoutConfirmation(context, ref);
        }),
      ],
    );
  }

  void _showLogoutConfirmation(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: const Text("Logout"),
        content: const Text("Are you sure you want to sign out of your account?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(authProvider.notifier).signOut();
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text("LOGOUT"),
          ),
        ],
      ),
    );
  }

  Widget _buildCredentialsRow(UserProfile? profile) {
    if (profile == null) return const SizedBox.shrink();
    
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          if (profile.isBishop) _buildBadge(LucideIcons.crown, "BISHOP", Colors.amber),
          if (profile.role == 'pastor') _buildBadge(LucideIcons.scroll, "PASTOR", Colors.blue),
          if (profile.role == 'usher') _buildBadge(LucideIcons.shieldCheck, "USHER", Colors.green),
          if (profile.role == 'writer') _buildBadge(LucideIcons.penTool, "WRITER", Colors.purple),
          if (profile.coins > 1000) _buildBadge(LucideIcons.star, "STEWARD", Colors.orange),
          _buildBadge(LucideIcons.checkCircle, "VERIFIED", Colors.blueGrey),
        ],
      ),
    );
  }

  Widget _buildBadge(IconData icon, String label, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        ],
      ),
    );
  }

  void _showNotificationSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Notification Settings", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            SwitchListTile(title: const Text("Push Notifications"), subtitle: const Text("Receive church updates"), value: true, onChanged: (_) {}),
            SwitchListTile(title: const Text("Prayer Requests"), subtitle: const Text("New prayer wall entries"), value: true, onChanged: (_) {}),
            SwitchListTile(title: const Text("Messages"), subtitle: const Text("Direct messages and groups"), value: true, onChanged: (_) {}),
            SwitchListTile(title: const Text("Events"), subtitle: const Text("Upcoming event reminders"), value: false, onChanged: (_) {}),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showSecuritySettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Security & Privacy", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            ListTile(leading: const Icon(LucideIcons.lock), title: const Text("Change Password"), trailing: const Icon(LucideIcons.chevronRight, size: 18), onTap: () {}),
            ListTile(leading: const Icon(LucideIcons.smartphone), title: const Text("Two-Factor Auth"), trailing: const Text("OFF", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)), onTap: () {}),
            ListTile(leading: const Icon(LucideIcons.eye), title: const Text("Profile Visibility"), trailing: const Text("Public", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)), onTap: () {}),
            ListTile(leading: const Icon(LucideIcons.download), title: const Text("Download My Data"), trailing: const Icon(LucideIcons.chevronRight, size: 18), onTap: () {}),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showHelpCenter(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Help Center", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            ListTile(leading: const Icon(LucideIcons.messageCircle, color: Colors.blue), title: const Text("Live Chat Support"), subtitle: const Text("Available 9am - 5pm CAT"), onTap: () {}),
            ListTile(leading: const Icon(LucideIcons.mail, color: Colors.green), title: const Text("Email Support"), subtitle: const Text("support@churchonapp.com"), onTap: () {}),
            ListTile(leading: const Icon(LucideIcons.bookOpen, color: Colors.orange), title: const Text("FAQs"), subtitle: const Text("Common questions answered"), onTap: () {}),
            ListTile(leading: const Icon(LucideIcons.flag, color: Colors.red), title: const Text("Report a Problem"), onTap: () {}),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showComingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("$feature — Coming Soon!"), backgroundColor: Colors.amber, duration: const Duration(seconds: 2)),
    );
  }

  Widget _buildFaithDashboard(BuildContext context, UserProfile? profile, WidgetRef ref) {
    final quizRank = ref.watch(myQuizRankProvider).value ?? "#--";

    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildDashboardMetric("Attendance", "85%", LucideIcons.calendarCheck, Colors.blue),
              _buildDashboardMetric("Quiz Rank", quizRank, LucideIcons.trophy, Colors.amber),
              _buildDashboardMetric("Tokens", "${profile?.coins ?? 0}", LucideIcons.zap, Colors.purple),
            ],
          ),
          const SizedBox(height: 30),
          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: [
                      const FlSpot(0, 3),
                      const FlSpot(1, 1),
                      const FlSpot(2, 4),
                      const FlSpot(3, 2),
                      const FlSpot(4, 5),
                      const FlSpot(5, 3),
                      const FlSpot(6, 4),
                    ],
                    isCurved: true,
                    color: Colors.amber,
                    barWidth: 4,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.amber.withValues(alpha: 0.1),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text("SPIRITUAL GROWTH INDEX", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.grey.shade400, letterSpacing: 2)),
        ],
      ),
    );
  }

  Widget _buildDashboardMetric(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 10),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildSettingItem(BuildContext context, WidgetRef ref, IconData icon, String title, {bool isDestructive = false, bool isPremium = false, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isPremium ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Icon(icon, color: isPremium ? Colors.white : (isDestructive ? Colors.red : Theme.of(context).colorScheme.secondary), size: 20),
            const SizedBox(width: 15),
            Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: isPremium ? Colors.white : (isDestructive ? Colors.red : Theme.of(context).colorScheme.secondary))),
            const Spacer(),
            Icon(LucideIcons.chevronRight, size: 16, color: isPremium ? Colors.white54 : Colors.grey),
          ],
        ),
      ),
    );
  }
}
