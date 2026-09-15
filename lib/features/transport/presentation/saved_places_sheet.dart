import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Saved pickup/dropoff locations for Carpso Ride + last-mile delivery.
///
/// Server-backed (`saved_places` table) so a place is reusable across devices,
/// by couriers, and by the delivery/marketplace checkout — with a
/// SharedPreferences cache for offline resilience.
class SavedPlace {
  final String id;
  final String label;
  final String address;
  final double? lat;
  final double? lng;
  final String placeType;
  final bool isPublic;

  const SavedPlace({
    required this.id,
    required this.label,
    required this.address,
    this.lat,
    this.lng,
    this.placeType = 'saved',
    this.isPublic = false,
  });

  bool get isServerId =>
      RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id);

  factory SavedPlace.fromJson(Map<String, dynamic> j) => SavedPlace(
        id: j['id']?.toString() ?? '',
        label: j['label']?.toString() ?? '',
        address: j['address']?.toString() ?? '',
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        placeType: j['place_type']?.toString() ?? 'saved',
        isPublic: j['is_public'] == true,
      );

  factory SavedPlace.fromMap(Map<String, dynamic> j) => SavedPlace.fromJson(j);

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'address': address,
        'lat': lat,
        'lng': lng,
        'place_type': placeType,
        'is_public': isPublic,
      };
}

/// A learned, frequently-used pickup/drop-off point (from trip history).
///
/// Read-only suggestions surfaced by the server-side gazetteer
/// (`get_popular_places`); tapping one is equivalent to a saved place.
class PopularPlace {
  final String id;
  final String placeType;
  final double lat;
  final double lng;
  final String? label;
  final int occurrenceCount;
  final double? distanceKm;

  const PopularPlace({
    required this.id,
    required this.placeType,
    required this.lat,
    required this.lng,
    this.label,
    this.occurrenceCount = 0,
    this.distanceKm,
  });

  factory PopularPlace.fromMap(Map<String, dynamic> m) => PopularPlace(
        id: m['id'].toString(),
        placeType: (m['place_type'] ?? 'dropoff').toString(),
        lat: (m['lat'] as num?)?.toDouble() ?? 0,
        lng: (m['lng'] as num?)?.toDouble() ?? 0,
        label: m['label']?.toString(),
        occurrenceCount: (m['occurrence_count'] as num?)?.toInt() ?? 0,
        distanceKm: (m['distance_km'] as num?)?.toDouble(),
      );

  SavedPlace toSavedPlace() => SavedPlace(
        id: 'popular:$id',
        label: (label != null && label!.isNotEmpty)
            ? label!
            : (placeType == 'pickup' ? 'Frequent pickup' : 'Frequent drop-off'),
        address: '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
        lat: lat,
        lng: lng,
        placeType: placeType,
      );
}

class SavedPlacesService {
  static const _key = 'carpso_saved_places';
  SupabaseClient get _client => Supabase.instance.client;

  /// Frequently-used points near a location (or top points globally when no
  /// coordinates are known). Backed by the `popular_places` gazetteer.
  Future<List<PopularPlace>> popularNear({
    double? lat,
    double? lng,
    int limit = 8,
  }) async {
    if (_client.auth.currentUser == null) return [];
    try {
      final res = await _client.rpc('get_popular_places', params: {
        'p_lat': lat,
        'p_lng': lng,
        'p_limit': limit,
        'p_max_km': 50,
      });
      final list = res is List ? res : const [];
      return list
          .map((e) => PopularPlace.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      debugPrint('popular_places: lookup failed (non-fatal): $e');
      return [];
    }
  }

  Future<List<SavedPlace>> load() async {
    final user = _client.auth.currentUser;
    if (user != null) {
      try {
        // RLS returns the user's own places plus their tenant's public
        // landmarks (so couriers can pick a depot / main gate).
        final rows = await _client
            .from('saved_places')
            .select()
            .order('created_at', ascending: false);
        final list = (rows as List)
            .map((r) => SavedPlace.fromMap(Map<String, dynamic>.from(r as Map)))
            .toList();
        await _cacheLocal(list);
        return list;
      } catch (e) {
        debugPrint('saved_places: server load failed, using cache: $e');
      }
    }
    return _loadLocal();
  }

  Future<void> _cacheLocal(List<SavedPlace> places) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _key, jsonEncode(places.map((p) => p.toJson()).toList()));
    } catch (_) {}
  }

  Future<List<SavedPlace>> _loadLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => SavedPlace.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Adds a place. Best-effort forward-geocodes the address so the place
  /// carries coordinates (required for last-mile routing/distance).
  ///
  /// Set [isPublic] to share it with the whole church (a tenant LANDMARK such
  /// as "Main Gate" / "Depot") — couriers can then select it too.
  Future<SavedPlace> add(
    String label,
    String address, {
    bool isPublic = false,
    double? lat,
    double? lng,
  }) async {
    if (lat == null || lng == null) {
      try {
        final hits = await locationFromAddress(address);
        if (hits.isNotEmpty) {
          lat = hits.first.latitude;
          lng = hits.first.longitude;
        }
      } catch (e) {
        debugPrint('saved_places: geocode failed (non-fatal): $e');
      }
    }

    final user = _client.auth.currentUser;
    if (user != null) {
      try {
        String? tenantId;
        try {
          final profile = await _client
              .from('profiles')
              .select('tenant_id')
              .eq('id', user.id)
              .maybeSingle();
          tenantId = profile?['tenant_id']?.toString();
        } catch (_) {}

        final inserted = await _client
            .from('saved_places')
            .insert({
              'user_id': user.id,
              'tenant_id': tenantId,
              'label': label,
              'address': address,
              'lat': lat,
              'lng': lng,
              'place_type': isPublic ? 'landmark' : 'saved',
              'is_public': isPublic,
            })
            .select()
            .single();
        final place = SavedPlace.fromMap(Map<String, dynamic>.from(inserted as Map));
        await _cacheLocal(await load());
        return place;
      } catch (e) {
        debugPrint('saved_places: insert failed, caching locally: $e');
      }
    }

    // Offline / failure fallback — local only.
    final places = await _loadLocal();
    final place = SavedPlace(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      label: label,
      address: address,
      lat: lat,
      lng: lng,
      placeType: isPublic ? 'landmark' : 'saved',
      isPublic: isPublic,
    );
    places.add(place);
    await _cacheLocal(places);
    return place;
  }

  Future<void> remove(String id) async {
    if (RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id)) {
      try {
        await _client.from('saved_places').delete().eq('id', id);
      } catch (e) {
        debugPrint('saved_places: delete failed (non-fatal): $e');
      }
    }
    final places = await _loadLocal();
    places.removeWhere((p) => p.id == id);
    await _cacheLocal(places);
  }
}

/// Reactive saved places (own places + tenant landmarks). Maps and the ride /
/// delivery flows watch this so a place saved anywhere appears everywhere.
final savedPlacesProvider = FutureProvider<List<SavedPlace>>((ref) async {
  return SavedPlacesService().load();
});

/// Bottom sheet picker — shows saved places with add/remove. Returns the
/// selected [SavedPlace] or null if dismissed.
Future<SavedPlace?> showSavedPlacesPicker(BuildContext context) async {
  return showModalBottomSheet<SavedPlace>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _SavedPlacesSheet(),
  );
}

class _SavedPlacesSheet extends StatefulWidget {
  const _SavedPlacesSheet();

  @override
  State<_SavedPlacesSheet> createState() => _SavedPlacesSheetState();
}

class _SavedPlacesSheetState extends State<_SavedPlacesSheet> {
  final _service = SavedPlacesService();
  List<SavedPlace> _places = [];
  List<PopularPlace> _popular = [];
  bool _loading = true;
  bool _adding = false;
  final _labelCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final places = await _service.load();
    final popular = await _service.popularNear();
    if (mounted) {
      setState(() {
        _places = places;
        _popular = popular;
        _loading = false;
      });
    }
  }

  Future<void> _addPlace() async {
    if (_labelCtrl.text.trim().isEmpty || _addressCtrl.text.trim().isEmpty) return;
    await _service.add(_labelCtrl.text.trim(), _addressCtrl.text.trim());
    _labelCtrl.clear();
    _addressCtrl.clear();
    await _load();
    if (mounted) setState(() => _adding = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          Center(child: Container(margin: const EdgeInsets.all(14), height: 5, width: 40,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Icon(LucideIcons.bookmark, color: theme.primaryColor),
              const SizedBox(width: 10),
              const Expanded(child: Text('SAVED PLACES',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1))),
              IconButton(
                icon: Icon(_adding ? LucideIcons.x : LucideIcons.plus, size: 20),
                onPressed: () => setState(() => _adding = !_adding),
              ),
            ]),
          ),
          if (_adding)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Column(children: [
                TextField(controller: _labelCtrl,
                    decoration: InputDecoration(hintText: 'Label (e.g. Home, Work)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        isDense: true)),
                const SizedBox(height: 8),
                TextField(controller: _addressCtrl,
                    decoration: InputDecoration(hintText: 'Address',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        isDense: true)),
                const SizedBox(height: 8),
                SizedBox(width: double.infinity,
                    child: FilledButton(onPressed: _addPlace, child: const Text('SAVE PLACE'))),
              ]),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : (_places.isEmpty && _popular.isEmpty)
                    ? Center(child: Text('No saved places yet.\nTap + to add one.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 13)))
                    : ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        children: [
                          if (_popular.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text('FREQUENTLY USED',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.3,
                                      color: Colors.grey.shade500)),
                            ),
                            ..._popular.map((p) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: CircleAvatar(
                                    backgroundColor:
                                        theme.primaryColor.withValues(alpha: 0.12),
                                    child: Icon(LucideIcons.history,
                                        size: 18, color: theme.primaryColor),
                                  ),
                                  title: Text(
                                      (p.label != null && p.label!.isNotEmpty)
                                          ? p.label!
                                          : (p.placeType == 'pickup'
                                              ? 'Frequent pickup'
                                              : 'Frequent drop-off'),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold, fontSize: 14)),
                                  subtitle: Text(
                                      '${p.occurrenceCount} trips'
                                      '${p.distanceKm != null ? ' · ${p.distanceKm!.toStringAsFixed(1)} km' : ''}',
                                      style: const TextStyle(fontSize: 12)),
                                  onTap: () =>
                                      Navigator.pop(context, p.toSavedPlace()),
                                )),
                            const SizedBox(height: 10),
                          ],
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text('SAVED PLACES',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.3,
                                    color: Colors.grey.shade500)),
                          ),
                          if (_places.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text('No saved places yet. Tap + to add one.',
                                  style: TextStyle(
                                      color: Colors.grey.shade500, fontSize: 13)),
                            )
                          else
                            ..._places.map((p) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: CircleAvatar(
                                    backgroundColor:
                                        theme.primaryColor.withValues(alpha: 0.12),
                                    child: Icon(LucideIcons.mapPin,
                                        size: 18, color: theme.primaryColor),
                                  ),
                                  title: Text(p.label,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold, fontSize: 14)),
                                  subtitle: Text(p.address,
                                      style: const TextStyle(fontSize: 12),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  trailing: GestureDetector(
                                    onTap: () async {
                                      await _service.remove(p.id);
                                      _load();
                                    },
                                    child: Icon(LucideIcons.trash2,
                                        size: 16, color: Colors.red.shade300),
                                  ),
                                  onTap: () => Navigator.pop(context, p),
                                )),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

}
