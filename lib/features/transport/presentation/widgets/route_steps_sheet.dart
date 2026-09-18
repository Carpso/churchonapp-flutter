import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:church_on_app/features/transport/data/navigation_instructions.dart';
import 'package:church_on_app/features/transport/data/route_service.dart';
import 'navigation_banner.dart' show maneuverIcon;

/// Shows the full turn-by-turn step list for a route. The step currently being
/// travelled is highlighted.
Future<void> showRouteStepsSheet(
  BuildContext context, {
  required RouteResult route,
  int currentIndex = 0,
}) {
  final steps = route.steps;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        builder: (ctx, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                  child: Row(
                    children: [
                      Icon(LucideIcons.list, color: theme.primaryColor),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Route steps',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                              ),
                            ),
                            Text(
                              '${route.distanceText} • ${route.etaText}',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.x, color: Colors.black54),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: steps.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('No turn-by-turn steps available.'),
                          ),
                        )
                      : ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: steps.length,
                          separatorBuilder: (_, __) => const Divider(
                            height: 1,
                            indent: 64,
                          ),
                          itemBuilder: (ctx, i) => _stepTile(
                            steps[i],
                            isCurrent: i == currentIndex,
                            accent: theme.primaryColor,
                          ),
                        ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

Widget _stepTile(
  RouteStep step, {
  required bool isCurrent,
  required Color accent,
}) {
  final subtitleParts = <String>[
    if (step.distanceMetres > 0) formatInstructionDistance(step.distanceMetres),
    if (step.durationSeconds > 0) _durationText(step.durationSeconds),
  ];
  return Container(
    color: isCurrent ? accent.withValues(alpha: 0.08) : null,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isCurrent ? accent : Colors.grey.shade100,
            shape: BoxShape.circle,
          ),
          child: Icon(
            maneuverIcon(step.type, step.modifier),
            size: 18,
            color: isCurrent ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                maneuverPhrase(step),
                style: TextStyle(
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                  fontSize: 14,
                ),
              ),
              if (subtitleParts.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitleParts.join(' • '),
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (isCurrent)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'NOW',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    ),
  );
}

String _durationText(int seconds) {
  if (seconds < 60) return '${seconds}s';
  final m = (seconds / 60).round();
  if (m < 60) return '$m min';
  final h = m ~/ 60;
  final rem = m % 60;
  return rem > 0 ? '$h hr $rem min' : '$h hr';
}
