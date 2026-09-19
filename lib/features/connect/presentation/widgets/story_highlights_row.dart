import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:church_on_app/core/widgets/app_image.dart';
import 'package:church_on_app/features/connect/data/story_service.dart';
import 'package:church_on_app/features/connect/presentation/widgets/stories_bar.dart';

/// Horizontal highlight reels on a profile. `canManage` is true on your own
/// profile, which enables create/edit/delete.
class StoryHighlightsRow extends ConsumerWidget {
  final String userId;
  final bool canManage;
  const StoryHighlightsRow({
    super.key,
    required this.userId,
    this.canManage = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(storyHighlightsProvider(userId));

    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (highlights) {
        if (highlights.isEmpty && !canManage) return const SizedBox.shrink();
        return SizedBox(
          height: 96,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            children: [
              if (canManage)
                _tile(
                  context,
                  label: 'New',
                  child: Icon(LucideIcons.plus,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
                  onTap: () => _create(context, ref),
                ),
              for (final h in highlights)
                _tile(
                  context,
                  label: (h['title'] ?? 'Highlight').toString(),
                  child: (h['cover_url'] ?? '').toString().isNotEmpty
                      ? AppImage(h['cover_url'].toString(),
                          width: 58, height: 58, fit: BoxFit.cover)
                      : const Icon(LucideIcons.star),
                  onTap: () => _open(context, ref, h),
                  onLongPress:
                      canManage ? () => _manage(context, ref, h) : null,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _tile(
    BuildContext context, {
    required String label,
    required Widget child,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: 76,
        margin: const EdgeInsets.only(right: 10),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: theme.primaryColor.withValues(alpha: 0.5),
                    width: 2),
              ),
              child: ClipOval(
                child: SizedBox(width: 58, height: 58, child: child),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(
      BuildContext context, WidgetRef ref, Map<String, dynamic> h) async {
    final id = h['id'].toString();
    final stories =
        await ref.read(storyServiceProvider).fetchHighlightStories(id);
    if (!context.mounted) return;
    if (stories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This highlight has no stories yet.')),
      );
      return;
    }
    final group = StoryGroup(
      userId: (h['user_id'] ?? '').toString(),
      name: (h['title'] ?? 'Highlight').toString(),
      avatarUrl: (h['cover_url'] ?? '').toString(),
      stories: stories,
      seen: true,
    );
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => StoryViewerScreen(groups: [group], initial: 0),
    ));
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final archive =
        await ref.read(storyServiceProvider).fetchArchive();
    if (!context.mounted) return;
    final result = await showModalBottomSheet<_HighlightDraft>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _HighlightEditorSheet(archive: archive),
    );
    if (result == null) return;
    try {
      await ref.read(storyServiceProvider).createHighlight(
            title: result.title,
            coverUrl: result.coverUrl,
            storyIds: result.storyIds,
          );
      ref.invalidate(storyHighlightsProvider(userId));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not create: $e')));
      }
    }
  }

  Future<void> _manage(
      BuildContext context, WidgetRef ref, Map<String, dynamic> h) async {
    final id = h['id'].toString();
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(LucideIcons.pencil),
              title: const Text('Rename'),
              onTap: () async {
                Navigator.pop(ctx);
                final controller =
                    TextEditingController(text: h['title'].toString());
                final title = await showDialog<String>(
                  context: context,
                  builder: (dctx) => AlertDialog(
                    title: const Text('Rename highlight'),
                    content: TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: const InputDecoration(labelText: 'Title'),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dctx),
                        child: const Text('CANCEL'),
                      ),
                      FilledButton(
                        onPressed: () =>
                            Navigator.pop(dctx, controller.text.trim()),
                        child: const Text('SAVE'),
                      ),
                    ],
                  ),
                );
                if (title == null || title.isEmpty) return;
                try {
                  await ref.read(storyServiceProvider).updateHighlight(
                        id,
                        title: title,
                        coverUrl: (h['cover_url'] ?? '').toString(),
                      );
                  ref.invalidate(storyHighlightsProvider(userId));
                } catch (e) {
                  debugPrint('rename highlight failed: $e');
                }
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.trash2, color: Colors.red),
              title: const Text('Delete',
                  style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  await ref.read(storyServiceProvider).deleteHighlight(id);
                  ref.invalidate(storyHighlightsProvider(userId));
                } catch (e) {
                  debugPrint('delete highlight failed: $e');
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _HighlightDraft {
  final String title;
  final String? coverUrl;
  final List<String> storyIds;
  _HighlightDraft(this.title, this.coverUrl, this.storyIds);
}

class _HighlightEditorSheet extends StatefulWidget {
  final List<Map<String, dynamic>> archive;
  const _HighlightEditorSheet({required this.archive});

  @override
  State<_HighlightEditorSheet> createState() => _HighlightEditorSheetState();
}

class _HighlightEditorSheetState extends State<_HighlightEditorSheet> {
  final _title = TextEditingController();
  final Set<String> _selected = {};

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  String? get _cover {
    if (_selected.isEmpty) return null;
    final first = widget.archive.firstWhere(
      (s) => _selected.contains(s['id'].toString()),
      orElse: () => <String, dynamic>{},
    );
    return (first['thumbnail_url'] ?? first['media_url'])?.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('New highlight',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            maxLength: 30,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Title (e.g. Baptisms 2026)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 4),
          const Text('Pick archived stories',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 8),
          if (widget.archive.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('No archived stories yet.',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
            )
          else
            SizedBox(
              height: 180,
              child: GridView.builder(
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                ),
                itemCount: widget.archive.length,
                itemBuilder: (_, i) {
                  final s = widget.archive[i];
                  final id = s['id'].toString();
                  final thumb = (s['thumbnail_url'] ??
                          (s['media_type'] == 'video' ? '' : s['media_url']))
                      .toString();
                  final on = _selected.contains(id);
                  return GestureDetector(
                    onTap: () => setState(() {
                      if (on) {
                        _selected.remove(id);
                      } else {
                        _selected.add(id);
                      }
                    }),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: thumb.isNotEmpty
                              ? AppImage(thumb, fit: BoxFit.cover)
                              : Container(color: theme.colorScheme.surfaceContainerHighest),
                        ),
                        if (on)
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.black45,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(LucideIcons.check,
                                color: Colors.white),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _title.text.trim().isEmpty
                  ? null
                  : () {
                      Navigator.pop(
                        context,
                        _HighlightDraft(
                          _title.text.trim(),
                          _cover,
                          _selected.toList(),
                        ),
                      );
                    },
              child: const Text('CREATE HIGHLIGHT'),
            ),
          ),
        ],
      ),
    );
  }
}
