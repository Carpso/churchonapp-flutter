import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';
import 'package:church_on_app/features/fundraising/data/fundraising_models.dart';
import 'package:church_on_app/features/fundraising/data/fundraising_providers.dart';
import 'package:church_on_app/core/widgets/app_image.dart';
import 'package:church_on_app/core/widgets/empty_state_widget.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'widgets/progress_card.dart';

class FundraisingListScreen extends ConsumerStatefulWidget {
  const FundraisingListScreen({super.key});

  @override
  ConsumerState<FundraisingListScreen> createState() => _FundraisingListScreenState();
}

class _FundraisingListScreenState extends ConsumerState<FundraisingListScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(currentTenantProvider);
    final tenantId = tenant?.id;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Fundraising'),
        bottom: TabBar(
          controller: _tabController,
          tabAlignment: TabAlignment.start,
          isScrollable: true,
          indicatorColor: const Color(0xFFFFB300),
          labelColor: const Color(0xFFFFB300),
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: 'My Church'),
            Tab(text: 'Partner Churches'),
            Tab(text: 'Group Giving'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _navigateToCreate(),
        backgroundColor: const Color(0xFFFFB300),
        foregroundColor: Colors.white,
        icon: const Icon(LucideIcons.plus),
        label: const Text('New Venture'),
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildMyChurchTab(tenantId),
                _buildPartnerTab(tenantId),
                _buildGroupGivingTab(tenantId),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyChurchTab(String? tenantId) {
    if (tenantId == null) {
      return const EmptyStateWidget(
        icon: LucideIcons.alertCircle,
        title: 'No church selected',
        subtitle: 'Please select a church to view fundraisers',
      );
    }
    final venturesAsync = ref.watch(myChurchVenturesProvider(tenantId));
    return _buildVenturesList(venturesAsync, isOwn: true);
  }

  Widget _buildPartnerTab(String? tenantId) {
    if (tenantId == null) {
      return const EmptyStateWidget(
        icon: LucideIcons.alertCircle,
        title: 'No church selected',
        subtitle: 'Please select a church to view fundraisers',
      );
    }
    final venturesAsync = ref.watch(invitedVenturesProvider(tenantId));
    return _buildVenturesList(venturesAsync, isOwn: false);
  }

  Widget _buildGroupGivingTab(String? tenantId) {
    if (tenantId == null) {
      return const EmptyStateWidget(
        icon: LucideIcons.alertCircle,
        title: 'No church selected',
        subtitle: 'Please select a church to view group contributions',
      );
    }
    final groupsAsync = ref.watch(groupContributionsProvider(tenantId));
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(groupContributionsProvider(tenantId)),
      child: groupsAsync.when(
        data: (groups) {
          if (groups.isEmpty) {
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.6,
                child: EmptyStateWidget(
                  icon: LucideIcons.users,
                  title: 'No group contributions',
                  subtitle: 'Start a group to give together',
                  actionLabel: 'Start Group',
                  onAction: () => context.push('/fundraising/groups/create'),
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final group = groups[index];
              final progress = group.targetAmount > 0 ? (group.collectedAmount / group.targetAmount).clamp(0.0, 1.0) : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: GestureDetector(
                  onTap: () => context.push('/fundraising/groups/${group.id}'),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: const Color(0xFFFFB300).withValues(alpha: 0.1), shape: BoxShape.circle),
                              child: const Icon(LucideIcons.users, color: Color(0xFFFFB300), size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Text(group.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                            Text("${(progress * 100).toInt()}%", style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFFB300))),
                          ],
                        ),
                        const SizedBox(height: 12),
                        LinearProgressIndicator(value: progress, backgroundColor: Colors.grey.shade100, color: const Color(0xFFFFB300), minHeight: 5),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("K ${group.collectedAmount.toStringAsFixed(0)} / K ${group.targetAmount.toStringAsFixed(0)}", style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                            Text("${group.memberCount} members", style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
        loading: () => Shimmer.fromColors(
          baseColor: Colors.grey[300]!,
          highlightColor: Colors.grey[100]!,
          child: const Center(child: CircularProgressIndicator(color: Color(0xFFFFB300))),
        ),
        error: (e, st) => Center(child: Text("Error: $e")),
      ),
    );
  }

  Widget _buildVenturesList(AsyncValue<List<FundraisingVenture>> venturesAsync, {required bool isOwn}) {
    return RefreshIndicator(
      onRefresh: () async {
        final tenantId = ref.read(currentTenantProvider)?.id;
        if (tenantId == null) return;
        ref.invalidate(myChurchVenturesProvider(tenantId));
        ref.invalidate(invitedVenturesProvider(tenantId));
        await Future.delayed(const Duration(milliseconds: 300));
      },
      child: venturesAsync.when(
        data: (ventures) {
          if (ventures.isEmpty) {
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.6,
                child: EmptyStateWidget(
                  icon: LucideIcons.hand,
                  title: 'No ventures yet',
                  subtitle: isOwn
                      ? 'Start your first fundraising campaign'
                      : 'No partner churches have invited you yet',
                  actionLabel: isOwn ? 'Start Fundraising' : null,
                  onAction: isOwn ? () => _navigateToCreate() : null,
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: ventures.length,
            itemBuilder: (context, index) => _buildVentureCard(ventures[index]),
          );
        },
        loading: () => Shimmer.fromColors(
          baseColor: Colors.grey[300]!,
          highlightColor: Colors.grey[100]!,
          child: const Center(
            child: CircularProgressIndicator(color: Color(0xFFFFB300)),
          ),
        ),
        error: (error, stack) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: EmptyStateWidget(
              icon: LucideIcons.alertTriangle,
              title: 'Something went wrong',
              subtitle: error.toString(),
              actionLabel: 'Retry',
              onAction: () {
                final tenantId = ref.read(currentTenantProvider)?.id;
                if (tenantId != null) {
                  ref.invalidate(myChurchVenturesProvider(tenantId));
                  ref.invalidate(invitedVenturesProvider(tenantId));
                }
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVentureCard(FundraisingVenture venture) {
    final theme = Theme.of(context);
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GestureDetector(
        onTap: () => _navigateToDetail(venture),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCardImage(venture, categoryColors, categoryLabels),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      venture.title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                        color: theme.colorScheme.secondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    FundraisingProgressCard(
                      raisedAmount: venture.raisedAmount,
                      targetAmount: venture.targetAmount,
                      currency: venture.currency,
                      daysLeft: venture.daysLeft,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            SharePlus.instance.share(ShareParams(
                              text: 'Support ${venture.title}! Help us raise ${venture.formattedTarget} for this cause. https://churchonapp.com/fundraising/${venture.id}',
                              subject: venture.title,
                            ));
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(LucideIcons.share2, size: 14, color: Colors.grey.shade600),
                                const SizedBox(width: 4),
                                Text(
                                  'Share',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Spacer(),
                        Icon(LucideIcons.users, size: 14, color: Colors.grey.shade400),
                        const SizedBox(width: 4),
                        Text(
                          '${venture.contributorCount}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardImage(
    FundraisingVenture venture,
    Map<FundraisingCategory, Color> categoryColors,
    Map<FundraisingCategory, String> categoryLabels,
  ) {
    if (venture.imageUrl != null && venture.imageUrl!.isNotEmpty) {
      return Stack(
        children: [
          AppImage(
            venture.imageUrl!,
            height: 160,
            width: double.infinity,
            fit: BoxFit.cover,
            errorWidget: (context, url) => _buildGradientHeader(venture, categoryColors),
          ),
          Positioned(
            top: 12,
            left: 12,
            child: _buildCategoryBadge(venture, categoryColors, categoryLabels),
          ),
          if (venture.statusEnum != FundraisingStatus.active)
            Positioned(
              top: 12,
              right: 12,
              child: _buildStatusBadge(venture),
            ),
        ],
      );
    }
    return Stack(
      children: [
        _buildGradientHeader(venture, categoryColors),
        Positioned(
          top: 12,
          left: 12,
          child: _buildCategoryBadge(venture, categoryColors, categoryLabels),
        ),
        Positioned(
          top: 12,
          right: 12,
          child: _buildStatusBadge(venture),
        ),
      ],
    );
  }

  Widget _buildGradientHeader(FundraisingVenture venture, Map<FundraisingCategory, Color> categoryColors) {
    final color = categoryColors[venture.categoryEnum] ?? const Color(0xFFFFB300);
    return Container(
      height: 160,
      width: double.infinity,
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
          size: 48,
          color: Colors.white.withValues(alpha: 0.3),
        ),
      ),
    );
  }

  Widget _buildCategoryBadge(
    FundraisingVenture venture,
    Map<FundraisingCategory, Color> categoryColors,
    Map<FundraisingCategory, String> categoryLabels,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_categoryIcon(venture.categoryEnum), size: 12, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            categoryLabels[venture.categoryEnum] ?? 'Other',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(FundraisingVenture venture) {
    if (venture.statusEnum == FundraisingStatus.active) return const SizedBox.shrink();
    final label = venture.statusEnum == FundraisingStatus.completed ? 'Completed' : 'Closed';
    final color = venture.statusEnum == FundraisingStatus.completed ? const Color(0xFF10B981) : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
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

  void _navigateToDetail(FundraisingVenture venture) {
    context.push('/fundraising/${venture.id}', extra: venture);
  }

  void _navigateToCreate() {
    context.push('/fundraising/create');
  }
}
