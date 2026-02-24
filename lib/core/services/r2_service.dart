import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/supabase_service.dart';
import '../config/env.dart';

class R2Service {
  // These are often handled by Supabase Edge Functions for security,
  // but if needed client-side, we use presigned URLs.
  
  static String get publicDomain => Env.r2PublicDomain;

  final SupabaseClient _client;
  R2Service(this._client);

  Future<String?> uploadFile(File file, String path) async {
    try {
      // 1. Request signed URL from Supabase Edge Function
      final response = await _client.functions.invoke('r2-sign', body: {
        'filename': path.split('/').last,
        'contentType': _getContentType(file.path),
        'folder': path.split('/').first,
      });

      if (response.status == 200) {
        final signedUrl = response.data['signedUrl'];
        final publicUrl = response.data['publicUrl'];

        // 2. Upload directly to R2
        final uploadResponse = await http.put(
          Uri.parse(signedUrl),
          body: await file.readAsBytes(),
          headers: {'Content-Type': _getContentType(file.path)},
        );

        if (uploadResponse.statusCode == 200) {
          return publicUrl;
        }
      }
      return null;
    } catch (e) {
      print("R2 Upload Error: $e");
      return null;
    }
  }

  String _getContentType(String path) {
    if (path.endsWith('.jpg') || path.endsWith('.jpeg')) return 'image/jpeg';
    if (path.endsWith('.png')) return 'image/png';
    if (path.endsWith('.mp4')) return 'video/mp4';
    if (path.endsWith('.pdf')) return 'application/pdf';
    return 'application/octet-stream';
  }
}

final r2ServiceProvider = Provider((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return R2Service(client);
});
