import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'transport_service.dart';
import '../../../core/providers/profile_provider.dart';

/// Specialized service for real-time geolocation synchronization.
/// This ensures that active drivers and riders have their coordinates 
/// mirrored to the cloud-hosted Supabase instance for live map tracking.
class LocationTrackerService {
  final Ref _ref;
  StreamSubscription<Position>? _positionSubscription;
  Timer? _heartbeatTimer;
  DateTime? _lastUpdate;

  LocationTrackerService(this._ref);

  /// Initializes the tracking heartbeat. Checks for permissions and user 'Work Mode' state.
  Future<void> startTracking() async {
    // 1. Check Permissions
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    if (permission == LocationPermission.deniedForever) return;

    // 2. Setup Position Stream
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5, // Update every 5 meters (was 10 — stuck in traffic left rider hanging)
    );

    _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (Position position) {
        _syncLocationToCloud(position);
      },
      onError: (e) => debugPrint("Location Tracking Error: $e"),
    );

    // Heartbeat: force a GPS fix every 30s even if distanceFilter doesn't fire
    // (driver stuck in traffic <5m/15s would otherwise appear frozen to rider).
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        );
        _syncLocationToCloud(pos);
      } catch (e) {
        debugPrint("Location heartbeat error: $e");
      }
    });
  }

  void stopTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Throttled synchronization to prevent database flooding.
  /// Only updates if at least 15 seconds have passed or significant movement occurred.
  Future<void> _syncLocationToCloud(Position position) async {
    final now = DateTime.now();
    if (_lastUpdate != null && now.difference(_lastUpdate!).inSeconds < 15) {
      return;
    }

    final profileAsync = _ref.read(profileProvider);
    final profile = profileAsync.value;
    
    // Safety Guard: Only sync if the user is in 'Work Mode' OR driver online.
    // Drivers toggle ON DUTY via driver_portal (driver_status='online') without
    // touching is_work_mode — accept either flag to actually start tracking.
    final isWorkOn = profile?.isWorkMode == true || profile?.driverStatus == 'online';
    if (profile == null || !isWorkOn) {
      stopTracking();
      return;
    }

    await _ref.read(transportServiceProvider).updateLocation(
      position.latitude,
      position.longitude,
    );
    
    _lastUpdate = now;
    debugPrint("[SYNC] GPS Heartbeat: ${position.latitude}, ${position.longitude}");
  }
}

final locationTrackerProvider = Provider((ref) => LocationTrackerService(ref));

