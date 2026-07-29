import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/services/r2_service.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/widgets/app_image.dart';

class CreateKlipScreen extends ConsumerStatefulWidget {
  const CreateKlipScreen({super.key});

  @override
  ConsumerState<CreateKlipScreen> createState() => _CreateKlipScreenState();
}

class _CreateKlipScreenState extends ConsumerState<CreateKlipScreen> {
  final _captionCtrl = TextEditingController();
  String? _videoUrl;
  String? _thumbnailUrl;
  int? _durationSeconds;
  bool _isSubmitting = false;
  bool _isUploading = false;
  double _uploadProgress = 0;

  static const _maxDurationSeconds = 30;
  static const _warnDurationSeconds = 25;

  @override
  void dispose() {
    _captionCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final video = await picker.pickVideo(source: ImageSource.gallery);
    if (video == null) return;

    try {
      // Check duration before doing anything expensive
      final mediaInfo = await VideoCompress.getMediaInfo(video.path);
      final durationMs = mediaInfo.duration ?? 0;
      final durationSec = (durationMs / 1000).ceil();

      if (durationSec > _maxDurationSeconds) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Video too long (${durationSec}s). Maximum is ${_maxDurationSeconds}s.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      if (durationSec > _warnDurationSeconds && mounted) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Long Video'),
            content: Text('This video is ${durationSec}s. Klips work best under ${_warnDurationSeconds}s. Continue anyway?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
            ],
          ),
        );
        if (proceed != true) return;
      }

      if (!mounted) return;
      setState(() {
        _isUploading = true;
        _uploadProgress = 0;
      });

      // Compress
      final compressed = await VideoCompress.compressVideo(
        video.path,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false,
      );

      if (compressed == null || compressed.file == null) {
        throw Exception('Compression failed');
      }

      if (!mounted) return;
      setState(() => _uploadProgress = 0.4);

      // Extract thumbnail
      final thumbFile = await VideoCompress.getFileThumbnail(
        video.path,
        quality: 80,
        position: 0,
      );

      if (!mounted) return;
      setState(() => _uploadProgress = 0.6);

      final supabase = Supabase.instance.client;
      final r2 = ref.read(r2ServiceProvider);
      final userId = supabase.auth.currentUser?.id ?? 'anon';
      final ts = DateTime.now().millisecondsSinceEpoch;

      // Upload compressed video
      final ext = compressed.file!.path.split('.').last;
      final videoPath = 'klips/${userId}_$ts.$ext';
      final videoUrl = await r2.uploadFile(compressed.file!, videoPath);
      if (videoUrl == null) throw Exception('R2 upload returned null. Check network connection.');

      if (!mounted) return;
      setState(() => _uploadProgress = 0.85);

      // Upload thumbnail
      String? thumbUrl;
      if (thumbFile.existsSync()) {
        final thumbPath = 'klips/thumbs/${userId}_${ts}_thumb.jpg';
        thumbUrl = await r2.uploadFile(thumbFile, thumbPath);
      }

      if (mounted) {
        setState(() {
          _videoUrl = videoUrl;
          _thumbnailUrl = thumbUrl;
          _durationSeconds = durationSec;
          _isUploading = false;
          _uploadProgress = 0;
        });
      }

      // Cleanup compressed temp files
      await VideoCompress.deleteAllCache();
    } catch (e) {
      debugPrint('Klip upload failed: $e');
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadProgress = 0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Upload failed. Try again.'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _submit() async {
    if (_videoUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a video'), backgroundColor: Colors.red),
      );
      return;
    }
    if (_captionCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add a caption'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final supabase = Supabase.instance.client;
      final profile = ref.read(profileProvider).value;
      final tenant = ref.read(currentTenantProvider);
      await supabase.from('klips').insert({
        'video_url': _videoUrl,
        'thumbnail_url': _thumbnailUrl,
        'description': _captionCtrl.text.trim(),
        'user_id': supabase.auth.currentUser?.id,
        'user_name': profile?.name ?? 'Believer',
        'user_avatar': profile?.avatarUrl,
        'duration': _durationSeconds,
        'amen_count': 0,
        'comments_count': 0,
        if (tenant?.id != null) 'tenant_id': tenant!.id,
      });

      // Notify church members about new Klip
      if (tenant?.id != null) {
        try {
          final authorName = profile?.name ?? 'Someone';
          final caption = _captionCtrl.text.trim();
          final others = await supabase
              .from('profiles')
              .select('id')
              .eq('tenant_id', tenant!.id)
              .neq('id', supabase.auth.currentUser?.id ?? '')
              .limit(500);
          if (others.isNotEmpty) {
            await supabase.functions.invoke('push-notifications', body: {
              'userIds': others.map((o) => o['id'] as String).toList(),
              'title': 'New Klip by $authorName',
              'body': caption.length > 80 ? '${caption.substring(0, 80)}...' : caption,
              'data': {
                'type': 'klip',
                'channel_id': 'coa_klips',
              },
            });
          }
        } catch (e) {
          debugPrint('[CreateKlip] Notification failed: $e');
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Klip created!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Failed to create klip: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).value;
    final canPostKlips = profile?.isLeadershipTeam == true;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Create Klip', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(LucideIcons.x, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: canPostKlips
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _isUploading ? null : _pickVideo,
                    child: Container(
                      height: 300,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: _isUploading
                          ? _buildUploadProgress()
                          : _videoUrl != null
                              ? _buildVideoPreview()
                              : _buildPlaceholder(),
                    ),
                  ),
                  if (_durationSeconds != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.clock, size: 14, color: Colors.white54),
                        const SizedBox(width: 4),
                        Text(
                          '${_durationSeconds}s',
                          style: TextStyle(
                            color: _durationSeconds! > _warnDurationSeconds
                                ? Colors.orangeAccent
                                : Colors.white54,
                            fontSize: 13,
                          ),
                        ),
                        if (_thumbnailUrl != null) ...[
                          const SizedBox(width: 12),
                          Icon(LucideIcons.image, size: 14, color: Colors.greenAccent),
                          const SizedBox(width: 4),
                          const Text('Poster ready', style: TextStyle(color: Colors.greenAccent, fontSize: 13)),
                        ],
                      ],
                    ),
                  ],
                  const SizedBox(height: 24),
                  TextField(
                    controller: _captionCtrl,
                    maxLines: 4,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Write a caption...',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white12,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: _isSubmitting || _videoUrl == null ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD700),
                      minimumSize: const Size(double.infinity, 60),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : const Text('POST KLIP', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black)),
                  ),
                ],
              ),
            )
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.lock, color: Colors.white30, size: 64),
                    const SizedBox(height: 20),
                    const Text(
                      'Klips are for Church Leaders',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Only pastors, bishops, and church leaders can create Klips. You can still view and react to Klips in the feed.',
                      style: TextStyle(color: Colors.white54, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 30),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white12,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                      child: const Text('BACK TO FEED', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildUploadProgress() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(value: _uploadProgress, color: const Color(0xFFFFD700)),
          const SizedBox(height: 16),
          Text(
            _uploadProgress < 0.4
                ? 'Compressing video...'
                : _uploadProgress < 0.85
                    ? 'Uploading video...'
                    : 'Generating poster...',
            style: const TextStyle(color: Colors.white54, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Text(
            '${(_uploadProgress * 100).toInt()}%',
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoPreview() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _thumbnailUrl != null
              ? AppImage(_thumbnailUrl!, fit: BoxFit.cover,
                  errorWidget: (_, __) => const Center(
                    child: Icon(LucideIcons.video, color: Colors.white54, size: 64),
                  ))
              : const Center(child: Icon(LucideIcons.video, color: Colors.white54, size: 64)),
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: () => setState(() {
                _videoUrl = null;
                _thumbnailUrl = null;
                _durationSeconds = null;
              }),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black54),
                child: const Icon(LucideIcons.x, color: Colors.white, size: 18),
              ),
            ),
          ),
          // Play button overlay
          const Center(
            child: Icon(LucideIcons.play, color: Colors.white70, size: 48),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder() {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(LucideIcons.video, color: Colors.white54, size: 64),
        SizedBox(height: 16),
        Text('Tap to select video', style: TextStyle(color: Colors.white54, fontSize: 16)),
        SizedBox(height: 8),
        Text('Max 30 seconds', style: TextStyle(color: Colors.white30, fontSize: 12)),
      ],
    );
  }
}
