import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/features/notebook/data/notebook_service.dart';
import 'package:church_on_app/core/providers/auth_provider.dart';
import 'package:church_on_app/features/home/data/sermon_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

class SermonNotesScreen extends ConsumerStatefulWidget {
  final Sermon sermon;
  const SermonNotesScreen({super.key, required this.sermon});

  @override
  ConsumerState<SermonNotesScreen> createState() => _SermonNotesScreenState();
}

class _SermonNotesScreenState extends ConsumerState<SermonNotesScreen> {
  final _reflectionCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _reflectionCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveToJournal() async {
    final user = ref.read(authProvider).user;
    if (user == null) return;
    setState(() => _saving = true);
    try {
      final title = widget.sermon.title;
      final transcript = widget.sermon.transcript ?? '';
      final reflection = _reflectionCtrl.text.trim();
      final content = [
        if (transcript.isNotEmpty) 'SERMON TRANSCRIPT\n\n$transcript',
        if (reflection.isNotEmpty) 'MY REFLECTION\n\n$reflection',
      ].join('\n\n');

      await ref.read(notebookServiceProvider).createNote(
            user.id,
            title,
            content,
            topic: 'Sermon Notes',
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Saved to your Journal!")),
        );
      }
    } catch (e) {
      debugPrint('Failed to save sermon notes: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to save: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sermon = widget.sermon;
    final transcript = sermon.transcript ?? '';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          "Sermon Notes",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(LucideIcons.save),
            onPressed: _saving ? null : _saveToJournal,
          ),
          IconButton(
            icon: const Icon(LucideIcons.share2),
            onPressed: () => SharePlus.instance.share(
              ShareParams(
                text:
                    '${sermon.title} — ${sermon.preacher}\n\n${transcript.isNotEmpty ? transcript : ''}',
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                sermon.title.toUpperCase(),
                style: TextStyle(
                  color: Theme.of(context).primaryColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Preacher: ${sermon.preacher}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              '${sermon.createdAt.day}/${sermon.createdAt.month}/${sermon.createdAt.year}',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const Divider(height: 40),
            if (transcript.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 20),
                child: Text(
                  'No transcript available for this sermon yet.',
                  style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
                ),
              )
            else
              Text(
                transcript,
                style: const TextStyle(color: Colors.black87, height: 1.7),
              ),
            const SizedBox(height: 30),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.black12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "MY PERSONAL REFLECTION",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _reflectionCtrl,
                    maxLines: 5,
                    maxLength: 2000,
                    decoration: const InputDecoration(
                      hintText: 'How does this sermon apply to your life?',
                      border: InputBorder.none,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : _saveToJournal,
        backgroundColor: Colors.black,
        icon: _saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(LucideIcons.bookmark, color: Colors.white),
        label: const Text(
          "Save to Journal",
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}