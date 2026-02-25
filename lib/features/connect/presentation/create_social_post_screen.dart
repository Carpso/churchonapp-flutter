import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/core/services/r2_service.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../data/social_service.dart';
import '../../../core/providers/profile_provider.dart';

class CreateSocialPostScreen extends ConsumerStatefulWidget {
  const CreateSocialPostScreen({super.key});

  @override
  ConsumerState<CreateSocialPostScreen> createState() => _CreateSocialPostScreenState();
}

class _CreateSocialPostScreenState extends ConsumerState<CreateSocialPostScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _isPosting = false;
  File? _selectedImage;

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 70);
    if (picked != null) {
      setState(() => _selectedImage = File(picked.path));
    }
  }

  Future<void> _handlePost() async {
    if (_controller.text.trim().isEmpty && _selectedImage == null) return;
    setState(() => _isPosting = true);
    
    try {
      String? mediaUrl;
      String? mediaType;

      if (_selectedImage != null) {
        final r2 = ref.read(r2ServiceProvider);
        final fileName = "social_${DateTime.now().millisecondsSinceEpoch}.jpg";
        mediaUrl = await r2.uploadFile(_selectedImage!, "social/$fileName");
        mediaType = 'image';
      }

      await ref.read(socialServiceProvider).createPost(
        content: _controller.text,
        mediaUrl: mediaUrl,
        mediaType: mediaType ?? 'text',
      );
      ref.invalidate(socialPostsProvider);
      
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Post failed: $e")));
      }
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("New Testimony or Post", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [
          TextButton(
            onPressed: _isPosting ? null : _handlePost,
            child: _isPosting 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text("POST", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.blue)),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(backgroundImage: NetworkImage(ref.watch(profileProvider).value?.avatarUrl ?? "https://i.pravatar.cc/100?u=me")),
                const SizedBox(width: 15),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ref.watch(profileProvider).value?.name ?? "Kingdom Partner", style: const TextStyle(fontWeight: FontWeight.bold)),
                    const Text("Public (Global Church)", style: TextStyle(color: Colors.grey, fontSize: 10)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (_selectedImage != null)
              Container(
                height: 200,
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  image: DecorationImage(image: FileImage(_selectedImage!), fit: BoxFit.cover),
                ),
                child: Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 20),
                    onPressed: () => setState(() => _selectedImage = null),
                  ),
                ),
              ),
            Expanded(
              child: TextField(
                controller: _controller,
                maxLines: null,
                style: const TextStyle(fontSize: 18),
                decoration: const InputDecoration(
                  hintText: "What miracle has God done today?",
                  border: InputBorder.none,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.black12))),
              child: Row(
                children: [
                  IconButton(icon: const Icon(LucideIcons.camera, color: Colors.blue), onPressed: () => _pickImage(ImageSource.camera)),
                  IconButton(icon: const Icon(LucideIcons.image, color: Colors.green), onPressed: () => _pickImage(ImageSource.gallery)),
                  IconButton(icon: const Icon(LucideIcons.mapPin, color: Colors.red), onPressed: () {}),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

