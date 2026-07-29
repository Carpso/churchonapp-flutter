import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:latlong2/latlong.dart';
import 'package:church_on_app/core/widgets/church_map.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/weather_model.dart';
import '../data/weather_service.dart';
import '../data/logistics_model.dart';
import 'providers/weather_provider.dart';

class WeatherMapsScreen extends ConsumerWidget {
  const WeatherMapsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weatherAsync = ref.watch(refreshableWeatherProvider);
    final busesAsync = ref.watch(refreshableBusesProvider);
    final trafficAsync = ref.watch(refreshableTrafficAlertsProvider);
    final parkingAsync = ref.watch(refreshableParkingZonesProvider);
    final routesAsync = ref.watch(refreshableQuickRoutesProvider);

    final bgGradient = weatherAsync.when(
      data: (w) => w.theme.backgroundGradient,
      loading: () => const LinearGradient(
        colors: [Color(0xFF0284C7), Color(0xFF075985)],
      ),
      error: (_, __) => const LinearGradient(
        colors: [Color(0xFF0284C7), Color(0xFF075985)],
      ),
    );

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: bgGradient),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Header Bar
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    const Text(
                      "Weather & Logistics",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.refreshCw, color: Colors.white, size: 20),
                      onPressed: () {
                        ref.read(weatherRefreshProvider.notifier).refresh();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 15),

                // City Preset Selector Chips
                SizedBox(
                  height: 38,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: WeatherService.cityPresets.length,
                    itemBuilder: (context, index) {
                      final city = WeatherService.cityPresets[index];
                      final selectedCity = ref.watch(selectedCityPresetProvider);
                      final isSelected = selectedCity.name == city.name;

                      return GestureDetector(
                        onTap: () {
                          ref.read(selectedCityPresetProvider.notifier).selectCity(city);
                        },
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            city.name.split(',')[0],
                            style: TextStyle(
                              color: isSelected ? Colors.black : Colors.white,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),

                // Weather Main Card
                weatherAsync.when(
                  data: (weather) => _buildWeatherCard(context, weather),
                  loading: () => _buildWeatherShimmer(context),
                  error: (e, _) => _buildWeatherFallback(context),
                ),
                const SizedBox(height: 35),

                const Text(
                  "Live Church Bus Tracking",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 15),
                busesAsync.when(
                  data: (buses) => buses.isEmpty
                      ? _buildEmptyState("No buses running")
                      : _buildBusTrackingCard(context, buses.first, ref),
                  loading: () => _buildBusShimmer(),
                  error: (e, _) => _buildBusTrackingCard(
                    context,
                    BusInfo(
                      id: 'default',
                      name: 'Bus #4',
                      route: 'Great East Road',
                      eta: '--',
                      nextStop: '--',
                    ),
                    ref,
                  ),
                ),
                const SizedBox(height: 30),
                const Text(
                  "Traffic & Parking Alerts",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 15),
                trafficAsync.when(
                  data: (alerts) => _buildTrafficSection(context, alerts),
                  loading: () => const SizedBox(height: 150, child: Center(child: CircularProgressIndicator(color: Colors.white))),
                  error: (e, _) => _buildTrafficSection(context, []),
                ),
                const SizedBox(height: 20),
                const Text(
                  "Parking Zones",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 15),
                parkingAsync.when(
                  data: (zones) => Column(
                    children: zones.map((z) => _buildParkingCard(context, z)).toList(),
                  ),
                  loading: () => const SizedBox(height: 150, child: Center(child: CircularProgressIndicator(color: Colors.white))),
                  error: (e, _) => Column(
                    children: [
                      ParkingZone(name: 'Zone A - Main Church', available: 12, total: 50),
                      ParkingZone(name: 'Zone B - Overflow', available: 35, total: 40),
                    ].map((z) => _buildParkingCard(context, z)).toList(),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  "Quick Routes",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 15),
                routesAsync.when(
                  data: (routes) => Column(
                    children: routes.map((r) => _buildRouteCard(context, r)).toList(),
                  ),
                  loading: () => const SizedBox(height: 150, child: Center(child: CircularProgressIndicator(color: Colors.white))),
                  error: (e, _) => const SizedBox.shrink(),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWeatherCard(BuildContext context, WeatherData weather) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: weather.theme.cardGradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    weather.location,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "Updated Just Now",
                    style: TextStyle(color: weather.theme.subtextColor, fontSize: 12),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Icon(weather.theme.statusIcon, color: Colors.white, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      weather.theme.statusBadge,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 25),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                "${weather.temperature.round()}°",
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 64,
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 15),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    weather.condition,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Feels like ${weather.feelsLike.round()}°C",
                    style: TextStyle(color: weather.theme.subtextColor, fontSize: 13),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(color: Colors.white24, height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _WeatherStat(
                icon: LucideIcons.wind,
                label: "${weather.windSpeed.round()} km/h",
                subLabel: "Wind",
              ),
              _WeatherStat(
                icon: LucideIcons.droplets,
                label: "${weather.humidity.round()}%",
                subLabel: "Humidity",
              ),
              _WeatherStat(
                icon: LucideIcons.umbrella,
                label: "${weather.precipitation.round()}%",
                subLabel: "Precip",
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 24-Hour Forecast Breakdown
          const Text(
            "Hourly Breakdown",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 75,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: weather.hourly.length,
              itemBuilder: (context, index) {
                final h = weather.hourly[index];
                return Container(
                  width: 60,
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Text(
                        h.time,
                        style: const TextStyle(color: Colors.white70, fontSize: 10),
                      ),
                      Text(
                        WeatherService.weatherEmoji(h.weatherCode),
                        style: const TextStyle(fontSize: 14),
                      ),
                      Text(
                        "${h.temperature.round()}°",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),

          // 5-Day Daily Forecast
          const Text(
            "5-Day Forecast",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          Column(
            children: weather.daily.map((d) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    SizedBox(
                      width: 70,
                      child: Text(
                        d.dayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      WeatherService.weatherEmoji(d.weatherCode),
                      style: const TextStyle(fontSize: 16),
                    ),
                    Row(
                      children: [
                        Text(
                          "${d.maxTemp.round()}°",
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "${d.minTemp.round()}°",
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),

          // Weather Scripture Reflection Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.bookOpen, color: Colors.amber, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    weather.scriptureVerse,
                    style: const TextStyle(
                      color: Colors.white,
                      fontStyle: FontStyle.italic,
                      fontSize: 11.5,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeatherShimmer(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF4FACFE), Color(0xFF00F2FE)]),
        borderRadius: BorderRadius.circular(30),
      ),
      child: const Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text("Loading...", style: TextStyle(color: Colors.white70, fontSize: 18)),
                Text("Please wait", style: TextStyle(color: Colors.white38, fontSize: 12)),
              ]),
            ],
          ),
          SizedBox(height: 40),
          Center(child: CircularProgressIndicator(color: Colors.white)),
        ],
      ),
    );
  }

  Widget _buildWeatherFallback(BuildContext context) {
    return _buildWeatherCard(context, WeatherData(
      temperature: 28,
      feelsLike: 30,
      humidity: 45,
      windSpeed: 12,
      precipitation: 5,
      weatherCode: 0,
    ));
  }

  Widget _buildBusTrackingCard(BuildContext context, BusInfo bus, WidgetRef ref) {
    final userPos = const LatLng(-15.3880, 28.3230);
    return ClipRRect(
      borderRadius: BorderRadius.circular(25),
      child: SizedBox(
        height: 310,
        child: Stack(
          children: [
            ChurchMap(
              center: userPos,
              zoom: 14,
              markers: [
                ...bus.stops.map((s) => buildBusStopMarker(point: s.position, name: s.name)),
                buildUserMarker(point: userPos),
              ],
              path: bus.path.isNotEmpty ? bus.path : null,
            ),
            Positioned(
              bottom: 15, left: 15, right: 15,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10)]),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(LucideIcons.bus, color: Colors.orange, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text("${bus.name} → ${bus.route}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              Text("ETA: ${bus.eta} • Next Stop: ${bus.nextStop}", style: const TextStyle(color: Colors.grey, fontSize: 11)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (bus.driverPhone != null && bus.driverPhone!.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _buildContactButton(
                              icon: LucideIcons.phone,
                              label: 'In-App Call',
                              color: Colors.green,
                              onTap: () => _contactDriver(context, bus, method: 'call'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildContactButton(
                              icon: LucideIcons.smartphone,
                              label: 'Cellular',
                              color: Colors.blue,
                              onTap: () => _contactDriver(context, bus, method: 'cellular'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildContactButton(
                              icon: LucideIcons.messageCircle,
                              label: 'Chat',
                              color: Colors.orange,
                              onTap: () => _contactDriver(context, bus, method: 'chat'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  void _contactDriver(BuildContext context, BusInfo bus, {required String method}) async {
    final phone = bus.driverPhone;
    if (phone == null || phone.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Driver contact not available")),
        );
      }
      return;
    }

    if (method == 'call') {
      if (context.mounted) {
        Navigator.pushNamed(context, '/call', arguments: {
          'targetName': bus.driverName ?? 'Driver',
          'targetPhone': phone,
        });
      }
    } else if (method == 'cellular') {
      final uri = Uri(scheme: 'tel', path: phone);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Could not launch phone dialer")),
          );
        }
      }
    } else {
      if (context.mounted) {
        final userId = Supabase.instance.client.auth.currentUser?.id;
        if (userId != null) {
          Navigator.pushNamed(context, '/chat/$userId',
            arguments: {'contactName': bus.driverName ?? 'Driver'});
        }
      }
    }
  }

  Widget _buildBusShimmer() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(25),
      child: Container(
        height: 250,
        color: Colors.grey[200],
        child: const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  Widget _buildTrafficSection(BuildContext context, List<TrafficAlert> alerts) {
    final activeAlerts = alerts.where((a) => a.severity != 'low').toList();
    final badges = alerts.take(3).toList();

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            height: 180,
            child: Stack(
              children: [
                const ChurchMap(
                  center: LatLng(-15.3900, 28.3100),
                  zoom: 13,
                ),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.6)],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 12, left: 12, right: 12,
                  child: Row(
                    children: badges.map((a) {
                      final color = a.severity == 'high' ? Colors.red : a.severity == 'medium' ? Colors.orange : Colors.green;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                            decoration: BoxDecoration(color: color.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(10)),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(a.road, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                Text(a.status, style: const TextStyle(color: Colors.white70, fontSize: 8)),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 15),
        ...activeAlerts.map((a) {
          final color = a.severity == 'high' ? Colors.red : a.severity == 'medium' ? Colors.orange : Colors.green;
          final icon = a.severity == 'high' ? LucideIcons.alertTriangle : a.severity == 'medium' ? LucideIcons.trendingUp : LucideIcons.checkCircle;
          return Container(
            margin: const EdgeInsets.only(bottom: 15),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)]),
            child: Row(
              children: [
                Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 18)),
                const SizedBox(width: 15),
                Expanded(child: Text(a.description, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildParkingCard(BuildContext context, ParkingZone zone) {
    final statusColor = zone.isFull ? Colors.red : zone.isLow ? Colors.amber : Colors.green;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(LucideIcons.car, color: statusColor, size: 20),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(zone.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                Text("${zone.available} of ${zone.total} spots available", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Text(
              zone.status,
              style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteCard(BuildContext context, QuickRoute route) {
    final iconMap = {
      'home': LucideIcons.home,
      'shoppingBag': LucideIcons.shoppingBag,
      'plane': LucideIcons.plane,
    };
    final colorMap = {
      'home': Colors.blue,
      'shoppingBag': Colors.purple,
      'plane': Colors.green,
    };
    final icon = iconMap[route.iconName] ?? LucideIcons.navigation;
    final color = colorMap[route.iconName] ?? Colors.blue;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(route.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                Text(route.via, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Text(route.time, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Container(
      height: 250,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.bus, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(message, style: const TextStyle(color: Colors.grey, fontSize: 16)),
          ],
        ),
      ),
    );
  }
}

class _WeatherStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subLabel;
  const _WeatherStat({required this.icon, required this.label, required this.subLabel});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Icon(icon, color: Colors.white70, size: 20),
      const SizedBox(height: 5),
      Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
      Text(subLabel, style: const TextStyle(color: Colors.white54, fontSize: 10)),
    ]);
  }
}
