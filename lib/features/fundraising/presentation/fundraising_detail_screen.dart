import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';
import 'package:church_on_app/features/fundraising/data/fundraising_models.dart';
import 'package:church_on_app/features/fundraising/data/fundraising_providers.dart';
import 'package:church_on_app/core/widgets/premium_toast.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/widgets/app_image.dart';
import 'widgets/progress_card.dart';
import 'widgets/contributor_tile.dart';

class FundraisingDetailScreen extends ConsumerStatefulWidget {
  final String ventureId;

  const FundraisingDetailScreen({super.key, required this.ventureId});

  @override
  ConsumerState<FundraisingDetailScreen> createState() => _FundraisingDetailScreenState();
}

class _FundraisingDetailScreenState extends ConsumerState<FundraisingDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final ventureAsync = ref.watch(ventureDetailProvider(widget.ventureId));
    final tenant = ref.watch(currentTenantProvider);

    return ventureAsync.when(
      data: (venture) {
        return _buildScreen(context, venture, tenant?.id);
      },
      loading: () => Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Shimmer.fromColors(
          baseColor: Colors.grey[300]!,
          highlightColor: Colors.grey[100]!,
          child: const Center(child: CircularProgressIndicator(color: Color(0xFFFFB300))),
        ),
      ),
      error: (error, stack) => Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(LucideIcons.arrowLeft),
            onPressed: () => _smartBack(),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.alertTriangle, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text('Failed to load venture', style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScreen(BuildContext context, FundraisingVenture venture, String? currentTenantId) {
    final isOwnVenture = venture.tenantId == currentTenantId;
    final categoryColors = {
      FundraisingCategory.building: const Color(0xFF3B82F6),
      FundraisingCategory.missions: const Color(0xFF10B981),
      FundraisingCategory.youth: const Color(0xFFF59E0B),
      FundraisingCategory.community: const Color(0xFF8B5CF6),
      FundraisingCategory.emergency: const Color(0xFFEF4444),
      FundraisingCategory.other: const Color(0xFF6B7280),
    };
    final categoryLabels = {
      FundraisingCategory.building: 'Building',
      FundraisingCategory.missions: 'Missions',
      FundraisingCategory.youth: 'Youth',
      FundraisingCategory.community: 'Community',
      FundraisingCategory.emergency: 'Emergency',
      FundraisingCategory.other: 'Other',
    };
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: venture.imageUrl != null && venture.imageUrl!.isNotEmpty
                  ? AppImage(venture.imageUrl!, fit: BoxFit.cover, errorWidget: (_, __) => _buildGradient(venture, categoryColors))
                  : _buildGradient(venture, categoryColors),
            ),
            leading: IconButton(
              icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
              onPressed: () => _smartBack(),
            ),
            actions: [
              IconButton(
                icon: const Icon(LucideIcons.share2, color: Colors.white),
                onPressed: () {
                  SharePlus.instance.share(ShareParams(
                    text: 'Support ${venture.title}! Help raise ${venture.formattedTarget} for this cause. https://churchonapp.com/fundraising/${venture.id}',
                    subject: venture.title,
                  ));
                },
              ),
              if (isOwnVenture)
                PopupMenuButton<String>(
                  icon: const Icon(LucideIcons.moreVertical, color: Colors.white),
                  onSelected: (value) {
                    if (value == 'edit') {
                      PremiumToast.showInfo(context, 'Edit feature launching soon');
                    } else if (value == 'close') {
                      _confirmCloseVenture(venture);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'edit', child: Row(
                      children: [Icon(LucideIcons.edit, size: 16), SizedBox(width: 8), Text('Edit')],
                    )),
                    const PopupMenuItem(value: 'close', child: Row(
                      children: [Icon(LucideIcons.xCircle, size: 16), SizedBox(width: 8), Text('Close Venture')],
                    )),
                  ],
                ),
            ],
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _buildBadge(categoryLabels[venture.categoryEnum] ?? 'Other', categoryColors[venture.categoryEnum] ?? const Color(0xFFFFB300)),
                        const SizedBox(width: 8),
                        _buildStatusBadge(venture.statusEnum),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      venture.title,
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, height: 1.2),
                    ),
                    const SizedBox(height: 24),
                    FundraisingProgressCard(
                      raisedAmount: venture.raisedAmount,
                      targetAmount: venture.targetAmount,
                      currency: venture.currency,
                      daysLeft: venture.daysLeft,
                    ),
                    const SizedBox(height: 24),
                    _buildStatsRow(venture),
                    const Divider(height: 40),
                    _buildStorySection(venture),
                    const Divider(height: 40),
                    _buildContributorsSection(),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ]),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(venture, isOwnVenture, theme),
    );
  }

  Widget _buildGradient(FundraisingVenture venture, Map<FundraisingCategory, Color> categoryColors) {
    final color = categoryColors[venture.categoryEnum] ?? const Color(0xFFFFB300);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withValues(alpha: 0.6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          _categoryIcon(venture.categoryEnum),
          size: 64,
          color: Colors.white.withValues(alpha: 0.3),
        ),
      ),
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildStatusBadge(FundraisingStatus status) {
    if (status == FundraisingStatus.active) return const SizedBox.shrink();
    final label = status == FundraisingStatus.completed ? 'Completed' : 'Closed';
    final color = status == FundraisingStatus.completed ? const Color(0xFF10B981) : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  Widget _buildStatsRow(FundraisingVenture venture) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _buildStatItem(LucideIcons.trendingUp, venture.formattedRaised, 'Total Raised', theme),
          _buildStatDivider(),
          _buildStatItem(LucideIcons.users, '${venture.contributorCount}', 'Contributors', theme),
          _buildStatDivider(),
          _buildStatItem(LucideIcons.clock, '${venture.daysLeft?.toString() ?? 'N/A'} days', 'Time Left', theme),
        ],
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label, ThemeData theme) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 20, color: const Color(0xFFFFB300)),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: theme.colorScheme.secondary)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  Widget _buildStatDivider() {
    return Container(width: 1, height: 40, color: Colors.grey.shade200);
  }

  Widget _buildStorySection(FundraisingVenture venture) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Story', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Text(
          venture.description,
          style: const TextStyle(fontSize: 15, height: 1.6, color: Colors.black87),
        ),
      ],
    );
  }

  Widget _buildContributorsSection() {
    final contributionsAsync = ref.watch(contributionsProvider(widget.ventureId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Contributors', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        contributionsAsync.when(
          data: (contributions) {
            if (contributions.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Column(
                    children: [
                      Icon(LucideIcons.users, size: 32, color: Colors.grey.shade300),
                      const SizedBox(height: 8),
                      Text('No contributions yet', style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
                      const SizedBox(height: 4),
                      Text('Be the first to give!', style: TextStyle(color: Colors.grey.shade300, fontSize: 12)),
                    ],
                  ),
                ),
              );
            }
            return Column(
              children: contributions.map((c) => ContributorTile(contribution: c)).toList(),
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator(color: Color(0xFFFFB300))),
          ),
          error: (error, stack) => Padding(
            padding: const EdgeInsets.all(20),
            child: Text('Failed to load contributors', style: TextStyle(color: Colors.grey.shade500)),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar(FundraisingVenture venture, bool isOwnVenture, ThemeData theme) {
    if (venture.statusEnum != FundraisingStatus.active) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: () => _navigateToContribute(venture),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFB300),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            child: const Text(
              'Contribute Now',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ),
      ),
    );
  }

  IconData _categoryIcon(FundraisingCategory category) {
    switch (category) {
      case FundraisingCategory.building: return LucideIcons.building2;
      case FundraisingCategory.missions: return LucideIcons.globe;
      case FundraisingCategory.youth: return LucideIcons.heart;
      case FundraisingCategory.community: return LucideIcons.users;
      case FundraisingCategory.emergency: return LucideIcons.alertTriangle;
      case FundraisingCategory.other: return LucideIcons.hand;
    }
  }

  void _confirmCloseVenture(FundraisingVenture venture) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Close Venture'),
        content: Text('Are you sure you want to close "${venture.title}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref.read(fundraisingServiceProvider).closeVenture(venture.id);
                ref.invalidate(ventureDetailProvider(widget.ventureId));
                if (mounted) PremiumToast.showSuccess(context, 'Venture closed');
              } catch (e) {
                if (mounted) PremiumToast.showError(context, 'Failed to close venture');
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _navigateToContribute(FundraisingVenture venture) {
    context.push('/fundraising/${venture.id}/contribute', extra: venture);
  }

  void _smartBack() {
    if (context.canPop()) {
      Navigator.pop(context);
    } else {
      context.go('/');
    }
  }
}
