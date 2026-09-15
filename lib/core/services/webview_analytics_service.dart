import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Records external-link opens so COA can see what members read.
///
/// Links open in the PLATFORM in-app browser (Chrome Custom Tabs on Android,
/// SFSafariViewController on iOS) rather than a full external browser — the
/// user stays inside Church On App.
class WebviewAnalyticsService {
  final SupabaseClient _client;
  WebviewAnalyticsService(this._client);

  /// Fire-and-forget: an analytics failure must never block the navigation.
  Future<void> recordOpen(String url, {String? source, String? tenantId}) async {
    try {
      final uid = _client.auth.currentUser?.id;
      await _client.from('webview_opens').insert({
        'user_id': uid,
        'tenant_id': tenantId,
        'url': url,
        'source': source,
      });
    } catch (e) {
      debugPrint('webview analytics record failed (non-fatal): $e');
    }
  }

  /// Record + open in the in-app browser. Returns true when launched.
  Future<bool> openTracked(
    String url, {
    String? source,
    String? tenantId,
  }) async {
    await recordOpen(url, source: source, tenantId: tenantId);
    try {
      final uri = Uri.tryParse(url);
      if (uri == null || !uri.hasScheme) return false;
      return await launchUrl(uri, mode: LaunchMode.inAppWebView);
    } catch (e) {
      debugPrint('openTracked launch failed: $e');
      return false;
    }
  }

  /// Aggregated opens for the COA dashboard.
  Future<List<Map<String, dynamic>>> topOpened({
    int days = 30,
    int limit = 25,
  }) async {
    try {
      final res = await _client.rpc('get_webview_analytics', params: {
        'p_days': days,
        'p_limit': limit,
      });
      return (res as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('webview analytics fetch failed: $e');
      return [];
    }
  }
}

final webviewAnalyticsProvider = Provider<WebviewAnalyticsService>((ref) {
  return WebviewAnalyticsService(Supabase.instance.client);
});
