import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';

import 'package:church_on_app/core/providers/profile_provider.dart';

class _ActionItem {
  const _ActionItem(this.icon, this.label, this.color, this.onTap);
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
}

class RoleQuickActions extends StatelessWidget {
  const RoleQuickActions({super.key, required this.profile});
  final UserProfile profile;

  List<_ActionItem> _buildActions(BuildContext context) {
    final actions = <_ActionItem>[];

    actions.add(_ActionItem(
      LucideIcons.users,
      'My Members',
      Theme.of(context).primaryColor,
      () => context.push('/admin/members'),
    ));
    actions.add(_ActionItem(
      LucideIcons.calendarDays,
      'Events',
      Colors.red,
      () => context.push('/admin/event-scheduler'),
    ));
    actions.add(_ActionItem(
      LucideIcons.uploadCloud,
      'Upload Sermon',
      Colors.orange,
      () => context.push('/media-upload'),
    ));
    actions.add(_ActionItem(
      LucideIcons.video,
      'Go Live',
      Colors.redAccent,
      () { if (profile.tenantId != null) context.push('/live-studio', extra: {'tenantId': profile.tenantId!}); },
    ));
    actions.add(_ActionItem(
      LucideIcons.megaphone,
      'Send Message',
      Theme.of(context).primaryColor,
      () => context.push('/global-broadcast'),
    ));
    actions.add(_ActionItem(
      LucideIcons.bookOpen,
      'Bookshop',
      Colors.orange,
      () => context.push('/bookshop-dashboard'),
    ));
    actions.add(_ActionItem(
      LucideIcons.map,
      'Growth Map',
      Theme.of(context).primaryColor,
      () => context.push('/prophetic-heatmap'),
    ));
    actions.add(_ActionItem(
      LucideIcons.bell,
      'Emergency (SOS)',
      Colors.red,
      () => context.push('/sos-alerts'),
    ));

    if (profile.isBishop) {
      actions.add(_ActionItem(
        LucideIcons.church,
        'My Churches',
        Theme.of(context).primaryColor,
        () => context.push('/select-church'),
      ));
      actions.add(_ActionItem(
        LucideIcons.wallet,
        'Money',
        Colors.green,
        () => context.push('/finance-dashboard'),
      ));
    } else {
      actions.add(_ActionItem(
        LucideIcons.fileText,
        'Reports',
        Colors.green,
        () => context.push('/pastor-report'),
      ));
    }

    return actions;
  }

  @override
  Widget build(BuildContext context) {
    final items = _buildActions(context);
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.25,
      children: items.map((item) => _ActionTile(item: item)).toList(),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.item});
  final _ActionItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: item.onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.1)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: item.color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
              child: Icon(item.icon, color: item.color, size: 24),
            ),
            const SizedBox(height: 10),
            Text(
              item.label,
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}
