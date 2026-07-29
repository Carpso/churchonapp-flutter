import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lucide_icons/lucide_icons.dart';

class LocationPermissionHelper {
  /// Checks location permission and displays a Prominent Disclosure and Consent Dialog if not yet granted.
  /// Returns [true] if permission is granted, [false] otherwise.
  static Future<bool> showDisclosureIfNeeded(
    BuildContext context, {
    required String purpose,
  }) async {
    // 1. Check current permission status
    LocationPermission status = await Geolocator.checkPermission();

    // If already granted, proceed directly
    if (status == LocationPermission.always || status == LocationPermission.whileInUse) {
      return true;
    }

    // 2. If denied or deniedForever, show the Prominent Disclosure Dialog first
    if (context.mounted) {
      final consented = await showDialog<bool>(
        context: context,
        barrierDismissible: false, // Force user to choose
        builder: (ctx) => PopScope(
          canPop: false, // Prevent dismissing by system back button
          child: AlertDialog(
            backgroundColor: const Color(0xFFFFFAEB), // Warm premium cream theme
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4820A).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(LucideIcons.mapPin, color: Color(0xFFD4820A), size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    "Location Access",
                    style: TextStyle(
                      color: Color(0xFF2C1A04),
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Church On App collects location data to enable transport routing, live ride coordination, emergency SOS dispatch, and on-duty driver tracking even when the app is closed or not in use.",
                    style: TextStyle(color: Color(0xFF2C1A04), fontWeight: FontWeight.bold, fontSize: 13, height: 1.45),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "This permission is required to enable the following features for $purpose:",
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  _buildListItem(
                    LucideIcons.zap,
                    "On-Duty Driver Tracking",
                    "Updates and tracks your location in the background when you go on duty. This runs even when the app is closed or not in use, allowing riders to match with you and trace your vehicle on the map.",
                  ),
                  const SizedBox(height: 12),
                  _buildListItem(
                    LucideIcons.navigation,
                    "Live Ride Coordination",
                    "Tracks your coordinates during active trips to provide real-time routes, live ETAs, and mapping.",
                  ),
                  const SizedBox(height: 12),
                  _buildListItem(
                    LucideIcons.shieldAlert,
                    "Emergency SOS",
                    "Pinpoints your exact location to dispatchers and church emergency personnel if you trigger the SOS button, ensuring help arrives when needed.",
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "Data Privacy Commitment:",
                    style: TextStyle(
                      color: Color(0xFF2C1A04),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Your location data is transmitted securely to our servers, shared only with active riders or dispatchers during rides/alerts, and is never sold or used for targeted ads.",
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 11.5, height: 1.45),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  "DECLINE",
                  style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD4820A),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  elevation: 0,
                ),
                child: const Text(
                  "AGREE & ACCEPT",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      );

      if (consented == true) {
        // 3. Request the platform permission
        LocationPermission newStatus = await Geolocator.requestPermission();
        if (newStatus == LocationPermission.always || newStatus == LocationPermission.whileInUse) {
          return true;
        }
      }
    }

    return false;
  }

  static Widget _buildListItem(IconData icon, String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFFD4820A), size: 18),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(color: Color(0xFF2C1A04), fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 3),
              Text(
                description,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 11.5, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
