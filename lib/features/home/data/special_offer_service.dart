import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A platform-wide promotional offer shown in the home screen carousel.
class SpecialOffer {
  final String id;
  final String title;
  final String? subtitle;
  final String? badge;
  final String? imageUrl;
  final String linkType; // marketplace | web | none
  final String? linkTarget;
  final bool isActive;
  final bool promoted;

  const SpecialOffer({
    required this.id,
    required this.title,
    this.subtitle,
    this.badge,
    this.imageUrl,
    this.linkType = 'marketplace',
    this.linkTarget,
    this.isActive = true,
    this.promoted = false,
  });

  factory SpecialOffer.fromMap(Map<String, dynamic> map) => SpecialOffer(
        id: (map['id'] ?? '').toString(),
        title: (map['title'] ?? '').toString(),
        subtitle: map['subtitle']?.toString(),
        badge: map['badge']?.toString(),
        imageUrl: map['image_url']?.toString(),
        linkType: map['link_type']?.toString() ?? 'marketplace',
        linkTarget: map['link_target']?.toString(),
        isActive: map['is_active'] == true,
        promoted: map['promoted'] == true,
      );
}

/// Active offers for the home carousel — promoted offers first, newest first.
final activeSpecialOffersProvider =
    FutureProvider.autoDispose<List<SpecialOffer>>((ref) async {
  final client = Supabase.instance.client;
  try {
    final res = await client
        .from('special_offers')
        .select()
        .eq('is_active', true)
        .order('promoted', ascending: false)
        .order('created_at', ascending: false)
        .limit(6);
    return (res as List)
        .map((e) =>
            SpecialOffer.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  } catch (e) {
    debugPrint('Error loading special offers: $e');
    return const [];
  }
});

/// Whether the current user may manage special offers
/// (superadmin / coa_employee / employee).
final canManageSpecialOffersProvider =
    FutureProvider.autoDispose<bool>((ref) async {
  final client = Supabase.instance.client;
  try {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return false;
    final profile = await client
        .from('profiles')
        .select('role')
        .eq('id', userId)
        .maybeSingle();
    final role = profile?['role']?.toString() ?? 'member';
    return role == 'superadmin' ||
        role == 'coa_employee' ||
        role == 'employee';
  } catch (_) {
    return false;
  }
});
