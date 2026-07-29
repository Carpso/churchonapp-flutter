import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'emergency_contact.dart';

class EmergencyContactService {
  final SupabaseClient _client;

  EmergencyContactService(this._client);

  Future<List<EmergencyContact>> fetchEmergencyContacts(String? tenantId) async {
    try {
      dynamic query = _client
          .from('emergency_contacts')
          .select()
          .order('sort_order', ascending: true);

      if (tenantId != null) {
        query = query.or('tenant_id.is.null,tenant_id.eq.$tenantId');
      } else {
        query = query.is_('tenant_id', null);
      }

      final data = await query;
      final contacts = (data as List).map((e) => EmergencyContact.fromMap(e)).toList();

      if (contacts.isNotEmpty) return contacts;

      return _defaultContacts();
    } catch (e) {
      debugPrint('[EmergencyContactService] Fetch error: $e');
      return _defaultContacts();
    }
  }

  Future<void> addContact(EmergencyContact contact) async {
    await _client.from('emergency_contacts').insert(contact.toMap());
  }

  Future<void> updateContact(EmergencyContact contact) async {
    if (contact.id == null) return;
    await _client
        .from('emergency_contacts')
        .update(contact.toMap())
        .eq('id', contact.id!);
  }

  Future<void> deleteContact(String id) async {
    await _client.from('emergency_contacts').delete().eq('id', id);
  }

  List<EmergencyContact> _defaultContacts() {
    return [
      EmergencyContact(name: 'Police', phone: '911', icon: 'shield', category: 'emergency_service', sortOrder: 1),
      EmergencyContact(name: 'Ambulance', phone: '992', icon: 'plusCircle', category: 'emergency_service', sortOrder: 2),
      EmergencyContact(name: 'Fire', phone: '993', icon: 'flame', category: 'emergency_service', sortOrder: 3),
    ];
  }
}

final emergencyContactServiceProvider = Provider((ref) => EmergencyContactService(Supabase.instance.client));

