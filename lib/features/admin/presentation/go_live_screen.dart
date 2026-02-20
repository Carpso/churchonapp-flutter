import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../home/data/live_streaming_service.dart';
import '../../../core/services/tenant_service.dart';

class GoLiveScreen extends ConsumerStatefulWidget {
  const GoLiveScreen({super.key});

  @override
  ConsumerState<GoLiveScreen> createState() => _GoLiveScreenState();
}

class _GoLiveScreenState extends ConsumerState<GoLiveScreen> {
  final _urlController = TextEditingController(text: "rtmp://vps.church-on-app.com/live");
  final _titleController = TextEditingController(text: "Sunday Morning Service");
  bool _isBroadcasting = false;

  void _toggleLive() async {
    final tenant = ref.read(currentTenantProvider);
    if (tenant == null) return;

    setState(() => _isBroadcasting = !_isBroadcasting);

    // Update VPS orientation in Supabase
    await ref.read(liveStreamingServiceProvider).setLiveStatus(
      tenant.id, 
      _isBroadcasting,
      streamUrl: "https://vps.church-on-app.com/hls/stream.m3u8", // HLS endpoint for players
      title: _titleController.text,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isBroadcasting ? "Streaming to VPS Started!" : "Broadcast Ended"),
        backgroundColor: _isBroadcasting ? Colors.green : Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Kingdom Live Studio", style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: BorderRadius.circular(30),
                image: const DecorationImage(
                  image: NetworkImage("https://images.unsplash.com/photo-1516280440614-37939bbacd81?w=800&q=80"),
                  fit: BoxFit.cover,
                  opacity: 0.3,
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_isBroadcasting)
                      const Icon(LucideIcons.radio, color: Colors.red, size: 80)
                    else
                      const Icon(LucideIcons.video, color: Colors.white24, size: 80),
                    const SizedBox(height: 20),
                    Text(
                      _isBroadcasting ? "BROADCASTING LIVE" : "READY TO STREAM",
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(30),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("VPS CONFIGURATION", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1.5, color: Colors.grey)),
                const SizedBox(height: 15),
                _buildInput("Stream Title", _titleController, LucideIcons.type),
                const SizedBox(height: 15),
                _buildInput("RTMP Endpoint", _urlController, LucideIcons.server),
                const SizedBox(height: 30),
                ElevatedButton(
                  onPressed: _toggleLive,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isBroadcasting ? Colors.red : const Color(0xFFFFD700),
                    minimumSize: const Size(double.infinity, 65),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(_isBroadcasting ? LucideIcons.square : LucideIcons.play, color: Colors.black),
                      const SizedBox(width: 15),
                      Text(
                        _isBroadcasting ? "STOP BROADCAST" : "START LIVE STREAM",
                        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 15),
                const Center(
                  child: Text("All media will be automatically archived to R2", style: TextStyle(color: Colors.grey, fontSize: 11)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInput(String label, TextEditingController controller, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(20)),
      child: TextField(
        controller: controller,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          icon: Icon(icon, size: 18, color: Colors.grey),
          labelText: label,
          labelStyle: const TextStyle(fontSize: 12),
          border: InputBorder.none,
        ),
      ),
    );
  }
}
