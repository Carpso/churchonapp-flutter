import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/i18n/l10n.dart';
import 'package:go_router/go_router.dart';
import 'home_section_title.dart';

class HomeQuickActions extends StatelessWidget {
  const HomeQuickActions({super.key});

  @override
  Widget build(BuildContext context) {
    final brand = Theme.of(context).primaryColor;
    final actions = [
      {"icon": LucideIcons.bookOpen, "label": "Sermons", "color": brand},
      {"icon": LucideIcons.calendar, "label": "Events", "color": Colors.orange},
      {"icon": LucideIcons.book, "label": "Bible", "color": Colors.green},
      {"icon": LucideIcons.qrCode, "label": "Check-in", "color": brand.withValues(alpha: 0.8)},
      {"icon": LucideIcons.flame, "label": "Fasting", "color": Colors.orange},
      {
        "icon": LucideIcons.helpCircle,
        "label": "Bible Quiz",
        "color": brand.withValues(alpha: 0.7),
      },
      {"icon": LucideIcons.penTool, "label": "Notebook", "color": Colors.brown},
      {"icon": LucideIcons.graduationCap, "label": "Bible Study", "color": Colors.teal},
      {
        "icon": LucideIcons.shoppingBag,
        "label": "Marketplace",
        "color": brand.withValues(alpha: 0.45),
      },
      {"icon": LucideIcons.car, "label": "Carpso Ride", "color": brand.withValues(alpha: 0.3)},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionTitle(title: context.tr('Quick Actions')),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            if (width < 600) {
              return SizedBox(
                height: 100,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: actions.length,
                  itemBuilder: (context, index) {
                    return Semantics(
                      label: "${actions[index]['label']} quick action",
                      button: true,
                      child: GestureDetector(
                        onTap: () =>
                            _handleTap(context, actions[index]['label'] as String),
                        child: _buildTile(context, actions[index], 80),
                      ),
                    );
                  },
                ),
              );
            }
            // Wide screens: wrap into a grid so all actions are visible.
            final perRow = (width / 100).floor().clamp(4, 10);
            final tileWidth = (width - 15 * (perRow - 1)) / perRow;
            return Wrap(
              spacing: 15,
              runSpacing: 15,
              children: [
                for (final action in actions)
                  GestureDetector(
                    onTap: () =>
                        _handleTap(context, action['label'] as String),
                    child: _buildTile(context, action, tileWidth),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildTile(BuildContext context, Map<String, Object> action, double width) {
    return Container(
      width: width,
      height: 100,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            (action['color'] as Color).withValues(alpha: 0.8),
            action['color'] as Color,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (action['color'] as Color).withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            action['icon'] as IconData,
            color: Colors.white,
            size: 28,
          ),
          const SizedBox(height: 8),
          Text(
            context.tr(action['label'] as String),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  void _handleTap(BuildContext context, String label) {
    final tenant = ProviderScope.containerOf(
      context,
    ).read(currentTenantProvider);
    if (label == "Fasting") {
      context.push('/fasting');
    } else if (label == "Life") {
      context.push('/more-hub');
    } else if (label == "Bible Quiz") {
      if (tenant?.settings?['game_arena'] == false) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "'Bible Quiz' module has been disabled by the Superadmin. 🔒",
            ),
            backgroundColor: Colors.amber,
          ),
        );
        return;
      }
      // Route through go_router so the subscription-expiry redirect guard
      // in app_router.dart is enforced (Navigator.push bypassed it).
      context.push('/quiz');
    } else if (label == "Bible") {
      context.push('/bible');
    } else if (label == "Bible Study") {
      context.push('/bible-study');
    } else if (label == "Check-in") {
      context.push('/ride-scanner');
    } else if (label == "Sermons") {
      context.push('/sermons');
    } else if (label == "Events") {
      if (tenant?.settings?['events_management'] == false) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "'Events' module has been disabled by the Superadmin. 🔒",
            ),
            backgroundColor: Colors.amber,
          ),
        );
        return;
      }
      context.push('/events');
    } else if (label == "Marketplace") {
      if (tenant?.settings?['marketplace'] == false) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "'Marketplace' module has been disabled by the Superadmin. 🔒",
            ),
            backgroundColor: Colors.amber,
          ),
        );
        return;
      }
      context.push('/marketplace');
    } else if (label == "Notebook") {
      context.push('/notebook');
    } else if (label == "Carpso Ride") {
      context.push('/ride');
    } else if (label == "Radio") {
      if (tenant?.settings?['kingdom_radio'] == false) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "'Radio' module has been disabled by the Superadmin. 🔒",
            ),
            backgroundColor: Colors.amber,
          ),
        );
        return;
      }
      context.push('/radio');
    }
  }
}
