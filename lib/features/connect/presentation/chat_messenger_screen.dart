import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/chat_service.dart';
import 'audio_call_screen.dart';

class ChatMessengerScreen extends ConsumerStatefulWidget {
  final String userName;
  final String userAvatar;
  final String? receiverId;
  final String? groupId;
  final bool isGroup;

  const ChatMessengerScreen({
    super.key, 
    required this.userName, 
    required this.userAvatar,
    this.receiverId,
    this.groupId,
    this.isGroup = false,
  });

  @override
  ConsumerState<ChatMessengerScreen> createState() => _ChatMessengerScreenState();
}

class _ChatMessengerScreenState extends ConsumerState<ChatMessengerScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isTyping = false;
  bool _showStickers = false;

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    
    _messageController.clear();
    setState(() => _isTyping = false);
    
    _sendProtocol(content: text, type: 'text');
  }

  void _sendProtocol({required String content, required String type, String? mediaUrl, String? stickerId, String? fileName}) async {
    if (widget.isGroup && widget.groupId != null) {
      await ref.read(chatServiceProvider).sendGroupMessage(
        widget.groupId!, 
        content,
        mediaType: type,
        mediaUrl: mediaUrl,
        stickerId: stickerId,
        fileName: fileName,
      );
    } else if (widget.receiverId != null) {
      await ref.read(chatServiceProvider).sendMessage(
        widget.receiverId!, 
        content,
        mediaType: type,
        mediaUrl: mediaUrl,
        stickerId: stickerId,
        fileName: fileName,
      );
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _startAudioCall() {
    if (widget.isGroup) return; // Disable for now in groups
    Navigator.push(
      context, 
      MaterialPageRoute(builder: (context) => AudioCallScreen(
        userName: widget.userName, 
        userAvatar: widget.userAvatar,
        recipientId: widget.receiverId!,
      ))
    );
  }

  @override
  Widget build(BuildContext context) {
    final chatService = ref.watch(chatServiceProvider);
    final messagesStream = widget.isGroup 
      ? chatService.streamGroupMessages(widget.groupId!)
      : chatService.streamMessages(widget.receiverId!);

    return Scaffold(
      backgroundColor: const Color(0xFFEBE5DF),
      appBar: AppBar(
        backgroundColor: Theme.of(context).primaryColor,
        elevation: 0,
        leadingWidth: 70,
        leading: Row(
          children: [
            IconButton(
              icon: const Icon(LucideIcons.arrowLeft, color: Colors.white, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            CircleAvatar(
              radius: 18,
              backgroundImage: NetworkImage(widget.userAvatar),
            )
          ],
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.userName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            const Text("Online", style: TextStyle(fontSize: 10, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(LucideIcons.phone, color: Colors.white), onPressed: _startAudioCall),
          IconButton(icon: const Icon(LucideIcons.moreVertical, color: Colors.white), onPressed: () {}),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: messagesStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final messages = (snapshot.data ?? []).reversed.toList();
                
                // If empty, show fallback mock data for demonstration
                if (messages.isEmpty && (widget.receiverId?.contains('general') == true || widget.isGroup)) {
                   return _buildMockMessages();
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(15),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    return _buildChatBubble(msg, msg.isMe, "${msg.createdAt.hour}:${msg.createdAt.minute}", "read");
                  },
                );
              },
            ),
          ),
          if (_showStickers) _buildStickerPanel(),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMockMessages() {
     return const Center(child: Text("Welcome to the Hub", style: TextStyle(color: Colors.grey)));
  }

  Widget _buildChatBubble(ChatMessage msg, bool isMe, String time, String status) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10, left: 10, right: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFFDCF8C6) : Colors.white,
          borderRadius: BorderRadius.circular(15).copyWith(
            bottomRight: isMe ? const Radius.circular(0) : const Radius.circular(15),
            bottomLeft: isMe ? const Radius.circular(15) : const Radius.circular(0),
          ),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 3, offset: const Offset(0, 1))]
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   if (msg.mediaType == 'image')
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(msg.mediaUrl!, fit: BoxFit.cover),
                      ),
                   if (msg.mediaType == 'sticker')
                      Image.network(msg.mediaUrl!, width: 120, height: 120),
                   if (msg.mediaType == 'file')
                      Row(
                        children: [
                          const Icon(LucideIcons.fileText, color: Colors.blue),
                          const SizedBox(width: 8),
                          Expanded(child: Text(msg.fileName ?? "Document", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
                        ],
                      ),
                   if (msg.text.isNotEmpty && msg.mediaType != 'sticker')
                      Padding(
                        padding: const EdgeInsets.only(top: 5, bottom: 20),
                        child: Text(msg.text, style: const TextStyle(fontSize: 15, color: Colors.black87)),
                      ),
                ],
              ),
            ),
            Positioned(
              bottom: 5,
              right: 10,
              child: Row(
                children: [
                  Text(time, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                  if (isMe) ...[
                    const SizedBox(width: 5),
                    Icon(status == "read" ? LucideIcons.checkCheck : LucideIcons.check, size: 14, color: status == "read" ? Colors.blue : Colors.grey),
                  ]
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildStickerPanel() {
    final List<String> stickers = [
      "https://images.rawpixel.com/image_png_800/cHJpdmF0ZS9sci9pbWFnZXMvd2Vic2l0ZS8yMDIzLTA3L2pvYjE4ODUta2V0LTExNi5wbmc.png", // Dove
      "https://png.pngtree.com/png-vector/20230303/ourmid/pngtree-golden-holy-bible-and-cross-vector-illustration-png-image_6628906.png", // Bible
      "https://png.pngtree.com/png-vector/20220610/ourmid/pngtree-god-bless-you-typography-and-lettering-png-image_4954045.png", // God Bless
      "https://png.pngtree.com/png-vector/20231014/ourmid/pngtree-cross-jesus-3d-model-christianity-religion-png-image_10161474.png", // Cross
    ];

    return Container(
      height: 250,
      color: Colors.white,
      padding: const EdgeInsets.all(20),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10),
        itemCount: stickers.length,
        itemBuilder: (context, index) {
          return InkWell(
            onTap: () {
              _sendProtocol(content: "[Sticker]", type: 'sticker', mediaUrl: stickers[index]);
              setState(() => _showStickers = false);
            },
            child: Image.network(stickers[index]),
          );
        },
      ),
    );
  }

  void _showAttachmentMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(30),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildAttachOption(LucideIcons.fileText, "Document", Colors.indigo, () {
               _sendProtocol(content: "Strategic Mission Document", type: 'file', fileName: "MISSION_PLAN.pdf");
               Navigator.pop(context);
            }),
            _buildAttachOption(LucideIcons.image, "Gallery", Colors.purple, () {
               _sendProtocol(content: "Kingdom Event Photo", type: 'image', mediaUrl: "https://images.unsplash.com/photo-1544427928-c49cdfebf193?q=80&w=1000&auto=format&fit=crop");
               Navigator.pop(context);
            }),
            _buildAttachOption(LucideIcons.mapPin, "Location", Colors.orange, () {
               _sendProtocol(content: "Kingdom Hub Location: Lusaka HQ", type: 'text');
               Navigator.pop(context);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachOption(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(radius: 25, backgroundColor: color.withValues(alpha: 0.1), child: Icon(icon, color: color)),
          const SizedBox(height: 10),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      color: Colors.transparent,
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 5)],
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(_showStickers ? LucideIcons.keyboard : LucideIcons.smile, color: Colors.grey),
                      onPressed: () => setState(() => _showStickers = !_showStickers),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        maxLines: null,
                        onChanged: (v) => setState(() => _isTyping = v.trim().isNotEmpty),
                        decoration: const InputDecoration(
                          hintText: "Message",
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    IconButton(icon: const Icon(LucideIcons.paperclip, color: Colors.grey), onPressed: _showAttachmentMenu),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _isTyping ? _sendMessage : null,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Theme.of(context).primaryColor, shape: BoxShape.circle),
                child: Icon(_isTyping ? LucideIcons.send : LucideIcons.mic, color: Colors.white, size: 24),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
