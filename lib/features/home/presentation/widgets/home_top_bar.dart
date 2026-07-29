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
                    Text(
                      _abbreviateChurchName(tenant),
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
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
                minWidth: 36,
                minHeight: 36,
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
                minWidth: 36,
                minHeight: 36,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _abbreviateChurchName(Tenant? tenant) {
    if (tenant == null) return '';
    final shortName = tenant.shortName;
    if (shortName != null && shortName.trim().isNotEmpty) return shortName.trim();
    final name = tenant.name.trim();
    if (name.isEmpty) return 'Church';
    if (name.length <= 12) return name;
    return '${name.substring(0, 10)}...';
  }

  Widget _buildWeatherChip(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final weatherAsync = ref.watch(weatherDataProvider);

        final chipGradient = weatherAsync.when(
          data: (w) => w.theme.chipGradient,
          loading: () => const LinearGradient(
            colors: [Color(0xFF1E88E5), Color(0xFFFFB300)],
          ),
          error: (_, __) => const LinearGradient(
            colors: [Color(0xFF1E88E5), Color(0xFFFFB300)],
          ),
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
                gradient: chipGradient,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: weatherAsync.when(
                data: (weather) {
                  final emoji = weather.isHot
                      ? '🔥'
                      : WeatherService.weatherEmoji(weather.weatherCode);
                  final label = weather.isHot ? 'Hot' : weather.condition;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        emoji,
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        "${weather.temperature.round()}°C $label",
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
                      "--°C Weather",
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
                    Icon(LucideIcons.cloud, color: Colors.white, size: 14),
                    SizedBox(width: 4),
                    Text(
                      "28°C Clear",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ],
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
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        );
        return ref
            .watch(unreadCountProvider)
            .when(
              data: (count) => Badge(
                isLabelVisible: count > 0,
                label: Text(
                  count > 99 ? '99+' : '$count',
                  style: const TextStyle(fontSize: 10),
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
