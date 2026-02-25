import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/services/supabase_service.dart';

class MeetingNote {
  final String id;
  final String meetingId;
  final String authorId;
  final String content;
  final bool isPrivate;
  final DateTime createdAt;

  MeetingNote({
    required this.id,
    required this.meetingId,
    required this.authorId,
    required this.content,
    this.isPrivate = false,
    required this.createdAt,
  });

  factory MeetingNote.fromMap(Map<String, dynamic> map) {
    return MeetingNote(
      id: map['id'],
      meetingId: map['meeting_id'],
      authorId: map['author_id'],
      content: map['content'],
      isPrivate: map['is_private'] ?? false,
      createdAt: DateTime.parse(map['created_at']),
    );
  }
}

class MeetingVote {
  final String meetingId;
  final String voterId;
  final String option;

  MeetingVote({required this.meetingId, required this.voterId, required this.option});

  factory MeetingVote.fromMap(Map<String, dynamic> map) {
    return MeetingVote(
      meetingId: map['meeting_id'],
      voterId: map['voter_id'],
      option: map['option_selected'],
    );
  }
}

class MeetingService {
  final SupabaseClient _client;
  MeetingService(this._client);

  Future<void> saveNote(String meetingId, String content, {bool isPrivate = false}) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    await _client.from('meeting_notes').insert({
      'meeting_id': meetingId,
      'author_id': user.id,
      'content': content,
      'is_private': isPrivate,
    });
  }

  Stream<List<MeetingNote>> streamNotes(String meetingId) {
    return _client
        .from('meeting_notes')
        .stream(primaryKey: ['id'])
        .eq('meeting_id', meetingId)
        .order('created_at', ascending: false)
        .map((data) => data.map((e) => MeetingNote.fromMap(e)).toList());
  }

  Future<void> castVote(String meetingId, String option) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    await _client.from('meeting_votes').upsert({
      'meeting_id': meetingId,
      'voter_id': user.id,
      'option_selected': option,
    });
  }

  Stream<Map<String, int>> streamVoteResults(String meetingId) {
    return _client
        .from('meeting_votes')
        .stream(primaryKey: ['id'])
        .eq('meeting_id', meetingId)
        .map((data) {
          final results = <String, int>{};
          for (var item in data) {
            final opt = item['option_selected'] as String;
            results[opt] = (results[opt] ?? 0) + 1;
          }
          return results;
        });
  }
}

final meetingServiceProvider = Provider((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return MeetingService(client);
});

final meetingNotesProvider = StreamProvider.family<List<MeetingNote>, String>((ref, meetingId) {
  return ref.watch(meetingServiceProvider).streamNotes(meetingId);
});

final meetingVotesProvider = StreamProvider.family<Map<String, int>, String>((ref, meetingId) {
  return ref.watch(meetingServiceProvider).streamVoteResults(meetingId);
});
