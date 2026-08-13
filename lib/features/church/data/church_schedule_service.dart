import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'church_service_time.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/tenant_service.dart';

class ChurchScheduleService {
  final SupabaseClient _client;
  ChurchScheduleService(this._client);

  Future<List<ChurchServiceTime>> fetchSchedule(String tenantId) async {
    final result = await _client
        .from('churches')
        .select('service_times')
        .eq('tenant_id', tenantId)
        .maybeSingle();
    return parseServiceTimes(result?['service_times']);
  }

  Future<void> saveSchedule(String tenantId, List<ChurchServiceTime> schedule) async {
    final list = schedule.map((s) => s.toMap()).toList();
    await _client
        .from('churches')
        .update({'service_times': list})
        .eq('tenant_id', tenantId);
  }
}

final churchScheduleServiceProvider = Provider((ref) {
  return ChurchScheduleService(ref.watch(supabaseServiceProvider).client);
});

final churchScheduleProvider = FutureProvider.family<List<ChurchServiceTime>, String>(
  (ref, tenantId) async {
    return ref.watch(churchScheduleServiceProvider).fetchSchedule(tenantId);
  },
);

/// Returns today's services for the given tenant, sorted by start time.
final todaysChurchServicesProvider = FutureProvider.family<List<ChurchServiceTime>, String>(
  (ref, tenantId) async {
    final all = await ref.watch(churchScheduleProvider(tenantId).future);
    final now = DateTime.now();
    final today = now.weekday; // Dart: 1=Mon...7=Sun
    return all
        .where((s) => s.dayOfWeek == today)
        .toList()
      ..sort((a, b) {
        final aMins = a.startTime.hour * 60 + a.startTime.minute;
        final bMins = b.startTime.hour * 60 + b.startTime.minute;
        return aMins.compareTo(bMins);
      });
  },
);

/// Provider that exposes the current tenant's service schedule.
final currentTenantScheduleProvider = FutureProvider<List<ChurchServiceTime>>((ref) async {
  final tenant = ref.watch(currentTenantProvider);
  if (tenant == null) return [];
  return ref.watch(churchScheduleProvider(tenant.id).future);
});
