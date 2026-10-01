import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

/// A navigation target the user can send directions to.
class MapAppTarget {
  const MapAppTarget({
    required this.name,
    required this.uri,
    required this.icon,
    this.available = true,
  });

  final String name;
  final Uri uri;
  final IconData icon;

  /// false when the app is not installed / the scheme is unresolvable.
  final bool available;
}

/// Hands a destination to another map / navigation app.
///
/// PLATFORM NOTE — this is deliberate and not a workaround:
///  * Android: the manifest registers the geo and google.navigation intent
///    filters AND a queries block, so Church On App itself is offered by
///    other apps' "Directions" buttons, and we can launch other maps here.
///  * iOS: Apple Maps PERMANENTLY owns the `geo:` scheme (Apple's platform
///    policy), so an iOS app can never appear as the handler for a `geo:`
///    link. The best iOS can do — and what this sheet does — is offer the
///    user a chooser of installed navigation apps.
class MapAppLauncher {
  const MapAppLauncher._();

  static const _label = 'Church On App';

  /// Canonical shareable link (our own domain, for copy/paste into messages).
  static String shareableLink(LatLng destination, {String? label}) {
    final q = Uri(
      queryParameters: {
        'lat': destination.latitude.toString(),
        'lng': destination.longitude.toString(),
        if (label != null && label.isNotEmpty) 'name': label,
      },
    );
    return 'https://churchonapp.com/navigate?$q';
  }

  /// The navigation apps we know how to hand a destination to.
  static List<MapAppTarget> targets(LatLng destination, {String? label}) {
    final lat = destination.latitude;
    final lng = destination.longitude;
    final name = label == null || label.isEmpty ? '' : label;


    return [
      MapAppTarget(
        name: 'Google Maps',
        uri: Uri.parse('https://www.google.com/maps/search/?api=1'
            '&query=$lat,$lng'),
        icon: LucideIcons.map,
      ),
      MapAppTarget(
        name: 'Waze',
        uri: Uri.parse('waze://?ll=$lat,$lng&navigate=yes'),
        icon: LucideIcons.navigation,
      ),
      MapAppTarget(
        name: 'OpenStreetMap',
        uri: Uri.parse(
            'osm://directions?to=$lat,$lng&engine=fossgis_osrm_car'),
        icon: LucideIcons.mapPin,
      ),
      MapAppTarget(
        name: 'Our own navigation',
        uri: Uri.parse(
            'https://churchonapp.com/navigate?lat=$lat&lng=$lng'
            '${name.isEmpty ? '' : '&name=${Uri.encodeComponent(name)}'}'),
        icon: LucideIcons.church,
      ),
    ];
  }

  /// Launch a target, reporting whether it actually worked. Never throws.
  static Future<bool> open(MapAppTarget target) async {
    try {
      if (await canLaunchUrl(target.uri)) {
        await launchUrl(target.uri, mode: LaunchMode.externalApplication);
        return true;
      }
      // waze:// / osm:// fail canLaunchUrl on some devices but still resolve;
      // fall back to the https page so the user is not stuck.
      if (target.uri.scheme != 'https') {
        final web = _httpsFallback(target.uri.scheme);
        if (web != null && await canLaunchUrl(web)) {
          await launchUrl(web, mode: LaunchMode.externalApplication);
          return true;
        }
      }
      return false;
    } catch (e) {
      debugPrint('MapAppLauncher.open failed: $e');
      return false;
    }
  }

  static Uri? _httpsFallback(String scheme) => switch (scheme) {
        'waze' => Uri.parse('https://www.waze.com/ul'),
        'osm' => Uri.parse('https://www.openstreetmap.org/'),
        _ => null,
      };

  /// Open the chooser. Returns the chosen app name, or null if dismissed.
  static Future<String?> showChooser(
    BuildContext context,
    LatLng destination, {
    String? label,
  }) async {
    final list = targets(destination, label: label);
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label == null || label.isEmpty
                          ? 'Navigate'
                          : 'Navigate to $label',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 3),
                  const Text('Choose an app for directions',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            for (final t in list)
              ListTile(
                leading: Icon(t.icon),
                title: Text(t.name),
                trailing: const Icon(LucideIcons.chevronRight, size: 18),
                onTap: () => Navigator.pop(ctx, t.name),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null || !context.mounted) return null;

    final target = list.firstWhere((t) => t.name == picked);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await open(target);
    if (!ok) {
      messenger.showSnackBar(SnackBar(
          content: Text('Could not open $picked on this device.')));
    } else if (picked != _label) {
      // Tell the user they can keep using us for turn-by-turn too.
      messenger.showSnackBar(const SnackBar(
        content: Text('Opened in the other app. Church On App navigation '
            'is always available from the link sheet.'),
      ));
    }
    return picked;
  }

  /// Copy the canonical link (works everywhere, no app required).
  static Future<void> copyLink(
      BuildContext context, LatLng destination, String? label) async {
    await Clipboard.setData(
        ClipboardData(text: shareableLink(destination, label: label)));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Navigation link copied')),
      );
    }
  }
}
