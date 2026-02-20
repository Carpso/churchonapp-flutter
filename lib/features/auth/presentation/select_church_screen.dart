import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:latlong2/latlong.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/widgets/church_map.dart';
import 'package:church_on_app/features/navigation/presentation/main_navigation_shell.dart';

class SelectChurchScreen extends ConsumerStatefulWidget {
  const SelectChurchScreen({super.key});

  @override
  ConsumerState<SelectChurchScreen> createState() => _SelectChurchScreenState();
}

class _SelectChurchScreenState extends ConsumerState<SelectChurchScreen> {
  List<Map<String, dynamic>> _churches = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchChurches();
  }

  Future<void> _fetchChurches() async {
    try {
      final data = await Supabase.instance.client
          .from('churches')
          .select('*')
          .eq('status', 'active');
      setState(() {
        _churches = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error fetching churches: $e');
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          ChurchMap(
            markers: _churches.asMap().entries.map((entry) {
              final index = entry.key;
              final church = entry.value;
              final lat = church['latitude'] ?? -15.3875 + (index * 0.01);
              final lng = church['longitude'] ?? 28.3228 + (index * 0.01);
              return buildChurchMarker(
                point: LatLng(lat as double, lng as double),
                name: church['name'],
                color: const Color(0xFFFFD700),
              );
            }).toList() + [
              buildUserMarker(point: const LatLng(-15.39, 28.32)),
            ],
          ),
          _buildSearchOverlay(),
          _buildChurchList(),
        ],
      ),
    );
  }

  Widget _buildSearchOverlay() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 20,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
        ),
        child: const TextField(
          decoration: InputDecoration(
            hintText: "Search for a church nearby...",
            border: InputBorder.none,
            icon: Icon(LucideIcons.search, size: 20, color: Colors.grey),
          ),
        ),
      ),
    );
  }

  Widget _buildChurchList() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        height: 350,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20)],
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 15),
              width: 50,
              height: 5,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 25, vertical: 10),
              child: Row(
                children: [
                  Text("Churches Near You", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Spacer(),
                  Icon(LucideIcons.mapPin, size: 16, color: Colors.grey),
                  SizedBox(width: 5),
                  Text("Lusaka", style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
            Expanded(
              child: _loading 
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 25),
                    itemCount: _churches.length,
                    itemBuilder: (context, index) {
                      final church = _churches[index];
                      return ListTile(
                        onTap: () => _selectChurch(church),
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        leading: CircleAvatar(
                          radius: 25,
                          backgroundColor: Colors.grey[100],
                          backgroundImage: church['logo_url'] != null ? NetworkImage(church['logo_url']) : null,
                          child: church['logo_url'] == null ? const Icon(LucideIcons.church) : null,
                        ),
                        title: Text(church['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(church['address'] ?? 'Lusaka, Zambia', style: const TextStyle(fontSize: 12)),
                        trailing: const Icon(LucideIcons.chevronRight, size: 18),
                      );
                    },
                  ),
            ),
          ],
        ),
      ),
    );
  }

  void _selectChurch(Map<String, dynamic> church) {
    ref.read(currentTenantProvider.notifier).setTenant(Tenant.fromMap(church));
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const MainNavigationShell()));
  }
}
