import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/core/widgets/kingdom_logo.dart';
import 'package:church_on_app/core/services/tenant_service.dart';

import 'package:church_on_app/features/auth/presentation/select_church_screen.dart'
    show SelectTenantScreen;
import 'package:church_on_app/features/modules/logistics/presentation/providers/weather_provider.dart';
import 'package:church_on_app/features/modules/logistics/data/weather_service.dart';
import 'package:church_on_app/features/modules/logistics/presentation/weather_maps_screen.dart';
import 'package:church_on_app/features/modules/navigation/presentation/more_hub_screen.dart';
import '../notifications_screen.dart';
import '../home_screen.dart' show unreadCountProvider;
import '../universal_search_screen.dart';

class HomeTopBar extends StatelessWidget {
  final Tenant? tenant;
  const HomeTopBar({super.key, this.tenant});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
      child: Row(
        children: [
          Semantics(
            label: "Select church",
            button: true,
            child: GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SelectTenantScreen(),
                ),
              ),
child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const KingdomLogo(size: 32),
                   if (tenant != null) ...[
                     const SizedBox(width: 8),
                     ConstrainedBox(
                       constraints: const BoxConstraints(maxWidth: 130),
                       child: Text(
                         _churchDisplayName(tenant),
                         style: GoogleFonts.plusJakartaSans(
                           fontWeight: FontWeight.bold,
                           fontSize: 12,
                         ),
                         overflow: TextOverflow.ellipsis,
                         maxLines: 2,
                       ),
                     ),
                  ],
                ],
              ),
            ),
          ),
          const Spacer(),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 56),
              child: _buildWeatherChip(context),
            ),
          ),
          const SizedBox(width: 4),
          _buildNotificationBell(context),
          Semantics(
            label: "Search",
            button: true,
            child: IconButton(
              icon: const Icon(LucideIcons.search, size: 20),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const UniversalSearchScreen(),
                ),
              ),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 40,
                minHeight: 40,
              ),
            ),
          ),
          Semantics(
            label: "More menu",
            button: true,
            child: IconButton(
              icon: Icon(
                LucideIcons.layoutGrid,
                size: 20,
                color: Theme.of(context).primaryColor,
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const MoreHubScreen(),
                ),
              ),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 40,
                minHeight: 40,
              ),
            ),
          ),
        ],
      ),
    );
  }

String _churchDisplayName(Tenant? tenant) {
    if (tenant == null) return '';
    final name = tenant.name.trim();
    return name.isEmpty ? 'Church' : name;
  }

  Widget _buildWeatherChip(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final weatherAsync = ref.watch(weatherDataProvider);

        // Solid weather-appropriate background colors (no gradients)
        final chipBgColor = weatherAsync.when(
          data: (w) {
            if (w.isNight) return const Color(0xFF1E1B4B);
            if (w.isRainy) return const Color(0xFF334155);
            if (w.isHot) return const Color(0xFFDC2626);
            if (w.weatherCode == 3) return const Color(0xFF475569);
            if (w.weatherCode >= 51 && w.weatherCode <= 67) return const Color(0xFF2563EB);
            return const Color(0xFF0369A1); // Clear sky
          },
          loading: () => const Color(0xFF0369A1),
          error: (_, __) => const Color(0xFF64748B),
        );

        return Semantics(
          label: "Weather and maps",
          button: true,
          child: GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const WeatherMapsScreen(),
              ),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: chipBgColor,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: weatherAsync.when(
                  data: (weather) {
                    final emoji = weather.isHot
                        ? '🔥'
                        : WeatherService.weatherEmoji(weather.weatherCode);
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          emoji,
                          style: const TextStyle(fontSize: 13),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          "${weather.temperature.isFinite ? weather.temperature.round() : 0}°C",
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            shadows: [
                              Shadow(
                                color: Colors.black38,
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                  loading: () => const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.sun, color: Colors.white, size: 14),
                      SizedBox(width: 4),
                      Text(
                        "--°",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  error: (_, __) => const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        LucideIcons.cloudOff,
                        color: Colors.white70,
                        size: 14,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNotificationBell(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final iconColor = Theme.of(context).brightness == Brightness.dark
            ? Colors.white70
            : Colors.black87;
        final bellButton = Semantics(
          label: "Notifications",
          button: true,
          child: IconButton(
            icon: Icon(LucideIcons.bell, size: 20, color: iconColor),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            ),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          ),
        );
        return ref
            .watch(unreadCountProvider)
            .when(
              data: (count) => Badge(
                isLabelVisible: count > 0,
                label: Text(
                  count > 99 ? '99+' : '$count',
                  style: const TextStyle(fontSize: 11),
                ),
                child: bellButton,
              ),
              loading: () => bellButton,
              error: (_, __) => bellButton,
            );
      },
    );
  }
}
