import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:church_on_app/features/transport/data/navigation_controller.dart';
import 'package:church_on_app/features/transport/data/navigation_instructions.dart';

/// Top-of-map turn-by-turn banner: maneuver arrow + instruction + live
/// distance countdown + ETA, a mute button and a "Route steps" button.
///
/// Renders nothing when the route has no real maneuvers (straight-line
/// fallback) so the UI never shows fake guidance.
class NavigationBanner extends StatelessWidget {
  final NavigationState state;
  final bool muted;
  final VoidCallback onToggleMute;
  final VoidCallback? onShowSteps;

  const NavigationBanner({
    super.key,
    required this.state,
    required this.muted,
    required this.onToggleMute,
    this.onShowSteps,
  });

  @override
  Widget build(BuildContext context) {
    final route = state.route;
    if (!state.hasGuidance || route == null || route.steps.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final accent = theme.primaryColor;
    final step = state.nextStep ?? route.steps.last;
    final instruction = state.instruction.isNotEmpty
        ? state.instruction
        : maneuverPhrase(step);
    final isArrive = step.type.toLowerCase() == 'arrive';

    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(18),
      color: Colors.white,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: state.isOffRoute
                ? Colors.amber.shade700
                : accent.withValues(alpha: 0.25),
            width: state.isOffRoute ? 2 : 1,
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    maneuverIcon(step.type, step.modifier),
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        instruction,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.black87,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          if (!isArrive) ...[
                            Text(
                              state.distanceToManeuverText,
                              style: TextStyle(
                                color: accent,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              '  •  ',
                              style: TextStyle(color: Colors.grey.shade500),
                            ),
                          ],
                          Flexible(
                            child: Text(
                              '${state.etaText} • ${state.remainingText} left',
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: muted ? 'Unmute voice' : 'Mute voice',
                  icon: Icon(
                    muted ? LucideIcons.volumeX : LucideIcons.volume2,
                    color: muted ? Colors.grey : accent,
                  ),
                  onPressed: onToggleMute,
                ),
                if (onShowSteps != null)
                  IconButton(
                    tooltip: 'Route steps',
                    icon: const Icon(LucideIcons.list, color: Colors.black87),
                    onPressed: onShowSteps,
                  ),
              ],
            ),
            if (state.isRerouting)
              _statusStrip(
                Colors.amber.shade800,
                LucideIcons.refreshCw,
                'Rerouting…',
              )
            else if (state.isOffRoute)
              _statusStrip(
                Colors.amber.shade800,
                LucideIcons.alertTriangle,
                'You are off the route',
              )
            else if (state.error != null)
              _statusStrip(
                Colors.red.shade700,
                LucideIcons.alertTriangle,
                state.error!,
              ),
          ],
        ),
      ),
    );
  }

  Widget _statusStrip(Color color, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Maps an OSRM maneuver type/modifier to a directional Lucide icon.
IconData maneuverIcon(String type, String? modifier) {
  final t = type.toLowerCase();
  final m = (modifier ?? '').toLowerCase();
  switch (t) {
    case 'arrive':
      return LucideIcons.mapPin;
    case 'roundabout':
    case 'rotary':
    case 'roundabout turn':
    case 'exit roundabout':
    case 'exit rotary':
      return LucideIcons.refreshCw;
    case 'merge':
      return LucideIcons.gitMerge;
    case 'fork':
      return LucideIcons.gitFork;
    case 'depart':
      return LucideIcons.navigation;
    default:
      if (m.contains('uturn')) return LucideIcons.undo2;
      if (m.contains('left')) return LucideIcons.cornerUpLeft;
      if (m.contains('right')) return LucideIcons.cornerUpRight;
      return LucideIcons.arrowUp;
  }
}
