import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'discipleship_models.dart';
import 'discipleship_service.dart';

final mentorsProvider = FutureProvider<List<Mentor>>((ref) async {
  final service = ref.watch(discipleshipServiceProvider);
  final raw = await service.getMentors();
  return raw.map((m) => Mentor.fromMap(m)).toList();
});

final myDisciplesProvider = FutureProvider.family<List<Disciple>, String>((ref, mentorId) async {
  final service = ref.watch(discipleshipServiceProvider);
  final raw = await service.getMentees(mentorId);
  return raw.map((m) => Disciple.fromMap(m)).toList();
});

final milestonesProvider = FutureProvider.family<List<DiscipleshipMilestone>, String>((ref, discipleId) async {
  final service = ref.watch(discipleshipServiceProvider);
  final raw = await service.getMilestones(discipleId);
  return raw.map((m) => DiscipleshipMilestone.fromMap(m)).toList();
});

final discipleshipPlansProvider = FutureProvider<List<DiscipleshipPlan>>((ref) async {
  return DiscipleshipPlan.defaultPlans
      .map((p) => DiscipleshipPlan.fromMap({...p, 'id': ''}))
      .toList();
});

final completedMilestonesProvider = Provider.family<int, List<DiscipleshipMilestone>>((ref, milestones) {
  return milestones.where((m) => m.isCompleted).length;
});
