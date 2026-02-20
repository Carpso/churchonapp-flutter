import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/r2_service.dart';
import '../../../core/services/supabase_service.dart';

class MediaUploadScreen extends ConsumerStatefulWidget {
  const MediaUploadScreen({super.key});

  @override
  ConsumerState<MediaUploadScreen> createState() => _MediaUploadScreenState();
}

class _MediaUploadScreenState extends ConsumerState<MediaUploadScreen> {
  bool _isUploading = false;
  double _progress = 0.0;
  String _targetFolder = 'sermons';
  final _titleController = TextEditingController();

  final List<String> _folders = ['sermons', 'klips', 'profiles', 'marketplace'];

  void _simulateUpload() async {
    if (_titleController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please enter a title")));
      return;
    }

    setState(() {
      _isUploading = true;
      _progress = 0.1;
    });

    // Simulate progress
    for (int i = 0; i <= 10; i++) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      setState(() => _progress = (i + 1) / 10);
    }

    // In a real scenario, we would call:
    // final url = await ref.read(r2ServiceProvider).uploadFile(pickedFile, "$_targetFolder/filename");
    
    setState(() => _isUploading = false);
    
    if (mounted) {
       _showSuccessDialog();
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.checkCircle, color: Colors.green, size: 60),
            const SizedBox(height: 20),
            const Text("Upload Successful!", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text("Your file has been saved to Cloudflare R2 and indexed in the Kingdom Database.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("GLORY TO GOD")),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text("Kingdom Media Manager"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Upload Content", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const Text("All assets are served via Cloudflare R2 Edge", style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 30),
            
            _buildInputLabel("CONTENT TITLE"),
            _buildTextField(_titleController, "e.g. Sunday Morning Miracle"),
            
            const SizedBox(height: 25),
            
            _buildInputLabel("TARGET FOLDER"),
            _buildFolderSelector(),
            
            const SizedBox(height: 40),
            
            _buildUploadZone(),
            
            const SizedBox(height: 50),
            
            if (_isUploading)
              _buildProgressIndicator()
            else
              ElevatedButton(
                onPressed: _simulateUpload,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  minimumSize: const Size(double.infinity, 65),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                ),
                child: const Text("START SECURE UPLOAD", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 5),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1.2, color: Colors.grey)),
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: hint,
          border: InputBorder.none,
          hintStyle: TextStyle(color: Colors.grey.shade300, fontSize: 14),
        ),
      ),
    );
  }

  Widget _buildFolderSelector() {
    return SizedBox(
      height: 45,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _folders.length,
        itemBuilder: (context, index) {
          final isSelected = _targetFolder == _folders[index];
          return GestureDetector(
            onTap: () => setState(() => _targetFolder = _folders[index]),
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: isSelected ? Theme.of(context).colorScheme.secondary : Colors.white,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Center(
                child: Text(
                  _folders[index].toUpperCase(),
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildUploadZone() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 50),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Theme.of(context).primaryColor.withOpacity(0.5), style: BorderStyle.none), // Should be dashed in real CSS
      ),
      child: Column(
        children: [
          Icon(LucideIcons.fileVideo, size: 50, color: Theme.of(context).primaryColor),
          const SizedBox(height: 20),
          const Text("TAP TO SELECT MEDIA", style: TextStyle(fontWeight: FontWeight.bold)),
          const Text("Supports MP4, JPG, PNG up to 5GB", style: TextStyle(color: Colors.grey, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Column(
      children: [
        LinearProgressIndicator(
          value: _progress,
          backgroundColor: Colors.grey.shade200,
          color: Theme.of(context).primaryColor,
          minHeight: 12,
          borderRadius: BorderRadius.circular(10),
        ),
        const SizedBox(height: 15),
        Text("UPLOADING TO R2: ${(_progress * 100).toInt()}%", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      ],
    );
  }
}
