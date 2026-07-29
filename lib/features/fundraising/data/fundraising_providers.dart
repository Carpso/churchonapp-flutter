import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/services/supabase_service.dart';
import 'package:church_on_app/core/providers/auth_provider.dart';
import 'fundraising_models.dart';
import 'fundraising_service.dart';
import 'group_contribution_service.dart';

final fundraisingServiceProvider = Provider<FundraisingService>((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return FundraisingService(client);
});

final myChurchVenturesProvider = StreamProvider.autoDispose.family<List<FundraisingVenture>, String>((ref, tenantId) {
  final authState = ref.watch(authProvider);
  final userId = authState.user?.id ?? '';
  return ref.watch(fundraisingServiceProvider).getVenturesStream(tenantId, userId);
});

final invitedVenturesProvider = StreamProvider.autoDispose.family<List<FundraisingVenture>, String>((ref, tenantId) {
  return ref.watch(fundraisingServiceProvider).getInvitedVenturesStream(tenantId);
});

final ventureDetailProvider = FutureProvider.autoDispose.family<FundraisingVenture, String>((ref, id) async {
  return await ref.watch(fundraisingServiceProvider).getVenture(id);
});

final contributionsProvider = StreamProvider.autoDispose.family<List<FundraisingContribution>, String>((ref, ventureId) {
  return ref.watch(fundraisingServiceProvider).getContributionsStream(ventureId);
});

final groupContributionServiceProvider = Provider<GroupContributionService>((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return GroupContributionService(client);
});

final groupContributionsProvider = StreamProvider.autoDispose.family<List<GroupContribution>, String>((ref, tenantId) {
  final service = ref.watch(groupContributionServiceProvider);
  return service.getGroupsStream(tenantId);
});

final groupMembersProvider = StreamProvider.autoDispose.family<List<GroupContributionMember>, String>((ref, groupId) {
  final service = ref.watch(groupContributionServiceProvider);
  return service.getMembersStream(groupId);
});

final groupPaymentsProvider = StreamProvider.autoDispose.family<List<GroupContributionPayment>, String>((ref, groupId) {
  final service = ref.watch(groupContributionServiceProvider);
  return service.getPaymentsStream(groupId);
});

final groupDetailProvider = FutureProvider.autoDispose.family<GroupContribution?, String>((ref, groupId) {
  final service = ref.watch(groupContributionServiceProvider);
  return service.getGroup(groupId);
});
