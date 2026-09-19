import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:church_on_app/core/widgets/app_image.dart';
import 'package:church_on_app/features/connect/data/story_service.dart';

/// The poster's own story archive: every own story (even expired ones), with
/// re-share, add-to-highlight, unarchive and delete actions.
class StoryArchiveScreen extends ConsumerWidget {
  const StoryArchiveScreen({super.key});

  String _expiryLabel(Map<String, dynamic> s) {
    final exp = DateTime.tryParse((s['expires_at'] ?? '').toString());
    if (exp == null) return '';
    final diff = exp.difference(DateTime.now());
    if (diff.isNegative) return 'Expired';
    if (diff.inHours < 1) return '${diff.inMinutes}m left';
    if (diff.inHours < 48) return '${diff.inHours}h left';
    return '${diff.inDays}d left';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final archiveAsync = ref.watch(storyArchiveProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Your story archive')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(storyArchiveProvider),
        child: archiveAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Could not load archive: $e')),
          data: (stories) {
            if (stories.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: 120),
                  Icon(LucideIcons.archive,
                      size: 48, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(height: 12),
                  const Center(
                    child: Text('No archived stories yet',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 4),
                  const Center(
                    child: Text('Stories you post are archived here automatically.',
                        style: TextStyle(fontSize: 12)),
                  ),
                ],
              );
            }
            return GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 0.72,
              ),
              itemCount: stories.length,
              itemBuilder: (context, i) {
                final s = stories[i];
                final thumb = (s['thumbnail_url'] ??
                        (s['media_type'] == 'video' ? '' : s['media_url']) ??
                        '')
                    .toString();
                return GestureDetector(
                  onTap: () => _openActions(context, ref, s),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: thumb.isNotEmpty
                            ? AppImage(thumb, fit: BoxFit.cover)
                            : Container(
                                color: theme.colorScheme.surfaceContainerHighest,
                                child: const Icon(LucideIcons.imageOff),
                              ),
                      ),
                      Positioned(
                        left: 4,
                        bottom: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _expiryLabel(s),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _openActions(
      BuildContext context, WidgetRef ref, Map<String, dynamic> s) async {
    final id = s['id'].toString();
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(LucideIcons.share2),
              title: const Text('Re-share'),
              onTap: () async {
                Navigator.pop(ctx);
                await _reshare(context, ref, s);
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.highlighter),
              title: const Text('Add to highlight'),
              onTap: () async {
                Navigator.pop(ctx);
                await _addToHighlight(context, ref, id);
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.archiveRestore),
              title: const Text('Remove from archive'),
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  await ref.read(storyServiceProvider).setArchived(id, false);
                  ref.invalidate(storyArchiveProvider);
                } catch (e) {
                  debugPrint('unarchive failed: $e');
                }
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.trash2, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  await ref.read(storyServiceProvider).deleteStory(id);
                  ref.invalidate(storyArchiveProvider);
                } catch (e) {
                  debugPrint('delete story failed: $e');
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reshare(
      BuildContext context, WidgetRef ref, Map<String, dynamic> s) async {
    final hours = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Share again for…'),
        children: [
          for (final o in kStoryDurationOptions)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, o.hours),
              child: Text(o.label),
            ),
        ],
      ),
    );
    if (hours == null) return;
    try {
      await ref.read(storyServiceProvider).reshare(s, hours: hours);
      ref.invalidate(storyArchiveProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Story re-shared'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not re-share: $e')));
      }
    }
  }

  Future<void> _addToHighlight(
      BuildContext context, WidgetRef ref, String storyId) async {
    final highlights = await ref
        .read(storyServiceProvider)
        .fetchHighlights();
    if (!context.mounted) return;
    if (highlights.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create a highlight first (from the profile).')),
      );
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final h in highlights)
              ListTile(
                leading: const Icon(LucideIcons.highlighter),
                title: Text(h['title']?.toString() ?? 'Highlight'),
                onTap: () => Navigator.pop(ctx, h['id'].toString()),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    try {
      await ref.read(storyServiceProvider).addToHighlight(picked, storyId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Added to highlight')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not add: $e')));
      }
    }
  }
}
