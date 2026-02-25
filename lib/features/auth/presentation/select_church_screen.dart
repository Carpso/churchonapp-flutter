import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/services/expansion_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/widgets/church_map.dart';
import 'package:church_on_app/features/navigation/presentation/main_navigation_shell.dart';
import 'package:go_router/go_router.dart';
import 'church_onboarding_screen.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

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
  Position? _currentPosition;
  String _currentCountry = "Zambia";
  bool _showOnlyRegistered = false;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initChurches();
  }

  Future<void> _initChurches() async {
    await _getUserLocation();
    await _fetchChurches();
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
      ];

      for (final dbChurch in registered) {
        // Update any matching hardcoded church with DB data
        final idx = allChurches.indexWhere((c) => c['slug'] == dbChurch['slug']);
        if (idx >= 0) {
          allChurches[idx] = {...allChurches[idx], ...dbChurch, '_registered': true};
        } else {
          allChurches.add({...dbChurch, '_registered': true});
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

      // Sort: Registered First, then Near User
      allChurches.sort((a, b) {
        final regA = a['_registered'] == true ? 0 : 1;
        final regB = b['_registered'] == true ? 0 : 1;
        if (regA != regB) return regA.compareTo(regB);
        
        final distA = (a['_distance'] ?? 9999999.0) as double;
        final distB = (b['_distance'] ?? 9999999.0) as double;
        return distA.compareTo(distB);
      });

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
          _churches = [..._getAllZambianChurches(), ..._getAllZimbabweanChurches()];
          _filteredChurches = _churches;
          _loading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> _getAllZambianChurches() {
    return [
      // ── LUSAKA ──
      {'id': 'zm_1', 'slug': 'bread-of-life', 'name': 'Bread of Life Church International', 'address': 'Addis Ababa Drive, Lusaka', 'latitude': -15.3872, 'longitude': 28.3165, 'primary_color': '#8B5CF6', '_registered': false, 'country': 'Zambia'},
      {'id': 'zm_2', 'slug': 'northmead-ag', 'name': 'Northmead Assembly of God', 'address': 'Great East Road, Northmead, Lusaka', 'latitude': -15.3980, 'longitude': 28.3100, 'primary_color': '#3B82F6', '_registered': false, 'country': 'Zambia'},
      {'id': 'zm_3', 'slug': 'chapel-zambia', 'name': 'The Chapel Zambia', 'address': 'Ibex Hill, Lusaka', 'latitude': -15.4150, 'longitude': 28.3550, 'primary_color': '#EF4444', '_registered': false, 'country': 'Zambia'},
      {'id': 'zm_4', 'slug': 'grace-chapel-intl', 'name': 'Grace Chapel International', 'address': 'Plot 123, Great East Rd, Lusaka', 'latitude': -15.3875, 'longitude': 28.3228, 'primary_color': '#FFD700', '_registered': false, 'country': 'Zambia'},
      {'id': 'zm_5', 'slug': 'victory-ministries', 'name': 'Victory Ministries International', 'address': 'Kafue Road, Chilenje, Lusaka', 'latitude': -15.4100, 'longitude': 28.3050, 'primary_color': '#10B981', '_registered': false, 'country': 'Zambia'},
      {'id': 'zm_6', 'slug': 'ucz-cathedral', 'name': 'UCZ Cathedral of the Holy Cross', 'address': 'Cathedral Hill, Lusaka', 'latitude': -15.4166, 'longitude': 28.2833, 'primary_color': '#6366F1', '_registered': false, 'country': 'Zambia'},
      {'id': 'zm_7', 'slug': 'kingsland-church', 'name': 'Kingsland Baptist Church', 'address': 'Kabulonga, Lusaka', 'latitude': -15.4200, 'longitude': 28.3200, 'primary_color': '#F59E0B', '_registered': false, 'country': 'Zambia'},
      {'id': 'zm_8', 'slug': 'kabwata-church', 'name': 'Kabwata Baptist Church', 'address': 'Kabwata, Lusaka', 'latitude': -15.4250, 'longitude': 28.2900, 'primary_color': '#059669', '_registered': false, 'country': 'Zambia'},
      {'id': 'zm_9', 'slug': 'faith-alive', 'name': 'Faith Alive Ministries', 'address': 'Kalingalinga, Lusaka', 'latitude': -15.4050, 'longitude': 28.3350, 'primary_color': '#DC2626', '_registered': false, 'country': 'Zambia'},
      {'id': 'zm_10', 'slug': 'new-apostolic-lsk', 'name': 'New Apostolic Church Lusaka', 'address': 'Olympia, Lusaka', 'latitude': -15.4000, 'longitude': 28.2950, 'primary_color': '#7C3AED', '_registered': false, 'country': 'Zambia'},
      {'id': 'zm_11', 'slug': 'rhema-word', 'name': 'Rhema Bible Church', 'address': 'Makeni, Lusaka', 'latitude': -15.4300, 'longitude': 28.3400, 'primary_color': '#0EA5E9', '_registered': false, 'country': 'Zambia'},
      {'id': 'zm_12', 'slug': 'livingstone-central', 'name': 'Central SDA Church Lusaka', 'address': 'Woodlands, Lusaka', 'latitude': -15.3950, 'longitude': 28.3000, 'primary_color': '#14B8A6', '_registered': false, 'country': 'Zambia'},
      {'id': 'zm_13', 'slug': 'zambia-shall-be-saved', 'name': 'Zambia Shall Be Saved Ministry', 'address': 'Cairo Road, Lusaka', 'latitude': -15.4166, 'longitude': 28.2870, 'primary_color': '#F97316', '_registered': false, 'country': 'Zambia'},
      {'id': 'zm_31', 'slug': 'harvest-lsk', 'name': 'Harvest House International Lusaka', 'address': 'Leopards Hill, Lusaka', 'latitude': -15.4350, 'longitude': 28.3700, 'primary_color': '#EF4444', '_registered': false, 'country': 'Zambia'},
      {'id': 'zm_32', 'slug': 'st-ignatius', 'name': 'St. Ignatius Catholic Church', 'address': 'Rhodes Park, Lusaka', 'latitude': -15.4080, 'longitude': 28.3020, 'primary_color': '#3B82F6', '_registered': false, 'country': 'Zambia'},
      {'id': 'zm_33', 'slug': 'emmanuel-church', 'name': 'Emmanuel Baptist Church', 'address': 'Longacres, Lusaka', 'latitude': -15.4120, 'longitude': 28.3150, 'primary_color': '#10B981', '_registered': false, 'country': 'Zambia'},
  
      // ── KITWE (Copperbelt) ──
      {'id': 'zm_14', 'slug': 'kitwe-chapel', 'name': 'Kitwe Chapel', 'address': 'Obote Avenue, Kitwe', 'latitude': -12.8024, 'longitude': 28.2132, 'primary_color': '#3B82F6', '_registered': false, 'country': 'Zambia'},
      {'id': 'zm_15', 'slug': 'ucz-mindolo', 'name': 'UCZ Mindolo Congregation', 'address': 'Mindolo, Kitwe', 'latitude': -12.8100, 'longitude': 28.2300, 'primary_color': '#6366F1', '_registered': false, 'country': 'Zambia'},
      {'id': 'zm_16', 'slug': 'sol-kitwe', 'name': 'Salvation Army Kitwe Citadel', 'address': 'Independence Avenue, Kitwe', 'latitude': -12.8050, 'longitude': 28.2100, 'primary_color': '#DC2626', '_registered': false, 'country': 'Zambia'},
      {'id': 'zm_34', 'slug': 'riverside-church', 'name': 'Riverside Chapel Kitwe', 'address': 'Riverside, Kitwe', 'latitude': -12.7950, 'longitude': 28.2350, 'primary_color': '#F59E0B', '_registered': false, 'country': 'Zambia'},

      // ── NDOLA ──
      {'id': 'zm_17', 'slug': 'ndola-baptist', 'name': 'Ndola Baptist Church', 'address': 'Broadway, Ndola', 'latitude': -12.9587, 'longitude': 28.6366, 'primary_color': '#10B981', '_registered': false, 'country': 'Zambia'},
      {'id': 'zm_18', 'slug': 'dag-ndola', 'name': 'Dag Heward-Mills Church Ndola', 'address': 'Kansenshi, Ndola', 'latitude': -12.9700, 'longitude': 28.6400, 'primary_color': '#8B5CF6', '_registered': false, 'country': 'Zambia'},
      {'id': 'zm_35', 'slug': 'st-andrews-ndola', 'name': 'St. Andrews United Church Ndola', 'address': 'Broadway, Ndola', 'latitude': -12.9620, 'longitude': 28.6320, 'primary_color': '#6366F1', '_registered': false, 'country': 'Zambia'},

      // ── LIVINGSTONE ──
      {'id': 'zm_19', 'slug': 'livingstone-ag', 'name': 'Livingstone Assembly of God', 'address': 'Mosi-oa-Tunya Road, Livingstone', 'latitude': -17.8419, 'longitude': 25.8606, 'primary_color': '#F59E0B', '_registered': false, 'country': 'Zambia'},
      {'id': 'zm_20', 'slug': 'victory-liv', 'name': 'Victory Assembly Livingstone', 'address': 'Central Livingstone', 'latitude': -17.8450, 'longitude': 25.8550, 'primary_color': '#EF4444', '_registered': false, 'country': 'Zambia'},

      // ── KABWE ──
      {'id': 'zm_21', 'slug': 'kabwe-central', 'name': 'Kabwe Central SDA Church', 'address': 'Freedom Way, Kabwe', 'latitude': -14.4376, 'longitude': 28.4512, 'primary_color': '#14B8A6', '_registered': false, 'country': 'Zambia'},

      // ── CHIPATA ──
      {'id': 'zm_22', 'slug': 'chipata-ucz', 'name': 'UCZ Chipata Congregation', 'address': 'Chipata Town Centre', 'latitude': -13.6333, 'longitude': 32.6500, 'primary_color': '#6366F1', '_registered': false, 'country': 'Zambia'},

      // ── SOLWEZI ──
      {'id': 'zm_23', 'slug': 'solwezi-gospel', 'name': 'Solwezi Gospel Church', 'address': 'Main Road, Solwezi', 'latitude': -12.1667, 'longitude': 25.8667, 'primary_color': '#059669', '_registered': false, 'country': 'Zambia'},

      // ── KASAMA ──
      {'id': 'zm_24', 'slug': 'kasama-ag', 'name': 'Kasama Assembly of God', 'address': 'Zambia Road, Kasama', 'latitude': -10.2130, 'longitude': 31.1811, 'primary_color': '#0EA5E9', '_registered': false, 'country': 'Zambia'},

      // ── MANSA ──
      {'id': 'zm_25', 'slug': 'mansa-ucz', 'name': 'UCZ Mansa Congregation', 'address': 'Mansa Town', 'latitude': -11.2006, 'longitude': 28.8894, 'primary_color': '#7C3AED', '_registered': false, 'country': 'Zambia'},

      // ── MONGU ──
      {'id': 'zm_26', 'slug': 'mongu-baptist', 'name': 'Mongu Baptist Church', 'address': 'Independence Ave, Mongu', 'latitude': -15.2547, 'longitude': 23.1283, 'primary_color': '#F97316', '_registered': false, 'country': 'Zambia'},

      // ── MAZABUKA ──
      {'id': 'zm_27', 'slug': 'mazabuka-ag', 'name': 'Mazabuka Assembly of God', 'address': 'Livingstone Road, Mazabuka', 'latitude': -15.8560, 'longitude': 27.7480, 'primary_color': '#3B82F6', '_registered': false, 'country': 'Zambia'},

      // ── CHOMA ──
      {'id': 'zm_28', 'slug': 'choma-chapel', 'name': 'Choma Community Chapel', 'address': 'Main Street, Choma', 'latitude': -16.5414, 'longitude': 26.9877, 'primary_color': '#10B981', '_registered': false, 'country': 'Zambia'},

      // ── MPIKA ──
      {'id': 'zm_29', 'slug': 'mpika-home', 'name': 'New Apostolic Church Mpika', 'address': 'Great North Road, Mpika', 'latitude': -11.8310, 'longitude': 31.4581, 'primary_color': '#DC2626', '_registered': false, 'country': 'Zambia'},

      // ── KAPIRI MPOSHI ──
      {'id': 'zm_30', 'slug': 'kapiri-sda', 'name': 'Kapiri Mposhi SDA Church', 'address': 'Great North Road, Kapiri Mposhi', 'latitude': -14.9710, 'longitude': 28.6831, 'primary_color': '#14B8A6', '_registered': false, 'country': 'Zambia'},

      // ── CHINGOLA ──
      {'id': 'zm_36', 'slug': 'chingola-ag', 'name': 'Chingola Assembly of God', 'address': 'Chiwa Rd, Chingola', 'latitude': -12.5292, 'longitude': 27.8500, 'primary_color': '#F59E0B', '_registered': false, 'country': 'Zambia'},
      {'id': 'zm_37', 'slug': 'nchanga-baptist', 'name': 'Nchanga Baptist Church', 'address': 'Nchanga, Chingola', 'latitude': -12.5350, 'longitude': 27.8450, 'primary_color': '#3B82F6', '_registered': false, 'country': 'Zambia'},

      // ── MUFULIRA ──
      {'id': 'zm_38', 'slug': 'mufulira-central', 'name': 'Mufulira Central SDA', 'address': 'Kantanshi Rd, Mufulira', 'latitude': -12.5417, 'longitude': 28.2417, 'primary_color': '#10B981', '_registered': false, 'country': 'Zambia'},
      {'id': 'zm_39', 'slug': 'ucz-mufulira', 'name': 'UCZ Trinity Congregation', 'address': 'Chati Ave, Mufulira', 'latitude': -12.5450, 'longitude': 28.2500, 'primary_color': '#6366F1', '_registered': false, 'country': 'Zambia'},

      // ── LUANSHYA ──
      {'id': 'zm_40', 'slug': 'luanshya-chapel', 'name': 'Luanshya Community Chapel', 'address': '15th St, Luanshya', 'latitude': -13.1333, 'longitude': 28.4167, 'primary_color': '#EF4444', '_registered': false, 'country': 'Zambia'},
    ];

  }

  List<Map<String, dynamic>> _getAllZimbabweanChurches() {
    return [
      // ── HARARE ──
      {'id': 'zw_1', 'slug': 'celebration', 'name': 'Celebration Church International', 'address': '162 Borrowdale Rd, Harare', 'latitude': -17.7562, 'longitude': 31.0847, 'primary_color': '#8B5CF6', '_registered': false, 'country': 'Zimbabwe'},
      {'id': 'zw_2', 'slug': 'zaoga-fif', 'name': 'ZAOGA Forward in Faith', 'address': 'Zindoga, Waterfalls, Harare', 'latitude': -17.8820, 'longitude': 31.0250, 'primary_color': '#3B82F6', '_registered': false, 'country': 'Zimbabwe'},
      {'id': 'zw_4', 'slug': 'methodist-zw', 'name': 'Methodist Church in Zimbabwe', 'address': 'Central Ave, Harare', 'latitude': -17.8250, 'longitude': 31.0530, 'primary_color': '#FFD700', '_registered': false, 'country': 'Zimbabwe'},
      {'id': 'zw_5', 'slug': 'catholic-harare', 'name': 'Roman Catholic Cathedral', 'address': 'Fourth St, Harare', 'latitude': -17.8290, 'longitude': 31.0570, 'primary_color': '#10B981', '_registered': false, 'country': 'Zimbabwe'},
      {'id': 'zw_7', 'slug': 'faith-ministries', 'name': 'Faith Ministries - Borrowdale', 'address': 'Borrowdale Way, Harare', 'latitude': -17.7600, 'longitude': 31.0900, 'primary_color': '#F59E0B', '_registered': false, 'country': 'Zimbabwe'},
      {'id': 'zw_8', 'slug': 'new-life-covenant', 'name': 'New Life Covenant Church', 'address': 'Harare City Centre', 'latitude': -17.8240, 'longitude': 31.0490, 'primary_color': '#DC2626', '_registered': false, 'country': 'Zimbabwe'},
      {'id': 'zw_9', 'slug': 'glad-tidings', 'name': 'Glad Tidings Fellowship', 'address': 'Mbare, Harare', 'latitude': -17.8590, 'longitude': 31.0370, 'primary_color': '#7C3AED', '_registered': false, 'country': 'Zimbabwe'},
      {'id': 'zw_13', 'slug': 'afm-harare', 'name': 'AFM in Zimbabwe - Central', 'address': 'Robert Mugabe Rd, Harare', 'latitude': -17.8310, 'longitude': 31.0450, 'primary_color': '#6366F1', '_registered': false, 'country': 'Zimbabwe'},
      {'id': 'zw_14', 'slug': 'upc-harare', 'name': 'United Pentecostal Church', 'address': 'Belvedere, Harare', 'latitude': -17.8350, 'longitude': 31.0150, 'primary_color': '#EF4444', '_registered': false, 'country': 'Zimbabwe'},
      {'id': 'zw_15', 'slug': 'sda-harare', 'name': 'Harare City Centre SDA', 'address': 'Second St, Harare', 'latitude': -17.8200, 'longitude': 31.0550, 'primary_color': '#14B8A6', '_registered': false, 'country': 'Zimbabwe'},

      // ── BULAWAYO ──
      {'id': 'zw_3', 'slug': 'harvest-house', 'name': 'Harvest House International', 'address': 'Fife St, Bulawayo', 'latitude': -20.1550, 'longitude': 28.5830, 'primary_color': '#EF4444', '_registered': false, 'country': 'Zimbabwe'},
      {'id': 'zw_6', 'slug': 'word-of-life-zw', 'name': 'Word of Life Christian Services', 'address': '8th Ave, Bulawayo', 'latitude': -20.1480, 'longitude': 28.5800, 'primary_color': '#6366F1', '_registered': false, 'country': 'Zimbabwe'},
      {'id': 'zw_10', 'slug': 'fog-bulawayo', 'name': 'Family of God Church', 'address': 'Bulawayo Centre', 'latitude': -20.1500, 'longitude': 28.5850, 'primary_color': '#0EA5E9', '_registered': false, 'country': 'Zimbabwe'},
      {'id': 'zw_16', 'slug': 'afm-bulawayo', 'name': 'AFM - Bulawayo Central', 'address': 'Main St, Bulawayo', 'latitude': -20.1600, 'longitude': 28.5750, 'primary_color': '#F59E0B', '_registered': false, 'country': 'Zimbabwe'},

      // ── MUTARE ──
      {'id': 'zw_11', 'slug': 'mutare-baptist', 'name': 'Mutare Baptist Church', 'address': 'Mutare CBD', 'latitude': -18.9720, 'longitude': 32.6670, 'primary_color': '#14B8A6', '_registered': false, 'country': 'Zimbabwe'},
      {'id': 'zw_17', 'slug': 'zaoga-mutare', 'name': 'ZAOGA FIF Mutare', 'address': 'Mutare Town', 'latitude': -18.9750, 'longitude': 32.6600, 'primary_color': '#3B82F6', '_registered': false, 'country': 'Zimbabwe'},

      // ── GWERU ──
      {'id': 'zw_12', 'slug': 'gweru-methodist', 'name': 'Methodist Church Gweru', 'address': 'Main St, Gweru', 'latitude': -19.4500, 'longitude': 29.8167, 'primary_color': '#F97316', '_registered': false, 'country': 'Zimbabwe'},
      {'id': 'zw_18', 'slug': 'celebration-gweru', 'name': 'Celebration Church Gweru', 'address': 'Gweru East', 'latitude': -19.4450, 'longitude': 29.8300, 'primary_color': '#8B5CF6', '_registered': false, 'country': 'Zimbabwe'},

      // ── MASVINGO ──
      {'id': 'zw_19', 'slug': 'masvingo-ag', 'name': 'Masvingo Assembly of God', 'address': 'Masvingo CBD', 'latitude': -20.0637, 'longitude': 30.8277, 'primary_color': '#3B82F6', '_registered': false, 'country': 'Zimbabwe'},
      {'id': 'zw_20', 'slug': 'sda-masvingo', 'name': 'Masvingo SDA Church', 'address': 'Masvingo Town', 'latitude': -20.0700, 'longitude': 30.8350, 'primary_color': '#14B8A6', '_registered': false, 'country': 'Zimbabwe'},

      // ── CHINHOYI ──
      {'id': 'zw_21', 'slug': 'chinhoyi-baptist', 'name': 'Chinhoyi Baptist Church', 'address': 'Chinhoyi CBD', 'latitude': -17.3667, 'longitude': 30.2000, 'primary_color': '#10B981', '_registered': false, 'country': 'Zimbabwe'},
      {'id': 'zw_22', 'slug': 'zaoga-chinhoyi', 'name': 'ZAOGA FIF Chinhoyi', 'address': 'Chinhoyi Town', 'latitude': -17.3750, 'longitude': 30.2100, 'primary_color': '#EF4444', '_registered': false, 'country': 'Zimbabwe'},
    ];

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
            zoom: _currentPosition != null ? 10 : 6,
            markers: _filteredChurches.map((church) {
              final lat = (church['latitude'] ?? -15.3875) as num;
              final lng = (church['longitude'] ?? 28.3228) as num;
              final isRegistered = church['_registered'] == true;
              return buildChurchMarker(
                point: LatLng(lat.toDouble(), lng.toDouble()),
                name: church['name'] ?? 'Church',
                color: isRegistered ? const Color(0xFFFFD700) : Colors.grey,
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
        child: TextField(
          controller: _searchController,
          onChanged: _filterChurches,
          decoration: InputDecoration(
            hintText: "Search churches in $_currentCountry...",
            border: InputBorder.none,
            icon: const Icon(Icons.search, size: 20, color: Colors.grey),
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
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20)],
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
                  Text("Available Churches", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                   const Icon(Icons.location_on, size: 16, color: Colors.grey),
                  const SizedBox(width: 5),
                  Text(_currentCountry, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(width: 15),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _showOnlyRegistered = !_showOnlyRegistered;
                        _filterChurches(_searchController.text);
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _showOnlyRegistered ? Colors.amber : Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        "Registered Only", 
                        style: TextStyle(
                          color: _showOnlyRegistered ? Colors.black : Colors.grey, 
                          fontSize: 10, 
                          fontWeight: FontWeight.bold
                        )
                      ),
                    ),
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
                           Icon(Icons.church, size: 50, color: Colors.grey[300]),
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
          color: isRegistered ? Colors.grey[50] : Colors.grey[50]?.withOpacity(0.6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isRegistered ? Colors.amber.withOpacity(0.3) : Colors.grey.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 25,
              backgroundColor: isRegistered ? Colors.amber.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
              backgroundImage: church['logo_url'] != null ? NetworkImage(church['logo_url']) : null,
              child: church['logo_url'] == null
                 ? Icon(Icons.church, color: isRegistered ? Colors.amber : Colors.grey)
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
                    "${church['address'] ?? 'Zambia'}, ${church['country'] ?? 'Zambia'}",
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                  if (church['_distance'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        "${((church['_distance'] as double) / 1000).toStringAsFixed(1)} km away",
                        style: const TextStyle(fontSize: 10, color: Colors.amber, fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
            ),
            if (isRegistered)
              Column(
                children: [
                   IconButton(
                     icon: const Icon(Icons.map, size: 20, color: Colors.blue),
                    onPressed: () {
                      final lat = church['latitude'];
                      final lng = church['longitude'];
                      if (lat != null && lng != null) {
                         final uri = Uri.parse("https://www.google.com/maps/search/?api=1&query=$lat,$lng");
                         // Use url_launcher if available, for now just print or use logic
                         debugPrint("Opening maps for $lat,$lng");
                      }
                    },
                  ),
                   const Icon(Icons.check_circle, size: 16, color: Colors.green),
                ],
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
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
          color: Colors.amber.withOpacity(0.05),
          borderRadius: BorderRadius.circular(25),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(color: Colors.amber, shape: BoxShape.circle),
               child: const Icon(Icons.add, color: Colors.black, size: 20),
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
             const Icon(Icons.chevron_right, size: 18, color: Colors.amber),
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
             Icon(Icons.info, color: Colors.amber.shade700),
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
              decoration: BoxDecoration(color: Colors.amber.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
              child: const Row(
                children: [
                   Icon(Icons.notifications_active, size: 16, color: Colors.amber),
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

