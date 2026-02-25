import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:latlong2/latlong.dart';
import 'package:church_on_app/core/widgets/church_map.dart';

class WeatherMapsScreen extends ConsumerWidget {
  const WeatherMapsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text("Logistics & Navigation", style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(LucideIcons.refreshCw, size: 20), onPressed: () {}),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Premium Weather Card
            Container(
              padding: const EdgeInsets.all(25),
              decoration: BoxDecoration(
                gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF4FACFE), Color(0xFF00F2FE)]),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))],
              ),
              child: const Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text("Lusaka, Zambia", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                        Text("Today", style: TextStyle(color: Colors.white70, fontSize: 12)),
                      ]),
                    ],
                  ),
                  SizedBox(height: 30),
                  Row(children: [
                    Text("28°", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 60)),
                    SizedBox(width: 10),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text("Mostly Sunny", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      Text("Feels like 30°", style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ]),
                  ]),
                  Divider(color: Colors.white24, height: 40),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                    _WeatherStat(icon: LucideIcons.wind, label: "12 km/h", subLabel: "Wind"),
                    _WeatherStat(icon: LucideIcons.droplets, label: "45%", subLabel: "Humidity"),
                    _WeatherStat(icon: LucideIcons.umbrella, label: "5%", subLabel: "Precip"),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 40),
            
            // Live Church Bus Tracking (renamed from shuttle)
            const Text("Live Church Bus Tracking", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            ClipRRect(
              borderRadius: BorderRadius.circular(25),
              child: SizedBox(
                height: 250,
                child: Stack(
                  children: [
                    ChurchMap(
                      center: const LatLng(-15.3875, 28.3228),
                      zoom: 14,
                      markers: [
                        buildBusStopMarker(point: const LatLng(-15.3850, 28.3200), name: "Stop A"),
                        buildBusStopMarker(point: const LatLng(-15.3900, 28.3250), name: "Stop B"),
                        buildBusStopMarker(point: const LatLng(-15.3950, 28.3300), name: "Stop C"),
                        buildUserMarker(point: const LatLng(-15.3880, 28.3230)),
                      ],
                      path: const [
                        LatLng(-15.3850, 28.3200),
                        LatLng(-15.3870, 28.3220),
                        LatLng(-15.3900, 28.3250),
                        LatLng(-15.3930, 28.3280),
                        LatLng(-15.3950, 28.3300),
                      ],
                    ),
                    Positioned(
                      bottom: 15,
                      left: 15,
                      right: 15,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)]),
                        child: const Row(
                          children: [
                            Icon(LucideIcons.bus, color: Colors.orange, size: 22),
                            SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text("Bus #4 → Great East Road", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  Text("ETA: 2 mins • Next Stop: Stop B", style: TextStyle(color: Colors.grey, fontSize: 11)),
                                ],
                              ),
                            ),
                            Icon(LucideIcons.navigation, color: Colors.blue, size: 20),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),
            
            // Traffic & Parking - Live tracking
            const Text("Traffic & Parking Alerts", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),

            // Live traffic map
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                height: 180,
                child: Stack(
                  children: [
                    ChurchMap(
                      center: LatLng(-15.3900, 28.3100),
                      zoom: 13,
                    ),
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black.withOpacity(0.6)],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 12, left: 12, right: 12,
                      child: Row(
                        children: [
                          _buildTrafficBadge("Cairo Rd", Colors.red, "Heavy"),
                          const SizedBox(width: 8),
                          _buildTrafficBadge("Great East", Colors.orange, "Moderate"),
                          const SizedBox(width: 8),
                          _buildTrafficBadge("Kafue Rd", Colors.green, "Clear"),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 15),

            // Traffic alerts
            _buildTrafficAlert(context, "Cairo Road: Heavy traffic — Use Los Angeles Blvd", LucideIcons.alertTriangle, Colors.red),
            _buildTrafficAlert(context, "Great East Road: Moderate — Expect 10 min delay", LucideIcons.trendingUp, Colors.orange),
            _buildTrafficAlert(context, "Kafue Road: Clear — All lanes open", LucideIcons.checkCircle, Colors.green),
            
            const SizedBox(height: 20),
            const Text("Parking Zones", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            _buildParkingCard("Zone A - Main Church", 12, 50, Colors.green),
            _buildParkingCard("Zone B - Overflow", 35, 40, Colors.amber),
            _buildParkingCard("Zone C - VIP/Pastoral", 2, 10, Colors.green),
            _buildParkingCard("Zone D - Street Parking", 0, 20, Colors.red),

            const SizedBox(height: 20),
            const Text("Quick Routes", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            _buildRouteCard(context, "Home → Church", "12 min", "Via Great East Rd", LucideIcons.home, Colors.blue),
            _buildRouteCard(context, "Church → Mall", "8 min", "Via Addis Ababa Dr", LucideIcons.shoppingBag, Colors.purple),
            _buildRouteCard(context, "Church → Airport", "25 min", "Via Airport Rd", LucideIcons.plane, Colors.green),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildTrafficBadge(String road, Color color, String status) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(color: color.withOpacity(0.9), borderRadius: BorderRadius.circular(10)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(road, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            Text(status, style: const TextStyle(color: Colors.white70, fontSize: 8)),
          ],
        ),
      ),
    );
  }

  Widget _buildParkingCard(String zone, int available, int total, Color statusColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(LucideIcons.car, color: statusColor, size: 20),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(zone, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                Text("$available of $total spots available", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: Text(
              available == 0 ? "FULL" : available < 5 ? "LOW" : "OPEN",
              style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteCard(BuildContext context, String title, String time, String via, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                Text(via, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Text(time, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildTrafficAlert(BuildContext context, String text, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)]),
      child: Row(
        children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 18)),
          const SizedBox(width: 15),
          Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
        ],
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

