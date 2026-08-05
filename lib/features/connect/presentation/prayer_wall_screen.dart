import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/widgets/error_retry_widget.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../data/prayer_service.dart';
import 'package:intl/intl.dart';

class PrayerWallScreen extends ConsumerStatefulWidget {
  const PrayerWallScreen({super.key});

  @override
  ConsumerState<PrayerWallScreen> createState() => _PrayerWallScreenState();
}

class _PrayerWallScreenState extends ConsumerState<PrayerWallScreen> {
  void _addPrayer() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildAddRequestSheet(),
    );
  }

  Widget _buildAddRequestSheet() {
    final controller = TextEditingController();
    String category = "general";
    bool isAnonymous = false;

    return StatefulBuilder(
      builder: (context, setModalState) => Container(
        padding: EdgeInsets.only(left: 25, right: 25, top: 30, bottom: MediaQuery.of(context).viewInsets.bottom + 40),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Share Prayer Request", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            TextField(
              controller: controller,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: "What are we interceding for?",
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                const Text("Post Anonymously", style: TextStyle(fontSize: 14)),
                const Spacer(),
                Switch(
                  value: isAnonymous, 
                  onChanged: (v) => setModalState(() => isAnonymous = v),
                  activeThumbColor: Colors.red,
                ),
              ],
            ),
            const SizedBox(height: 25),
            ElevatedButton(
              onPressed: () async {
                if (controller.text.isNotEmpty) {
                  await ref.read(prayerServiceProvider).submitPrayer(
                    controller.text, 
                    category, 
                    "public", 
                    isAnonymous
                  );
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Request added to the wall! 🙌")));
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              child: const Text("POST REQUEST", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prayersAsync = ref.watch(prayerStreamProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Prayer Wall", style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(LucideIcons.plusCircle), onPressed: _addPrayer),
        ],
      ),
      body: prayersAsync.when(
        data: (prayers) {
          if (prayers.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(LucideIcons.flame, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text("No prayer requests yet", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text("Be the first to share a prayer request\nwith your church community.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade500)),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(prayerStreamProvider);
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: prayers.length,
              itemBuilder: (context, index) {
              final prayer = prayers[index];
              return _buildPrayerCard(prayer);
            },
          ),
          );
        },
        loading: () => const ListSkeleton(count: 3),
        error: (err, stack) => ErrorRetryWidget(
          message: "Failed to load prayer wall",
          onRetry: () => ref.invalidate(prayerStreamProvider),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addPrayer,
        backgroundColor: Colors.red,
        child: const Icon(LucideIcons.flame, color: Colors.white),
      ),
    );
  }

  Widget _buildPrayerCard(PrayerRequest prayer) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFF1A1A1A),
                backgroundImage: (prayer.userPhoto != null && prayer.userPhoto!.isNotEmpty)
                    ? CachedNetworkImageProvider(prayer.userPhoto!)
                    : null,
                child: (prayer.userPhoto == null || prayer.userPhoto!.isEmpty)
                    ? Text(
                        prayer.userName.isNotEmpty ? prayer.userName[0].toUpperCase() : 'P',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      )
                    : null,
              ),
              const SizedBox(width: 15),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(prayer.userName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(DateFormat.jm().format(prayer.createdAt), style: const TextStyle(color: Colors.grey, fontSize: 10)),
                ],
              ),
              const Spacer(),
              if (prayer.isAnonymous)
                const Icon(LucideIcons.userX, size: 14, color: Colors.grey),
            ],
          ),
          const SizedBox(height: 15),
          Text(prayer.content, style: const TextStyle(fontSize: 15, height: 1.5)),
          if (prayer.aiEncouragement != null) ...[
            const SizedBox(height: 15),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.1)),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.sparkles, color: Colors.blue, size: 14),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      prayer.aiEncouragement!,
                      style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.blueGrey),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              _buildActionButton(LucideIcons.helpingHand, "I'M PRAYING", Colors.blue, () {
                ref.read(prayerServiceProvider).prayForRequest(prayer.id, prayer.prayedBy);
              }),
              const SizedBox(width: 15),
              Text("${prayer.prayerCount} INTERCEDING", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, Color color, VoidCallback onTap) {
    return Semantics(
      label: "$label button",
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(15)),
          child: Row(
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}

