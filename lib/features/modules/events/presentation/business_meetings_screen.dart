import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

class BusinessMeetingsScreen extends StatefulWidget {
  final String meetingTitle;
  const BusinessMeetingsScreen({super.key, this.meetingTitle = "Weekly Leadership Sync"});

  @override
  State<BusinessMeetingsScreen> createState() => _BusinessMeetingsScreenState();
}

class _BusinessMeetingsScreenState extends State<BusinessMeetingsScreen> {
  bool _isMuted = false;
  bool _isVideoOff = false;
  bool _isScreenSharing = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Premium obsidian dark
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.meetingTitle, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const Row(
              children: [
                Icon(LucideIcons.lock, color: Colors.greenAccent, size: 10),
                SizedBox(width: 5),
                Text("End-to-End Encrypted", style: TextStyle(color: Colors.white54, fontSize: 10)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(LucideIcons.users, color: Colors.white), onPressed: () {}),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: GridView.count(
              padding: const EdgeInsets.all(15),
              crossAxisCount: 2,
              mainAxisSpacing: 15,
              crossAxisSpacing: 15,
              children: [
                _buildParticipant("Pastor John (You)", "https://i.pravatar.cc/150?u=me", isMe: true),
                _buildParticipant("Bishop David", "https://i.pravatar.cc/150?u=bishop"),
                _buildParticipant("Deacon Sarah", "https://i.pravatar.cc/150?u=deacon"),
                _buildParticipant("Elder Moses", "https://i.pravatar.cc/150?u=elder"),
              ],
            ),
          ),
          _buildControlBar(),
        ],
      ),
    );
  }

  Widget _buildParticipant(String name, String avatar, {bool isMe = false}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
        image: DecorationImage(image: NetworkImage(avatar), fit: BoxFit.cover, opacity: 0.3),
      ),
      child: Stack(
        children: [
          if (_isVideoOff && isMe)
            const Center(child: Icon(LucideIcons.user, color: Colors.white24, size: 50)),
          Positioned(
            bottom: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
              child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ),
          if (isMe && _isMuted)
            const Positioned(top: 12, right: 12, child: Icon(LucideIcons.micOff, color: Colors.redAccent, size: 16)),
        ],
      ),
    );
  }

  Widget _buildControlBar() {
    return Container(
      padding: const EdgeInsets.only(top: 20, bottom: 40, left: 30, right: 30),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildControlButton(
            _isMuted ? LucideIcons.micOff : LucideIcons.mic,
            _isMuted ? Colors.redAccent : Colors.white,
            () => setState(() => _isMuted = !_isMuted),
          ),
          _buildControlButton(
            _isVideoOff ? LucideIcons.videoOff : LucideIcons.video,
            _isVideoOff ? Colors.redAccent : Colors.white,
            () => setState(() => _isVideoOff = !_isVideoOff),
          ),
          _buildControlButton(
            LucideIcons.monitorUp,
            _isScreenSharing ? Colors.blueAccent : Colors.white,
            () => setState(() => _isScreenSharing = !_isScreenSharing),
          ),
          _buildControlButton(LucideIcons.messageSquare, Colors.white, () {}),
          Container(
            height: 50,
            width: 70,
            decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(15)),
            child: IconButton(
              icon: const Icon(LucideIcons.phoneOff, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton(IconData icon, Color color, VoidCallback onTap) {
    return IconButton(
      icon: Icon(icon, color: color, size: 24),
      onPressed: onTap,
    );
  }
}
