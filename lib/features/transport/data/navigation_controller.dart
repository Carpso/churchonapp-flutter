import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:church_on_app/core/services/voice_direction_service.dart';
import 'navigation_instructions.dart';
import 'route_service.dart';

/// Off-route threshold (metres): a position this far from the polyline means
/// the driver has left the route and should be rerouted.
const double kOffRouteThresholdMetres = 40.0;

/// Minimum time between automatic reroutes.
const Duration kRerouteCooldown = Duration(seconds: 20);

/// Immutable navigation state exposed to the UI.
class NavigationState {
  final RouteResult? route;

  /// Index of the step currently being travelled.
  final int stepIndex;

  /// Step whose maneuver is next (usually [stepIndex] + 1).
  final int nextIndex;

  final RouteStep? currentStep;
  final RouteStep? nextStep;

  /// Live distance to the next maneuver (metres).
  final double distanceToManeuverMetres;

  /// How far the current position is from the route polyline (metres).
  final double snapDistanceMetres;

  final bool isOffRoute;
  final bool isRerouting;

  final double remainingMetres;
  final int etaSecondsRemaining;

  /// Full human instruction for the next maneuver (e.g. "In 300 m, turn left").
  final String instruction;

  final bool isFallback;
  final String? error;

  const NavigationState({
    this.route,
    this.stepIndex = 0,
    this.nextIndex = 0,
    this.currentStep,
    this.nextStep,
    this.distanceToManeuverMetres = 0,
    this.snapDistanceMetres = 0,
    this.isOffRoute = false,
    this.isRerouting = false,
    this.remainingMetres = 0,
    this.etaSecondsRemaining = 0,
    this.instruction = '',
    this.isFallback = false,
    this.error,
  });

  /// True only when OSRM provided real maneuvers.
  bool get hasGuidance =>
      route != null && !isFallback && route!.steps.isNotEmpty;

  String get distanceToManeuverText =>
      formatInstructionDistance(distanceToManeuverMetres);

  String get remainingText => formatInstructionDistance(remainingMetres);

  String get etaText {
    final s = etaSecondsRemaining;
    if (s <= 0) return 'Arriving now';
    final m = (s / 60).ceil();
    if (m < 60) return '$m min';
    final h = m ~/ 60;
    final rem = m % 60;
    return rem > 0 ? '$h hr $rem min' : '$h hr';
  }

  NavigationState copyWith({
    RouteResult? route,
    int? stepIndex,
    int? nextIndex,
    RouteStep? currentStep,
    RouteStep? nextStep,
    double? distanceToManeuverMetres,
    double? snapDistanceMetres,
    bool? isOffRoute,
    bool? isRerouting,
    double? remainingMetres,
    int? etaSecondsRemaining,
    String? instruction,
    bool? isFallback,
    String? error,
    bool clearError = false,
  }) {
    return NavigationState(
      route: route ?? this.route,
      stepIndex: stepIndex ?? this.stepIndex,
      nextIndex: nextIndex ?? this.nextIndex,
      currentStep: currentStep ?? this.currentStep,
      nextStep: nextStep ?? this.nextStep,
      distanceToManeuverMetres:
          distanceToManeuverMetres ?? this.distanceToManeuverMetres,
      snapDistanceMetres: snapDistanceMetres ?? this.snapDistanceMetres,
      isOffRoute: isOffRoute ?? this.isOffRoute,
      isRerouting: isRerouting ?? this.isRerouting,
      remainingMetres: remainingMetres ?? this.remainingMetres,
      etaSecondsRemaining: etaSecondsRemaining ?? this.etaSecondsRemaining,
      instruction: instruction ?? this.instruction,
      isFallback: isFallback ?? this.isFallback,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Computes live turn-by-turn progress from a route + a position stream:
/// current step, distance to the next maneuver, off-route detection with
/// debounced rerouting, and a remaining ETA.
class NavigationNotifier extends Notifier<NavigationState> {
  StreamSubscription<LatLng>? _sub;
  LatLng? _destination;
  LatLng? _lastPosition;

  /// Cumulative distance (metres) from the route start to each route point.
  List<double> _cumulative = const [];

  /// Cumulative distance (metres) at the END of each step.
  List<double> _stepEnds = const [];

  double _totalMetres = 0;
  DateTime? _lastReroute;

  /// Announcement bookkeeping: keys of already-spoken thresholds per step.
  final Set<String> _announced = {};

  @override
  NavigationState build() {
    ref.onDispose(() {
      _sub?.cancel();
      _sub = null;
    });
    return const NavigationState();
  }

  /// Begin guidance. [positions] is optional — callers may instead push
  /// positions via [updatePosition].
  void start({
    required RouteResult route,
    required LatLng destination,
    LatLng? origin,
    Stream<LatLng>? positions,
  }) {
    _sub?.cancel();
    _sub = null;
    _destination = destination;
    _lastReroute = null;
    _lastPosition = origin;
    _announced.clear();
    _prepare(route);

    if (positions != null) {
      _sub = positions.listen(
        updatePosition,
        onError: (Object e) => debugPrint('Navigation position stream error: $e'),
      );
    }
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _destination = null;
    _lastPosition = null;
    _cumulative = const [];
    _stepEnds = const [];
    _totalMetres = 0;
    _announced.clear();
    state = const NavigationState();
  }

  void _prepare(RouteResult route) {
    _cumulative = _cumulativeDistances(route.points);
    _totalMetres = _cumulative.isEmpty ? 0 : _cumulative.last;

    _stepEnds = [];
    var acc = 0.0;
    for (final s in route.steps) {
      final d = s.distanceMetres;
      if (d.isFinite && d > 0) acc += d;
      _stepEnds.add(acc);
    }

    final steps = route.steps;
    final RouteStep? first = steps.isNotEmpty ? steps.first : null;
    final RouteStep? next = steps.length > 1 ? steps[1] : first;
    state = NavigationState(
      route: route,
      stepIndex: 0,
      nextIndex: steps.length > 1 ? 1 : 0,
      currentStep: first,
      nextStep: next,
      distanceToManeuverMetres: first?.distanceMetres ?? 0,
      remainingMetres: route.distanceMetres,
      etaSecondsRemaining: route.durationSeconds,
      isFallback: route.isFallback,
      instruction: next == null
          ? ''
          : buildInstruction(next, distanceMetres: first?.distanceMetres),
    );
  }

  /// Recompute guidance for a new position. Safe for degenerate routes.
  void updatePosition(LatLng position) {
    final route = state.route;
    if (route == null) return;
    _lastPosition = position;

    final points = route.points;
    final snap = _snap(points, position);
    final travelled = snap.travelled.clamp(0.0, _totalMetres);
    final remaining = (_totalMetres - travelled).clamp(0.0, _totalMetres);

    final isOffRoute = snap.distance > kOffRouteThresholdMetres;

    // Locate the step currently being travelled.
    final steps = route.steps;
    var currentIdx = 0;
    if (steps.isNotEmpty && _stepEnds.length == steps.length) {
      currentIdx = steps.length - 1;
      for (var i = 0; i < _stepEnds.length; i++) {
        if (travelled <= _stepEnds[i] + 0.5) {
          currentIdx = i;
          break;
        }
      }
    }
    final nextIdx = steps.isEmpty
        ? 0
        : (currentIdx + 1 < steps.length ? currentIdx + 1 : currentIdx);
    final currentStep = steps.isEmpty ? null : steps[currentIdx];
    final nextStep = steps.isEmpty ? null : steps[nextIdx];

    final distToManeuver = _stepEnds.length > currentIdx
        ? (_stepEnds[currentIdx] - travelled).clamp(0.0, _totalMetres)
        : remaining;

    final eta = _totalMetres > 0
        ? (route.durationSeconds * (remaining / _totalMetres)).round()
        : 0;

    final instruction = nextStep == null
        ? ''
        : buildInstruction(nextStep, distanceMetres: distToManeuver);

    state = state.copyWith(
      stepIndex: currentIdx,
      nextIndex: nextIdx,
      currentStep: currentStep,
      nextStep: nextStep,
      distanceToManeuverMetres: distToManeuver,
      snapDistanceMetres: snap.distance,
      isOffRoute: isOffRoute,
      remainingMetres: remaining,
      etaSecondsRemaining: eta,
      instruction: instruction,
      clearError: true,
    );

    if (nextStep != null) {
      _maybeAnnounce(nextIdx, nextStep, distToManeuver);
    }

    if (isOffRoute) {
      _maybeReroute(position);
    }
  }

  /// Announce at ~400 m, ~150 m and "now" — once per step per threshold.
  void _maybeAnnounce(int stepIndex, RouteStep step, double distance) {
    // Smallest first so an already-close position announces the right band.
    const bands = <double>[30, 150, 400];
    for (var i = 0; i < bands.length; i++) {
      final key = 'step-$stepIndex-band${bands[i].toInt()}';
      if (_announced.contains(key)) continue;
      if (distance <= bands[i]) {
        // Any larger band is also passed — never announce it later.
        for (var j = i; j < bands.length; j++) {
          _announced.add('step-$stepIndex-band${bands[j].toInt()}');
        }
        final isNow = i == 0;
        final text = isNow
            ? (step.type.toLowerCase() == 'arrive'
                ? 'You have arrived at your destination'
                : '${maneuverPhrase(step)} now')
            : buildInstruction(step, distanceMetres: bands[i], spoken: true);
        VoiceDirectionService.announceManeuver(
          text,
          urgency: isNow ? 'now' : (i == 1 ? 'near' : 'far'),
          stepKey: key,
        );
        return;
      }
    }
  }

  void _maybeReroute(LatLng position) {
    final dest = _destination;
    if (dest == null || state.isRerouting) return;
    final now = DateTime.now();
    if (_lastReroute != null && now.difference(_lastReroute!) < kRerouteCooldown) {
      return;
    }
    _lastReroute = now;
    _reroute(position, dest);
  }

  Future<void> _reroute(LatLng from, LatLng destination) async {
    state = state.copyWith(isRerouting: true, clearError: true);
    final result = await RouteService.fetchRoute(from: from, to: destination);
    if (result.points.isEmpty) {
      state = state.copyWith(isRerouting: false, error: 'Could not reroute');
      return;
    }
    _announced.clear();
    _stepEnds = const [];
    _cumulative = const [];
    _prepare(result);
    if (_lastPosition != null) {
      updatePosition(_lastPosition!);
    }
  }

  // --- geometry helpers ---

  static List<double> _cumulativeDistances(List<LatLng> pts) {
    if (pts.isEmpty) return const [];
    final out = <double>[0];
    for (var i = 1; i < pts.length; i++) {
      out.add(out[i - 1] + const Distance().as(LengthUnit.Meter, pts[i - 1], pts[i]));
    }
    return out;
  }

  /// Distance from [p] to the polyline plus the distance travelled along it at
  /// the nearest point.
  ({double distance, double travelled}) _snap(List<LatLng> pts, LatLng p) {
    if (pts.isEmpty) return (distance: double.infinity, travelled: 0);
    if (pts.length == 1) {
      return (
        distance: const Distance().as(LengthUnit.Meter, p, pts.first),
        travelled: 0,
      );
    }
    var best = double.infinity;
    var bestTravelled = 0.0;
    for (var i = 0; i < pts.length - 1; i++) {
      final a = pts[i];
      final b = pts[i + 1];
      final segLen = const Distance().as(LengthUnit.Meter, a, b);
      if (segLen <= 0) {
        final d = const Distance().as(LengthUnit.Meter, p, a);
        if (d < best) {
          best = d;
          bestTravelled = _cumulative.length > i ? _cumulative[i] : 0;
        }
        continue;
      }
      final t = _projectionT(p, a, b);
      final projected = LatLng(
        a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t,
      );
      final d = const Distance().as(LengthUnit.Meter, p, projected);
      if (d < best) {
        best = d;
        final base = _cumulative.length > i ? _cumulative[i] : 0;
        bestTravelled = base + segLen * t;
      }
    }
    return (distance: best, travelled: bestTravelled);
  }

  /// Normalised projection of [p] onto segment a→b using a local planar
  /// approximation (accurate at city scale).
  static double _projectionT(LatLng p, LatLng a, LatLng b) {
    final latRef = a.latitude * math.pi / 180;
    double x(LatLng q) => q.longitude * math.pi / 180 * math.cos(latRef);
    double y(LatLng q) => q.latitude * math.pi / 180;
    final ax = x(a), ay = y(a);
    final dx = x(b) - ax, dy = y(b) - ay;
    final len2 = dx * dx + dy * dy;
    if (len2 == 0) return 0;
    final t = ((x(p) - ax) * dx + (y(p) - ay) * dy) / len2;
    return t.clamp(0.0, 1.0);
  }
}

final navigationProvider =
    NotifierProvider<NavigationNotifier, NavigationState>(
  NavigationNotifier.new,
);

/// Persisted mute toggle for spoken maneuver announcements.
class VoiceMuteNotifier extends Notifier<bool> {
  static const _key = 'voice_directions_muted';

  @override
  bool build() {
    _load();
    return false;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final muted = prefs.getBool(_key) ?? false;
      VoiceDirectionService.setMuted(muted);
      if (muted) state = true;
    } catch (e) {
      debugPrint('VoiceMute load failed: $e');
    }
  }

  Future<void> setMuted(bool value) async {
    state = value;
    VoiceDirectionService.setMuted(value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, value);
    } catch (e) {
      debugPrint('VoiceMute save failed: $e');
    }
  }

  void toggle() => setMuted(!state);
}

final voiceMuteProvider = NotifierProvider<VoiceMuteNotifier, bool>(
  VoiceMuteNotifier.new,
);
