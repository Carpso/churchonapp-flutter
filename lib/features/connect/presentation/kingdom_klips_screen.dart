import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:animations/animations.dart';
// Theme imported via context

class KingdomKlipsScreen extends StatefulWidget {
  const KingdomKlipsScreen({super.key});

  @override
  State<KingdomKlipsScreen> createState() => _KingdomKlipsScreenState();
}

class _KingdomKlipsScreenState extends State<KingdomKlipsScreen> {
  late PageController _pageController;

  final List<Map<String, String>> _mockVideos = [
    {
      'url': 'https://assets.mixkit.co/videos/preview/mixkit-pastor-preaching-at-a-church-service-34538-large.mp4',
      'author': '@pastor_hope',
      'caption': 'God has a plan for your journey. Stay faithful! 🙏✨ #Faith #Grace',
    },
    {
      'url': 'https://assets.mixkit.co/videos/preview/mixkit-people-praying-in-a-church-34537-large.mp4',
      'author': '@worship_unity',
      'caption': 'Power in corporate prayer. The Spirit is moving! 🕊️',
    },
    {
      'url': 'https://assets.mixkit.co/videos/preview/mixkit-close-up-of-a-bible-being-read-34539-large.mp4',
      'author': '@bible_study_hub',
      'caption': 'Psalm 23: The Lord is my Shepherd. Mediate on this today.',
    },
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: _mockVideos.length,
        itemBuilder: (context, index) {
          return VideoClipPlayer(
            videoUrl: _mockVideos[index]['url']!,
            author: _mockVideos[index]['author']!,
            caption: _mockVideos[index]['caption']!,
          );
        },
      ),
    );
  }
}

class VideoClipPlayer extends StatefulWidget {
  final String videoUrl;
  final String author;
  final String caption;

  const VideoClipPlayer({
    super.key, 
    required this.videoUrl,
    required this.author,
    required this.caption,
  });

  @override
  State<VideoClipPlayer> createState() => _VideoClipPlayerState();
}

class _VideoClipPlayerState extends State<VideoClipPlayer> with SingleTickerProviderStateMixin {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _showAmen = false;
  int _amenCount = 1450;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        setState(() {
          _isInitialized = true;
          _controller.play();
          _controller.setLooping(true);
        });
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    setState(() {
      _showAmen = true;
      _amenCount++;
    });
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _showAmen = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Center(child: CircularProgressIndicator(color: Theme.of(context).primaryColor));
    }

    return GestureDetector(
      onDoubleTap: _handleDoubleTap,
      onTap: () {
        if (_controller.value.isPlaying) {
          _controller.pause();
        } else {
          _controller.play();
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: VideoPlayer(_controller),
            ),
          ),
          // Gradient Overlay
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.3),
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black.withOpacity(0.6),
                ],
              ),
            ),
          ),
          // Amen Burst Animation
          if (_showAmen)
            Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.2),
                duration: const Duration(milliseconds: 300),
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: value,
                    child: Icon(LucideIcons.flame, color: Theme.of(context).primaryColor, size: 100),
                  );
                },
              ),
            ),
          // Content Overlay
          Positioned(
            bottom: 40,
            left: 20,
            right: 80,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: Theme.of(context).primaryColor,
                      child: CircleAvatar(radius: 18, backgroundImage: NetworkImage("https://i.pravatar.cc/100")),
                    ),
                    const SizedBox(width: 12),
                    Text(widget.author, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Theme.of(context).primaryColor, borderRadius: BorderRadius.circular(4)),
                      child: Text("FAITHFUL", style: TextStyle(color: Theme.of(context).colorScheme.secondary, fontSize: 8, fontWeight: FontWeight.w900)),
                    )
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  widget.caption,
                  style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Right Actions (Icons)
          Positioned(
            right: 15,
            bottom: 40,
            child: Column(
              children: [
                _buildActionIcon(LucideIcons.flame, _amenCount.toString(), color: Theme.of(context).primaryColor),
                const SizedBox(height: 25),
                _buildActionIcon(LucideIcons.messageSquare, "152"),
                const SizedBox(height: 25),
                _buildActionIcon(LucideIcons.share2, "Share"),
                const SizedBox(height: 25),
                _buildActionIcon(LucideIcons.moreVertical, ""),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionIcon(IconData icon, String label, {Color color = Colors.white}) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 28),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
