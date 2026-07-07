import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/features/home/data/news_service.dart';

class WriterStudioScreen extends ConsumerStatefulWidget {
  const WriterStudioScreen({super.key});

  @override
  ConsumerState<WriterStudioScreen> createState() => _WriterStudioScreenState();
}

class _WriterStudioScreenState extends ConsumerState<WriterStudioScreen> {
  final _titleCtrl = TextEditingController();
  final _excerptCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  final _imageUrlCtrl = TextEditingController();
  bool _isPublishing = false;

  Future<void> _handlePublish() async {
    if (_titleCtrl.text.isEmpty || _contentCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Title and Content are required")));
      return;
    }

    setState(() => _isPublishing = true);
    final profile = ref.read(profileProvider).value;
    if (profile == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile not loaded yet. Please wait.")));
        setState(() => _isPublishing = false);
      }
      return;
    }

    try {
      await ref.read(newsServiceProvider).publishArticle(
        title: _titleCtrl.text,
        excerpt: _excerptCtrl.text.isEmpty ? _titleCtrl.text : _excerptCtrl.text,
        content: _contentCtrl.text,
        imageUrl: _imageUrlCtrl.text.isEmpty 
          ? "https://images.unsplash.com/photo-1438232992991-995b7058bbb3?w=800" 
          : _imageUrlCtrl.text,
        authorId: profile.id,
        authorName: profile.name,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Kingdom News Published!"), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to publish: $e")));
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text("Kingdom News Studio", style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        actions: [
          Padding(
            padding: const EdgeInsets.all(10.0),
            child: ElevatedButton(
              onPressed: _isPublishing ? null : _handlePublish,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: _isPublishing 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text("PUBLISH", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader("Article Header"),
            const SizedBox(height: 15),
            _buildInputField(_titleCtrl, "Catchy Headline", LucideIcons.heading, fontSize: 24, fontWeight: FontWeight.bold),
            const SizedBox(height: 15),
            _buildInputField(_imageUrlCtrl, "Header Image URL", LucideIcons.image),
            const SizedBox(height: 30),
            _buildSectionHeader("The Lead (Short Excerpt)"),
            const SizedBox(height: 15),
            _buildInputField(_excerptCtrl, "A brief summary for the feed ticker...", LucideIcons.fileText, maxLines: 2),
            const SizedBox(height: 30),
            _buildSectionHeader("Main Story (Markdown Supported)"),
            const SizedBox(height: 15),
            _buildInputField(_contentCtrl, "Write your story here... Use clear blocks for better reading.", null, maxLines: 15),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2));
  }

  Widget _buildInputField(TextEditingController ctrl, String hint, IconData? icon, {int maxLines = 1, double fontSize = 14, FontWeight fontWeight = FontWeight.normal}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: TextStyle(fontSize: fontSize, fontWeight: fontWeight),
      decoration: InputDecoration(
        prefixIcon: icon != null ? Icon(icon, size: 20, color: Colors.grey) : null,
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
      ),
    );
  }
}

