import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/admin_service.dart';
import '../../connect/data/social_service.dart';

class KingdomAIModeratorScreen extends ConsumerStatefulWidget {
  const KingdomAIModeratorScreen({super.key});

  @override
  ConsumerState<KingdomAIModeratorScreen> createState() => _KingdomAIModeratorScreenState();
}

class _KingdomAIModeratorScreenState extends ConsumerState<KingdomAIModeratorScreen> {
  bool _isModerating = false;

  @override
  Widget build(BuildContext context) {
    final postsAsync = ref.watch(postsStreamProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text("Kingdom AI Moderator", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: Column(
        children: [
          _buildModerationControl(),
          Expanded(
            child: postsAsync.when(
              data: (posts) => ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: posts.length,
                itemBuilder: (context, index) => _buildModeratedPostTile(posts[index]),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, s) => Center(child: Text("Error: $e")),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModerationControl() {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.shieldCheck, color: Colors.blue, size: 30),
          const SizedBox(width: 15),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Apostolic Gatekeeper", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text("Analyze prophetic weight & category", style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: _isModerating ? null : _runModeration,
            icon: _isModerating 
              ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(LucideIcons.zap, size: 16),
            label: Text(_isModerating ? "ANALYZING..." : "MODERATE ALL"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runModeration() async {
    setState(() => _isModerating = true);
    try {
      final count = await ref.read(adminServiceProvider).runApostolicModeration(ref);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Successfully moderated $count Kingdom posts via Gemini.")),
        );
      }
    } finally {
      if (mounted) setState(() => _isModerating = false);
    }
  }

  Widget _buildModeratedPostTile(SocialPost post) {
    final bool isModerated = post.isModerated;
    final double weight = post.propheticWeight;
    final String category = post.category;

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: isModerated ? Colors.green.withValues(alpha: 0.2) : Colors.orange.withValues(alpha: 0.2)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundImage: post.userAvatar != null ? NetworkImage(post.userAvatar!) : null,
                child: post.userAvatar == null ? const Icon(LucideIcons.user, size: 18) : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(post.userName ?? "Member", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    Text(isModerated ? "Prophetic Analysis Complete" : "Pending Apostolic Review", 
                         style: TextStyle(color: isModerated ? Colors.green : Colors.orange, fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              if (isModerated)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: Text(category.toUpperCase(), style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 10)),
                ),
            ],
          ),
          const SizedBox(height: 15),
          Text(post.content ?? "", style: const TextStyle(fontSize: 13, height: 1.4)),
          if (isModerated) ...[
            const Divider(height: 30),
            Row(
              children: [
                const Icon(LucideIcons.flame, color: Colors.amber, size: 16),
                const SizedBox(width: 8),
                const Text("Prophetic Weight:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Expanded(
                  child: LinearProgressIndicator(
                    value: weight,
                    backgroundColor: Colors.grey.withValues(alpha: 0.1),
                    color: weight > 0.7 ? Colors.green : Colors.amber,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 12),
                Text("${(weight * 100).toInt()}%", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
