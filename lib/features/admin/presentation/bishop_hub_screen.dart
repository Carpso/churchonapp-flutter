import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/features/admin/presentation/bishop_heatmap_screen.dart';
import 'package:church_on_app/features/admin/data/organization_service.dart';

class BishopHubScreen extends ConsumerWidget {
  const BishopHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value;
    if (profile == null) return const Scaffold(body: Center(child: Text("Access Denied")));

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text("BISHOP'S COMMAND HUB", style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w900, letterSpacing: 1.2)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildExecutiveProfile(profile)),
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 15,
                mainAxisSpacing: 15,
                childAspectRatio: 1.5,
              ),
              delegate: SliverChildListDelegate([
                _buildActionCard(context, LucideIcons.church, "Ministries & Branches", Colors.blue),
                _buildActionCard(context, LucideIcons.map, "Kingdom Map", Colors.green, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BishopHeatmapScreen()))),
                _buildActionCard(context, LucideIcons.fileText, "Pastor Reports", Colors.purple),
                _buildActionCard(context, LucideIcons.banknote, "Central Treasury", Colors.orange),
              ]),
            ),
          ),
          const SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(
              child: Text("Secure Leadership Memos", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
          _buildPrivateMemoList(ref),
          const SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            sliver: SliverToBoxAdapter(
              child: Text("Managed Church Branches", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
          _buildActivityList(ref),
        ],
      ),
    );
  }

  Widget _buildExecutiveProfile(UserProfile profile) {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 35,
            backgroundColor: Colors.white24,
            child: Text(profile.name[0], style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(profile.name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                Text(profile.role?.toUpperCase() ?? "EXECUTIVE", style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                const SizedBox(height: 10),
                const Row(
                  children: [
                    Icon(LucideIcons.globe, color: Colors.white54, size: 12),
                    SizedBox(width: 5),
                    Text("Global Jurisdiction", style: TextStyle(color: Colors.white54, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(BuildContext context, IconData icon, String label, Color color, {VoidCallback? onTap}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: InkWell(
        onTap: onTap ?? () {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Opening $label...")));
        },
        borderRadius: BorderRadius.circular(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 10),
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildPrivateMemoList(WidgetRef ref) {
    return SliverPadding(
      padding: const EdgeInsets.all(20),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.amber.withOpacity(0.1)),
            ),
            child: const Row(
              children: [
                Icon(LucideIcons.lock, color: Colors.amber, size: 16),
                SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("CONFIDENTIAL: New Mission Directive", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      Text("Bishop's office has released the Q3 strategy memo. Please review.", style: TextStyle(color: Colors.grey, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          childCount: 1,
        ),
      ),
    );
  }

  Widget _buildActivityList(WidgetRef ref) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            StreamBuilder<List<Tenant>>(
              stream: ref.read(organizationServiceProvider).streamLinkedChurches('default_org'),
              builder: (context, snapshot) {
                final churches = snapshot.data ?? [];
                if (churches.isEmpty) {
                  return const Text("No branches linked yet.", style: TextStyle(color: Colors.grey, fontSize: 12));
                }
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: churches.length,
                  itemBuilder: (context, index) {
                    final church = churches[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(backgroundImage: NetworkImage(church.logoUrl ?? "")),
                      title: Text(church.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: const Text("Active Branch • Fully Synced", style: TextStyle(fontSize: 10, color: Colors.green)),
                      trailing: const Icon(LucideIcons.chevronRight, size: 16),
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.blue,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: Colors.blue)),
              ),
              icon: const Icon(LucideIcons.link, size: 16),
              label: const Text("LINK NEW BRANCH TO ORGANIZATION", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
            ),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }
}

