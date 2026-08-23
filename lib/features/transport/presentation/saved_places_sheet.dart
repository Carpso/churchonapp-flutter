import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Saved pickup/dropoff locations for Carpso Ride. Stored locally in
/// SharedPreferences — lightweight, per-device, no DB table needed.
class SavedPlace {
  final String id;
  final String label;
  final String address;

  const SavedPlace({required this.id, required this.label, required this.address});

  factory SavedPlace.fromJson(Map<String, dynamic> j) => SavedPlace(
        id: j['id']?.toString() ?? '',
        label: j['label']?.toString() ?? '',
        address: j['address']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {'id': id, 'label': label, 'address': address};
}

class SavedPlacesService {
  static const _key = 'carpso_saved_places';

  Future<List<SavedPlace>> load() async {
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

  Future<void> save(List<SavedPlace> places) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(places.map((p) => p.toJson()).toList()));
  }

  Future<void> add(String label, String address) async {
    final places = await load();
    places.add(SavedPlace(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      label: label,
      address: address,
    ));
    await save(places);
  }

  Future<void> remove(String id) async {
    final places = await load();
    places.removeWhere((p) => p.id == id);
    await save(places);
  }
}

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
    if (mounted) setState(() { _places = places; _loading = false; });
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
                : _places.isEmpty
                    ? Center(child: Text('No saved places yet.\nTap + to add one.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 13)))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: _places.length,
                        itemBuilder: (_, i) {
                          final p = _places[i];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: theme.primaryColor.withValues(alpha: 0.12),
                              child: Icon(LucideIcons.mapPin, size: 18, color: theme.primaryColor),
                            ),
                            title: Text(p.label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            subtitle: Text(p.address, style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: GestureDetector(
                              onTap: () async { await _service.remove(p.id); _load(); },
                              child: Icon(LucideIcons.trash2, size: 16, color: Colors.red.shade300),
                            ),
                            onTap: () => Navigator.pop(context, p),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

}
