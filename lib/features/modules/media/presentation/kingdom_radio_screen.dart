import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:audio_service/audio_service.dart';
import '../data/radio_service.dart';
import 'package:church_on_app/core/providers/audio_provider.dart';
import 'dart:math' as math;

class KingdomRadioScreen extends ConsumerStatefulWidget {
  const KingdomRadioScreen({super.key});

  @override
  ConsumerState<KingdomRadioScreen> createState() => _KingdomRadioScreenState();
}

class _KingdomRadioScreenState extends ConsumerState<KingdomRadioScreen> with SingleTickerProviderStateMixin {
  late AnimationController _visualizerController;
  String _selectedStationName = "Radio Christian Voice";

  @override
  void initState() {
    super.initState();
    _visualizerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _visualizerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radioService = ref.read(radioServiceProvider);
    final audioHandler = ref.watch(audioHandlerProvider);
    final metadataAsync = ref.watch(radioMetadataProvider(_selectedStationName));
    final currentTrack = metadataAsync.value ?? "Fetching Live Stream...";

    return StreamBuilder<PlaybackState>(
      stream: audioHandler.playbackState,
      builder: (context, snapshot) {
        final playing = snapshot.data?.playing ?? false;

        return Scaffold(
          backgroundColor: const Color(0xFF0F172A), // Premium Dark Deep Blue
          body: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.3),
                radius: 1.5,
                colors: [
                  Theme.of(context).primaryColor.withValues(alpha: 0.1),
                  const Color(0xFF0F172A),
                ],
              ),
            ),
            child: CustomScrollView(
              slivers: [
                _buildSliverAppBar(),
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      _buildLiveIndicator(playing),
                      const SizedBox(height: 40),
                      _buildVisualizerHub(playing),
                      const SizedBox(height: 50),
                      _buildNowPlayingInfo(_selectedStationName, currentTrack),
                      const SizedBox(height: 50),
                      _buildMainControls(playing, radioService),
                      const SizedBox(height: 60),
                      _buildStationDirectory(radioService, _selectedStationName),
                      _buildDisclaimer(),
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      backgroundColor: Colors.transparent,
      floating: true,
      elevation: 0,
      title: const Text("KINGDOM RADIO", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 16)),
      centerTitle: true,
      actions: [
        IconButton(icon: const Icon(LucideIcons.share2), onPressed: () {}),
      ],
    );
  }

  Widget _buildLiveIndicator(bool playing) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: playing ? Colors.red.withValues(alpha: 0.1) : Colors.white10,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: playing ? Colors.red.withValues(alpha: 0.5) : Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              color: playing ? Colors.red : Colors.grey,
              shape: BoxShape.circle,
              boxShadow: playing ? [BoxShadow(color: Colors.red, blurRadius: 10)] : [],
            ),
          ),
          const SizedBox(width: 8),
          Text(playing ? "LIVE STREAMING" : "OFFLINE", style: TextStyle(color: playing ? Colors.red : Colors.grey, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
        ],
      ),
    );
  }

  Widget _buildVisualizerHub(bool playing) {
    return SizedBox(
      height: 300,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (playing)
            AnimatedBuilder(
              animation: _visualizerController,
              builder: (context, child) {
                return CustomPaint(
                  size: const Size(280, 280),
                  painter: VisualizerPainter(_visualizerController.value),
                );
              },
            ),
          Container(
            width: 220, height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 30, spreadRadius: 5),
                if (playing) BoxShadow(color: Theme.of(context).primaryColor.withValues(alpha: 0.3), blurRadius: 60, spreadRadius: 10),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(110),
              child: Image.network(
                "https://images.unsplash.com/photo-1598488035139-bdbb2231ce04?q=80&w=2070&auto=format&fit=crop",
                fit: BoxFit.cover,
                color: Colors.black38,
                colorBlendMode: BlendMode.darken,
              ),
            ),
          ),
          if (!playing)
            const Icon(LucideIcons.radio, color: Colors.white24, size: 80),
        ],
      ),
    );
  }

  Widget _buildNowPlayingInfo(String station, String track) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        children: [
          Text(station, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10)),
            child: Text(
              track.toUpperCase(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainControls(bool playing, RadioService service) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(icon: const Icon(LucideIcons.volumeX, color: Colors.white54), onPressed: () {}),
        const SizedBox(width: 30),
        GestureDetector(
          onTap: () => playing ? service.pause() : service.play(),
          child: Container(
            width: 90, height: 90,
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Theme.of(context).primaryColor.withValues(alpha: 0.4), blurRadius: 30, offset: const Offset(0, 10))],
            ),
            child: Icon(playing ? LucideIcons.pause : LucideIcons.play, color: Colors.black, size: 40),
          ),
        ),
        const SizedBox(width: 30),
        IconButton(icon: const Icon(LucideIcons.messageSquare, color: Colors.white54), onPressed: () {}),
      ],
    );
  }

  Widget _buildStationDirectory(RadioService service, String selectedName) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 25),
          child: Text("KINGDOM FREQUENCIES", style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: service.stations.length,
            itemBuilder: (context, index) {
              final station = service.stations[index];
              final isCurrent = selectedName == station.name;
              return GestureDetector(
                onTap: () {
                  setState(() => _selectedStationName = station.name);
                  service.playStation(station);
                },
                child: Container(
                  width: 160,
                  margin: const EdgeInsets.only(right: 15),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isCurrent ? Theme.of(context).primaryColor : Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(color: isCurrent ? Colors.transparent : Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: isCurrent ? Colors.black12 : Colors.white10, shape: BoxShape.circle),
                        child: Icon(LucideIcons.radio, color: isCurrent ? Colors.black : Colors.amber, size: 20),
                      ),
                      const Spacer(),
                      Text(station.name, style: TextStyle(color: isCurrent ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 14), maxLines: 2),
                      const SizedBox(height: 5),
                      Text(station.location, style: TextStyle(color: isCurrent ? Colors.black54 : Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDisclaimer() {
    return Container(
      margin: const EdgeInsets.all(25),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: const Text(
        "COA Radio provides a sovereign gateway to high-fidelity spiritual broadcasts from across Zambia. Content provided by third-party Kingdom partners.",
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white30, fontSize: 10, height: 1.5),
      ),
    );
  }
}

class VisualizerPainter extends CustomPainter {
  final double animationValue;
  VisualizerPainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = Colors.amber.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    for (int i = 0; i < 60; i++) {
      final angle = (i * 6 * math.pi / 180) + (animationValue * 2 * math.pi);
      final h = 10 + math.sin(animationValue * 5 + i) * 30;
      final start = Offset(
        center.dx + 115 * math.cos(angle),
        center.dy + 115 * math.sin(angle),
      );
      final end = Offset(
        center.dx + (115 + h) * math.cos(angle),
        center.dy + (115 + h) * math.sin(angle),
      );
      canvas.drawLine(start, end, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
