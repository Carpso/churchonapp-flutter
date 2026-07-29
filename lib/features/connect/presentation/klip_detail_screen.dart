import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

class KlipDetailScreen extends StatefulWidget {
  final String klipId;
  const KlipDetailScreen({super.key, required this.klipId});

  @override
  State<KlipDetailScreen> createState() => _KlipDetailScreenState();
}

class _KlipDetailScreenState extends State<KlipDetailScreen> {
  VideoPlayerController? _vc;
  Map<String, dynamic>? _klip;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchKlip();
  }

  Future<void> _fetchKlip() async {
    try {
      final data = await Supabase.instance.client
          .from('klips')
          .select('id, video_url, url, description, caption')
          .eq('id', widget.klipId)
          .maybeSingle();
      if (data != null) {
        setState(() => _klip = data);
        _initVideo();
      }
    } catch (e) {
      debugPrint('Failed to fetch klip: $e');
    }
    setState(() => _isLoading = false);
  }

  void _initVideo() {
    final url = _klip?['video_url'] ?? _klip?['url'] as String?;
    if (url != null && url.isNotEmpty) {
      _vc = VideoPlayerController.networkUrl(Uri.parse(url))
        ..initialize().then((_) {
          if (mounted) {
            setState(() {});
            _vc?.play();
            _vc?.setLooping(true);
          }
        }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _vc?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text("Klip", style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.amber))
          : _klip == null
              ? const Center(child: Text("Klip not found", style: TextStyle(color: Colors.white)))
              : Center(
                  child: _vc != null && _vc!.value.isInitialized
                      ? AspectRatio(aspectRatio: _vc!.value.aspectRatio, child: VideoPlayer(_vc!))
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(LucideIcons.video, size: 64, color: Colors.white54),
                            const SizedBox(height: 16),
                            Text(
                              _klip!['description'] ?? _klip!['caption'] ?? '',
                              style: const TextStyle(color: Colors.white, fontSize: 16),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                ),
    );
  }
}
