import 'dart:async';
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
      distanceFilter: 10, // Update every 10 meters
    );

    _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (Position position) {
        _syncLocationToCloud(position);
      },
      onError: (e) => print("Location Tracking Error: $e"),
    );
  }

  void stopTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
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
    
    // Safety Guard: Only sync if the user is in 'Work Mode'
    if (profile == null || !profile.isWorkMode) {
      stopTracking();
      return;
    }

    await _ref.read(transportServiceProvider).updateLocation(
      position.latitude,
      position.longitude,
    );
    
    _lastUpdate = now;
    print("[SYNC] GPS Heartbeat: ${position.latitude}, ${position.longitude}");
  }
}

final locationTrackerProvider = Provider((ref) => LocationTrackerService(ref));

