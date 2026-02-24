import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/media_service.dart';

class KingdomKlipsScreen extends ConsumerStatefulWidget {
  const KingdomKlipsScreen({super.key});

  @override
  ConsumerState<KingdomKlipsScreen> createState() => _KingdomKlipsScreenState();
}

class _KingdomKlipsScreenState extends ConsumerState<KingdomKlipsScreen> {
  final PageController _pageController = PageController();

  @override
  Widget build(BuildContext context) {
    final klipsAsync = ref.watch(klipsStreamProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: klipsAsync.when(
        data: (klips) {
          if (klips.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(LucideIcons.videoOff, color: Colors.white24, size: 80),
                  const SizedBox(height: 16),
                  const Text("No Klips yet", style: TextStyle(color: Colors.white)),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => ref.read(mediaServiceProvider).seedMedia(),
                    child: const Text("Seed Demo Content"),
                  )
                ],
              ),
            );
          }
          return PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            itemCount: klips.length,
            onPageChanged: (index) {
              ref.read(mediaServiceProvider).logKlipView(klips[index].id);
            },
            itemBuilder: (context, index) {
              final klip = klips[index];
              return KlipPlayer(
                url: klip.videoUrl,
                title: klip.title,
                speaker: klip.speaker ?? "Kingdom Member",
                description: klip.description ?? "",
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFFFD700))),
        error: (e, s) => Center(child: Text("Error loading klips: $e", style: const TextStyle(color: Colors.white))),
      ),
    );
  }
}

class KlipPlayer extends StatefulWidget {
  final String url;
  final String title;
  final String speaker;
  final String description;

  const KlipPlayer({
    super.key, 
    required this.url,
    required this.title,
    required this.speaker,
    required this.description,
  });

  @override
  State<KlipPlayer> createState() => _KlipPlayerState();
}

class _KlipPlayerState extends State<KlipPlayer> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        setState(() {});
        _controller.play();
        _controller.setLooping(true);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (_controller.value.isInitialized)
          SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _controller.value.size.width,
                height: _controller.value.size.height,
                child: VideoPlayer(_controller),
              ),
            ),
          )
        else
          const Center(child: CircularProgressIndicator(color: Color(0xFFFFD700))),

        // UI Overlay
        Positioned(
          top: 40,
          left: 20,
          child: IconButton(
            icon: const Icon(LucideIcons.arrowLeft, color: Colors.white, size: 30),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        
        Positioned(
          bottom: 20,
          right: 20,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildInteractionButton(LucideIcons.heart, "12K"),
              _buildInteractionButton(LucideIcons.messageCircle, "400"),
              _buildInteractionButton(LucideIcons.share2, "Share"),
              const SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFFFD700), width: 2),
                ),
                child: const CircleAvatar(
                  radius: 20,
                  backgroundImage: NetworkImage('https://i.pravatar.cc/150?img=33'),
                ),
              ),
            ],
          ),
        ),

        Positioned(
          bottom: 20,
          left: 20,
          right: 80,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "@${widget.speaker.replaceAll(' ', '_').toLowerCase()}",
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                "${widget.title}: ${widget.description}",
                style: const TextStyle(color: Colors.white, fontSize: 14),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(LucideIcons.music, color: Colors.white, size: 14),
                  const SizedBox(width: 8),
                  Text(
                    "Original Sound - Kingdom Worship",
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInteractionButton(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 35),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
