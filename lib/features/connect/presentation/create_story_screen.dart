import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/services/r2_service.dart';
import 'package:church_on_app/core/services/supabase_service.dart';
import 'package:church_on_app/core/widgets/kael_explain_sheet.dart';
import 'package:church_on_app/features/connect/data/story_service.dart';

/// Post a 24-hour story to Church Social.
///
/// Bytes-based upload (works on web too), archived to R2, then a row in
/// `social_stories`. After posting, the story appears in the stories bar.
class CreateStoryScreen extends ConsumerStatefulWidget {
  const CreateStoryScreen({super.key});

  @override
  ConsumerState<CreateStoryScreen> createState() => _CreateStoryScreenState();
}

class _CreateStoryScreenState extends ConsumerState<CreateStoryScreen> {
  final _caption = TextEditingController();
  final _picker = ImagePicker();

  XFile? _file;
  bool _isVideo = false;
  bool _isPublic = false;
  bool _busy = false;
  int _durationHours = 24;

  bool get _isCustomDuration =>
      !kStoryDurationOptions.any((o) => o.hours == _durationHours);

  String get _durationLabel {
    final match =
        kStoryDurationOptions.where((o) => o.hours == _durationHours);
    if (match.isNotEmpty) return match.first.label;
    if (_durationHours % 24 == 0) return '${_durationHours ~/ 24} day(s)';
    return '$_durationHours hours';
  }

  Future<void> _pickCustomDuration() async {
    var days = (_durationHours / 24).clamp(1, 365).toDouble();
    final picked = await showDialog<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Custom duration'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${days.round()} day(s) — up to 1 year',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Slider(
                value: days,
                min: 1,
                max: 365,
                divisions: 364,
                label: '${days.round()} days',
                onChanged: (v) => setLocal(() => days = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(days),
              child: const Text('USE'),
            ),
          ],
        ),
      ),
    );
    if (picked != null) {
      setState(() {
        _durationHours =
            (picked * 24).round().clamp(1, kStoryMaxHours).toInt();
      });
    }
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source, {required bool video}) async {
    try {
      final picked = video
          ? await _picker.pickVideo(source: source)
          : await _picker.pickImage(source: source, imageQuality: 85);
      if (picked == null) return;
      setState(() {
        _file = picked;
        _isVideo = video;
      });
    } catch (e) {
      debugPrint('story pick failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not pick media: $e')),
        );
      }
    }
  }

  /// Opens Kael AI to draft a story caption; the user COPIES or INSERTs it.
  void _draftCaptionWithKael() {
    showKaelExplainSheet(
      context,
      action: 'caption',
      title: 'Kael AI caption drafts',
      insertLabel: 'USE THIS',
      prompt:
          'Write one short, uplifting caption for a 24-hour church photo/video story. '
          'Keep it under 140 characters, warm and encouraging, with light emojis. Return only the caption text.',
      onInsert: (text) => setState(() => _caption.text = text),
    );
  }

  Future<void> _post() async {
    final file = _file;
    if (file == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a photo or video first.')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final client = ref.read(supabaseServiceProvider).client;
      final r2 = R2Service(client);
      final uid = client.auth.currentUser?.id;
      if (uid == null) throw Exception('Not authenticated');

      final bytes = await file.readAsBytes();
      final name = file.name;
      final ext = name.contains('.') ? name.split('.').last.toLowerCase() : 'jpg';
      final path =
          'social/story_${DateTime.now().millisecondsSinceEpoch}.$ext';

      final url = await r2.uploadBytes(
        bytes,
        path,
        contentType: _isVideo ? 'video/mp4' : 'image/jpeg',
      );
      if (url == null || url.isEmpty) {
        throw Exception('Upload failed. Please try again.');
      }

      await client.from('social_stories').insert({
        'user_id': uid,
        'tenant_id': ref.read(profileProvider).value?.tenantId,
        'media_url': url,
        'media_type': _isVideo ? 'video' : 'image',
        'caption': _caption.text.trim().isEmpty ? null : _caption.text.trim(),
        'is_public': _isPublic,
        'duration_hours': _durationHours,
      });

      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Story posted — live for $_durationLabel'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not post story: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Story'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _post,
            child: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('POST',
                    style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Preview
          Container(
            height: 300,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.4)),
            ),
            clipBehavior: Clip.antiAlias,
            child: _file == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.imagePlus,
                            size: 44, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        const Text('Pick a photo or video for your story',
                            style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  )
                : _isVideo
                    ? const Center(
                        child: Icon(LucideIcons.video,
                            size: 52, color: Colors.white54),
                      )
                    : FutureBuilder(
                        future: _file!.readAsBytes(),
                        builder: (c, s) {
                          if (!s.hasData) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }
                          return Image.memory(
                            s.data!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                          );
                        },
                      ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _pick(ImageSource.camera, video: false),
                  icon: const Icon(LucideIcons.camera, size: 18),
                  label: const Text('CAMERA'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _pick(ImageSource.gallery, video: false),
                  icon: const Icon(LucideIcons.image, size: 18),
                  label: const Text('GALLERY'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _pick(ImageSource.gallery, video: true),
                  icon: const Icon(LucideIcons.video, size: 18),
                  label: const Text('VIDEO'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _caption,
            maxLines: 3,
            maxLength: 200,
            decoration: const InputDecoration(
              labelText: 'Caption (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _busy ? null : _draftCaptionWithKael,
              icon: const Icon(LucideIcons.sparkles, size: 16, color: Colors.amber),
              label: const Text(
                'Draft with Kael',
                style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ),
          SwitchListTile(
            value: _isPublic,
            onChanged: (v) => setState(() => _isPublic = v),
            title: const Text('Share beyond my church',
                style: TextStyle(fontSize: 14)),
            subtitle: const Text(
              'Off = only your church sees this story. On = it also shows in the global feed.',
              style: TextStyle(fontSize: 11),
            ),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),
          const Text('How long should this story last?',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final o in kStoryDurationOptions)
                ChoiceChip(
                  label: Text(o.label),
                  selected: _durationHours == o.hours,
                  onSelected: _busy
                      ? null
                      : (_) => setState(() => _durationHours = o.hours),
                ),
              ChoiceChip(
                label: Text(_isCustomDuration
                    ? 'Custom: $_durationLabel'
                    : 'Custom'),
                selected: _isCustomDuration,
                onSelected: _busy ? null : (_) => _pickCustomDuration(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Stories disappear automatically after $_durationLabel '
            '(24h is the default).',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
