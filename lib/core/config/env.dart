import 'package:flutter_dotenv/flutter_dotenv.dart';

class Env {
  static String get supabaseUrl => dotenv.env['SUPABASE_URL'] ?? '';
  static String get supabaseAnonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? '';
  
  static String get mapsZambiaUrl => dotenv.env['MAPS_ZAMBIA_URL'] ?? 'https://maps.churchonapp.com/zambia.pmtiles';
  static String get mapsZimbabweUrl => dotenv.env['MAPS_ZIMBABWE_URL'] ?? 'https://maps.churchonapp.com/zimbabwe.pmtiles';
  static String get liveStreamUrl => dotenv.env['LIVE_STREAM_URL'] ?? 'http://db.churchonapp.com:8088/live/';
  
  static String get r2Endpoint => dotenv.env['R2_ENDPOINT'] ?? '';
  static String get r2PublicDomain => dotenv.env['R2_PUBLIC_DOMAIN'] ?? 'media.churchonapp.com';
  
  static String get geminiApiKey => dotenv.env['GEMINI_API_KEY'] ?? '';
  static String get googleWebClientId => dotenv.env['GOOGLE_WEB_CLIENT_ID'] ?? '';
  static String get huggingFaceToken => dotenv.env['HUGGINGFACE_TOKEN'] ?? '';

  static String get lipilaWebhookUrl =>
      dotenv.env['LIPILA_WEBHOOK_URL'] ??
      'https://supabase.churchonapp.com/functions/v1/lipila-webhook';
  static String get lipilaPayoutWebhookUrl =>
      dotenv.env['LIPILA_PAYOUT_WEBHOOK_URL'] ??
      'https://supabase.churchonapp.com/functions/v1/lipila-webhook';

  static String get coaTreasuryPhone => dotenv.env['COA_TREASURY_PHONE'] ?? '260977000000';
  static String get coaMoMoNumber => dotenv.env['COA_MOMO_NUMBER'] ?? '0977000000';
  static String get coaMoMoName => dotenv.env['COA_MOMO_NAME'] ?? 'Church On App Official';
  static String get treasuryId => dotenv.env['TREASURY_ID'] ?? '';
}

