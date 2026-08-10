import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:go_router/go_router.dart';
import 'home_section_title.dart';

class HomeQuickActions extends StatelessWidget {
  const HomeQuickActions({super.key});

  @override
  Widget build(BuildContext context) {
    final actions = [
      {"icon": LucideIcons.book, "label": "Bible", "color": Colors.green},
      {"icon": LucideIcons.bookOpen, "label": "Sermons", "color": Colors.blue},
      {"icon": LucideIcons.calendar, "label": "Events", "color": Colors.orange},
      {"icon": LucideIcons.qrCode, "label": "Check-in", "color": Colors.purple},
      {"icon": LucideIcons.flame, "label": "Fasting", "color": Colors.orange},
      {"icon": LucideIcons.heart, "label": "Life", "color": Colors.red},
      {
        "icon": LucideIcons.helpCircle,
        "label": "Bible Quiz",
        "color": Colors.indigo,
      },
      {
        "icon": LucideIcons.shoppingBag,
        "label": "Marketplace",
        "color": Colors.teal,
      },
      {"icon": LucideIcons.penTool, "label": "Notebook", "color": Colors.brown},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const HomeSectionTitle(title: "Quick Actions"),
        SizedBox(
          height: 100,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: actions.length,
            itemBuilder: (context, index) {
              final label = actions[index]['label'] as String;
              return Semantics(
                label: "$label quick action",
                button: true,
                child: GestureDetector(
                  onTap: () => _handleTap(context, label),
                  child: Container(
                    width: 80,
                    margin: const EdgeInsets.only(right: 15),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          (actions[index]['color'] as Color).withValues(
                            alpha: 0.8,
                          ),
                          actions[index]['color'] as Color,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: (actions[index]['color'] as Color).withValues(
                            alpha: 0.3,
                          ),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          actions[index]['icon'] as IconData,
                          color: Colors.white,
                          size: 28,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
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
