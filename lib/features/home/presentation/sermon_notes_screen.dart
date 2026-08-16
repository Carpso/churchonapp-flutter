import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/features/notebook/data/notebook_service.dart';
import 'package:church_on_app/core/providers/auth_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

class SermonNotesScreen extends ConsumerWidget {
  const SermonNotesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Sermon Notes", style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.save), 
            onPressed: () async {
              final user = ref.read(authProvider).user;
              if (user == null) return;
              
              final content = """
TOPIC: THE MARKS OF A BELIEVER
Acts 2:42-47

1. Devotion to the Apostles' Doctrine
The early church prioritized the Word of God above all traditions.

2. The Fellowship of the Brethren
Koinonia is not just meeting, it's sharing a common life in Christ.

3. Breaking of Bread & Prayer
Consistency in communion and intercession leads to community miracles.
              """;

              await ref.read(notebookServiceProvider).createNote(
                user.id, 
                "The Marks of a Believer", 
                content,
                topic: "SERMON NOTES",
                category: "sermon_notes",
              );

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Saved to your Journal!")),
                );
              }
            }
          ),
          IconButton(icon: const Icon(LucideIcons.share2), onPressed: () => SharePlus.instance.share(ShareParams(text: 'The Marks of a Believer — Acts 2:42-47\n\n1. Devotion to the Apostles\' Doctrine\n2. The Fellowship of the Brethren\n3. Breaking of Bread & Prayer'))),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: Theme.of(context).primaryColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Text("TOPIC: THE MARKS OF A BELIEVER", style: TextStyle(color: Theme.of(context).primaryColor, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 20),
            const Text("Scripture Reference: Acts 2:42-47", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Divider(height: 40),
            _buildNotePoint("1. Devotion to the Apostles' Doctrine", "The early church prioritized the Word of God above all traditions."),
            _buildNotePoint("2. The Fellowship of the Brethren", "Koinonia is not just meeting, it's sharing a common life in Christ."),
            _buildNotePoint("3. Breaking of Bread & Prayer", "Consistency in communion and intercession leads to community miracles."),
            const SizedBox(height: 40),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.black12)),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("MY PERSONAL REFLECTION", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                  SizedBox(height: 10),
                  Text("How can I apply this fellowship to my daily life this week?", style: TextStyle(fontStyle: FontStyle.italic)),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Add your own notes"))),
        backgroundColor: Colors.black,
        child: const Icon(LucideIcons.pencil, color: Colors.white),
      ),
    );
  }

  Widget _buildNotePoint(String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 8),
          Text(desc, style: const TextStyle(color: Colors.black87, height: 1.5)),
        ],
      ),
    );
  }
}

