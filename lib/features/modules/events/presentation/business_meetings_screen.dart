import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/features/modules/events/presentation/meeting_subscription_sheet.dart';
import '../data/meeting_service.dart';

class BusinessMeetingsScreen extends ConsumerStatefulWidget {
  final String meetingId;
  final String meetingTitle;
  const BusinessMeetingsScreen({
    super.key, 
    this.meetingId = "MEET-2024-SYS",
    this.meetingTitle = "Weekly Leadership Sync"
  });

  @override
  ConsumerState<BusinessMeetingsScreen> createState() => _BusinessMeetingsScreenState();
}

class _BusinessMeetingsScreenState extends ConsumerState<BusinessMeetingsScreen> {
  bool _isMuted = false;
  bool _isVideoOff = false;
  // ignore: unused_field
  final bool _isScreenSharing = false;

  void _showRecords() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _MeetingRecordsPanel(meetingId: widget.meetingId),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
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
          IconButton(icon: const Icon(LucideIcons.users, color: Colors.white), onPressed: () {
            showModalBottomSheet(
              context: context,
              backgroundColor: const Color(0xFF1E293B),
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
              builder: (ctx) => Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Center(child: Text("MEETING PARTICIPANTS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
                    const SizedBox(height: 20),
                    _buildParticipant("Pastor (You)", '', isMe: true),
                    const SizedBox(height: 12),
                    _buildParticipant("Bishop David", ''),
                    const SizedBox(height: 12),
                    _buildParticipant("Secretary", ''),
                    const SizedBox(height: 12),
                    _buildParticipant("Elder Moses", ''),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          }),
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
                _buildParticipant("Pastor (You)", '', isMe: true),
                _buildParticipant("Bishop David", ''),
                _buildParticipant("Secretary", ''),
                _buildParticipant("Elder Moses", ''),
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
          _buildControlButton(_isMuted ? LucideIcons.micOff : LucideIcons.mic, _isMuted ? Colors.redAccent : Colors.white, () => setState(() => _isMuted = !_isMuted)),
          _buildControlButton(_isVideoOff ? LucideIcons.videoOff : LucideIcons.video, _isVideoOff ? Colors.redAccent : Colors.white, () => setState(() => _isVideoOff = !_isVideoOff)),
          _buildControlButton(LucideIcons.messageSquare, Colors.blueAccent, _showRecords),
          _buildControlButton(LucideIcons.bell, Colors.amberAccent, () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (ctx) => MeetingSubscriptionSheet(
              onSubscribe: (planType, amountZmw, paymentRef) async {
                return true;
              },
            ),
          )),
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

class _MeetingRecordsPanel extends ConsumerWidget {
  final String meetingId;
  const _MeetingRecordsPanel({required this.meetingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(meetingNotesProvider(meetingId));
    final votesAsync = ref.watch(meetingVotesProvider(meetingId));
    final noteCtrl = TextEditingController();

    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: const BoxDecoration(color: Color(0xFF0F172A), borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      padding: const EdgeInsets.all(25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Leadership Records", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 25),
          
          // Voting Section
          const Text("CURRENT MOTION: 'Approve Building Expansion'", style: TextStyle(color: Colors.blueAccent, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildVoteBtn(ref, "YES", Colors.green),
              const SizedBox(width: 10),
              _buildVoteBtn(ref, "NO", Colors.red),
              const Spacer(),
              votesAsync.when(
                data: (results) => Text("Results: ${results['YES'] ?? 0}Y | ${results['NO'] ?? 0}N", style: const TextStyle(color: Colors.white54, fontSize: 12)),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ],
          ),
          
          const Divider(height: 40, color: Colors.white10),
          
          // Notes Section
          const Text("Live Minutes", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          Expanded(
            child: notesAsync.when(
              data: (notes) => ListView.builder(
                itemCount: notes.length,
                itemBuilder: (context, i) => Container(
                  margin: const EdgeInsets.only(bottom: 15),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(15)),
                  child: Text(notes[i].content, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text("Sync Error: $e", style: const TextStyle(color: Colors.red))),
            ),
          ),
          
          Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: TextField(
              controller: noteCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "Enter record or motion...",
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                suffixIcon: IconButton(
                  icon: const Icon(LucideIcons.send, color: Colors.blueAccent),
                  onPressed: () {
                    if (noteCtrl.text.isEmpty) return;
                    ref.read(meetingServiceProvider).saveNote(meetingId, noteCtrl.text);
                    noteCtrl.clear();
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoteBtn(WidgetRef ref, String label, Color color) {
    return ElevatedButton(
      onPressed: () => ref.read(meetingServiceProvider).castVote(meetingId, label),
      style: ElevatedButton.styleFrom(backgroundColor: color.withValues(alpha: 0.2), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
    );
  }
}

