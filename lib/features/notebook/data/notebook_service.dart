import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';
import 'note_model.dart';

class NotebookService {
  final SupabaseClient _client;

  NotebookService(this._client);

  Future<List<Note>> getNotes(String userId, {String category = 'general'}) async {
    final response = await _client
        .from('user_notes')
        .select()
        .eq('user_id', userId)
        .eq('category', category)
        .order('updated_at', ascending: false);
    
    return (response as List).map((e) => Note.fromMap(e)).toList();
  }

  Future<Note> createNote(String userId, String title, String content, {String? topic, String category = 'general'}) async {
    final response = await _client.from('user_notes').insert({
      'user_id': userId,
      'title': title,
      'content': content,
      'topic': topic,
      'category': category,
      'is_favorite': false,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    }).select().single();

    return Note.fromMap(response);
  }

  Future<void> updateNote(String noteId, Map<String, dynamic> updates) async {
    await _client.from('user_notes').update({
      ...updates,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', noteId);
  }

  Future<void> deleteNote(String noteId) async {
    await _client.from('user_notes').delete().eq('id', noteId);
  }

  Stream<List<Note>> streamNotes(String userId, {String category = 'general'}) {
    return _client
        .from('user_notes')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('updated_at', ascending: false)
        .map((data) => data
            .where((e) => e['category'] == category)
            .map((e) => Note.fromMap(e))
            .toList());
  }
}

final notebookServiceProvider = Provider((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return NotebookService(client);
});

final notesProvider = StreamProvider.family<List<Note>, String>((ref, userId) {
  return ref.watch(notebookServiceProvider).streamNotes(userId);
});
