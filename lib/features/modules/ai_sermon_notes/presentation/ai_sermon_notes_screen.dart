import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/widgets/premium_toast.dart';

/// AI Sermon Notes service
class SermonNotesService {
  final SupabaseClient _client;

  SermonNotesService(this._client);

  /// Get sermon notes for a sermon
  Future<List<Map<String, dynamic>>> getSermonNotes(String sermonId) async {
    final result = await _client
        .from('sermon_notes')
        .select('*, profiles!author_id(full_name, avatar_url)')
        .eq('sermon_id', sermonId)
        .order('created_at');

    return List<Map<String, dynamic>>.from(result);
  }

  /// Generate AI summary for a sermon using Kael AI (or Gemini fallback)
  Future<Map<String, dynamic>> generateAISummary({
    required String sermonId,
    required String title,
    required String content,
    String? transcript,
  }) async {
    final textToSummarize = (transcript != null && transcript.trim().isNotEmpty) ? transcript : content;
    final promptText = "Please summarize this sermon titled '$title'. Extract: 1) Key Summary, 2) 3 Main Takeaways, 3) 2 Application Steps, and 4) 3 Study Questions.\n\nContent:\n$textToSummarize";

    // 1. Try Kael AI Edge Function (Hugging Face Open Source / Kael model)
    try {
      final result = await _client.functions.invoke('kael-ai', body: {
        'action': 'summary',
        'prompt': promptText,
      });
      final data = result.data as Map<String, dynamic>?;
      if (data != null && data['response'] != null && (data['response'] as String).isNotEmpty) {
        final respText = data['response'] as String;
        return {
          'summary': respText,
          'key_takeaways': ['Key points detailed in AI summary above.'],
          'action_steps': ['Reflect on the scripture readings.'],
          'study_questions': ['How can you apply this sermon to your life this week?'],
        };
      }
    } catch (e) {
      debugPrint('Kael AI summary invoke failed, falling back to dedicated function/Gemini: $e');
    }

    // 2. Try dedicated Edge Function if present
    try {
      final result = await _client.functions.invoke('ai-sermon-notes', body: {
        'sermon_id': sermonId,
        'title': title,
        'content': content,
        'transcript': transcript,
      });

      if (result.data != null) {
        return result.data as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('ai-sermon-notes function error: $e');
    }

    // 3. Structured fallback response
    return {
      'summary': "Summary for '$title': $textToSummarize",
      'key_takeaways': ['Walk in faith and love', 'Stay rooted in the Word', 'Serve the Lord with gladness'],
      'action_steps': ['Pray daily', 'Apply the sermon message in your community'],
      'study_questions': ['What stood out to you most in this message?'],
    };
  }

  /// Save a sermon note
  Future<Map<String, dynamic>> saveNote({
    required String sermonId,
    required String content,
    String? title,
    bool isAiGenerated = false,
    String? aiPrompt,
  }) async {
    final userId = _client.auth.currentUser?.id;

    final result = await _client
        .from('sermon_notes')
        .insert({
          'sermon_id': sermonId,
          'author_id': userId,
          'content': content,
          'title': title,
          'is_ai_generated': isAiGenerated,
          'ai_prompt': aiPrompt,
        })
        .select()
        .single();

    return result;
  }

  /// Update a sermon note
  Future<void> updateNote(String noteId, String content) async {
    await _client
        .from('sermon_notes')
        .update({'content': content, 'updated_at': DateTime.now().toIso8601String()})
        .eq('id', noteId);
  }

  /// Delete a sermon note
  Future<void> deleteNote(String noteId) async {
    await _client.from('sermon_notes').delete().eq('id', noteId);
  }

  /// Generate study prompts from sermon content
  Future<List<String>> generateStudyPrompts({
    required String title,
    required String content,
  }) async {
    final result = await _client.functions.invoke('ai-sermon-study-prompts', body: {
      'title': title,
      'content': content,
    });

    if (result.data == null) return [];

    final data = result.data as Map<String, dynamic>;
    return List<String>.from(data['prompts'] ?? []);
  }

  /// Get study prompts for a sermon
  Future<List<Map<String, dynamic>>> getStudyPrompts(String sermonId) async {
    final result = await _client
        .from('sermon_study_prompts')
        .select()
        .eq('sermon_id', sermonId)
        .order('created_at');

    return List<Map<String, dynamic>>.from(result);
  }

  /// Save study prompts
  Future<void> saveStudyPrompts({
    required String sermonId,
    required List<String> prompts,
  }) async {
    // Delete existing prompts
    await _client.from('sermon_study_prompts').delete().eq('sermon_id', sermonId);

    // Insert new prompts
    final data = prompts.map((p) => {
      'sermon_id': sermonId,
      'prompt': p,
    }).toList();

    await _client.from('sermon_study_prompts').insert(data);
  }
}

final sermonNotesServiceProvider = Provider<SermonNotesService>((ref) {
  return SermonNotesService(Supabase.instance.client);
});

/// AI Sermon Notes screen
class AISermonNotesScreen extends ConsumerStatefulWidget {
  final String sermonId;
  final String sermonTitle;
  final String? sermonContent;

  const AISermonNotesScreen({
    super.key,
    required this.sermonId,
    required this.sermonTitle,
    this.sermonContent,
  });

  @override
  ConsumerState<AISermonNotesScreen> createState() => _AISermonNotesScreenState();
}

class _AISermonNotesScreenState extends ConsumerState<AISermonNotesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _noteController = TextEditingController();
  List<Map<String, dynamic>> _notes = [];
  List<String> _studyPrompts = [];
  String? _aiSummary;
  bool _loading = true;
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    final service = ref.read(sermonNotesServiceProvider);

    try {
      final notes = await service.getSermonNotes(widget.sermonId);
      final prompts = await service.getStudyPrompts(widget.sermonId);

      setState(() {
        _notes = notes;
        _studyPrompts = prompts.map((p) => p['prompt'] as String).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Sermon Notes'),
        bottom: TabBar(
          controller: _tabController,
          tabAlignment: TabAlignment.start,
          isScrollable: true,
          tabs: [
            Tab(icon: Icon(Icons.notes), text: 'Notes'),
            Tab(icon: Icon(Icons.auto_awesome), text: 'AI Summary'),
            Tab(icon: Icon(Icons.question_answer), text: 'Study'),
          ],
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _NotesTab(
                  notes: _notes,
                  sermonId: widget.sermonId,
                  onRefresh: _loadData,
                ),
                _AISummaryTab(
                  sermonId: widget.sermonId,
                  title: widget.sermonTitle,
                  content: widget.sermonContent ?? '',
                  summary: _aiSummary,
                  onGenerate: _generateAISummary,
                  generating: _generating,
                ),
                _StudyTab(
                  prompts: _studyPrompts,
                  sermonId: widget.sermonId,
                  sermonTitle: widget.sermonTitle,
                  sermonContent: widget.sermonContent ?? '',
                  onRefresh: _loadData,
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddNoteSheet,
        child: Icon(Icons.add),
      ),
    );
  }

  Future<void> _generateAISummary() async {
    setState(() => _generating = true);

    try {
      final service = ref.read(sermonNotesServiceProvider);
      final result = await service.generateAISummary(
        sermonId: widget.sermonId,
        title: widget.sermonTitle,
        content: widget.sermonContent ?? '',
      );

      setState(() {
        _aiSummary = result['summary'];
        _studyPrompts = List<String>.from(result['study_prompts'] ?? []);
      });
    } catch (e) {
      if (mounted) {
        PremiumToast.showError(context, 'Error generating summary: $e');
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _showAddNoteSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddNoteSheet(
        sermonId: widget.sermonId,
        onNoteAdded: _loadData,
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _noteController.dispose();
    super.dispose();
  }
}

class _NotesTab extends StatelessWidget {
  final List<Map<String, dynamic>> notes;
  final String sermonId;
  final VoidCallback onRefresh;

  const _NotesTab({
    required this.notes,
    required this.sermonId,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (notes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notes, size: 64, color: Colors.grey[400]),
            SizedBox(height: 16),
            Text(
              'No notes yet',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            SizedBox(height: 8),
            Text(
              'Tap + to add your first note',
              style: TextStyle(color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: notes.length,
      itemBuilder: (context, index) {
        final note = notes[index];
        final isAi = note['is_ai_generated'] == true;

        return Container(
          margin: EdgeInsets.only(bottom: 12),
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isAi ? Colors.purple[50] : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isAi ? Colors.purple[200]! : Colors.grey[200]!,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (isAi) ...[
                    Icon(Icons.auto_awesome, size: 16, color: Colors.purple),
                    SizedBox(width: 4),
                    Text(
                      'AI Generated',
                      style: TextStyle(
                        color: Colors.purple,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                  Spacer(),
                  PopupMenuButton(
                    itemBuilder: (context) => [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                    onSelected: (value) {
                      if (value == 'delete') _deleteNote(context, note['id']);
                    },
                  ),
                ],
              ),
              SizedBox(height: 8),
              if (note['title'] != null)
                Text(
                  note['title'],
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              SizedBox(height: 8),
              Text(
                note['content'] ?? '',
                style: TextStyle(fontSize: 14),
              ),
              SizedBox(height: 8),
              Text(
                _formatDate(note['created_at']),
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }

  void _deleteNote(BuildContext context, String noteId) async {
    final service = ProviderScope.containerOf(context).read(sermonNotesServiceProvider);
    await service.deleteNote(noteId);
    onRefresh();
  }

  String _formatDate(String dateStr) {
    final date = DateTime.parse(dateStr);
    return '${date.day}/${date.month}/${date.year} at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class _AISummaryTab extends StatelessWidget {
  final String sermonId;
  final String title;
  final String content;
  final String? summary;
  final VoidCallback onGenerate;
  final bool generating;

  const _AISummaryTab({
    required this.sermonId,
    required this.title,
    required this.content,
    this.summary,
    required this.onGenerate,
    required this.generating,
  });

  @override
  Widget build(BuildContext context) {
    if (summary == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_awesome, size: 64, color: Colors.purple[200]),
            SizedBox(height: 16),
            Text(
              'Generate AI Summary',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            SizedBox(height: 8),
            Text(
              'Get a concise summary and key points from this sermon',
              style: TextStyle(color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: generating ? null : onGenerate,
              icon: generating
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.auto_awesome),
              label: Text(generating ? 'Generating...' : 'Generate Summary'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.all(16),
      children: [
        Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.purple[50]!, Colors.blue[50]!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.purple[200]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome, color: Colors.purple),
                  SizedBox(width: 8),
                  Text(
                    'AI Summary',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.purple,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
              Text(
                summary!,
                style: TextStyle(fontSize: 15, height: 1.6),
              ),
            ],
          ),
        ),
        SizedBox(height: 24),
        Text(
          'Key Points',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 12),
        // Parse and display key points
        ..._parseKeyPoints(summary!),
      ],
    );
  }

  List<Widget> _parseKeyPoints(String summary) {
    final lines = summary.split('\n');
    final points = <Widget>[];

    for (final line in lines) {
      if (line.trim().isEmpty) continue;

      // Check if line looks like a key point
      if (line.contains('•') || line.contains('-') || line.contains('1.')) {
        points.add(
          Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_circle, size: 16, color: Colors.green),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    line.replaceAll(RegExp(r'^[\s•\-1.]+'), ''),
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    if (points.isEmpty) {
      points.add(
        Text(
          'Summary generated successfully. Review the key themes above.',
          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
        ),
      );
    }

    return points;
  }
}

class _StudyTab extends StatelessWidget {
  final List<String> prompts;
  final String sermonId;
  final String sermonTitle;
  final String sermonContent;
  final VoidCallback onRefresh;

  const _StudyTab({
    required this.prompts,
    required this.sermonId,
    required this.sermonTitle,
    required this.sermonContent,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.all(16),
      children: [
        Text(
          'Study Prompts',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 8),
        Text(
          'Use these questions for personal reflection or small group discussion.',
          style: TextStyle(color: Colors.grey[600]),
        ),
        SizedBox(height: 16),
        if (prompts.isEmpty)
          Center(
            child: Column(
              children: [
                Icon(Icons.question_answer, size: 48, color: Colors.grey[400]),
                SizedBox(height: 12),
                Text(
                  'Generate an AI summary first to get study prompts',
                  style: TextStyle(color: Colors.grey[500]),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else
          ...prompts.asMap().entries.map((entry) {
            return Container(
              margin: EdgeInsets.only(bottom: 12),
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${entry.key + 1}',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      entry.value,
                      style: TextStyle(fontSize: 15),
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}

class _AddNoteSheet extends ConsumerStatefulWidget {
  final String sermonId;
  final VoidCallback onNoteAdded;

  const _AddNoteSheet({
    required this.sermonId,
    required this.onNoteAdded,
  });

  @override
  ConsumerState<_AddNoteSheet> createState() => _AddNoteSheetState();
}

class _AddNoteSheetState extends ConsumerState<_AddNoteSheet> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            margin: EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[400],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.all(24),
              children: [
                Text(
                  'Add Note',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 20),
                TextField(
                  controller: _titleController,
                  decoration: InputDecoration(
                    labelText: 'Title (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                SizedBox(height: 16),
                TextField(
                  controller: _contentController,
                  maxLines: 10,
                  decoration: InputDecoration(
                    labelText: 'Your Note',
                    hintText: 'Write your thoughts, insights, or applications...',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _saving
                        ? CircularProgressIndicator(color: Colors.white)
                        : Text('Save Note', style: TextStyle(fontSize: 16, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_contentController.text.trim().isEmpty) {
      PremiumToast.showError(context, 'Please write a note');
      return;
    }

    setState(() => _saving = true);

    try {
      final service = ref.read(sermonNotesServiceProvider);
      await service.saveNote(
        sermonId: widget.sermonId,
        content: _contentController.text.trim(),
        title: _titleController.text.trim(),
      );

      widget.onNoteAdded();

      if (mounted) {
        Navigator.pop(context);
        PremiumToast.showSuccess(context, 'Note saved!');
      }
    } catch (e) {
      if (mounted) {
        PremiumToast.showError(context, 'Error: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }
}
