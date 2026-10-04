import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:church_on_app/core/services/voice_direction_service.dart';
import 'package:church_on_app/core/widgets/church_map.dart';
import 'package:church_on_app/features/transport/data/navigation_controller.dart';
import 'package:church_on_app/features/transport/data/route_service.dart';

import 'widgets/navigation_banner.dart';
import 'widgets/route_steps_sheet.dart';

/// Standalone turn-by-turn navigation on the Carpso Ride map.
///
/// Opened when the phone hands us a destination — the Android app chooser
/// listing for `geo:` / `google.navigation:` intents, a `churchonapp://navigate`
/// link, or `https://churchonapp.com/navigate?...`. Uses the exact same engines
/// as the active-ride screen: OSRM routing ([RouteService]), the live guidance
/// controller ([navigationProvider]), the maneuver banner and voice directions.
class MapNavigationScreen extends ConsumerStatefulWidget {
  final double lat;
  final double lng;
  final String? label;

  const MapNavigationScreen({
    super.key,
    required this.lat,
    required this.lng,
    this.label,
  });

  @override
  ConsumerState<MapNavigationScreen> createState() =>
      _MapNavigationScreenState();
}

class _MapNavigationScreenState extends ConsumerState<MapNavigationScreen> {
  final StreamController<LatLng> _posController =
      StreamController<LatLng>.broadcast();
  StreamSubscription<Position>? _posSub;

  LatLng? _me;
  RouteResult? _route;
  bool _loading = true;
  String? _error;
  bool _arrived = false;

  LatLng get _dest => LatLng(widget.lat, widget.lng);

  String get _destLabel =>
      (widget.label == null || widget.label!.trim().isEmpty)
          ? 'Destination'
          : widget.label!.trim();

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    // Track which stage failed so the retry message is actionable. Telling
    // someone whose GPS is perfect to "check GPS" because the public OSRM
    // routing server was unreachable sends them down the wrong path entirely.
    var stage = 'location';
    try {
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      if (!serviceOn) {
        if (mounted) {
          setState(() {
            _error = 'Location services are turned off. Enable GPS to navigate.';
            _loading = false;
          });
        }
        return;
      }

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _error =
                'Location permission is needed to show your position and guide you.';
            _loading = false;
          });
        }
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 30),
        ),
      );
      if (!mounted) return;
      setState(() => _me = LatLng(pos.latitude, pos.longitude));

      stage = 'routing';
      final route = await RouteService.fetchRoute(from: _me!, to: _dest);
      if (!mounted) return;
      setState(() {
        _route = route;
        _loading = false;
      });

      // Hand the route to the shared guidance controller (maneuvers, off-route
      // rerouting, voice announcements) — same engine as the ride screen.
      ref.read(navigationProvider.notifier).start(
            route: route,
            destination: _dest,
            origin: _me,
            positions: _posController.stream,
          );

      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 15,
        ),
      ).listen(
        (p) {
          final ll = LatLng(p.latitude, p.longitude);
          if (!_posController.isClosed) _posController.add(ll);
          if (mounted) setState(() => _me = ll);
          _checkArrival(ll);
        },
        onError: (Object e) =>
            debugPrint('MapNavigation position stream error: $e'),
      );
    } catch (e) {
      debugPrint('MapNavigation init failed (stage=$stage): $e');
      if (mounted) {
        setState(() {
          // Be specific about WHICH stage failed. Reporting a routing outage as
          // "check GPS" sends a user with perfect GPS signal down the wrong path
          // and hides the real problem (the public OSRM server being
          // unreachable) from anyone trying to diagnose it.
          _error = stage == 'routing'
              ? 'We have your location and the destination, but could not load '
                  'a road route right now. The routing service may be '
                  'unreachable - please try again in a moment.'
              : 'Could not get your location. Check GPS and try again.';
          _loading = false;
        });
      }
    }
  }

  void _checkArrival(LatLng me) {
    if (_arrived) return;
    final d = const Distance()(me, _dest);
    if (d <= 30) {
      setState(() => _arrived = true);
      _posSub?.cancel();
      ref.read(navigationProvider.notifier).stop();
      VoiceDirectionService.announceManeuver(
        'You have arrived at your destination',
        urgency: 'now',
        stepKey: 'nav-arrive',
      );
    }
  }

  @override
  void dispose() {
    VoiceDirectionService.stop();
    _posSub?.cancel();
    // Closing the stream ends the navigation controller's subscription without
    // mutating providers mid-teardown (same pattern as the ride screen).
    _posController.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final navState = ref.watch(navigationProvider);
    final muted = ref.watch(voiceMuteProvider);
    final route = _route;
    final dest = _dest;
    final padding = MediaQuery.of(context).padding.top;

    return Scaffold(
      body: Stack(
        children: [
          ChurchMap(
            center: _me ?? dest,
            zoom: _me != null ? 16 : 13,
            showPin: false,
            showSavePin: false,
            markers: [
              // Destination flag.
              Marker(
                point: dest,
                width: 100,
                height: 70,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 4)
                        ],
                      ),
                      child: Text(
                        _destLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Icon(LucideIcons.flag, color: Colors.red, size: 28),
                  ],
                ),
              ),
              // My position (blue puck).
              if (_me != null)
                Marker(
                  point: _me!,
                  width: 40,
                  height: 40,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 6)
                      ],
                    ),
                    child: const Icon(
                      Icons.navigation_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
            ],
            path: route != null && route.points.length >= 2
                ? route.points
                : (_me != null ? [_me!, dest] : null),
          ),

          // Back.
          Positioned(
            top: padding + 10,
            left: 20,
            child: CircleAvatar(
              backgroundColor: Colors.white,
              child: IconButton(
                icon: const Icon(LucideIcons.arrowLeft, color: Colors.black),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),

          // Voice mute.
          Positioned(
            top: padding + 10,
            left: 70,
            child: CircleAvatar(
              backgroundColor:
                  muted ? Colors.white : theme.primaryColor,
              child: IconButton(
                icon: Icon(
                  muted ? LucideIcons.volumeX : LucideIcons.volume2,
                  color: muted ? Colors.black : Colors.white,
                ),
                onPressed: () {
                  final nowMuted = !muted;
                  ref.read(voiceMuteProvider.notifier).setMuted(nowMuted);
                  if (nowMuted) {
                    VoiceDirectionService.stop();
                  } else {
                    VoiceDirectionService.speak(navState.hasGuidance
                        ? 'Voice directions enabled. I will announce each turn.'
                        : 'Voice directions enabled.');
                  }
                },
              ),
            ),
          ),

          // Turn-by-turn banner (renders nothing on straight-line fallbacks).
          Positioned(
            top: padding + 66,
            left: 12,
            right: 12,
            child: NavigationBanner(
              state: navState,
              muted: muted,
              onToggleMute: () {
                final nowMuted = !muted;
                ref.read(voiceMuteProvider.notifier).setMuted(nowMuted);
                if (nowMuted) {
                  VoiceDirectionService.stop();
                } else {
                  VoiceDirectionService.speak('Voice directions enabled.');
                }
              },
              onShowSteps: navState.route != null &&
                      navState.route!.steps.isNotEmpty
                  ? () => showRouteStepsSheet(
                        context,
                        route: navState.route!,
                        currentIndex: navState.stepIndex,
                      )
                  : null,
            ),
          ),

          // Bottom status card.
          Align(
            alignment: Alignment.bottomCenter,
            child: _buildBottomCard(theme, navState, route),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomCard(
    ThemeData theme,
    NavigationState navState,
    RouteResult? route,
  ) {
    final padding = MediaQuery.of(context).padding.bottom;

    if (_loading) {
      return _card(
        padding,
        child: const Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Text(
                'Calculating your route…',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return _card(
        padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(LucideIcons.mapPinOff,
                    color: Colors.red.shade700, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _error!,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Geolocator.openLocationSettings(),
                    child: const Text('LOCATION SETTINGS'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _start,
                    child: const Text('TRY AGAIN'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (_arrived) {
      return _card(
        padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(LucideIcons.checkCircle,
                      color: Colors.green.shade700, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'You have arrived',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _destLabel,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('DONE'),
              ),
            ),
          ],
        ),
      );
    }

    // Live guidance values when available, else the fetched route's estimate.
    final hasLive = navState.route != null;
    final eta = hasLive ? navState.etaText : (route?.etaText ?? '—');
    final dist = hasLive
        ? navState.remainingText
        : (route?.distanceText ?? '—');
    final fallback = route?.isFallback == true;

    return _card(
      padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(LucideIcons.navigation,
                    color: theme.primaryColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _destLabel,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      fallback
                          ? 'Approximate route — road guidance unavailable'
                          : 'Turn-by-turn guidance active',
                      style: TextStyle(
                        fontSize: 12,
                        color: fallback
                            ? Colors.amber.shade800
                            : Colors.grey.shade600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    eta,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    dist,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _card(double bottomPadding, {required Widget child}) {
    return Container(
      margin: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottomPadding),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 20)
        ],
      ),
      child: child,
    );
  }
}
