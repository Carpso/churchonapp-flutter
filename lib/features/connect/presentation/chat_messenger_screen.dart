import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../data/chat_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/r2_service.dart';
import 'audio_call_screen.dart';
import 'group_call_screen.dart';

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

  static const Color _bgColor = Color(0xFFE5DDD5);
  static const Color _myBubble = Color(0xFFDCF8C6);
  static const Color _theirBubble = Colors.white;
  static const Color _appBarColor = Color(0xFF075E54);

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _messageController.clear();
    setState(() => _isTyping = false);
    _sendProtocol(content: text, type: 'text');
  }

  void _sendProtocol({
    required String content,
    required String type,
    String? mediaUrl,
    String? stickerId,
    String? fileName,
  }) async {
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
    Future.delayed(const Duration(milliseconds: 120), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _startAudioCall() {
    if (widget.isGroup) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GroupCallScreen(
            groupName: widget.userName,
            groupAvatar: widget.userAvatar,
            groupId: widget.groupId ?? '',
          ),
        ),
      );
    } else if (widget.receiverId != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AudioCallScreen(
            userName: widget.userName,
            userAvatar: widget.userAvatar,
            recipientId: widget.receiverId!,
          ),
        ),
      );
    }
  }

  Future<void> _pickAndSendImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (picked != null && mounted) {
      final file = File(picked.path);
      final fileName = 'chat_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final client = ref.read(supabaseServiceProvider).client;
      try {
        final r2 = R2Service(client);
        final url = await r2.uploadFile(file, "chat/$fileName");
        _sendProtocol(content: '📷 Photo', type: 'image', mediaUrl: url);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  void _showLocationDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Share Location'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter location name or coordinates',
            prefixIcon: Icon(LucideIcons.mapPin),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final location = controller.text.trim();
              if (location.isNotEmpty) {
                _sendProtocol(content: '📍 $location', type: 'text');
              }
              Navigator.pop(ctx);
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chatService = ref.watch(chatServiceProvider);
    final messagesStream = widget.isGroup
        ? chatService.streamGroupMessages(widget.groupId!)
        : chatService.streamMessages(widget.receiverId ?? '');

    return Scaffold(
      backgroundColor: _bgColor,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: messagesStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Color(0xFF075E54)));
                }
                final messages = snapshot.data ?? [];

                if (messages.isEmpty) {
                  return _buildEmptyState();
                }

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final showSenderInfo = widget.isGroup && !msg.isMe &&
                        (index == messages.length - 1 ||
                            messages[index + 1].senderId != msg.senderId);
                    return _buildChatBubble(msg, showSenderInfo: showSenderInfo);
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

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: _appBarColor,
      elevation: 0,
      leadingWidth: 30,
      leading: IconButton(
        icon: const Icon(LucideIcons.arrowLeft, color: Colors.white, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundImage: NetworkImage(widget.userAvatar),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.userName,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                Text(
                  widget.isGroup ? 'Group · tap for info' : 'Online',
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(LucideIcons.video, color: Colors.white, size: 22),
          tooltip: widget.isGroup ? 'Group Video Call' : 'Video Call',
          onPressed: _startAudioCall,
        ),
        IconButton(
          icon: const Icon(LucideIcons.phone, color: Colors.white, size: 22),
          tooltip: widget.isGroup ? 'Group Audio Call' : 'Audio Call',
          onPressed: _startAudioCall,
        ),
        IconButton(
          icon: const Icon(LucideIcons.moreVertical, color: Colors.white),
          onPressed: () {
            showModalBottomSheet(
              context: context,
              builder: (ctx) => SafeArea(
                child: Wrap(
                  children: [
                    ListTile(
                      leading: const Icon(LucideIcons.flag, color: Colors.red),
                      title: const Text("Report"),
                      onTap: () {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Report submitted"), duration: Duration(seconds: 2)),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(LucideIcons.ban, color: Colors.red),
                      title: const Text("Block"),
                      onTap: () {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("User blocked"), duration: Duration(seconds: 2)),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(LucideIcons.trash2, color: Colors.red),
                      title: const Text("Clear Chat"),
                      onTap: () {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Chat cleared"), duration: Duration(seconds: 2)),
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF075E54).withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(LucideIcons.messageSquare, size: 60, color: Color(0xFF075E54)),
          ),
          const SizedBox(height: 20),
          Text(
            widget.isGroup ? 'No messages yet in ${widget.userName}' : 'Say Hello to ${widget.userName}!',
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 8),
          const Text(
            'Messages are end-to-end encrypted. 🔒',
            style: TextStyle(color: Colors.grey, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildChatBubble(ChatMessage msg, {bool showSenderInfo = false}) {
    final isMe = msg.isMe;
    final time = _formatTime(msg.createdAt);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: 4,
          left: isMe ? 60 : 0,
          right: isMe ? 0 : 60,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMe && widget.isGroup)
              Padding(
                padding: const EdgeInsets.only(right: 6, bottom: 2),
                child: showSenderInfo
                    ? CircleAvatar(
                        radius: 14,
                        backgroundImage: msg.senderAvatar != null
                            ? NetworkImage(msg.senderAvatar!)
                            : null,
                        backgroundColor: const Color(0xFF075E54),
                        child: msg.senderAvatar == null
                            ? Text(
                                (msg.senderName.isNotEmpty ? msg.senderName[0] : 'M').toUpperCase(),
                                style: const TextStyle(color: Colors.white, fontSize: 11),
                              )
                            : null,
                      )
                    : const SizedBox(width: 28),
              ),
            Flexible(
              child: Container(
                margin: const EdgeInsets.only(bottom: 2),
                decoration: BoxDecoration(
                  color: isMe ? _myBubble : _theirBubble,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
                    bottomRight: isMe ? Radius.zero : const Radius.circular(16),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!isMe && widget.isGroup && showSenderInfo)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(
                            msg.senderName,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _senderColor(msg.senderId),
                            ),
                          ),
                        ),
                      if (msg.mediaType == 'image' && msg.mediaUrl != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            msg.mediaUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const Icon(LucideIcons.imageOff, color: Colors.grey),
                          ),
                        ),
                      if (msg.mediaType == 'sticker' && msg.mediaUrl != null)
                        Image.network(msg.mediaUrl!, width: 120, height: 120),
                      if (msg.mediaType == 'file')
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(LucideIcons.fileText, color: Colors.indigo, size: 20),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                msg.fileName ?? 'Document',
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo),
                              ),
                            ),
                          ],
                        ),
                      if (msg.text.isNotEmpty && msg.mediaType != 'sticker')
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            msg.text,
                            style: const TextStyle(
                              fontSize: 15,
                              color: Colors.black87,
                              height: 1.35,
                            ),
                          ),
                        ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          const Spacer(),
                          Text(
                            time,
                            style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                          ),
                          if (isMe) ...[
                            const SizedBox(width: 4),
                            const Icon(LucideIcons.checkCheck, size: 14, color: Color(0xFF34B7F1)),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _senderColor(String senderId) {
    final colors = [
      const Color(0xFF2196F3),
      const Color(0xFF9C27B0),
      const Color(0xFFE91E63),
      const Color(0xFF00897B),
      const Color(0xFFF4511E),
      const Color(0xFF3949AB),
    ];
    return colors[senderId.hashCode.abs() % colors.length];
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Widget _buildStickerPanel() {
    final stickers = [
      'https://media.giphy.com/media/l0MYt5jPR6QX5pnqM/giphy.gif',
      'https://media.giphy.com/media/3oz8xGme7vEndhrsly/giphy.gif',
      'https://media.giphy.com/media/l2JehQ2GitHGdVG9a/giphy.gif',
      'https://media.giphy.com/media/xT0xeJpnrWC4XWblEk/giphy.gif',
      'https://media.giphy.com/media/l0HlBO7eyXzSZkJri/giphy.gif',
      'https://media.giphy.com/media/xT9IgG50Lg7rusNZ68/giphy.gif',
    ];

    return Container(
      height: 220,
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Kingdom Stickers 🙌', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF075E54))),
          const SizedBox(height: 10),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4, crossAxisSpacing: 10, mainAxisSpacing: 10),
              itemCount: stickers.length,
              itemBuilder: (context, index) => InkWell(
                onTap: () {
                  _sendProtocol(content: '[Sticker]', type: 'sticker', mediaUrl: stickers[index]);
                  setState(() => _showStickers = false);
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(stickers[index], fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(LucideIcons.smile)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAttachmentMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(30),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildAttachOption(LucideIcons.fileText, 'Document', Colors.indigo, () {
              _sendProtocol(content: 'Mission Document', type: 'file', fileName: 'MISSION_PLAN.pdf');
              Navigator.pop(context);
            }),
            _buildAttachOption(LucideIcons.image, 'Gallery', Colors.purple, () {
              Navigator.pop(context);
              _pickAndSendImage();
            }),
            _buildAttachOption(LucideIcons.mapPin, 'Location', Colors.orange, () {
              Navigator.pop(context);
              _showLocationDialog();
            }),
            _buildAttachOption(LucideIcons.headphones, 'Audio', Colors.green, () {
              _sendProtocol(content: '🎵 Worship Audio Clip', type: 'text');
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
          CircleAvatar(
            radius: 26,
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 8),
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
                      icon: Icon(
                        _showStickers ? LucideIcons.keyboard : LucideIcons.smile,
                        color: Colors.grey,
                      ),
                      onPressed: () => setState(() => _showStickers = !_showStickers),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        maxLines: null,
                        textCapitalization: TextCapitalization.sentences,
                        onChanged: (v) => setState(() => _isTyping = v.trim().isNotEmpty),
                        decoration: const InputDecoration(
                          hintText: 'Message',
                          hintStyle: TextStyle(color: Colors.grey),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.paperclip, color: Colors.grey),
                      onPressed: _showAttachmentMenu,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _isTyping ? _sendMessage : null,
              child: Container(
                padding: const EdgeInsets.all(13),
                decoration: const BoxDecoration(
                  color: Color(0xFF075E54),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isTyping ? LucideIcons.send : LucideIcons.mic,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
