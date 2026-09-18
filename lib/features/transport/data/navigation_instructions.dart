import 'route_service.dart';

/// Human-readable distance: metres under 1 km, km (1 decimal) above.
///
/// When [spoken] is true the unit is spelled out ("300 metres") for TTS;
/// otherwise the compact form ("300 m") is used in the UI.
String formatInstructionDistance(double metres, {bool spoken = false}) {
  var m = metres;
  if (m.isNaN || m.isInfinite || m < 0) m = 0;
  if (m < 1000) {
    final rounded = m < 15 ? 0 : (m / 10).round() * 10;
    return spoken ? '$rounded metres' : '$rounded m';
  }
  final km = m / 1000;
  return spoken
      ? '${km.toStringAsFixed(1)} kilometres'
      : '${km.toStringAsFixed(1)} km';
}

/// The maneuver-only phrase (no distance), e.g. "Turn left onto Great East
/// Road", "At the roundabout, take the 2nd exit", "Arrive at your destination".
String maneuverPhrase(RouteStep step) {
  final type = step.type.toLowerCase();
  final modifier = step.modifier?.toLowerCase();
  final road = step.roadLabel;
  final onto = road == null ? '' : ' onto $road';
  final on = road == null ? '' : ' on $road';

  switch (type) {
    case 'arrive':
      return 'Arrive at your destination';
    case 'depart':
      if (modifier == 'left') return 'Head left$on';
      if (modifier == 'right') return 'Head right$on';
      return 'Head straight$on';
    case 'turn':
      switch (modifier) {
        case 'slight left':
          return 'Bear left$onto';
        case 'slight right':
          return 'Bear right$onto';
        case 'sharp left':
          return 'Turn sharp left$onto';
        case 'sharp right':
          return 'Turn sharp right$onto';
        case 'uturn':
          return 'Make a U-turn$onto';
        case 'left':
          return 'Turn left$onto';
        case 'right':
          return 'Turn right$onto';
        default:
          return 'Continue$onto';
      }
    case 'new name':
    case 'continue':
      return 'Continue straight$on';
    case 'merge':
      if (modifier == 'left') return 'Merge left$onto';
      if (modifier == 'right') return 'Merge right$onto';
      return 'Merge$onto';
    case 'fork':
      if (modifier == 'left' || modifier == 'slight left') {
        return 'Keep left$onto';
      }
      if (modifier == 'right' || modifier == 'slight right') {
        return 'Keep right$onto';
      }
      return 'Keep straight$onto';
    case 'end of road':
      if (modifier == 'left') return 'Turn left at the end of the road$onto';
      if (modifier == 'right') return 'Turn right at the end of the road$onto';
      return 'Continue at the end of the road$on';
    case 'roundabout':
    case 'rotary':
      final exit = step.exitNumber;
      if (exit != null && exit > 0) {
        return 'At the roundabout, take the ${ordinal(exit)} exit$onto';
      }
      return 'At the roundabout, take the exit$onto';
    case 'roundabout turn':
      return 'At the roundabout, turn ${modifier ?? 'ahead'}$onto';
    case 'exit roundabout':
    case 'exit rotary':
      return 'Exit the roundabout$on';
    case 'on ramp':
      return 'Take the ramp${modifier != null ? ' on the $modifier' : ''}$onto';
    case 'off ramp':
      return 'Take the exit$onto';
    case 'notification':
      return 'Continue$on';
    default:
      return 'Continue$on';
  }
}

/// Full instruction text, optionally prefixed with a distance
/// ("In 300 metres, turn right") or the "now" form.
String buildInstruction(RouteStep step, {double? distanceMetres, bool spoken = false}) {
  final type = step.type.toLowerCase();
  if (type == 'arrive') {
    if (distanceMetres != null && distanceMetres > 25) {
      final d = formatInstructionDistance(distanceMetres, spoken: spoken);
      return spoken
          ? 'Your destination is $d ahead'
          : 'Destination in $d';
    }
    return 'You have arrived at your destination';
  }

  final phrase = maneuverPhrase(step);
  if (distanceMetres == null) return phrase;
  if (distanceMetres <= 25) return '$phrase now';
  final d = formatInstructionDistance(distanceMetres, spoken: spoken);
  return 'In $d, ${_lowerFirst(phrase)}';
}

/// 1 -> 1st, 2 -> 2nd, 3 -> 3rd, 11 -> 11th, 21 -> 21st.
String ordinal(int n) {
  if (n <= 0) return '$n';
  final mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 13) return '${n}th';
  switch (n % 10) {
    case 1:
      return '${n}st';
    case 2:
      return '${n}nd';
    case 3:
      return '${n}rd';
    default:
      return '${n}th';
  }
}

String _lowerFirst(String s) {
  if (s.isEmpty) return s;
  return s[0].toLowerCase() + s.substring(1);
}
