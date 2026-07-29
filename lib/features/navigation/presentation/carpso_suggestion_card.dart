import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';

class CarpsoSuggestionCard extends ConsumerWidget {
  final String contextType;
  final VoidCallback? onDismiss;

  const CarpsoSuggestionCard({
    super.key,
    this.contextType = 'general',
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestion = _getSuggestion(contextType);
    if (suggestion == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4F46E5).withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _handleTap(context, suggestion),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(suggestion.icon, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        suggestion.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        suggestion.subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text("Ride", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(width: 4),
                      Icon(LucideIcons.chevronRight, color: Colors.white.withValues(alpha: 0.7), size: 14),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  _SuggestionData? _getSuggestion(String contextType) {
    switch (contextType) {
      case 'home':
        return _SuggestionData(
          icon: LucideIcons.car,
          title: "Need a ride to church?",
          subtitle: "Book a Carpso Ride and get there safely",
          mode: 'ride',
          preset: 'church',
        );
      case 'marketplace':
        return _SuggestionData(
          icon: LucideIcons.package,
          title: "Delivery available",
          subtitle: "Get your purchases delivered via Carpso Ride",
          mode: 'delivery',
          preset: 'marketplace',
        );
      case 'event':
        return _SuggestionData(
          icon: LucideIcons.calendar,
          title: "Ride to this event",
          subtitle: "Book a Carpso Ride to and from the venue",
          mode: 'ride',
          preset: 'general',
        );
      case 'connect':
        return _SuggestionData(
          icon: LucideIcons.users,
          title: "Carpool with church members",
          subtitle: "Share a ride and connect on the way",
          mode: 'ride',
          preset: 'church',
        );
      default:
        return _SuggestionData(
          icon: LucideIcons.car,
          title: "Carpso Ride",
          subtitle: "Safe, affordable rides for the church community",
          mode: 'ride',
          preset: 'general',
        );
    }
  }

  void _handleTap(BuildContext context, _SuggestionData data) {
    context.push('/ride', extra: {
      'mode': data.mode,
      'preset': data.preset,
    });
  }
}

class _SuggestionData {
  final IconData icon;
  final String title;
  final String subtitle;
  final String mode;
  final String preset;

  _SuggestionData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.mode,
    required this.preset,
  });
}
