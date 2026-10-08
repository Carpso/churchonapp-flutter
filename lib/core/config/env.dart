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
  
  /// Base (country/regional) PMTiles archive — z0–15, always matches.
  static String get mapsZambiaUrl => dotenv.env['MAPS_ZAMBIA_URL'] ?? 'https://maps.churchonapp.com/region-zm-zw-mw-mz.pmtiles';

  /// Optional second country archive. Skipped automatically when it equals
  /// [mapsZambiaUrl] (the current regional build covers Zimbabwe too).
  static String get mapsZimbabweUrl => dotenv.env['MAPS_ZIMBABWE_URL'] ?? 'https://maps.churchonapp.com/region-zm-zw-mw-mz.pmtiles';

  /// Raw `MAPS_EXTRA_SOURCES` value: a JSON array of high-detail city archives
  /// the basemap switches to when the camera is inside one and zoomed in far
  /// enough, e.g.
  ///
  /// ```json
  /// [{"name":"lusaka",
  ///   "bbox":[-15.78,27.66,-15.02,28.62],
  ///   "minZoom":16,"maxZoom":19,
  ///   "url":"https://maps.churchonapp.com/tiles/lusaka-z13-19.pmtiles"}]
  /// ```
  ///
  /// `bbox` is `[south, west, north, east]`. Build these with
  /// `scripts/map/build-city-tiles.ps1` (or `.sh`).
    static String get mapsExtraSources => dotenv.env['MAPS_EXTRA_SOURCES'] ?? '';

    /// Raster basemap template, e.g.
    /// `https://maps.churchonapp.com/raster/{z}/{x}/{y}.png`.
    ///
    /// Empty by default. This is what makes the map work on WEB, where the
    /// vector-tile executor cannot run (`Unsupported operation: ReceivePort`
    /// from `executor_lib`'s isolate `PoolExecutor` branch, which is only
    /// bypassed under `kDebugMode`). It must point at tiles WE host — do not
    /// point this at OpenStreetMap's public raster servers: a browser cannot set
    /// a compliant User-Agent, and OSM answers non-compliant requests with
    /// HTTP 200 carrying a "403 Access blocked" tile, so the map appears to load
    /// while showing no roads or labels.
    static String get rasterBaseUrl =>
        dotenv.env['MAPS_RASTER_BASE_URL'] ?? '';
  
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

