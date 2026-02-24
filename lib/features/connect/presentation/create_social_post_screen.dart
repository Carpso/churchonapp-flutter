import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("New Testimony or Post", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () async {
              if (_controller.text.trim().isEmpty) return;
              setState(() => _isPosting = true);
              
              await ref.read(socialServiceProvider).createPost(
                content: _controller.text,
                mediaType: 'text',
              );
              
              if (mounted) Navigator.pop(context);
            },
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
                  IconButton(icon: const Icon(LucideIcons.camera, color: Colors.blue), onPressed: () {}),
                  IconButton(icon: const Icon(LucideIcons.image, color: Colors.green), onPressed: () {}),
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
