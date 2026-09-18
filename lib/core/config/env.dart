import 'package:flutter_dotenv/flutter_dotenv.dart';

class Env {
  static String get supabaseUrl => dotenv.env['SUPABASE_URL'] ?? '';
  static String get supabaseAnonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? '';

  /// True only when the bundled .env carries REAL Supabase credentials.
  ///
  /// Guards against placeholder builds (e.g. `.env.example` copied by CI or a
  /// stale `.env`) that would otherwise silently break sign-in with a
  /// "you're offline" error against `https://your-project.supabase.co`.
  static bool get isSupabaseConfigured {
    final url = supabaseUrl.trim();
    if (url.isEmpty) return false;
    if (url.contains('your-project') || url.contains('YOUR_PROJECT')) return false;
    final key = supabaseAnonKey.trim();
    if (key.isEmpty || !key.startsWith('eyJ')) return false;
    return true;
  }
  
  static String get mapsZambiaUrl => dotenv.env['MAPS_ZAMBIA_URL'] ?? 'https://maps.churchonapp.com/zambia.pmtiles';
  static String get mapsZimbabweUrl => dotenv.env['MAPS_ZIMBABWE_URL'] ?? 'https://maps.churchonapp.com/zimbabwe.pmtiles';
  
  static String get r2PublicDomain => dotenv.env['R2_PUBLIC_DOMAIN'] ?? 'media.churchonapp.com';

  /// Turn-by-turn routing endpoint (OSRM-compatible).
  ///
  /// Defaults to the public OSRM demo server, which is rate-limited and has no
  /// SLA — point `OSRM_BASE_URL` at your own OSRM/Valhalla instance before the
  /// ride/delivery volume grows.
  static String get osrmBaseUrl =>
      dotenv.env['OSRM_BASE_URL'] ?? 'https://router.project-osrm.org/route/v1/driving';

  /// Optional live-traffic RASTER tile template (e.g.
  /// `https://.../{z}/{x}/{y}.png`). Compile-time only — pass it with
  /// `--dart-define=TRAFFIC_TILES_URL=...`. When empty (the default) the map
  /// falls back to the crowd-sourced driver-speed overlay instead.
  static const String trafficTilesUrl =
      String.fromEnvironment('TRAFFIC_TILES_URL');

  // Public OAuth web client ID (safe to ship — Google publishes it in web
  // bundles; it is NOT a secret).
  static String get googleWebClientId => dotenv.env['GOOGLE_WEB_CLIENT_ID'] ?? '';

  // NOTE: Server-side secrets (R2 keys, Cloudflare token, Gemini/HuggingFace
  // keys, Resend, Lipila) are NEVER read in the app — they live only in the
  // Edge Function environment (Deno.env.get). Never add them here: any value
  // in this file that is bundled as an asset ships inside every release APK/AAB.

  static String get lipilaWebhookUrl =>
      dotenv.env['LIPILA_WEBHOOK_URL'] ??
      'https://supabase.churchonapp.com/functions/v1/lipila-webhook';
  static String get lipilaPayoutWebhookUrl =>
      dotenv.env['LIPILA_PAYOUT_WEBHOOK_URL'] ??
      'https://supabase.churchonapp.com/functions/v1/lipila-webhook';

  static String get coaTreasuryPhone => dotenv.env['COA_TREASURY_PHONE'] ?? '2609776847775';
  static String get coaMoMoNumber => dotenv.env['COA_MOMO_NUMBER'] ?? '0976847775';
  static String get coaMoMoName => dotenv.env['COA_MOMO_NAME'] ?? 'Church On App Official';
  static String get treasuryId => dotenv.env['TREASURY_ID'] ?? '';
}

