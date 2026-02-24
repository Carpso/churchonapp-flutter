import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:latlong2/latlong.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/widgets/church_map.dart';
import 'package:church_on_app/features/navigation/presentation/main_navigation_shell.dart';
import 'package:go_router/go_router.dart';
import 'church_onboarding_screen.dart';

class SelectChurchScreen extends ConsumerStatefulWidget {
  const SelectChurchScreen({super.key});

  @override
  ConsumerState<SelectChurchScreen> createState() => _SelectChurchScreenState();
}

class _SelectChurchScreenState extends ConsumerState<SelectChurchScreen> {
  List<Map<String, dynamic>> _churches = [];
  List<Map<String, dynamic>> _filteredChurches = [];
  Set<String> _registeredIds = {};
  bool _loading = true;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchChurches();
  }

  Future<void> _fetchChurches() async {
    try {
      final data = await Supabase.instance.client.from('churches').select('*');
      final registered = List<Map<String, dynamic>>.from(data);
      final regIds = registered.map((c) => c['id'].toString()).toSet();

      // Merge DB churches with all Zambian churches
      final allChurches = _getAllZambianChurches();
      for (final dbChurch in registered) {
        // Update any matching hardcoded church with DB data
        final idx = allChurches.indexWhere((c) => c['slug'] == dbChurch['slug']);
        if (idx >= 0) {
          allChurches[idx] = {...allChurches[idx], ...dbChurch, '_registered': true};
        } else {
          allChurches.add({...dbChurch, '_registered': true});
        }
      }

      if (mounted) {
        setState(() {
          _churches = allChurches;
          _filteredChurches = allChurches;
          _registeredIds = regIds;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching churches: $e');
      if (mounted) {
        setState(() {
          _churches = _getAllZambianChurches();
          _filteredChurches = _churches;
          _loading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> _getAllZambianChurches() {
    return [
      // ── LUSAKA ──
      {'id': 'zm_1', 'slug': 'bread-of-life', 'name': 'Bread of Life Church International', 'address': 'Addis Ababa Drive, Lusaka', 'latitude': -15.3872, 'longitude': 28.3165, 'primary_color': '#8B5CF6', '_registered': false},
      {'id': 'zm_2', 'slug': 'northmead-ag', 'name': 'Northmead Assembly of God', 'address': 'Great East Road, Northmead, Lusaka', 'latitude': -15.3980, 'longitude': 28.3100, 'primary_color': '#3B82F6', '_registered': false},
      {'id': 'zm_3', 'slug': 'chapel-zambia', 'name': 'The Chapel Zambia', 'address': 'Ibex Hill, Lusaka', 'latitude': -15.4150, 'longitude': 28.3550, 'primary_color': '#EF4444', '_registered': false},
      {'id': 'zm_4', 'slug': 'grace-chapel-intl', 'name': 'Grace Chapel International', 'address': 'Plot 123, Great East Rd, Lusaka', 'latitude': -15.3875, 'longitude': 28.3228, 'primary_color': '#FFD700', '_registered': false},
      {'id': 'zm_5', 'slug': 'victory-ministries', 'name': 'Victory Ministries International', 'address': 'Kafue Road, Chilenje, Lusaka', 'latitude': -15.4100, 'longitude': 28.3050, 'primary_color': '#10B981', '_registered': false},
      {'id': 'zm_6', 'slug': 'ucz-cathedral', 'name': 'UCZ Cathedral of the Holy Cross', 'address': 'Cathedral Hill, Lusaka', 'latitude': -15.4166, 'longitude': 28.2833, 'primary_color': '#6366F1', '_registered': false},
      {'id': 'zm_7', 'slug': 'kingsland-church', 'name': 'Kingsland Baptist Church', 'address': 'Kabulonga, Lusaka', 'latitude': -15.4200, 'longitude': 28.3200, 'primary_color': '#F59E0B', '_registered': false},
      {'id': 'zm_8', 'slug': 'kabwata-church', 'name': 'Kabwata Baptist Church', 'address': 'Kabwata, Lusaka', 'latitude': -15.4250, 'longitude': 28.2900, 'primary_color': '#059669', '_registered': false},
      {'id': 'zm_9', 'slug': 'faith-alive', 'name': 'Faith Alive Ministries', 'address': 'Kalingalinga, Lusaka', 'latitude': -15.4050, 'longitude': 28.3350, 'primary_color': '#DC2626', '_registered': false},
      {'id': 'zm_10', 'slug': 'new-apostolic-lsk', 'name': 'New Apostolic Church Lusaka', 'address': 'Olympia, Lusaka', 'latitude': -15.4000, 'longitude': 28.2950, 'primary_color': '#7C3AED', '_registered': false},
      {'id': 'zm_11', 'slug': 'rhema-word', 'name': 'Rhema Bible Church', 'address': 'Makeni, Lusaka', 'latitude': -15.4300, 'longitude': 28.3400, 'primary_color': '#0EA5E9', '_registered': false},
      {'id': 'zm_12', 'slug': 'livingstone-central', 'name': 'Central SDA Church Lusaka', 'address': 'Woodlands, Lusaka', 'latitude': -15.3950, 'longitude': 28.3000, 'primary_color': '#14B8A6', '_registered': false},
      {'id': 'zm_13', 'slug': 'zambia-shall-be-saved', 'name': 'Zambia Shall Be Saved Ministry', 'address': 'Cairo Road, Lusaka', 'latitude': -15.4166, 'longitude': 28.2870, 'primary_color': '#F97316', '_registered': false},
  
      // ── KITWE (Copperbelt) ──
      {'id': 'zm_14', 'slug': 'kitwe-chapel', 'name': 'Kitwe Chapel', 'address': 'Obote Avenue, Kitwe', 'latitude': -12.8024, 'longitude': 28.2132, 'primary_color': '#3B82F6', '_registered': false},
      {'id': 'zm_15', 'slug': 'ucz-mindolo', 'name': 'UCZ Mindolo Congregation', 'address': 'Mindolo, Kitwe', 'latitude': -12.8100, 'longitude': 28.2300, 'primary_color': '#6366F1', '_registered': false},
      {'id': 'zm_16', 'slug': 'sol-kitwe', 'name': 'Salvation Army Kitwe Citadel', 'address': 'Independence Avenue, Kitwe', 'latitude': -12.8050, 'longitude': 28.2100, 'primary_color': '#DC2626', '_registered': false},

      // ── NDOLA ──
      {'id': 'zm_17', 'slug': 'ndola-baptist', 'name': 'Ndola Baptist Church', 'address': 'Broadway, Ndola', 'latitude': -12.9587, 'longitude': 28.6366, 'primary_color': '#10B981', '_registered': false},
      {'id': 'zm_18', 'slug': 'dag-ndola', 'name': 'Dag Heward-Mills Church Ndola', 'address': 'Kansenshi, Ndola', 'latitude': -12.9700, 'longitude': 28.6400, 'primary_color': '#8B5CF6', '_registered': false},

      // ── LIVINGSTONE ──
      {'id': 'zm_19', 'slug': 'livingstone-ag', 'name': 'Livingstone Assembly of God', 'address': 'Mosi-oa-Tunya Road, Livingstone', 'latitude': -17.8419, 'longitude': 25.8606, 'primary_color': '#F59E0B', '_registered': false},
      {'id': 'zm_20', 'slug': 'victory-liv', 'name': 'Victory Assembly Livingstone', 'address': 'Central Livingstone', 'latitude': -17.8450, 'longitude': 25.8550, 'primary_color': '#EF4444', '_registered': false},

      // ── KABWE ──
      {'id': 'zm_21', 'slug': 'kabwe-central', 'name': 'Kabwe Central SDA Church', 'address': 'Freedom Way, Kabwe', 'latitude': -14.4376, 'longitude': 28.4512, 'primary_color': '#14B8A6', '_registered': false},

      // ── CHIPATA ──
      {'id': 'zm_22', 'slug': 'chipata-ucz', 'name': 'UCZ Chipata Congregation', 'address': 'Chipata Town Centre', 'latitude': -13.6333, 'longitude': 32.6500, 'primary_color': '#6366F1', '_registered': false},

      // ── SOLWEZI ──
      {'id': 'zm_23', 'slug': 'solwezi-gospel', 'name': 'Solwezi Gospel Church', 'address': 'Main Road, Solwezi', 'latitude': -12.1667, 'longitude': 25.8667, 'primary_color': '#059669', '_registered': false},

      // ── KASAMA ──
      {'id': 'zm_24', 'slug': 'kasama-ag', 'name': 'Kasama Assembly of God', 'address': 'Zambia Road, Kasama', 'latitude': -10.2130, 'longitude': 31.1811, 'primary_color': '#0EA5E9', '_registered': false},

      // ── MANSA ──
      {'id': 'zm_25', 'slug': 'mansa-ucz', 'name': 'UCZ Mansa Congregation', 'address': 'Mansa Town', 'latitude': -11.2006, 'longitude': 28.8894, 'primary_color': '#7C3AED', '_registered': false},

      // ── MONGU ──
      {'id': 'zm_26', 'slug': 'mongu-baptist', 'name': 'Mongu Baptist Church', 'address': 'Independence Ave, Mongu', 'latitude': -15.2547, 'longitude': 23.1283, 'primary_color': '#F97316', '_registered': false},

      // ── MAZABUKA ──
      {'id': 'zm_27', 'slug': 'mazabuka-ag', 'name': 'Mazabuka Assembly of God', 'address': 'Livingstone Road, Mazabuka', 'latitude': -15.8560, 'longitude': 27.7480, 'primary_color': '#3B82F6', '_registered': false},

      // ── CHOMA ──
      {'id': 'zm_28', 'slug': 'choma-chapel', 'name': 'Choma Community Chapel', 'address': 'Main Street, Choma', 'latitude': -16.5414, 'longitude': 26.9877, 'primary_color': '#10B981', '_registered': false},

      // ── MPIKA ──
      {'id': 'zm_29', 'slug': 'mpika-home', 'name': 'New Apostolic Church Mpika', 'address': 'Great North Road, Mpika', 'latitude': -11.8310, 'longitude': 31.4581, 'primary_color': '#DC2626', '_registered': false},

      // ── KAPIRI MPOSHI ──
      {'id': 'zm_30', 'slug': 'kapiri-sda', 'name': 'Kapiri Mposhi SDA Church', 'address': 'Great North Road, Kapiri Mposhi', 'latitude': -14.9710, 'longitude': 28.6831, 'primary_color': '#14B8A6', '_registered': false},
    ];
  }

  void _filterChurches(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredChurches = _churches;
      } else {
        _filteredChurches = _churches.where((c) {
          final name = (c['name'] ?? '').toString().toLowerCase();
          final address = (c['address'] ?? '').toString().toLowerCase();
          return name.contains(query.toLowerCase()) || address.contains(query.toLowerCase());
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          ChurchMap(
            center: const LatLng(-15.3875, 28.3228),
            zoom: 6, // Show all of Zambia
            markers: _filteredChurches.map((church) {
              final lat = (church['latitude'] ?? -15.3875) as num;
              final lng = (church['longitude'] ?? 28.3228) as num;
              final isRegistered = church['_registered'] == true;
              return buildChurchMarker(
                point: LatLng(lat.toDouble(), lng.toDouble()),
                name: church['name'] ?? 'Church',
                color: isRegistered ? const Color(0xFFFFD700) : Colors.grey,
                logoUrl: church['logo_url'],
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
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10)],
        ),
        child: TextField(
          controller: _searchController,
          onChanged: _filterChurches,
          decoration: const InputDecoration(
            hintText: "Search for a church in Zambia...",
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
        height: 380,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 20)],
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 15),
              width: 50, height: 5,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 10),
              child: Row(
                children: [
                  const Text("Churches in Zambia", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  const Icon(LucideIcons.mapPin, size: 16, color: Colors.grey),
                  const SizedBox(width: 5),
                  const Text("Zambia", style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
                    child: Text("${_filteredChurches.length}", style: const TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                ? const Center(child: CircularProgressIndicator(color: Colors.amber))
                : _filteredChurches.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.church, size: 50, color: Colors.grey[300]),
                          const SizedBox(height: 10),
                          Text("No churches found", style: TextStyle(color: Colors.grey[400])),
                          const SizedBox(height: 5),
                          TextButton(onPressed: _fetchChurches, child: const Text("Tap to retry")),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 25),
                      itemCount: _filteredChurches.length + 1,
                      itemBuilder: (context, index) {
                        if (index == _filteredChurches.length) {
                          return _buildOnboardingTile();
                        }
                        return _buildChurchTile(_filteredChurches[index]);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChurchTile(Map<String, dynamic> church) {
    final isRegistered = church['_registered'] == true;

    return GestureDetector(
      onTap: () {
        if (isRegistered) {
          _selectChurch(church);
        } else {
          _showNotRegisteredDialog(church);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: isRegistered ? Colors.grey[50] : Colors.grey[50]?.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isRegistered ? Colors.amber.withValues(alpha: 0.3) : Colors.grey.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 25,
              backgroundColor: isRegistered ? Colors.amber.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
              backgroundImage: church['logo_url'] != null ? NetworkImage(church['logo_url']) : null,
              child: church['logo_url'] == null
                ? Icon(LucideIcons.church, color: isRegistered ? Colors.amber : Colors.grey)
                : null,
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    church['name'] ?? 'Church',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isRegistered ? Colors.black : Colors.grey[600]),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    church['address'] ?? 'Zambia',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
            if (isRegistered)
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: const Icon(LucideIcons.checkCircle, size: 16, color: Colors.green),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: const Text("Pending", style: TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOnboardingTile() {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ChurchOnboardingScreen())),
      child: Container(
        margin: const EdgeInsets.only(bottom: 30, top: 10),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(25),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(color: Colors.amber, shape: BoxShape.circle),
              child: const Icon(LucideIcons.plus, color: Colors.black, size: 20),
            ),
            const SizedBox(width: 15),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Register a New Church", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  Text("Join the Kingdom digital ecosystem today.", style: TextStyle(color: Colors.grey, fontSize: 11)),
                ],
              ),
            ),
            const Icon(LucideIcons.chevronRight, size: 18, color: Colors.amber),
          ],
        ),
      ),
    );
  }

  void _showNotRegisteredDialog(Map<String, dynamic> church) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: Row(
          children: [
            Icon(LucideIcons.info, color: Colors.amber.shade700),
            const SizedBox(width: 10),
            const Expanded(child: Text("Not Yet Available", style: TextStyle(fontSize: 18))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              church['name'] ?? 'This church',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 10),
            const Text(
              "This church has not yet registered on Church On App. Once they sign up and activate their profile, you'll be able to join their community.",
              style: TextStyle(color: Colors.grey, height: 1.5),
            ),
            const SizedBox(height: 15),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
              child: const Row(
                children: [
                  Icon(LucideIcons.bell, size: 16, color: Colors.amber),
                  SizedBox(width: 8),
                  Expanded(child: Text("We'll notify you when they join!", style: TextStyle(fontSize: 12, color: Colors.amber, fontWeight: FontWeight.bold))),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK")),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("You'll be notified when ${church['name']} joins!"), backgroundColor: Colors.green),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
            child: const Text("NOTIFY ME"),
          ),
        ],
      ),
    );
  }

  void _selectChurch(Map<String, dynamic> church) {
    ref.read(currentTenantProvider.notifier).setTenant(Tenant.fromMap(church));
    context.go('/');
  }
}
