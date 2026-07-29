import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'tithe_service.dart';
import 'tithe_models.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/services/code_generator_service.dart';

final titheServiceProvider = Provider<TitheService>((ref) {
  final client = Supabase.instance.client;
  return TitheService(client, CodeGeneratorService(client));
});

final titheCardProvider = FutureProvider.autoDispose.family<TitheCard?, String>((ref, tenantId) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return null;
  final service = ref.watch(titheServiceProvider);
  return service.getTitheCard(tenantId, user.id);
});

final titheHistoryProvider = FutureProvider.autoDispose.family<List<TitheRecord>, String>((ref, userId) async {
  final service = ref.watch(titheServiceProvider);
  return service.getTitheHistory(userId);
});

final currentTitheCardProvider = FutureProvider.autoDispose<TitheCard?>((ref) async {
  final tenant = ref.watch(currentTenantProvider);
  if (tenant == null) return null;
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return null;
  final service = ref.watch(titheServiceProvider);
  return service.getTitheCard(tenant.id, user.id);
});