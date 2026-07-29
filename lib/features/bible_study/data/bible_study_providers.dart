import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/services/supabase_service.dart';
import 'bible_study_service.dart';

final bibleStudyServiceProvider = Provider<BibleStudyService>((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return BibleStudyService(client);
});

final studiesProvider = FutureProvider.autoDispose.family<List<BibleStudy>, String>((ref, tenantId) async {
  final service = ref.watch(bibleStudyServiceProvider);
  return service.getStudies(tenantId);
});

final upcomingStudiesProvider = FutureProvider.autoDispose.family<List<BibleStudy>, String>((ref, tenantId) async {
  final service = ref.watch(bibleStudyServiceProvider);
  return service.getUpcomingStudies(tenantId);
});

final studiesStreamProvider = StreamProvider.autoDispose.family<List<BibleStudy>, String>((ref, tenantId) {
  final service = ref.watch(bibleStudyServiceProvider);
  return service.streamStudies(tenantId);
});

final attendanceProvider = FutureProvider.autoDispose.family<List<BibleStudyAttendance>, String>((ref, studyId) async {
  final service = ref.watch(bibleStudyServiceProvider);
  return service.getAttendance(studyId);
});
