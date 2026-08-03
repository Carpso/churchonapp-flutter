import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';

class SosAlertService {
  final SupabaseClient _client;

  SosAlertService(this._client);

  /// Request location permission and return current position.
  Future<Position?> _getCurrentLocation() async {
    var status = await Permission.location.status;

    if (!status.isGranted) {
      status = await Permission.location.request();
      if (!status.isGranted) {
        debugPrint('[SosAlertService] Location permission denied');
        return null;
      }
    }

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
    } catch (e) {
      debugPrint('[SosAlertService] Location error: $e');
      return null;
    }
  }

  /// Trigger an SOS alert. Inserts into `sos_alerts` and notifies superadmins/employees via FCM.
  /// Falls back to SMS via edge function if push notification fails.
  Future<void> triggerSOS({
    required String contactName,
    required String contactPhone,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final position = await _getCurrentLocation();

    await _client.from('sos_alerts').insert({
      'user_id': user.id,
      'contact_name': contactName,
      'contact_phone': contactPhone,
      'lat': position?.latitude,
      'lng': position?.longitude,
      'status': 'active',
    });

    // Notify all superadmins and employees via FCM
    try {
      List<Map<String, dynamic>> admins = [];
      for (final role in ['superadmin', 'coa_employee']) {
        final batch = await _client
            .from('profiles')
            .select('id, phone_number')
            .eq('role', role)
            .limit(100);
        admins.addAll(List<Map<String, dynamic>>.from(batch));
      }

      if (admins.isNotEmpty) {
        final userName = user.userMetadata?['full_name'] ?? user.email ?? 'Unknown';
        final lat = position?.latitude;
        final lng = position?.longitude;
        final locationInfo = lat != null && lng != null ? " at https://maps.google.com/?q=$lat,$lng" : '';

        try {
          await _client.functions.invoke('push-notifications', body: {
            'userIds': admins.map((a) => a['id'] as String).toList(),
            'title': 'SOS Emergency Alert',
            'body': '$userName needs immediate help!$locationInfo',
            'data': {
              'type': 'sos_alert',
              'channel_id': 'coa_announcements',
            },
          });
        } catch (pushError) {
          debugPrint('[SosAlertService] FCM notification failed, trying SMS fallback: $pushError');

          // SMS fallback: try sending SMS to each admin with a phone number
          for (final admin in admins) {
            final adminPhone = admin['phone_number']?.toString();
            if (adminPhone != null && adminPhone.isNotEmpty) {
              try {
                await _client.functions.invoke('send-sms', body: {
                  'to': adminPhone,
                  'message': 'SOS ALERT: $userName needs immediate help! Emergency contact: $contactName ($contactPhone).$locationInfo',
                });
              } catch (smsError) {
                debugPrint('[SosAlertService] SMS fallback failed for $adminPhone: $smsError');
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[SosAlertService] Notification dispatch failed: $e');
    }
  }

  /// Fetch SOS alerts with optional status filter.
  Future<List<Map<String, dynamic>>> fetchAlerts({String? status}) async {
    dynamic query = _client
        .from('sos_alerts')
        .select('*, profiles(full_name)')
        .order('created_at', ascending: false);

    if (status != null && status != 'all') {
      query = query.eq('status', status);
    }

    final data = await query;
    return List<Map<String, dynamic>>.from(data);
  }

  /// Update the status of an SOS alert.
  Future<void> updateStatus(String alertId, String status) async {
    await _client.from('sos_alerts').update({'status': status}).eq('id', alertId);
  }
}
