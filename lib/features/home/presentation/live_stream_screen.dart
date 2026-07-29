import 'package:flutter/material.dart';
import 'package:chewie/chewie.dart';
import 'package:video_player/video_player.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:church_on_app/core/services/tenant_service.dart';
import '../../finance/presentation/giving_screen.dart';
import 'package:church_on_app/features/admin/data/reporting_service.dart';
import '../data/live_chat_service.dart';
import '../../../core/providers/profile_provider.dart';
import '../../../core/widgets/app_image.dart';
import 'dart:async';

class LiveStreamScreen extends ConsumerStatefulWidget {
  final String streamUrl;
  final String title;

  const LiveStreamScreen({
    super.key, 
    required this.streamUrl,
    required this.title,
  });

  @override
  ConsumerState<LiveStreamScreen> createState() => _LiveStreamScreenState();
}

class _LiveStreamScreenState extends ConsumerState<LiveStreamScreen> {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;
  final _chatCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    _videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(widget.streamUrl));
    await _videoPlayerController.initialize();
    
    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController,
      autoPlay: true,
      looping: false,
      isLive: true,
      aspectRatio: _videoPlayerController.value.aspectRatio,
      placeholder: Container(color: Colors.black),
      materialProgressColors: ChewieProgressColors(
        playedColor: const Color(0xFFFFD700),
        handleColor: const Color(0xFFFFD700),
        backgroundColor: Colors.grey,
        bufferedColor: Colors.white.withValues(alpha: 0.3),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    _chewieController?.dispose();
    _chatCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(currentTenantProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 16)),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(5),
            ),
            child: const Center(
              child: Text("LIVE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: _chewieController != null && _chewieController!.videoPlayerController.value.isInitialized
                ? Chewie(controller: _chewieController!)
                : const Center(child: CircularProgressIndicator(color: Color(0xFFFFD700))),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFF1A1A1A),
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Row(
                    children: [
                       ClipOval(child: AppImage(tenant?.logoUrl ?? '', width: 40, height: 40, fit: BoxFit.cover)),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tenant?.name ?? "Church", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          Text("Join the community", style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12)),
                        ],
                      ),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const GivingScreen()));
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFD700),
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        child: const Text("GIVE", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 10)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildannouncementTicker(tenant),
                  const SizedBox(height: 20),
                  const Text("LIVE CHAT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 12)),
                  const SizedBox(height: 15),
                  Expanded(
                    child: _buildChatMessages(tenant),
                  ),
                  _buildChatInput(tenant),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildannouncementTicker(Tenant? tenant) {
    if (tenant == null) return const SizedBox.shrink();
    final reportsAsync = ref.watch(reportsStreamProvider(tenant.id));

    return reportsAsync.when(
      data: (reports) {
        final announcements = reports.where((r) => r.type == 'announcement').toList();
        if (announcements.isEmpty) return const SizedBox.shrink();
        
        final latest = announcements.first;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(LucideIcons.megaphone, color: Colors.amber, size: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("LATEST ANNOUNCEMENT", style: TextStyle(color: Colors.amber, fontSize: 9, fontWeight: FontWeight.bold)),
                    Text(latest.title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildChatMessages(Tenant? tenant) {
    if (tenant == null) return const Center(child: Text("Select a church to chat", style: TextStyle(color: Colors.white54)));

    final chatAsync = ref.watch(liveChatStreamProvider(tenant.id));

    return chatAsync.when(
      data: (messages) {
        if (messages.isEmpty) {
          return const Center(child: Text("No messages yet. Be the first to chat!", style: TextStyle(color: Colors.white24, fontSize: 12)));
        }
        
        // Auto scroll to bottom on new messages
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollCtrl.hasClients) {
            _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
          }
        });

        return ListView.builder(
          controller: _scrollCtrl,
          itemCount: messages.length,
          itemBuilder: (context, index) => _buildChatMessage(messages[index]),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFFFD700))),
      error: (e, _) => Center(child: Text("Chat unavailable", style: const TextStyle(color: Colors.red, fontSize: 10))),
    );
  }

  Widget _buildChatMessage(LiveChatMessage msg) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipOval(child: AppImage(msg.senderPhoto ?? '', width: 16, height: 16, fit: BoxFit.cover)),
          const SizedBox(width: 8),
          Text("${msg.senderName}: ", style: const TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold, fontSize: 13)),
          Expanded(child: Text(msg.text, style: const TextStyle(color: Colors.white, fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildChatInput(Tenant? tenant) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _chatCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: "Say something...",
                hintStyle: TextStyle(color: Colors.white24),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 20),
              ),
              onSubmitted: (_) => _handleSendMessage(tenant),
            ),
          ),
          IconButton(
            icon: const Icon(LucideIcons.send, color: Color(0xFFFFD700), size: 20),
            onPressed: () => _handleSendMessage(tenant),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSendMessage(Tenant? tenant) async {
    if (tenant == null || _chatCtrl.text.trim().isEmpty) return;

    final profile = ref.read(profileProvider).value;
    if (profile == null) return;
    final message = _chatCtrl.text.trim();
    _chatCtrl.clear();

    try {
      await ref.read(liveChatServiceProvider).sendLiveMessage(
        tenantId: tenant.id,
        content: message,
        userName: profile.name,
        userPhoto: profile.avatarUrl ?? '',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to send message")));
      }
    }
  }
}

