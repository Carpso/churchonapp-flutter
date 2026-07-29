
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:church_on_app/features/modules/jobs/data/jobs_service.dart';
import 'package:church_on_app/features/modules/jobs/data/job_model.dart';
import '../../../../test_mocks.dart';

void main() {
  late MockSupabaseClient mockClient;
  late MockAuth mockAuth;
  late MockUser mockUser;
  late MockQueryBuilder mockQuery;
  late MockFilterBuilder mockFilter;
  late MockSupabaseStreamBuilder mockStream;
  late JobsService service;

  setUp(() {
    mockClient = MockSupabaseClient();
    mockAuth = MockAuth();
    mockUser = MockUser();
    mockQuery = MockQueryBuilder();
    mockFilter = MockFilterBuilder();
    mockStream = MockSupabaseStreamBuilder();
    service = JobsService(mockClient);

    when(() => mockClient.auth).thenReturn(mockAuth);
    when(() => mockAuth.currentUser).thenReturn(mockUser);
    when(() => mockUser.id).thenReturn('user_1');
  });

  group('getJobs', () {
    test('returns jobs from supabase', () async {
      when(() => mockClient.from('jobs')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.order('created_at', ascending: false)).thenAnswer((_) => mockFilter);
      mockFilter.mockResult = [
        {
          'id': 'j1',
          'title': 'Developer',
          'company': 'Tech Co',
          'location': 'Lusaka',
          'type': 'Full-time',
          'description': 'Build software',
          'salary': 'K5000',
          'contact': 'hr@tech.co',
          'employer_id': 'emp1',
          'created_at': DateTime.now().toIso8601String(),
        },
      ];

      final jobs = await service.getJobs();
      expect(jobs.length, 1);
      expect(jobs.first.title, 'Developer');
    });

    test('returns empty list on empty response', () async {
      when(() => mockClient.from('jobs')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.order('created_at', ascending: false)).thenAnswer((_) => mockFilter);
      mockFilter.mockResult = [];

      final jobs = await service.getJobs();
      expect(jobs, isEmpty);
    });
  });

  group('postJob', () {
    test('inserts a job', () async {
      when(() => mockClient.from('jobs')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.insert(any())).thenAnswer((_) => mockFilter);

      final job = Job(
        id: 'j1',
        title: 'Developer',
        company: 'Tech Co',
        location: 'Lusaka',
        type: 'Full-time',
        description: 'Build software',
        contact: 'hr@tech.co',
        employerId: 'emp1',
        createdAt: DateTime.now(),
      );

      await service.postJob(job);
      verify(() => mockQuery.insert(any())).called(1);
    });

    test('inserts job with user id when authenticated', () async {
      when(() => mockClient.from('jobs')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.insert(any())).thenAnswer((_) => mockFilter);

      final job = Job(
        id: 'j2',
        title: 'Pastor',
        company: 'Church',
        location: 'Lusaka',
        type: 'Full-time',
        description: 'Lead congregation',
        contact: 'info@church.org',
        employerId: 'emp1',
        createdAt: DateTime.now(),
      );

      await service.postJob(job);
      verify(() => mockQuery.insert(any())).called(1);
    });
  });

  group('streamJobs', () {
    test('returns stream from supabase', () {
      when(() => mockClient.from('jobs')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.stream(primaryKey: ['id'])).thenAnswer((_) => mockStream);
      when(() => mockStream.order(any(), ascending: any(named: 'ascending'))).thenAnswer((_) => mockStream);
      mockStream.streamResult = Stream.value([]);

      final stream = service.streamJobs();
      expect(stream, isA<Stream<List<Job>>>());
    });
  });

  group('applyForJob', () {
    test('creates job application', () async {
      when(() => mockClient.from('job_applications')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.insert(any())).thenAnswer((_) => mockFilter);

      final application = JobApplication(
        id: 'a1',
        jobId: 'j1',
        applicantId: 'user_1',
        applicantName: 'Test User',
        status: 'pending',
        createdAt: DateTime.now(),
      );

      await service.applyForJob(application);
      verify(() => mockQuery.insert(any())).called(1);
    });
  });

  group('updateApplicationStatus', () {
    test('updates application status', () async {
      when(() => mockClient.from('job_applications')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.update({'status': 'accepted'})).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('id', 'a1')).thenAnswer((_) => mockFilter);

      await service.updateApplicationStatus('a1', 'accepted');
      verify(() => mockQuery.update({'status': 'accepted'})).called(1);
    });
  });

  group('streamMyJobPostings', () {
    test('returns empty stream when user is null', () async {
      when(() => mockAuth.currentUser).thenReturn(null);

      final stream = service.streamMyJobPostings();
      final jobs = await stream.first;
      expect(jobs, isEmpty);
    });
  });

  group('Job model', () {
    test('fromMap parses all fields', () {
      final map = {
        'id': 'j1',
        'title': 'Developer',
        'company': 'Tech Co',
        'location': 'Lusaka',
        'type': 'Full-time',
        'description': 'Build software',
        'salary': 'K5000',
        'contact': 'hr@tech.co',
        'employer_id': 'emp1',
        'created_at': DateTime.now().toIso8601String(),
      };
      final job = Job.fromMap(map);
      expect(job.title, 'Developer');
      expect(job.company, 'Tech Co');
    });
  });

  group('JobApplication model', () {
    test('fromMap parses all fields', () {
      final map = {
        'id': 'a1',
        'job_id': 'j1',
        'applicant_id': 'u1',
        'applicant_name': 'Test',
        'status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
      };
      final app = JobApplication.fromMap(map);
      expect(app.jobId, 'j1');
      expect(app.status, 'pending');
    });

    test('toMap excludes id and createdAt', () {
      final app = JobApplication(
        id: 'a1',
        jobId: 'j1',
        applicantId: 'u1',
        applicantName: 'Test',
        status: 'pending',
        createdAt: DateTime.now(),
      );
      final map = app.toMap();
      expect(map.containsKey('id'), false);
      expect(map.containsKey('created_at'), false);
    });
  });
}
