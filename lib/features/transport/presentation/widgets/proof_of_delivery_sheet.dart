import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:church_on_app/core/services/r2_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// What a courier/driver captured at the drop-off point.
class ProofOfDeliveryResult {
  final String? photoUrl;
  final double? lat;
  final double? lng;
  final String note;

  const ProofOfDeliveryResult({
    this.photoUrl,
    this.lat,
    this.lng,
    this.note = '',
  });
}

/// Bottom sheet that captures PROOF OF DELIVERY — a photo at the drop-off point
/// plus the GPS coordinates — for last-mile handovers.
///
/// Returns null if dismissed. Photo uploads go to R2 (`delivery-proof/…`);
/// callers persist the result onto `delivery_requests` / `ride_requests`
/// (`proof_photo_url`, `proof_lat`, `proof_lng`, `proof_note`).
Future<ProofOfDeliveryResult?> showProofOfDeliverySheet(
  BuildContext context, {
  bool photoRequired = true,
  /// Expected drop-off point. When provided, the sheet GEOFENCES the captured
  /// GPS and warns if the courier is far from the recorded destination.
  LatLng? destination,
}) {
  return showModalBottomSheet<ProofOfDeliveryResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ProofOfDeliverySheet(
      photoRequired: photoRequired,
      destination: destination,
    ),
  );
}

class _ProofOfDeliverySheet extends StatefulWidget {
  final bool photoRequired;
  final LatLng? destination;
  const _ProofOfDeliverySheet({this.photoRequired = true, this.destination});

  @override
  State<_ProofOfDeliverySheet> createState() => _ProofOfDeliverySheetState();
}

class _ProofOfDeliverySheetState extends State<_ProofOfDeliverySheet> {
  static const double _geofenceMetres = 200;

  final _noteCtrl = TextEditingController();
  Uint8List? _photo;
  double? _lat;
  double? _lng;
  double? _distanceFromDest;
  bool _locating = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _captureGps();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _captureGps() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) setState(() => _locating = false);
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) setState(() => _locating = false);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      if (mounted) {
        final dest = widget.destination;
        setState(() {
          _lat = pos.latitude;
          _lng = pos.longitude;
          if (dest != null) {
            _distanceFromDest = const Distance().as(
              LengthUnit.Meter,
              dest,
              LatLng(pos.latitude, pos.longitude),
            );
          }
          _locating = false;
        });
      }
    } catch (e) {
      debugPrint('ProofOfDelivery: GPS failed (non-fatal): $e');
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (mounted) setState(() => _photo = bytes);
    } catch (e) {
      debugPrint('ProofOfDelivery: photo pick failed: $e');
      if (mounted) setState(() => _error = 'Could not read that photo.');
    }
  }

  Future<void> _submit() async {
    if (widget.photoRequired && _photo == null) {
      setState(() => _error = 'A photo of the drop-off is required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    String? photoUrl;
    if (_photo != null) {
      try {
        final client = Supabase.instance.client;
        final name = 'delivery-proof/${DateTime.now().millisecondsSinceEpoch}.jpg';
        photoUrl = await R2Service(client).uploadBytes(
          _photo!,
          name,
          contentType: 'image/jpeg',
        );
        if (photoUrl == null) {
          if (mounted) {
            setState(() {
              _saving = false;
              _error = 'Photo upload failed. Check your connection and retry.';
            });
          }
          return;
        }
      } catch (e) {
        debugPrint('ProofOfDelivery: upload failed: $e');
        if (mounted) {
          setState(() {
            _saving = false;
            _error = 'Photo upload failed: $e';
          });
        }
        return;
      }
    }

    if (!mounted) return;
    Navigator.pop(
      context,
      ProofOfDeliveryResult(
        photoUrl: photoUrl,
        lat: _lat,
        lng: _lng,
        note: _noteCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                height: 5,
                width: 40,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            Row(
              children: [
                Icon(LucideIcons.packageCheck, color: theme.primaryColor),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('PROOF OF DELIVERY',
                      style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          letterSpacing: 1)),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Photo
            GestureDetector(
              onTap: () => _pickPhoto(ImageSource.camera),
              child: Container(
                height: 150,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: theme.primaryColor.withValues(alpha: 0.4)),
                  image: _photo != null
                      ? DecorationImage(
                          image: MemoryImage(_photo!), fit: BoxFit.cover)
                      : null,
                ),
                child: _photo == null
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(LucideIcons.camera,
                              size: 30, color: theme.primaryColor),
                          const SizedBox(height: 6),
                          const Text('Tap to take a photo of the drop-off',
                              style: TextStyle(fontSize: 12)),
                        ],
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => _pickPhoto(ImageSource.camera),
                  icon: const Icon(LucideIcons.camera, size: 16),
                  label: const Text('CAMERA'),
                ),
                TextButton.icon(
                  onPressed: () => _pickPhoto(ImageSource.gallery),
                  icon: const Icon(LucideIcons.image, size: 16),
                  label: const Text('GALLERY'),
                ),
              ],
            ),

            // GPS
            Row(
              children: [
                Icon(
                  _locating ? LucideIcons.loader : LucideIcons.mapPin,
                  size: 16,
                  color: _lat != null ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _locating
                        ? 'Locating drop-off point…'
                        : _lat != null
                            ? 'Location captured: ${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}'
                            : 'Location unavailable (off?)',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Geofence warning — the courier is not at the drop-off point.
            if (_distanceFromDest != null &&
                _distanceFromDest! > _geofenceMetres) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber),
                ),
                child: Row(
                  children: [
                    const Icon(LucideIcons.alertTriangle,
                        size: 16, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'You are ${(_distanceFromDest! / 1000).toStringAsFixed(2)} km '
                        'from the recorded destination — make sure you are at the drop-off point.',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],

            TextField(
              controller: _noteCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Note (e.g. left with receptionist)',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],

            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('CONFIRM HANDOVER'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
