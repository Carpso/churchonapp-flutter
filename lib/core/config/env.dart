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
  static String get lipilaShortCode => dotenv.env['LIPILA_SHORT_CODE'] ?? '68907';
  static String get lipilaApiKey => (dotenv.env['LIPILA_API_KEY'] ?? '').trim();
  static String get googleWebClientId => dotenv.env['GOOGLE_WEB_CLIENT_ID'] ?? '';
  static String get huggingFaceToken => dotenv.env['HUGGINGFACE_TOKEN'] ?? '';

  static String get lipilaWebhookUrl =>
      dotenv.env['LIPILA_WEBHOOK_URL'] ??
      'https://supabase.churchonapp.com/functions/v1/lipila-webhook';
  static String get lipilaPayoutWebhookUrl =>
      dotenv.env['LIPILA_PAYOUT_WEBHOOK_URL'] ??
      'https://supabase.churchonapp.com/functions/v1/lipila-webhook';
}

