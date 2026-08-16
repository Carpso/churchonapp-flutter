import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import 'package:church_on_app/core/widgets/app_error_view.dart';
import 'package:church_on_app/features/admin/presentation/bishop_heatmap_screen.dart';
import 'package:church_on_app/features/admin/presentation/finance_dashboard_screen.dart';
import 'package:church_on_app/features/admin/data/organization_service.dart';
import 'package:church_on_app/core/widgets/app_image.dart';

class BishopHubScreen extends ConsumerWidget {
  const BishopHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);
    return profileAsync.when(
      data: (profile) {
        if (profile == null) return const Scaffold(body: Center(child: Text("Access Denied")));
        return _buildScreen(context, ref, profile);
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, st) => Scaffold(body: AppErrorView(error: e.toString(), onRetry: () => ref.invalidate(profileProvider))),
    );
  }

  Widget _buildScreen(BuildContext context, WidgetRef ref, UserProfile profile) {
    final statsAsync = ref.watch(bishopCommandHubStatsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text("BISHOP'S COMMAND HUB", style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w900, letterSpacing: 1.2)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
      ),
      body: statsAsync.when(
        data: (stats) => _buildDashboard(context, ref, profile, stats),
        loading: () => const _BishopHubShimmer(),
        error: (e, st) => AppErrorView(
          error: e,
          onRetry: () => ref.invalidate(bishopCommandHubStatsProvider),
        ),
      ),
    );
  }

  Widget _buildDashboard(
    BuildContext context,
    WidgetRef ref,
    UserProfile profile,
    BishopCommandHubStats stats,
  ) {
    final currency = NumberFormat.compactCurrency(symbol: 'K ');

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildExecutiveProfile(context, ref, profile, stats, currency)),
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
              _buildActionCard(context, LucideIcons.church, "Ministries & Branches", Theme.of(context).primaryColor),
              _buildActionCard(context, LucideIcons.map, "Map", Colors.green, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BishopHeatmapScreen()))),
              _buildActionCard(context, LucideIcons.fileText, "Pastor Reports", Theme.of(context).primaryColor),
              _buildActionCard(context, LucideIcons.banknote, "Central Treasury", Colors.orange, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FinanceDashboardScreen()))),
            ]),
          ),
        ),
        if (stats.presbyteries.isNotEmpty) ...[
          const SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(
              child: Text("Network Aggregation", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
          _buildPresbyteryList(ref, stats),
        ],
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
        _buildActivityList(context, ref, profile),
      ],
    );
  }

  Widget _buildExecutiveProfile(
    BuildContext context,
    WidgetRef ref,
    UserProfile profile,
    BishopCommandHubStats stats,
    NumberFormat currency,
  ) {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 35,
                backgroundColor: Colors.white24,
                child: Text(profile.name.isNotEmpty ? profile.name[0] : 'B', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(profile.name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    Text(profile.role.toUpperCase(), style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    const SizedBox(height: 10),
                    const Row(
                      children: [
                        Icon(LucideIcons.globe, color: Colors.white54, size: 12),
                        SizedBox(width: 5),
                        Flexible(child: Text("Global Jurisdiction", style: TextStyle(color: Colors.white54, fontSize: 11))),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(color: Colors.white12),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMiniStat("Branches", "${stats.branches}", LucideIcons.building),
              _buildMiniStat("Members", _formatCompact(stats.members), LucideIcons.users),
              _buildMiniStat("Giving (MTD)", currency.format(stats.monthlyGiving), LucideIcons.banknote),
              _buildMiniStat("Live", "${stats.activeStreams}", LucideIcons.radio),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.white54, size: 14),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
      ],
    );
  }

  Widget _buildPresbyteryList(WidgetRef ref, BishopCommandHubStats stats) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final node = stats.presbyteries[index];
            final nodeStatsAsync = ref.watch(nodeAggregatedStatsProvider(node.id));
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFF1F5F9)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Theme.of(context).primaryColor.withValues(alpha: 0.1), shape: BoxShape.circle),
                    child: Icon(LucideIcons.map, color: Theme.of(context).primaryColor, size: 18),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(node.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 3),
                        nodeStatsAsync.when(
                          data: (stats) => Text(
                            "${stats['branches']} branches • ${stats['attendance']} attendance • K${NumberFormat.compact().format(stats['giving'])} MTD",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.grey, fontSize: 11),
                          ),
                          loading: () => const ShimmerLoader.rectangular(height: 12, width: 200),
                          error: (e, st) => const Text("Stats unavailable", style: TextStyle(color: Colors.grey, fontSize: 11)),
                        ),
                      ],
                    ),
                  ),
                  const Icon(LucideIcons.chevronRight, size: 16),
                ],
              ),
            );
          },
          childCount: stats.presbyteries.length,
        ),
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
              color: Colors.amber.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.1)),
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

  Widget _buildActivityList(BuildContext context, WidgetRef ref, UserProfile profile) {
    final orgId = profile.organizationId;
    if (orgId == null || orgId.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text("No organization assigned. Contact central administration.", style: TextStyle(color: Colors.grey, fontSize: 12)),
        ),
      );
    }

    final churchesAsync = ref.watch(bishopLinkedChurchesProvider(orgId));

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            churchesAsync.when(
              data: (churches) {
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
                      leading: CircleAvatar(
                        backgroundColor: Colors.grey[200],
                        child: ClipOval(
                          child: AppImage(church.logoUrl ?? "", width: 40, height: 40, fit: BoxFit.cover),
                        ),
                      ),
                      title: Text(church.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: const Text("Active Branch • Fully Synced", style: TextStyle(fontSize: 11, color: Colors.green)),
                      trailing: const Icon(LucideIcons.chevronRight, size: 16),
                    );
                  },
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: ShimmerLoader.rectangular(height: 60),
              ),
              error: (e, st) => Text("Failed to load branches: $e", style: const TextStyle(color: Colors.grey, fontSize: 11)),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text("Link New Branch"),
                    content: const Text(
                      "To link a new branch, please contact the central administration office with the following details:\n\n"
                      "• Branch Name\n"
                      "• Pastor/Leader Name\n"
                      "• Location\n"
                      "• Organization ID\n\n"
                      "An invitation token will be generated and sent to the branch leader's email.",
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CLOSE")),
                    ],
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF7A5C00),
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: Color(0xFF7A5C00))),
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

  String _formatCompact(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : n.toString();
}

class _BishopHubShimmer extends StatelessWidget {
  const _BishopHubShimmer();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const ShimmerLoader.rectangular(height: 140, width: double.infinity),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(child: ShimmerLoader.rectangular(height: 90)),
            const SizedBox(width: 12),
            Expanded(child: ShimmerLoader.rectangular(height: 90)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: ShimmerLoader.rectangular(height: 90)),
            const SizedBox(width: 12),
            Expanded(child: ShimmerLoader.rectangular(height: 90)),
          ],
        ),
        const SizedBox(height: 25),
        const ShimmerLoader.rectangular(height: 16, width: 160),
        const SizedBox(height: 15),
        ...List.generate(
          3,
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ShimmerLoader.rectangular(height: 60),
          ),
        ),
      ],
    );
  }
}
