import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:audio_service/audio_service.dart';
import '../data/radio_service.dart';
import 'package:church_on_app/core/providers/audio_provider.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:church_on_app/core/widgets/app_image.dart';
import 'dart:math' as math;

class RadioScreen extends ConsumerStatefulWidget {
  const RadioScreen({super.key});

  @override
  ConsumerState<RadioScreen> createState() => _RadioScreenState();
}

class _RadioScreenState extends ConsumerState<RadioScreen> with SingleTickerProviderStateMixin {
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
    final radioService = ref.watch(radioServiceProvider);
    final profile = ref.watch(profileProvider).value;
    final handler = ref.watch(audioHandlerProvider);

    final metadataAsync = ref.watch(radioMetadataProvider(_selectedStationName));
    final currentTrack = metadataAsync.value ?? "Fetching Live Stream...";

    return StreamBuilder<PlaybackState>(
      stream: handler?.playbackState ?? Stream.value(PlaybackState()),
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
                      _buildStationDirectory(radioService, _selectedStationName, profile),
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
      title: const Text("RADIO", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 16)),
      centerTitle: true,
      actions: [
        IconButton(icon: const Icon(LucideIcons.share2), onPressed: () => SharePlus.instance.share(ShareParams(text: 'Tune in to $_selectedStationName on Radio!'))),
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
          Text(playing ? "LIVE STREAMING" : "OFFLINE", style: TextStyle(color: playing ? Colors.red : Colors.grey, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
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
              child: AppImage(
                '',
                fit: BoxFit.cover,
                color: Colors.black38,
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
              style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2),
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
        IconButton(icon: const Icon(LucideIcons.volumeX, color: Colors.white54), onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Volume control coming soon")))),
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
        IconButton(icon: const Icon(LucideIcons.messageSquare, color: Colors.white54), onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Radio chat coming soon")))),
      ],
    );
  }

  Future<void> _showAddStationDialog() async {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final locCtrl = TextEditingController();
    bool isPrivate = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text("Add New Frequency", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: "Station Name",
                    labelStyle: TextStyle(color: Colors.white60),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.amber)),
                  ),
                ),
                TextField(
                  controller: urlCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: "Stream URL",
                    labelStyle: TextStyle(color: Colors.white60),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.amber)),
                  ),
                ),
                TextField(
                  controller: locCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: "Location / Country",
                    labelStyle: TextStyle(color: Colors.white60),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.amber)),
                  ),
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    Theme(
                      data: ThemeData(unselectedWidgetColor: Colors.white60),
                      child: Checkbox(
                        value: isPrivate,
                        activeColor: Colors.amber,
                        checkColor: Colors.black,
                        onChanged: (val) {
                          setDialogState(() => isPrivate = val ?? false);
                        },
                      ),
                    ),
                    const Text("Private Station (Coming Soon)", style: TextStyle(color: Colors.white70)),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("CANCEL", style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.isEmpty || urlCtrl.text.isEmpty || locCtrl.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("All fields are required"), backgroundColor: Colors.red),
                  );
                  return;
                }
                try {
                  await ref.read(radioServiceProvider).addStation(
                    name: nameCtrl.text.trim(),
                    streamUrl: urlCtrl.text.trim(),
                    location: locCtrl.text.trim(),
                    isPrivate: isPrivate,
                  );
                  ref.invalidate(radioStationsFutureProvider);
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Frequency added successfully! 📻"), backgroundColor: Colors.green),
                    );
                  }
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
              child: const Text("ADD STATION"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStationDirectory(RadioService service, String selectedName, UserProfile? profile) {
    final stationsAsync = ref.watch(radioStationsFutureProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 25),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("FREQUENCIES", style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2)),
              if (profile?.isSuperadmin == true || profile?.role == 'coa_employee')
                TextButton.icon(
                  onPressed: () => _showAddStationDialog(),
                  icon: const Icon(LucideIcons.plus, size: 14, color: Colors.amber),
                  label: const Text("ADD FREQUENCY", style: TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 180,
          child: stationsAsync.when(
            data: (stations) {
              if (stations.isEmpty) {
                return const Center(child: Text("No frequencies found.", style: TextStyle(color: Colors.white38)));
              }
              return ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: stations.length,
                itemBuilder: (context, index) {
                  final station = stations[index];
                  final isCurrent = selectedName == station.name;
                  return GestureDetector(
                    onTap: () {
                      if (station.isPrivate) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Coming Soon 📻"),
                            backgroundColor: Colors.amber,
                          ),
                        );
                        return;
                      }
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
                            child: Icon(
                              station.isPrivate ? LucideIcons.lock : LucideIcons.radio, 
                              color: isCurrent ? Colors.black : Colors.amber, 
                              size: 20,
                            ),
                          ),
                          const Spacer(),
                          Text(station.name, style: TextStyle(color: isCurrent ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 14), maxLines: 2),
                          const SizedBox(height: 5),
                          Text(
                            station.isPrivate ? "PRIVATE" : station.location, 
                            style: TextStyle(color: isCurrent ? Colors.black54 : Colors.white38, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
             loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => Center(child: Text("Error: $err", style: const TextStyle(color: Colors.red))),
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
        "COA Radio provides a sovereign gateway to high-fidelity spiritual broadcasts from across Zambia. Content provided by third-party partners.",
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white30, fontSize: 11, height: 1.5),
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

