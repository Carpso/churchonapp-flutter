import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WhatsAppService {
  final SupabaseClient _client;

  WhatsAppService(this._client);

  Future<Map<String, dynamic>?> getConfig() async {
    try {
      return await _client
          .from('whatsapp_config')
          .select()
          .eq('is_enabled', true)
          .maybeSingle();
    } catch (e) {
      debugPrint('WhatsAppService: getConfig error: $e');
      return null;
    }
  }

  Future<bool> isEnabled() async {
    final config = await getConfig();
    return config?['is_enabled'] == true;
  }

  Future<void> updateConfig({
    bool? isEnabled,
    String? phoneNumberId,
    String? accessToken,
    String? businessAccountId,
    String? verifyToken,
    String? webhookUrl,
    String? appId,
    String? whatsappNumber,
    String? description,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final updates = <String, dynamic>{
      'last_updated': DateTime.now().toIso8601String(),
      'updated_by': user.id,
    };
    if (isEnabled != null) updates['is_enabled'] = isEnabled;
    if (phoneNumberId != null) updates['phone_number_id'] = phoneNumberId;
    if (accessToken != null) updates['access_token'] = accessToken;
    if (businessAccountId != null) updates['business_account_id'] = businessAccountId;
    if (verifyToken != null) updates['verify_token'] = verifyToken;
    if (webhookUrl != null) updates['webhook_url'] = webhookUrl;
    if (appId != null) updates['app_id'] = appId;
    if (whatsappNumber != null) updates['whatsapp_number'] = whatsappNumber;
    if (description != null) updates['description'] = description;

    await _client.from('whatsapp_config').upsert(updates);
  }

  Future<bool> sendTemplateMessage({
    required String toPhoneNumber,
    required String templateName,
    Map<String, dynamic>? variables,
    String languageCode = 'en',
  }) async {
    final config = await getConfig();
    if (config == null || config['is_enabled'] != true) {
      debugPrint('WhatsAppService: WhatsApp not enabled');
      return false;
    }

    try {
      final result = await _client.functions.invoke('whatsapp-send', body: {
        'to': toPhoneNumber,
        'template': templateName,
        'language': languageCode,
        'variables': variables,
      });

      if (result.data != null && result.data['success'] == true) {
        debugPrint('WhatsAppService: Template message sent to $toPhoneNumber');
        return true;
      }
      debugPrint('WhatsAppService: Send failed: ${result.data}');
      return false;
    } catch (e) {
      debugPrint('WhatsAppService: Send error: $e');
      return false;
    }
  }

  Future<bool> sendTextMessage({
    required String toPhoneNumber,
    required String message,
  }) async {
    final config = await getConfig();
    if (config == null || config['is_enabled'] != true) return false;

    try {
      final result = await _client.functions.invoke('whatsapp-send', body: {
        'to': toPhoneNumber,
        'type': 'text',
        'message': message,
      });

      return result.data != null && result.data['success'] == true;
    } catch (e) {
      debugPrint('WhatsAppService: Text send error: $e');
      return false;
    }
  }

  Future<bool> sendPaymentReceipt({
    required String toPhoneNumber,
    required String userName,
    required String amount,
    required String paymentType,
    required String reference,
  }) async {
    return sendTemplateMessage(
      toPhoneNumber: toPhoneNumber,
      templateName: 'payment_receipt',
      variables: {
        '1': userName,
        '2': amount,
        '3': paymentType,
        '4': reference,
      },
    );
  }

  Future<bool> sendEventReminder({
    required String toPhoneNumber,
    required String userName,
    required String eventName,
    required String eventDate,
  }) async {
    return sendTemplateMessage(
      toPhoneNumber: toPhoneNumber,
      templateName: 'event_reminder',
      variables: {
        '1': userName,
        '2': eventName,
        '3': eventDate,
      },
    );
  }

  Future<bool> sendWelcomeMessage({
    required String toPhoneNumber,
    required String userName,
    required String churchName,
  }) async {
    return sendTemplateMessage(
      toPhoneNumber: toPhoneNumber,
      templateName: 'welcome_message',
      variables: {
        '1': userName,
        '2': churchName,
      },
    );
  }

  Future<List<Map<String, dynamic>>> getTemplates() async {
    try {
      final result = await _client
          .from('whatsapp_templates')
          .select('id, template_name, language_code, category, is_active, created_at')
          .order('created_at', ascending: false);
      return (result as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('WhatsAppService: getTemplates error: $e');
      return [];
    }
  }

  Future<void> saveTemplate({
    required String templateName,
    required String category,
    required List<Map<String, dynamic>> components,
    String languageCode = 'en',
    bool isActive = true,
  }) async {
    await _client.from('whatsapp_templates').upsert({
      'template_name': templateName,
      'language_code': languageCode,
      'category': category,
      'components': components,
      'is_active': isActive,
    });
  }
}

final whatsappServiceProvider = Provider<WhatsAppService>((ref) {
  return WhatsAppService(Supabase.instance.client);
});
