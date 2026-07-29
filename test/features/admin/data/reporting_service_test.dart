import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:church_on_app/features/admin/data/reporting_service.dart';
import '../../../test_mocks.dart';

void main() {
  late MockSupabaseClient mockClient;
  late MockQueryBuilder mockQuery;
  late MockFilterBuilder mockFilter;
  late ReportingService service;

  setUp(() {
    mockClient = MockSupabaseClient();
    mockQuery = MockQueryBuilder();
    mockFilter = MockFilterBuilder();
    service = ReportingService(mockClient);
  });

  group('submitReport', () {
    test('inserts service report', () async {
      when(() => mockClient.from('service_reports')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.insert(any())).thenAnswer((_) => mockFilter);

      await service.submitReport(ServiceReport(
        id: 'r1',
        tenantId: 'tenant_1',
        title: 'Sunday Service',
        description: 'Morning worship service',
        attendance: 100,
        offering: 5000.0,
        testimony: 'Blessed service',
        date: DateTime.now(),
        reporterId: 'user_1',
      ));
    });

    test('insert uses correct collection', () async {
      when(() => mockClient.from('service_reports')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.insert(any())).thenAnswer((_) => mockFilter);

      await service.submitReport(ServiceReport(
        id: 'r2',
        tenantId: 'tenant_2',
        title: 'Evening Service',
        description: 'Evening worship',
        attendance: 50,
        offering: 3000.0,
        testimony: 'God is faithful',
        date: DateTime.now(),
        reporterId: 'user_2',
      ));
      verify(() => mockQuery.insert(any())).called(1);
    });
  });
}
