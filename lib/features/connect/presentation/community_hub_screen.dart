import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'communities_screen.dart';
import 'ministries_screen.dart';

/// Merged Communities + Ministries view for the Connect tab. Ministries live
/// inside Communities — one place for groups, church members and ministries.
class CommunityHubScreen extends StatefulWidget {
  const CommunityHubScreen({super.key});

  @override
  State<CommunityHubScreen> createState() => _CommunityHubScreenState();
}

class _CommunityHubScreenState extends State<CommunityHubScreen> {
  bool _showMinistries = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildSegment(
                    context,
                    icon: LucideIcons.users,
                    label: 'Communities',
                    selected: !_showMinistries,
                    onTap: () => setState(() => _showMinistries = false),
                  ),
                ),
                Expanded(
                  child: _buildSegment(
                    context,
                    icon: LucideIcons.church,
                    label: 'Ministries',
                    selected: _showMinistries,
                    onTap: () => setState(() => _showMinistries = true),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
          child: Text(
            _showMinistries
                ? 'Service teams with leaders, meeting times & rosters (e.g. Choir, Ushering, Youth)'
                : 'Social groups for fellowship & chat — join any community to participate',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 11, height: 1.3),
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          child: _showMinistries
              ? const MinistriesScreen(embedded: true)
              : const CommunitiesScreen(),
        ),
      ],
    );
  }

  Widget _buildSegment(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Theme.of(context).primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: selected ? Colors.white : Colors.grey),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.grey,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}