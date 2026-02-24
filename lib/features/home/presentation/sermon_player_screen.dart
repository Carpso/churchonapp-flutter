import 'package:flutter/material.dart';
import 'package:chewie/chewie.dart';
import 'package:video_player/video_player.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../connect/data/social_service.dart';
// Theme via context
import '../data/sermon_service.dart';
import 'sermon_notes_screen.dart';

class SermonPlayerScreen extends ConsumerStatefulWidget {
  final Sermon sermon;
  const SermonPlayerScreen({super.key, required this.sermon});

  @override
  ConsumerState<SermonPlayerScreen> createState() => _SermonPlayerScreenState();
}

class _SermonPlayerScreenState extends ConsumerState<SermonPlayerScreen> {
  late VideoPlayerController _videoController;
  ChewieController? _chewieController;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    _videoController = VideoPlayerController.networkUrl(Uri.parse(widget.sermon.videoUrl));
    await _videoController.initialize();

    _chewieController = ChewieController(
      videoPlayerController: _videoController,
      autoPlay: true,
      looping: false,
      aspectRatio: _videoController.value.aspectRatio,
      placeholder: Image.network(widget.sermon.thumbnailUrl, fit: BoxFit.cover),
      materialProgressColors: ChewieProgressColors(
        playedColor: Theme.of(context).primaryColor,
        handleColor: Theme.of(context).primaryColor,
        backgroundColor: Colors.grey.withValues(alpha: 0.5),
        bufferedColor: Colors.white.withValues(alpha: 0.3),
      ),
    );
    setState(() {});
  }

  @override
  void dispose() {
    _videoController.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPlayer(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(25),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.sermon.title,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.secondary),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      CircleAvatar(radius: 12, backgroundColor: Theme.of(context).primaryColor, child: const Icon(LucideIcons.user, size: 14)),
                      const SizedBox(width: 8),
                      Text(widget.sermon.preacher, style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor)),
                      const Spacer(),
                      const Icon(LucideIcons.calendar, size: 14, color: Colors.grey),
                      const SizedBox(width: 5),
                      Text(
                        "${widget.sermon.createdAt.day}/${widget.sermon.createdAt.month}/${widget.sermon.createdAt.year}",
                        style: const TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  _buildActionRow(),
                  const SizedBox(height: 30),
                  const Text(
                    "Description",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "Discover the spiritual foundations of stewardship and how to manage the blessings of the Kingdom in this powerful message. Pastor John explores the biblical principles of faith and finance.",
                    style: TextStyle(color: Colors.grey, height: 1.6),
                  ),
                  const SizedBox(height: 30),
                  _buildApostolicArchive(),
                  const SizedBox(height: 30),
                  _buildRecommendedSection(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayer() {
    if (_chewieController != null && _chewieController!.videoPlayerController.value.isInitialized) {
      return Stack(
        children: [
          AspectRatio(
            aspectRatio: _videoController.value.aspectRatio,
            child: Chewie(controller: _chewieController!),
          ),
          if (widget.sermon.isLive)
            Positioned(
              top: 40,
              left: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    const Icon(LucideIcons.radio, color: Colors.white, size: 14),
                    const SizedBox(width: 8),
                    const Text("LIVE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(width: 12),
                    const Icon(LucideIcons.eye, color: Colors.white, size: 14),
                    const SizedBox(width: 4),
                    Text("${widget.sermon.viewerCount}", style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ],
                ),
              ),
            ),
        ],
      );
    } else {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          color: Colors.black,
          child: Center(child: CircularProgressIndicator(color: Theme.of(context).primaryColor)),
        ),
      );
    }
  }

  Widget _buildActionRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildActionItem(LucideIcons.heart, "Amen", onTap: () async {
          // In a real app, this would use the social service to like a linked post
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Amen! Seed of faith received.")));
        }),
        _buildActionItem(LucideIcons.messageSquare, "Discuss", onTap: () {
          _showComments();
        }),
        _buildActionItem(LucideIcons.share2, "Forward", onTap: () {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Sharing spiritual wisdom...")));
        }),
        _buildActionItem(LucideIcons.bookOpen, "Notes", onTap: () {
          Navigator.push(context, MaterialPageRoute(builder: (context) => const SermonNotesScreen()));
        }),
      ],
    );
  }

  void _showComments() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
        padding: const EdgeInsets.all(25),
        child: Column(
          children: [
            const Text("Communal Insights", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const Divider(height: 40),
            const Expanded(child: Center(child: Text("Join the spiritual conversation. First insight pending..."))),
            Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: TextField(
                decoration: InputDecoration(
                  hintText: "Add your spiritual insight...",
                  suffixIcon: const Icon(LucideIcons.send),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionItem(IconData icon, String label, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: Colors.grey.withValues(alpha: 0.1))),
            child: Icon(icon, color: Theme.of(context).colorScheme.secondary, size: 22),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildRecommendedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
         const Text("More from this Series", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
         const SizedBox(height: 20),
         _buildRecommendedItem("Part 1: The Covenant of Plenty", "12:45"),
         _buildRecommendedItem("Part 2: Kingdom Multipliers", "15:20"),
      ],
    );
  }

  Widget _buildRecommendedItem(String title, String duration) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
      child: Row(
        children: [
          Container(
            width: 80,
            height: 50,
            decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(10)),
            child: const Icon(LucideIcons.play, size: 20),
          ),
          const SizedBox(width: 15),
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold))),
          Text(duration, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildApostolicArchive() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Apostolic Archive", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 15),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(LucideIcons.sparkles, color: Colors.amber, size: 18),
                  const SizedBox(width: 10),
                  const Text("AI Summary", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                widget.sermon.aiSummary ?? "This sermon explores the foundational principles of Kingdom stewardship, emphasizing faithfulness and spiritual multiplier effects in everyday life.",
                style: const TextStyle(color: Colors.grey, fontSize: 13, height: 1.5),
              ),
              const Divider(height: 30),
              Row(
                children: [
                  const Icon(LucideIcons.fileText, color: Colors.blue, size: 18),
                  const SizedBox(width: 10),
                  const Text("Full Transcription", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _showFullTranscript(),
                    child: const Text("VIEW FULL", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                widget.sermon.transcript?.substring(0, 200) ?? "In the beginning of this profound message, Pastor John Doe invites us to consider the ultimate source of all our blessings. He reminds us that true prosperity is not measured solely by material wealth, but by our capacity to be faithful stewards of what the Kingdom has entrusted to us...",
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.grey, fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showFullTranscript() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.fromLTRB(25, 40, 25, 25),
        child: Column(
          children: [
            Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(5))),
            const SizedBox(height: 25),
            Row(
              children: [
                const Icon(LucideIcons.fileText, color: Colors.blue),
                const SizedBox(width: 15),
                const Text("Sermon Transcription", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  widget.sermon.transcript ?? "Transcription pending... In the beginning of this profound message, Pastor John Doe invites us to consider the ultimate source of all our blessings. He reminds us that true prosperity is not measured solely by material wealth, but by our capacity to be faithful stewards of what the Kingdom has entrusted to us. As we dive into the Word today, let us open our hearts to the multiplier effect that comes from a life fully surrendered to spiritual service. It's about being a conduit for grace, not just a reservoir. (Complete archive available on the Kingdom VPS)",
                  style: const TextStyle(height: 1.8, color: Colors.black87),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
