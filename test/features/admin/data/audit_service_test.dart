import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:church_on_app/features/admin/data/audit_service.dart';
import '../../../test_mocks.dart';

void main() {
  late MockSupabaseClient mockClient;
  late MockAuth mockAuth;
  late MockUser mockUser;
  late MockQueryBuilder mockQuery;
  late MockFilterBuilder mockFilter;
  // ignore: unused_local_variable
  late MockMaybeSingleBuilder mockMaybeSingle;
  late AuditService service;

  setUp(() {
    mockClient = MockSupabaseClient();
    mockAuth = MockAuth();
    mockUser = MockUser();
    mockQuery = MockQueryBuilder();
    mockFilter = MockFilterBuilder();
    mockMaybeSingle = MockMaybeSingleBuilder();
    service = AuditService(mockClient);

    when(() => mockClient.auth).thenReturn(mockAuth);
    when(() => mockAuth.currentUser).thenReturn(mockUser);
    when(() => mockUser.id).thenReturn('admin_1');
    when(() => mockUser.email).thenReturn('admin@church.org');
  });

  group('logAction', () {
    test('inserts audit log entry', () async {
      when(() => mockClient.from('admin_audit_log')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.insert(any())).thenAnswer((_) => mockFilter);

      await service.logAction(
        action: 'delete_post',
        entityType: 'social_post',
        entityId: 'post_1',
        details: {'reason': 'spam'},
      );
      verify(() => mockQuery.insert(any(that: allOf(
        containsPair('admin_id', 'admin_1'),
        containsPair('action', 'delete_post'),
        containsPair('entity_type', 'social_post'),
        containsPair('entity_id', 'post_1'),
      )))).called(1);
    });

    test('does nothing when user is null', () async {
      when(() => mockAuth.currentUser).thenReturn(null);

      await service.logAction(action: 'test', entityType: 'test');
    });
  });

  group('getRecentAuditLogs', () {
    test('returns audit logs with profile join', () async {
      when(() => mockClient.from('admin_audit_log')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select(any())).thenAnswer((_) => mockFilter);
      when(() => mockFilter.order('created_at', ascending: false)).thenAnswer((_) => mockFilter);
      when(() => mockFilter.limit(50)).thenAnswer((_) => mockFilter);
      mockFilter.mockResult = [
        {'id': 'log_1', 'action': 'delete_post', 'admin_id': 'admin_1'},
      ];

      final logs = await service.getRecentAuditLogs();
      expect(logs.length, 1);
      expect(logs.first['action'], 'delete_post');
    });
  });

  group('logRoleChange', () {
    test('logs role change action', () async {
      when(() => mockClient.from('admin_audit_log')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.insert(any())).thenAnswer((_) => mockFilter);

      await service.logRoleChange(targetUserId: 'user_1', oldRole: 'member', newRole: 'pastor');
      verify(() => mockQuery.insert(any(that: allOf(
        containsPair('action', 'role_change'),
        containsPair('entity_id', 'user_1'),
      )))).called(1);
    });
  });

  group('logPaymentAction', () {
    test('logs payment action', () async {
      when(() => mockClient.from('admin_audit_log')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.insert(any())).thenAnswer((_) => mockFilter);

      await service.logPaymentAction(action: 'process_payout', paymentId: 'pay_1', amount: 500.0);
      verify(() => mockQuery.insert(any(that: containsPair('action', 'process_payout')))).called(1);
    });
  });
}
