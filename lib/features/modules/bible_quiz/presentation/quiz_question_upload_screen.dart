import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Question import for quiz admins (superadmin / coa_employee / employee)
/// and Quiz Engine leasing churches.
///
/// Sources:
///  - Paste plain text (formatted like the quiz bank docs)
///  - Upload TXT / PDF / DOC / DOCX (extracted via Hugging Face / Kael AI in the edge function)
///  - Paste a pre-parsed JSON `questions` array
class QuizQuestionUploadScreen extends StatefulWidget {
  const QuizQuestionUploadScreen({super.key});

  @override
  State<QuizQuestionUploadScreen> createState() =>
      _QuizQuestionUploadScreenState();
}

class _QuizQuestionUploadScreenState extends State<QuizQuestionUploadScreen> {
  final _textCtrl = TextEditingController();
  final _jsonCtrl = TextEditingController();
  String? _pickedFileName;
  Uint8List? _pickedBytes;
  bool _busy = false;
  Map<String, dynamic>? _result;
  String? _error;

  @override
  void dispose() {
    _textCtrl.dispose();
    _jsonCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'pdf', 'doc', 'docx'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    final f = res.files.single;
    setState(() {
      _pickedFileName = f.name;
      _pickedBytes = f.bytes;
    });
  }

  Future<void> _submit({required String source}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) {
        throw Exception("Not authenticated");
      }

      Map<String, dynamic> body;
      switch (source) {
        case 'text':
          final text = _textCtrl.text.trim();
          if (text.isEmpty) throw Exception("Paste some question text first");
          body = {'text': text};
        case 'file':
          if (_pickedBytes == null) throw Exception("Pick a file first");
          body = {
            'fileName': _pickedFileName,
            'dataBase64': base64Encode(_pickedBytes!),
          };
        case 'json':
          final jsonText = _jsonCtrl.text.trim();
          if (jsonText.isEmpty) throw Exception("Paste the questions JSON first");
          final decoded = jsonDecode(jsonText);
          body = {'questions': decoded};
        default:
          throw Exception("Unknown source");
      }

      final res = await Supabase.instance.client.functions.invoke(
        'quiz-import',
        body: body,
      );
      final data = (res.data as Map<String, dynamic>?) ?? const {};
      setState(() => _result = data);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.primaryColor;

    return Scaffold(
      backgroundColor: const Color(0xFF0E0E10),
      appBar: AppBar(
        title: const Text("Import Questions"),
        backgroundColor: const Color(0xFF0E0E10),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: primary.withAlpha(18),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: primary.withAlpha(60)),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.shieldCheck, color: primary, size: 26),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      "Admins, COA employees and Quiz Engine leasing churches can add "
                      "questions. Duplicates are skipped automatically.",
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _sectionTitle("PASTE TEXT", LucideIcons.clipboardPaste),
            const SizedBox(height: 10),
            TextField(
              controller: _textCtrl,
              maxLines: 10,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText:
                    'One question per block, e.g.\n\n'
                    "Question: Who was the first king of Israel?\n"
                    "Options: David, Saul, Solomon, Samuel\n"
                    "Answer: Saul\n\n"
                    "You can also write it free-form — the AI extracts the questions.",
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                filled: true,
                fillColor: const Color(0xFF1A1A1E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _busy ? null : () => _submit(source: 'text'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: Colors.black,
                ),
                icon: const Icon(LucideIcons.fileText, size: 18),
                label: const Text("Extract Questions from Text"),
              ),
            ),
            const SizedBox(height: 28),
            _sectionTitle("UPLOAD DOCUMENT", LucideIcons.paperclip),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _pickFile,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _pickedFileName == null
                        ? Colors.white24
                        : primary.withAlpha(120),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _pickedFileName == null
                          ? LucideIcons.upload
                          : LucideIcons.fileCheck,
                      color: _pickedFileName == null
                          ? Colors.white54
                          : primary,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _pickedFileName ?? "Choose TXT / PDF / DOC / DOCX",
                        style: TextStyle(
                          color: _pickedFileName == null
                              ? Colors.white54
                              : Colors.white,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _busy ? null : () => _submit(source: 'file'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: Colors.black,
                ),
                icon: const Icon(LucideIcons.sparkles, size: 18),
                label: const Text("Extract Questions from Document"),
              ),
            ),
            const SizedBox(height: 28),
            _sectionTitle("PASTE JSON (advanced)", LucideIcons.braces),
            const SizedBox(height: 10),
            TextField(
              controller: _jsonCtrl,
              maxLines: 6,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                hintText: '[{"question": "...", "options": ["a","b","c","d"],'
                    ' "correctAnswer": 0, "category": "Bible", "difficulty": "easy"}]',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                filled: true,
                fillColor: const Color(0xFF1A1A1E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _busy ? null : () => _submit(source: 'json'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white12,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(LucideIcons.database, size: 18),
                label: const Text("Import JSON Questions"),
              ),
            ),
            const SizedBox(height: 24),
            if (_busy)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              ),
            if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.red.withAlpha(22),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withAlpha(90)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(LucideIcons.alertTriangle,
                        color: Colors.redAccent, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            if (_result != null) _buildResultCard(theme),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 16),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildResultCard(ThemeData theme) {
    final inserted = _result!['inserted'] ?? 0;
    final skipped = _result!['skipped'] ?? 0;
    final batchId = _result!['batch_id'];
    final errors = (_result!['errors'] as List?) ?? const [];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.withAlpha(20),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.green.withAlpha(90)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.checkCircle2, color: Colors.green, size: 22),
              const SizedBox(width: 10),
              Text(
                "Import complete — $inserted new, $skipped duplicates",
                style: const TextStyle(
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 14),
              ),
            ],
          ),
          if (batchId != null) ...[
            const SizedBox(height: 8),
            Text(
              "Batch: $batchId",
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
          if (errors.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              "${errors.length} row(s) failed:",
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
            ),
            ...errors.take(5).map((e) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    "- $e",
                    style: const TextStyle(
                        color: Colors.orangeAccent, fontSize: 11),
                  ),
                )),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _textCtrl.clear();
                  _jsonCtrl.clear();
                  _pickedFileName = null;
                  _pickedBytes = null;
                  _result = null;
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primaryColor,
                foregroundColor: Colors.black,
              ),
              icon: const Icon(LucideIcons.plus, size: 18),
              label: const Text("Import Another Batch"),
            ),
          ),
        ],
      ),
    );
  }
}