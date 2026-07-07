import 'package:church_on_app/core/services/supabase_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ChurchLead {
  final String id;
  final String? referredByUserId;
  final String? referrerName;
  final String? referrerPhone;
  final String pastorName;
  final String pastorPhone;
  final String? churchName;
  final String? churchLocation;
  final String? notes;
  final String status;
  final DateTime? contactedAt;
  final String? registeredChurchId;
  final String? assignedTo;
  final DateTime createdAt;

  ChurchLead({
    required this.id,
    this.referredByUserId,
    this.referrerName,
    this.referrerPhone,
    required this.pastorName,
    required this.pastorPhone,
    this.churchName,
    this.churchLocation,
    this.notes,
    this.status = 'new',
    this.contactedAt,
    this.registeredChurchId,
    this.assignedTo,
    required this.createdAt,
  });

  factory ChurchLead.fromMap(Map<String, dynamic> map) {
    return ChurchLead(
      id: map['id'] as String,
      referredByUserId: map['referred_by_user_id'] as String?,
      referrerName: map['referrer_name'] as String?,
      referrerPhone: map['referrer_phone'] as String?,
      pastorName: map['pastor_name'] as String,
      pastorPhone: map['pastor_phone'] as String,
      churchName: map['church_name'] as String?,
      churchLocation: map['church_location'] as String?,
      notes: map['notes'] as String?,
      status: map['status'] as String? ?? 'new',
      contactedAt: map['contacted_at'] != null ? DateTime.parse(map['contacted_at'] as String) : null,
      registeredChurchId: map['registered_church_id'] as String?,
      assignedTo: map['assigned_to'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

class ChurchLeadService {
  final SupabaseService _supabase;

  ChurchLeadService(this._supabase);

  Future<List<ChurchLead>> getMyLeads() async {
    final userId = _supabase.client.auth.currentUser!.id;
    final result = await _supabase.client
        .from('church_leads')
        .select('*')
        .eq('referred_by_user_id', userId)
        .order('created_at', ascending: false);
    return (result as List).map((e) => ChurchLead.fromMap(e)).toList();
  }

  Future<List<ChurchLead>> getAllLeads() async {
    final result = await _supabase.client
        .from('church_leads')
        .select('*')
        .order('created_at', ascending: false);
    return (result as List).map((e) => ChurchLead.fromMap(e)).toList();
  }

  Future<void> submitLead({
    required String pastorName,
    required String pastorPhone,
    String? churchName,
    String? churchLocation,
    String? notes,
  }) async {
    final userId = _supabase.client.auth.currentUser!.id;
    final profile = await _supabase.client
        .from('profiles')
        .select('full_name, phone')
        .eq('id', userId)
        .single();
    await _supabase.client.from('church_leads').insert({
      'referred_by_user_id': userId,
      'referrer_name': profile['full_name'],
      'referrer_phone': profile['phone'],
      'pastor_name': pastorName,
      'pastor_phone': pastorPhone,
      'church_name': churchName,
      'church_location': churchLocation,
      'notes': notes,
    });
  }

  Future<void> updateLeadStatus(String leadId, String status) async {
    final updates = <String, dynamic>{'status': status};
    if (status == 'contacted') {
      updates['contacted_at'] = DateTime.now().toUtc().toIso8601String();
    }
    await _supabase.client.from('church_leads').update(updates).eq('id', leadId);
  }
}

final churchLeadServiceProvider = Provider<ChurchLeadService>((ref) {
  final supabase = ref.read(supabaseServiceProvider);
  return ChurchLeadService(supabase);
});

final myChurchLeadsProvider = FutureProvider<List<ChurchLead>>((ref) async {
  return ref.read(churchLeadServiceProvider).getMyLeads();
});

final allChurchLeadsProvider = FutureProvider<List<ChurchLead>>((ref) async {
  return ref.read(churchLeadServiceProvider).getAllLeads();
});
