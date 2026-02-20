import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import '../../finance/presentation/giving_screen.dart';
import '../../marketplace/presentation/my_library_screen.dart';
import '../../auth/presentation/select_church_screen.dart';
import '../../../core/services/supabase_service.dart';
import '../../admin/presentation/admin_hub_screen.dart';
import 'account_settings_screen.dart';
import '../../finance/presentation/giving_history_screen.dart';
import 'membership_card_screen.dart';
import '../../finance/presentation/wallet_screen.dart';

import '../../../core/providers/profile_provider.dart';
import '../../../core/providers/auth_provider.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(currentTenantProvider);
    final profileAsync = ref.watch(profileProvider);
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(context, ref),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                   profileAsync.when(
                     data: (profile) => _buildStewardCard(context, ref, profile),
                     loading: () => const Center(child: CircularProgressIndicator()),
                     error: (e, s) => Text("Error: $e"),
                   ),
                   const SizedBox(height: 30),
                   _buildSection(context, "Kingdom Assets"),
                   _buildAssetGrid(context),
                   const SizedBox(height: 30),
                   if (profileAsync.value?.role == 'driver') ...[
                     _buildSection(context, "Driver Console"),
                     _buildSettingItem(context, ref, LucideIcons.truck, "Earnings & Trips", onTap: () {}),
                     const SizedBox(height: 20),
                   ],
                   _buildSection(context, "Ministry Settings"),
                   _buildSettingsList(context, ref),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(currentTenantProvider);
    final profile = ref.watch(profileProvider).value;
    
    final userName = profile?.name ?? tenant?.name ?? "Kingdom Believer";
    final avatar = "https://i.pravatar.cc/300?u=${profile?.id ?? '1'}";
    
    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor,
                  ),
                ),
                Positioned(
                  bottom: 40,
                  left: 0,
                  right: 0,
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: Colors.white,
                        child: CircleAvatar(
                          radius: 46,
                          backgroundImage: NetworkImage(avatar),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        userName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        profile?.role?.toUpperCase() ?? "MEMBER",
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 10,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
      ),
    );
  }

  Widget _buildStewardCard(BuildContext context, WidgetRef ref, UserProfile? profile) {
    final coins = profile?.coins ?? 0;
    final walletId = profile?.id ?? "wallet_placeholder";

    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("KINGDOM BALANCE", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  SizedBox(height: 5),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const WalletScreen()));
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("K ${coins.toDouble()}", style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.secondary)),
                        const SizedBox(width: 5),
                        Icon(LucideIcons.chevronRight, size: 20, color: Theme.of(context).colorScheme.secondary),
                      ],
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const MembershipCardScreen()));
                },
                child: QrImageView(
                  data: walletId,
                  version: QrVersions.auto,
                  size: 60.0,
                  foregroundColor: Theme.of(context).colorScheme.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Divider(color: Colors.grey.withOpacity(0.1)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStewardAction(context, LucideIcons.arrowUpRight, "Give", () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const GivingScreen()));
              }),
              _buildStewardAction(context, LucideIcons.history, "History", () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const GivingHistoryScreen()));
              }),
              _buildStewardAction(context, LucideIcons.gift, "Rewards", () {}),
              _buildStewardAction(context, LucideIcons.users, "Tithes", () {}),
            ],
          ),
          const SizedBox(height: 20),
          Divider(color: Colors.grey.withOpacity(0.1)),
          const SizedBox(height: 10),
          _buildSettingItem(context, ref, LucideIcons.refreshCcw, "Switch Church", onTap: () {
            ref.read(currentTenantProvider.notifier).state = null;
            Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const SelectChurchScreen()), (route) => false);
          }),
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
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
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

  Widget _buildAssetGrid(BuildContext context) {
    final assets = [
      {"icon": LucideIcons.book, "title": "My Library", "count": "156 items"},
      {"icon": LucideIcons.calendar, "title": "Events", "count": "3 upcoming"},
      {"icon": LucideIcons.flame, "title": "Prayer Wall", "count": "12 entries"},
      {"icon": LucideIcons.award, "title": "Certificates", "count": "4 earned"},
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 15,
        mainAxisSpacing: 15,
        childAspectRatio: 1.4,
      ),
      itemCount: assets.length,
      itemBuilder: (context, index) {
        return GestureDetector(
          onTap: () {
            if (assets[index]['title'] == "My Library") {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const MyLibraryScreen()));
            }
          },
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.withOpacity(0.05)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(assets[index]['icon'] as IconData, color: Theme.of(context).primaryColor, size: 24),
                const SizedBox(height: 10),
                Text(assets[index]['title'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text(assets[index]['count'] as String, style: const TextStyle(color: Colors.grey, fontSize: 11)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSettingsList(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _buildSettingItem(context, ref, LucideIcons.layoutDashboard, "Admin Management", onTap: () {
          Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminHubScreen()));
        }),
        _buildSettingItem(context, ref, LucideIcons.user, "Account Settings", onTap: () {
          Navigator.push(context, MaterialPageRoute(builder: (context) => const AccountSettingsScreen()));
        }),
        _buildSettingItem(context, ref, LucideIcons.bell, "Notifications"),
        _buildSettingItem(context, ref, LucideIcons.church, "Switch Church", onTap: () {
          ref.read(currentTenantProvider.notifier).setTenant(null);
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const SelectChurchScreen()));
        }),
        _buildSettingItem(context, ref, LucideIcons.shield, "Security & Privacy"),
        _buildSettingItem(context, ref, LucideIcons.helpCircle, "Help Center"),
        _buildSettingItem(context, ref, LucideIcons.logOut, "Logout", isDestructive: true, onTap: () {
          ref.read(authProvider.notifier).signOut();
        }),
      ],
    );
  }

  Widget _buildSettingItem(BuildContext context, WidgetRef ref, IconData icon, String title, {bool isDestructive = false, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Icon(icon, color: isDestructive ? Colors.red : Theme.of(context).colorScheme.secondary, size: 20),
            const SizedBox(width: 15),
            Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: isDestructive ? Colors.red : Theme.of(context).colorScheme.secondary)),
            const Spacer(),
            const Icon(LucideIcons.chevronRight, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
