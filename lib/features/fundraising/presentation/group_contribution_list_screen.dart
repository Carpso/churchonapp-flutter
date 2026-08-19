import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import '../data/fundraising_providers.dart';
import '../data/fundraising_models.dart';

class GroupContributionListScreen extends ConsumerWidget {
  const GroupContributionListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(currentTenantProvider);
    final tenantId = tenant?.id;
    final profile = ref.watch(profileProvider).value;
    final canCreate = profile?.isAdminOrHigher == true;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Group Giving", style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (canCreate)
            IconButton(
              icon: const Icon(LucideIcons.plus),
              onPressed: () => context.push('/fundraising/groups/create', extra: tenantId),
            ),
        ],
      ),
      body: tenantId == null
          ? const Center(child: Text("Select a church first", style: TextStyle(color: Colors.grey)))
          : _buildGroupsList(context, ref, tenantId),
    );
  }

  Widget _buildGroupsList(BuildContext context, WidgetRef ref, String tenantId) {
    final groupsAsync = ref.watch(groupContributionsProvider(tenantId));

    return groupsAsync.when(
      data: (groups) {
        if (groups.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.users, size: 60, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                const Text("No group contributions yet", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text("Start a group to give together", style: TextStyle(color: Colors.grey.shade500)),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(groupContributionsProvider(tenantId)),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: groups.length,
            itemBuilder: (context, index) => _buildGroupCard(context, groups[index]),
          ),
        );
      },
      loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFFFFB300)),
        ),
      error: (e, st) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.wifiOff, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text("Couldn't load group giving", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text("$e", style: TextStyle(color: Colors.grey.shade500, fontSize: 12), textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => ref.invalidate(groupContributionsProvider(tenantId)),
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text("Retry"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupCard(BuildContext context, GroupContribution group) {
    final progress = group.targetAmount > 0 ? (group.collectedAmount / group.targetAmount).clamp(0.0, 1.0) : 0.0;
    final freqLabel = {'one_time': 'One-time', 'weekly': 'Weekly', 'monthly': 'Monthly'}[group.frequency] ?? group.frequency;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GestureDetector(
        onTap: () => context.push('/fundraising/groups/${group.id}'),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB300).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(LucideIcons.users, color: Color(0xFFFFB300), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(group.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text(freqLabel, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                      ],
                    ),
                  ),
                  if (group.status == 'cancelled')
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                      child: const Text("Closed", style: TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              if (group.description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(group.description, style: TextStyle(color: Colors.grey.shade600, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.grey.shade100,
                  color: const Color(0xFFFFB300),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("K ${group.collectedAmount.toStringAsFixed(0)} raised", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  Text("Target: K ${group.targetAmount.toStringAsFixed(0)}", style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(LucideIcons.users, size: 14, color: Colors.grey.shade400),
                  const SizedBox(width: 4),
                  Text("${group.memberCount} members", style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
