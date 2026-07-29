import 'package:flutter_test/flutter_test.dart';

import 'package:church_on_app/core/providers/stats_provider.dart';
import 'package:church_on_app/features/admin/data/admin_service.dart';
import 'package:mocktail/mocktail.dart';

class MockAdminService extends Mock implements AdminService {}

void main() {
  /* late MockAdminService mockAdminService;

  setUp(() {
    mockAdminService = MockAdminService();
  }); */

  /* test('adminStatsProvider fetches stats correctly', () async {
    when(() => mockAdminService.getMembersStream(tenantId: any(named: 'tenantId')))
        .thenAnswer((_) => Stream.value([]));
    when(() => mockAdminService.getTotalRidesCount(tenantId: any(named: 'tenantId')))
        .thenAnswer((_) async => 10);
    when(() => mockAdminService.getPendingDeliveriesCount(tenantId: any(named: 'tenantId')))
        .thenAnswer((_) async => 5);
    when(() => mockAdminService.getActiveCouriersCount(tenantId: any(named: 'tenantId')))
        .thenAnswer((_) async => 3);
    when(() => mockAdminService.getMonthlyFinancialStats())
        .thenAnswer((_) async => {'total': 50000.0, 'rides': 20000.0, 'deliveries': 10000.0, 'tithes': 20000.0});

    final container = ProviderContainer(
      overrides: [
        adminServiceProvider.overrideWith((ref) => mockAdminService),
      ],
    );

    final stats = await container.read(adminStatsProvider.future);
    expect(stats.totalMembers, 0);
    expect(stats.growthRate, '0%');
    expect(stats.recentGiving, 'K 50000');
    expect(stats.totalMissions, 10);
    expect(stats.pendingCargo, 5);
    expect(stats.activeCouriers, 3);
    container.dispose();
  }); */

  /* test('adminStatsProvider handles empty response', () async {
    when(() => mockAdminService.getMembersStream(tenantId: any(named: 'tenantId')))
        .thenAnswer((_) => Stream.value([]));
    when(() => mockAdminService.getTotalRidesCount(tenantId: any(named: 'tenantId')))
        .thenAnswer((_) async => 0);
    when(() => mockAdminService.getPendingDeliveriesCount(tenantId: any(named: 'tenantId')))
        .thenAnswer((_) async => 0);
    when(() => mockAdminService.getActiveCouriersCount(tenantId: any(named: 'tenantId')))
        .thenAnswer((_) async => 0);
    when(() => mockAdminService.getMonthlyFinancialStats())
        .thenAnswer((_) async => {'total': 0.0, 'rides': 0.0, 'deliveries': 0.0, 'tithes': 0.0});

    final container = ProviderContainer(
      overrides: [
        adminServiceProvider.overrideWith((ref) => mockAdminService),
      ],
    );

    final stats = await container.read(adminStatsProvider.future);
    expect(stats.totalMembers, 0);
    expect(stats.growthRate, '0%');
    container.dispose();
  }); */

  test('AdminStats has correct structure', () {
    final stats = AdminStats(
      totalMembers: 100,
      growthRate: '+10%',
      recentGiving: 'K 10000',
      liveViewers: '500',
      totalMissions: 20,
      pendingCargo: 5,
      activeCouriers: 3,
    );
    expect(stats.totalMembers, 100);
    expect(stats.totalMissions, 20);
    expect(stats.activeCouriers, 3);
  });
}
