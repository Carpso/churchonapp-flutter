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
          _buildWeatherChip(context),
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

  /// Weather chip: a fixed-size circle showing emoji + current temperature
  /// number, tappable → Weather & Maps. No Flexible/FittedBox squeezing —
  /// those let long church names compress the chip until the temperature
  /// text vanished. The circle keeps its intrinsic size; the church name
  /// truncates instead.
  Widget _buildWeatherChip(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final weatherAsync = ref.watch(weatherDataProvider);

        // Solid weather-appropriate background colors (no gradients)
        final chipBgColor = weatherAsync.when(
          data: (w) {
            if (w.isNight) return const Color(0xFF1E1B4B);
            if (w.weatherCode >= 95) return const Color(0xFF4C1D95);
            if (w.weatherCode >= 71 && w.weatherCode <= 77) {
              return const Color(0xFF0E7490);
            }
            if (w.weatherCode >= 51 && w.weatherCode <= 67) {
              return const Color(0xFF2563EB);
            }
            if (w.weatherCode >= 80 && w.weatherCode <= 82) {
              return const Color(0xFF334155);
            }
            if (w.weatherCode == 45 || w.weatherCode == 48) {
              return const Color(0xFF64748B);
            }
            if (w.isHot) return const Color(0xFFDC2626);
            if (w.weatherCode == 3) return const Color(0xFF475569);
            return const Color(0xFF0369A1); // Clear sky
          },
          loading: () => const Color(0xFF0369A1),
          error: (_, __) => const Color(0xFF64748B),
        );

        return Semantics(
          label: "Weather and maps. Current temperature.",
          button: true,
          child: Tooltip(
            message: 'Weather & Maps',
            child: InkWell(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const WeatherMapsScreen(),
                ),
              ),
              customBorder: const CircleBorder(),
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: chipBgColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                // Column stacks emoji over the temperature number so both are
                // always fully visible inside the same circle.
                alignment: Alignment.center,
                child: weatherAsync.when(
                  data: (w) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        w.isHot
                            ? '🔥'
                            : WeatherService.weatherEmoji(w.weatherCode),
                        style: const TextStyle(fontSize: 15),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '${w.temperature.isFinite ? w.temperature.round() : "--"}°',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          height: 1.1,
                          shadows: [
                            Shadow(color: Colors.black38, blurRadius: 3)
                          ],
                        ),
                      ),
                    ],
                  ),
                  loading: () => const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.sun, color: Colors.white, size: 15),
                      SizedBox(height: 1),
                      Text('--°',
                          style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w900,
                              fontSize: 11)),
                    ],
                  ),
                  error: (e, st) => const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.cloudOff,
                          color: Colors.white70, size: 15),
                      SizedBox(height: 1),
                      Text('--°',
                          style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w900,
                              fontSize: 11)),
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
