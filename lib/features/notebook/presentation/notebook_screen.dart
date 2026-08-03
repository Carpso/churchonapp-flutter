import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import 'package:church_on_app/features/notebook/data/note_model.dart';
import 'package:church_on_app/features/notebook/data/notebook_service.dart';
import 'package:church_on_app/core/providers/auth_provider.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';

class NotebookScreen extends ConsumerStatefulWidget {
  const NotebookScreen({super.key});

  @override
  ConsumerState<NotebookScreen> createState() => _NotebookScreenState();
}

class _NotebookScreenState extends ConsumerState<NotebookScreen> {
  String _searchQuery = "";
  Timer? _debounceTimer;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    if (user == null) {
      return const Scaffold(body: Center(child: Text("Please login to use the notebook")));
    }

    final notesAsync = ref.watch(notesProvider(user.id));

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text("My Journal", style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: notesAsync.when(
              data: (notes) {
                final filteredNotes = notes.where((n) => 
                  n.title.toLowerCase().contains(_searchQuery.toLowerCase()) || 
                  (n.topic?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false)
                ).toList();

                if (filteredNotes.isEmpty) {
                  return _buildEmptyState();
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: filteredNotes.length,
                  itemBuilder: (context, index) {
                    return _buildNoteCard(filteredNotes[index]);
                  },
                );
              },
              loading: () => const ListSkeleton(count: 4),
              error: (e, st) => Center(child: Text("Error: $e")),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(null),
        backgroundColor: const Color(0xFF0F172A),
        label: const Text("New Entry", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        icon: const Icon(LucideIcons.plus, color: Colors.white),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: TextField(
        onChanged: (v) {
          _debounceTimer?.cancel();
          _debounceTimer = Timer(const Duration(milliseconds: 500), () {
            if (mounted) setState(() => _searchQuery = v);
          });
        },
        decoration: InputDecoration(
          hintText: "Search your revelations...",
          prefixIcon: const Icon(LucideIcons.search, size: 20),
          filled: true,
          fillColor: const Color(0xFFF1F5F9),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.bookOpen, size: 80, color: Colors.grey.withValues(alpha: 0.2)),
          const SizedBox(height: 20),
          Text("No entries found", style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 10),
          const Text("Capture what God is speaking to you.", style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildNoteCard(Note note) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(20),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (note.topic != null && note.topic!.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                child: Text(note.topic!.toUpperCase(), style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
              ),
            const SizedBox(height: 8),
            Text(note.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            note.content.replaceAll(RegExp(r'\{\{.*?\}\}'), '_____'), 
            maxLines: 2, 
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF64748B)),
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: Icon(note.isFavorite ? LucideIcons.bookmark : LucideIcons.bookmark, color: note.isFavorite ? Colors.amber : const Color(0xFFCBD5E1)),
              onPressed: () => ref.read(notebookServiceProvider).updateNote(note.id, {'is_favorite': !note.isFavorite}),
            ),
          ],
        ),
        onTap: () => _openEditor(note),
      ),
    );
  }

  void _openEditor(Note? note) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => NoteEditorScreen(note: note)),
    );
  }
}

class NoteEditorScreen extends ConsumerStatefulWidget {
  final Note? note;
  const NoteEditorScreen({super.key, this.note});

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  late TextEditingController _titleCtrl;
  late TextEditingController _topicCtrl;
  late TextEditingController _contentCtrl;
  bool _isInteractive = false;
  Timer? _autoSaveTimer;
  String _saveStatus = "Saved";

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.note?.title ?? "");
    _topicCtrl = TextEditingController(text: widget.note?.topic ?? "");
    _contentCtrl = TextEditingController(text: widget.note?.content ?? "");
    
    _contentCtrl.addListener(_onContentChanged);
  }

  void _onContentChanged() {
    setState(() => _saveStatus = "Unsaved");
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 2), _saveNote);
  }

  Future<void> _saveNote() async {
    if (_titleCtrl.text.isEmpty && _contentCtrl.text.isEmpty) return;
    
    setState(() => _saveStatus = "Saving...");
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;

    try {
      if (widget.note != null) {
        await ref.read(notebookServiceProvider).updateNote(widget.note!.id, {
          'title': _titleCtrl.text,
          'topic': _topicCtrl.text,
          'content': _contentCtrl.text,
        });
      } else {
        await ref.read(notebookServiceProvider).createNote(
          userId,
          _titleCtrl.text.isEmpty ? "Untitled Entry" : _titleCtrl.text,
          _contentCtrl.text,
          topic: _topicCtrl.text,
        );
      }
      if (mounted) setState(() => _saveStatus = "Saved");
    } catch (e) {
      if (mounted) setState(() => _saveStatus = "Error");
    }
  }

  Future<void> _finalizeSave() async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;

    if (widget.note == null) {
      await ref.read(notebookServiceProvider).createNote(
        userId, 
        _titleCtrl.text.isEmpty ? "Untitled Entry" : _titleCtrl.text, 
        _contentCtrl.text,
        topic: _topicCtrl.text,
      );
    } else {
      await _saveNote();
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _titleCtrl.dispose();
    _topicCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        title: Text(_saveStatus, style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8), fontWeight: FontWeight.bold)),
        actions: [
          TextButton(
            onPressed: () => setState(() => _isInteractive = !_isInteractive),
            child: Text(_isInteractive ? "EDIT MODE" : "FILL-IN MODE", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
          ),
          IconButton(icon: const Icon(LucideIcons.check, color: Colors.green), onPressed: _finalizeSave),
        ],
      ),
      body: _isInteractive ? _buildInteractiveView() : _buildEditorView(),
    );
  }

  Widget _buildEditorView() {
    final editorItems = <Widget>[
      TextField(
        controller: _titleCtrl,
        style: GoogleFonts.plusJakartaSans(fontSize: 28, fontWeight: FontWeight.bold),
        decoration: const InputDecoration(hintText: "Untitled Entry", border: InputBorder.none, hintStyle: TextStyle(color: Colors.black12)),
      ),
      TextField(
        controller: _topicCtrl,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.amber),
        decoration: const InputDecoration(hintText: "ADD TOPIC", border: InputBorder.none, hintStyle: TextStyle(color: Colors.black12, fontSize: 12)),
      ),
      const Divider(height: 40),
      TextField(
        controller: _contentCtrl,
        maxLines: null,
        style: const TextStyle(fontSize: 18, height: 1.6),
        decoration: const InputDecoration(
          hintText: "Write what the Spirit is saying...\nUse {{answer}} to create blanks for study.",
          border: InputBorder.none,
          hintStyle: TextStyle(color: Colors.black12),
        ),
      ),
    ];
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(25, 25, 25, MediaQuery.of(context).viewInsets.bottom + 100),
      itemCount: editorItems.length,
      itemBuilder: (context, index) => editorItems[index],
    );
  }

  Widget _buildInteractiveView() {
    final content = _contentCtrl.text;
    final fragments = _parseContent(content);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(25, 25, 25, MediaQuery.of(context).viewInsets.bottom + 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_titleCtrl.text, style: GoogleFonts.plusJakartaSans(fontSize: 28, fontWeight: FontWeight.bold)),
          if (_topicCtrl.text.isNotEmpty) Text(_topicCtrl.text.toUpperCase(), style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
          const Divider(height: 40),
          Wrap(
            spacing: 4,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: fragments,
          ),
        ],
      ),
    );
  }

  List<Widget> _parseContent(String content) {
    List<Widget> widgets = [];
    final regExp = RegExp(r'\{\{(.*?)\}\}');
    int lastMatchEnd = 0;

    for (final match in regExp.allMatches(content)) {
      // Add preceding text
      if (match.start > lastMatchEnd) {
        widgets.add(Text(content.substring(lastMatchEnd, match.start), style: const TextStyle(fontSize: 18, height: 1.6)));
      }
      
      // Add interactive blank
      widgets.add(_InteractiveBlank(answer: match.group(1)!));
      
      lastMatchEnd = match.end;
    }

    // Add remaining text
    if (lastMatchEnd < content.length) {
      widgets.add(Text(content.substring(lastMatchEnd), style: const TextStyle(fontSize: 18, height: 1.6)));
    }

    return widgets;
  }
}

class _InteractiveBlank extends StatefulWidget {
  final String answer;
  const _InteractiveBlank({required this.answer});

  @override
  State<_InteractiveBlank> createState() => _InteractiveBlankState();
}

class _InteractiveBlankState extends State<_InteractiveBlank> {
  final TextEditingController _ctrl = TextEditingController();
  bool _isCorrect = false;

  @override
  Widget build(BuildContext context) {
    if (_isCorrect) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.green.withValues(alpha: 0.2))),
        child: Text(widget.answer, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 18)),
      );
    }

    return SizedBox(
      width: 100,
      child: TextField(
        controller: _ctrl,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 4),
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.amber, width: 2)),
          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.amber, width: 3)),
        ),
        onChanged: (v) {
          if (v.trim().toLowerCase() == widget.answer.trim().toLowerCase()) {
            setState(() => _isCorrect = true);
          }
        },
      ),
    );
  }
}

