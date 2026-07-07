import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/expansion_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/widgets/church_map.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';

class SelectChurchScreen extends ConsumerStatefulWidget {
  const SelectChurchScreen({super.key});

  @override
  ConsumerState<SelectChurchScreen> createState() => _SelectChurchScreenState();
}

class _SelectChurchScreenState extends ConsumerState<SelectChurchScreen> {
  List<Map<String, dynamic>> _churches = [];
  List<Map<String, dynamic>> _filteredChurches = [];
  // ignore: unused_field
  final Set<String> _registeredIds = {};
  bool _loading = true;
  Position? _currentPosition;
  String _currentCountry = "Zambia";
  bool _showOnlyRegistered = false;
  final _searchController = TextEditingController();
  LatLng? _pinPosition;

  @override
  void initState() {
    super.initState();
    _initChurches();
  }

  Future<void> _initChurches() async {
    // Fetch immediately so the list displays fallback offline churches right away
    await _fetchChurches();
    
    // Attempt to resolve user location in background to calculate distances
    _getUserLocation().then((_) {
      if (mounted) {
        _fetchChurches();
      }
    }).catchError((e) {
      debugPrint('Error loading user location: $e');
    });
  }

  Future<void> _getUserLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      
      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        final position = await Geolocator.getCurrentPosition();
        if (mounted) {
          setState(() {
            _currentPosition = position;
            // Simple bound check for Zimbabwe vs Zambia
            if (position.latitude < -17.5 && position.longitude > 25.0 && position.longitude < 33.0) {
              _currentCountry = "Zimbabwe";
            } else {
              _currentCountry = "Zambia";
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error getting location: $e');
    }
  }

  Future<void> _fetchChurches() async {
    try {
      final data = await Supabase.instance.client.from('churches').select('*');
      final registered = List<Map<String, dynamic>>.from(data);
      final regIds = registered.map((c) => c['id'].toString()).toSet();

      // Merge DB churches with all Zambia & Zimbabwe churches
      final allChurches = [
        ..._getAllZambianChurches(),
        ..._getAllZimbabweanChurches(),
      ].map((c) {
        // Only Rock of Ages Kabulonga is registered/approved by default
        final isROA = c['slug'] == 'rock-of-ages-kabulonga';
        return {...c, '_registered': isROA};
      }).toList();

      for (final dbChurch in registered) {
        // Update any matching hardcoded church with DB data
        final idx = allChurches.indexWhere((c) => c['slug'] == dbChurch['slug']);
        final isVerified = dbChurch['is_verified'] == true;
        if (idx >= 0) {
          allChurches[idx] = {...allChurches[idx], ...dbChurch, '_registered': isVerified};
        } else {
          allChurches.add({...dbChurch, '_registered': isVerified});
        }
      }

      // Add distance if position available
      if (_currentPosition != null) {
        for (var church in allChurches) {
          final lat = (church['latitude'] ?? 0.0) as num;
          final lng = (church['longitude'] ?? 0.0) as num;
          if (lat != 0.0) {
            final distance = Geolocator.distanceBetween(
              _currentPosition!.latitude, 
              _currentPosition!.longitude, 
              lat.toDouble(), 
              lng.toDouble()
            );
            church['_distance'] = distance;
          }
        }
      }

      // Sort: Proximity First (if location available), otherwise Registered First
      allChurches.sort((a, b) {
        if (_currentPosition != null) {
          final distA = (a['_distance'] ?? 9999999.0) as double;
          final distB = (b['_distance'] ?? 9999999.0) as double;
          if (distA != distB) return distA.compareTo(distB);
        }
        final regA = a['_registered'] == true ? 0 : 1;
        final regB = b['_registered'] == true ? 0 : 1;
        return regA.compareTo(regB);
      });

      debugPrint('DB churches: ${registered.length}');
      debugPrint('Total churches (merged): ${allChurches.length}');
      if (mounted) {
        setState(() {
          _churches = allChurches;
          _filteredChurches = allChurches;
          _registeredIds.clear();
          _registeredIds.addAll(regIds);
          _loading = false;
        });
      }
    } catch (e, stackTrace) {
      debugPrint('Error fetching churches: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          final offlineChurches = [
            ..._getAllZambianChurches(),
            ..._getAllZimbabweanChurches(),
          ].map((c) {
            final isROA = c['slug'] == 'rock-of-ages-kabulonga';
            return {...c, '_registered': isROA};
          }).toList();
          _churches = offlineChurches;
          _filteredChurches = offlineChurches;
          _loading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> _getAllZambianChurches() {
    return TenantService.fallbackChurches.where((c) => c['country'] == 'Zambia').toList();
  }

  List<Map<String, dynamic>> _getAllZimbabweanChurches() {
    return TenantService.fallbackChurches.where((c) => c['country'] == 'Zimbabwe').toList();
  }

  void _filterChurches(String query) {
    setState(() {
      if (query.isEmpty) {
        if (_showOnlyRegistered) {
          _filteredChurches = _churches.where((c) => c['_registered'] == true).toList();
        } else {
          _filteredChurches = _churches;
        }
      } else {
        _filteredChurches = _churches.where((c) {
          final name = (c['name'] ?? '').toString().toLowerCase();
          final address = (c['address'] ?? '').toString().toLowerCase();
          final country = (c['country'] ?? '').toString().toLowerCase();
          final matchesQuery = name.contains(query.toLowerCase()) || 
                               address.contains(query.toLowerCase()) ||
                               country.contains(query.toLowerCase());
          
          if (_showOnlyRegistered) {
            return matchesQuery && c['_registered'] == true;
          }
          return matchesQuery;
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);
    final isSuperadmin = profileAsync.value?.isSuperadmin == true;

    final center = _currentPosition != null 
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : (_currentCountry == "Zimbabwe" ? const LatLng(-17.825, 31.053) : const LatLng(-15.3875, 28.3228));

    return Scaffold(
      body: Stack(
        children: [
          ChurchMap(
            center: center,
            pmtilesUrl: _currentCountry == "Zimbabwe" 
                ? dotenv.get('MAPS_ZIMBABWE_URL') 
                : dotenv.get('MAPS_ZAMBIA_URL'),
            zoom: _currentPosition != null ? 13 : 6,
            showPin: true,
            initialPinPosition: _pinPosition,
            onPinChanged: (point) {
              setState(() => _pinPosition = point);
            },
            showAddressSearch: true,
            addressSearchHint: "Search address in $_currentCountry...",
            onAddressSelected: (address) {
              _searchController.text = address;
            },
            markers: _filteredChurches.map((church) {
              final lat = (church['latitude'] ?? -15.3875) as num;
              final lng = (church['longitude'] ?? 28.3228) as num;
              final isRegistered = church['_registered'] == true;
              return buildChurchMarker(
                point: LatLng(lat.toDouble(), lng.toDouble()),
                name: church['name'] ?? 'Church',
                color: isRegistered ? Theme.of(context).primaryColor : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                logoUrl: church['logo_url'],
                onTap: () {
                  if (isRegistered) {
                    _selectChurch(church);
                  } else {
                    _showNotRegisteredDialog(church);
                  }
                },
              );
            }).toList() + [

              if (_currentPosition != null) buildUserMarker(point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude)),
            ],
          ),
          _buildSearchOverlay(),
          _buildChurchList(isSuperadmin),
        ],
      ),
    );
  }

  Widget _buildSearchOverlay() {
    final theme = Theme.of(context);
    return Positioned(
      top: MediaQuery.of(context).padding.top + 20,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10)],
        ),
        child: TextField(
          controller: _searchController,
          onChanged: _filterChurches,
          decoration: InputDecoration(
            hintText: "Search churches in $_currentCountry...",
            border: InputBorder.none,
            icon: Icon(Icons.search, size: 20, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
          ),
        ),
      ),
    );
  }

  Widget _buildChurchList(bool isSuperadmin) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        height: 380,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 20)],
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 15),
              width: 50, height: 5,
              decoration: BoxDecoration(color: theme.colorScheme.onSurface.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Available Churches", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                      Row(
                        children: [
                          Icon(Icons.location_on, size: 14, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                          const SizedBox(width: 4),
                          Text(_currentCountry, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _showOnlyRegistered = !_showOnlyRegistered;
                        _filterChurches(_searchController.text);
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: _showOnlyRegistered ? theme.primaryColor.withValues(alpha: 0.15) : theme.colorScheme.onSurface.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _showOnlyRegistered ? theme.primaryColor : theme.colorScheme.onSurface.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _showOnlyRegistered ? Icons.check_circle : Icons.circle_outlined,
                            size: 14,
                            color: _showOnlyRegistered ? theme.primaryColor : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            "Registered Only", 
                            style: TextStyle(
                              color: _showOnlyRegistered ? theme.primaryColor : theme.colorScheme.onSurface.withValues(alpha: 0.7), 
                              fontSize: 11, 
                              fontWeight: FontWeight.bold
                            )
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                ? Center(child: CircularProgressIndicator(color: theme.primaryColor))
                : _filteredChurches.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                           Icon(Icons.church, size: 50, color: theme.colorScheme.onSurface.withValues(alpha: 0.2)),
                          const SizedBox(height: 10),
                          Text("No churches found", style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.4))),
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
                        return _buildChurchTile(_filteredChurches[index], isSuperadmin);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChurchTile(Map<String, dynamic> church, bool isSuperadmin) {
    final theme = Theme.of(context);
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
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isRegistered ? theme.primaryColor.withValues(alpha: 0.3) : theme.colorScheme.onSurface.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 25,
              backgroundColor: isRegistered ? theme.primaryColor.withValues(alpha: 0.1) : theme.colorScheme.onSurface.withValues(alpha: 0.1),
              child: ClipOval(
                child: church['logo_url'] != null && (church['logo_url'] as String).isNotEmpty
                    ? Image.network(
                        church['logo_url'],
                        width: 50,
                        height: 50,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(Icons.church, color: isRegistered ? theme.primaryColor : theme.colorScheme.onSurface.withValues(alpha: 0.5));
                        },
                      )
                    : Icon(Icons.church, color: isRegistered ? theme.primaryColor : theme.colorScheme.onSurface.withValues(alpha: 0.5)),
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    church['name'] ?? 'Church',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isRegistered ? theme.colorScheme.onSurface : theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    "${church['address'] ?? 'Zambia'}, ${church['country'] ?? 'Zambia'}",
                    style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                  ),
                  if (church['_distance'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        "${((church['_distance'] as double) / 1000).toStringAsFixed(1)} km away",
                        style: TextStyle(fontSize: 10, color: theme.primaryColor, fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
            ),
            if (isRegistered)
              Column(
                children: [
                   IconButton(
                      icon: Icon(Icons.map, size: 20, color: theme.primaryColor),
                    onPressed: () {
                      final lat = church['latitude'];
                      final lng = church['longitude'];
                      if (lat != null && lng != null) {
                         final uri = Uri.parse("https://www.google.com/maps/search/?api=1&query=$lat,$lng");
                         launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                  ),
                   Icon(Icons.check_circle, size: 16, color: Colors.green),
                ],
              )
            else
              GestureDetector(
                onTap: () => _showNotRegisteredDialog(church),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: theme.colorScheme.onSurface.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text("Pending", style: TextStyle(fontSize: 9, color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontWeight: FontWeight.bold)),
                ),
              ),
            if (isSuperadmin) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(
                  isRegistered ? Icons.remove_circle : Icons.add_circle,
                  color: isRegistered ? Colors.red : Colors.green,
                  size: 24,
                ),
                onPressed: () => _toggleChurchVerification(church),
                tooltip: isRegistered ? "Remove Registered Status" : "Approve/Register Church",
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _toggleChurchVerification(Map<String, dynamic> church) async {
    final slug = church['slug'] as String;
    final currentlyRegistered = church['_registered'] == true;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(currentlyRegistered ? "Remove Registration" : "Approve Registration"),
        content: Text("Are you sure you want to set ${church['name'] ?? 'this church'} to ${currentlyRegistered ? 'Pending' : 'Approved'}?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("CANCEL"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: currentlyRegistered ? Colors.red : Colors.green,
              foregroundColor: Colors.white,
            ),
            child: Text(currentlyRegistered ? "REMOVE" : "APPROVE"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _loading = true;
    });

    try {
      final dbRes = await Supabase.instance.client
          .from('churches')
          .select('id')
          .eq('slug', slug)
          .maybeSingle();
      
      if (dbRes == null) {
        await Supabase.instance.client.from('churches').insert({
          'slug': slug,
          'name': church['name'] ?? 'Church',
          'logo_url': church['logo_url'],
          'primary_color': church['primary_color'] ?? '#FFD700',
          'accent_color': church['accent_color'] ?? '#1A1A1A',
          'latitude': church['latitude'],
          'longitude': church['longitude'],
          'address': church['address'],
          'country': church['country'] ?? 'Zambia',
          'is_verified': !currentlyRegistered,
        });
      } else {
        await Supabase.instance.client
            .from('churches')
            .update({'is_verified': !currentlyRegistered})
            .eq('slug', slug);
      }
      
      await _fetchChurches();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("${church['name']} set to ${!currentlyRegistered ? 'Approved' : 'Pending'}"),
            backgroundColor: !currentlyRegistered ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint("Error toggling church verification: $e");
      if (mounted) {
        setState(() {
          _loading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to update status: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildOnboardingTile() {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => context.push('/register-church'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 30, top: 10),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: theme.primaryColor.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(25),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: theme.primaryColor, shape: BoxShape.circle),
               child: Icon(Icons.add, color: theme.colorScheme.onSecondary, size: 20),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Register a New Church", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: theme.colorScheme.onSurface)),
                  Text("Join the Kingdom digital ecosystem today.", style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 11)),
                ],
              ),
            ),
             Icon(Icons.chevron_right, size: 18, color: theme.primaryColor),
          ],
        ),
      ),
    );
  }

  void _showNotRegisteredDialog(Map<String, dynamic> church) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: Row(
          children: [
             Icon(Icons.info, color: theme.primaryColor),
            const SizedBox(width: 10),
            Expanded(child: Text("Not Yet Available", style: TextStyle(fontSize: 18, color: theme.colorScheme.onSurface))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              church['name'] ?? 'This church',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: theme.colorScheme.onSurface),
            ),
            const SizedBox(height: 10),
            Text(
              "This church has not yet registered on Church On App. Once they sign up and activate their profile, you'll be able to join their community.",
              style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6), height: 1.5),
            ),
            const SizedBox(height: 15),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: theme.primaryColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                   Icon(Icons.notifications_active, size: 16, color: theme.primaryColor),
                  SizedBox(width: 8),
                  Expanded(child: Text("We'll notify you when they join!", style: TextStyle(fontSize: 12, color: theme.primaryColor, fontWeight: FontWeight.bold))),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text("OK", style: TextStyle(color: theme.primaryColor))),
          ElevatedButton(
            onPressed: () async {
              final churchName = church['name'] ?? 'Unknown Church';
              final location = church['address'] ?? 'Zambia';
              
              await ref.read(expansionServiceProvider).trackChurchInterest(
                churchName: churchName,
                location: location,
                type: 'notify_on_registration',
              );
              
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Expansion interest logged for $churchName!"), backgroundColor: Colors.green),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: theme.primaryColor, foregroundColor: theme.colorScheme.onSecondary),
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

