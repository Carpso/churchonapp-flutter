import 'dart:async';
import 'package:universal_io/io.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../data/chat_service.dart';
import '../data/presence_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/r2_service.dart';
import 'audio_call_screen.dart';
import 'group_call_screen.dart';
import 'widgets/chat_bubble_widget.dart';
import 'widgets/chat_input_widgets.dart';

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
  bool _isSending = false;
  bool _online = false;
  StreamSubscription<bool>? _onlineSub;
  PresenceService? _presence;
  Stream<List<ChatMessage>>? _cachedMessagesStream;

  static const Color _appBarColor = Color(0xFF1A1A1A);

  @override
  void initState() {
    super.initState();
    _presence = ref.read(presenceServiceProvider);
    _presence?.startHeartbeat();
    if (!widget.isGroup && widget.receiverId != null) {
      _onlineSub = _presence?.watchOnline(widget.receiverId!).listen((online) {
        if (mounted) setState(() => _online = online);
      });
    }
    _messageController.addListener(() {
      final hasText = _messageController.text.trim().isNotEmpty;
      if (hasText != _isTyping) {
        setState(() => _isTyping = hasText);
      }
    });
    // Mark incoming messages as read so the sender sees real read receipts.
    if (!widget.isGroup && widget.receiverId != null) {
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          ref.read(chatServiceProvider).markAsRead(widget.receiverId!);
        }
      });
    }
  }

  @override
  void dispose() {
    _onlineSub?.cancel();
    _presence?.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    final replyTo = _replyingTo;
    _messageController.clear();
    setState(() {
      _isTyping = false;
      _replyingTo = null;
    });
    _sendProtocol(
      content: text,
      type: 'text',
      replyToId: replyTo?.id,
      replyToText: replyTo?.text,
    );
  }

  void _sendProtocol({
    required String content,
    required String type,
    String? mediaUrl,
    String? stickerId,
    String? fileName,
    String? replyToId,
    String? replyToText,
  }) async {
    if (mounted) setState(() => _isSending = true);
    try {
      if (widget.isGroup && widget.groupId != null) {
        await ref.read(chatServiceProvider).sendGroupMessage(
              widget.groupId!,
              content,
              mediaType: type,
              mediaUrl: mediaUrl,
              stickerId: stickerId,
              fileName: fileName,
              replyToId: replyToId,
              replyToText: replyToText,
            );
      } else if (widget.receiverId != null) {
        await ref.read(chatServiceProvider).sendMessage(
              widget.receiverId!,
              content,
              mediaType: type,
              mediaUrl: mediaUrl,
              stickerId: stickerId,
              fileName: fileName,
              replyToId: replyToId,
              replyToText: replyToText,
            );
      }
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                const Expanded(child: Text('Failed to send. Tap to retry.')),
              ],
            ),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'RETRY',
              textColor: Colors.white,
              onPressed: () {
                _sendProtocol(
                  content: content,
                  type: type,
                  mediaUrl: mediaUrl,
                  stickerId: stickerId,
                  fileName: fileName,
                  replyToId: replyToId,
                  replyToText: replyToText,
                );
              },
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
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
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70, maxWidth: 1080, maxHeight: 1080);
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

  Future<void> _pickAndSendFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final picked = result.files.single;
    final fileName = picked.name;
    final client = ref.read(supabaseServiceProvider).client;
    try {
      final r2 = R2Service(client);
      final url = picked.bytes != null
          ? await r2.uploadBytes(picked.bytes!, 'chat/$fileName', contentType: 'application/octet-stream')
          : picked.path != null
              ? await r2.uploadFile(File(picked.path!), 'chat/$fileName')
              : null;
      if (url == null) throw Exception('Upload returned no URL');
      _sendProtocol(content: '📎 $fileName', type: 'file', mediaUrl: url, fileName: fileName);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _pickAndSendAudio() async {
    final result = await FilePicker.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final picked = result.files.single;
    final fileName = picked.name;
    final client = ref.read(supabaseServiceProvider).client;
    try {
      final r2 = R2Service(client);
      final url = picked.bytes != null
          ? await r2.uploadBytes(picked.bytes!, 'chat/$fileName', contentType: 'audio/mpeg')
          : picked.path != null
              ? await r2.uploadFile(File(picked.path!), 'chat/$fileName')
              : null;
      if (url == null) throw Exception('Upload returned no URL');
      _sendProtocol(content: '🎵 $fileName', type: 'audio', mediaUrl: url, fileName: fileName);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.red),
        );
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
    // Cache the stream so rebuilds don't re-subscribe to PostgREST changes.
    final messagesStream = _cachedMessagesStream ??= widget.isGroup
        ? chatService.streamGroupMessages(widget.groupId!)
        : chatService.streamMessages(widget.receiverId ?? '');

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildAppBar(),
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: Column(
          children: [
            Expanded(
              child: StreamBuilder<List<ChatMessage>>(
                stream: messagesStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: Color(0xFF1A1A1A)));
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
                      return _buildChatBubble(msg);
                    },
                  );
                },
              ),
            ),
          if (_showStickers) _buildStickerPanel(),
          if (_replyingTo != null) _buildReplyPreview(),
          _buildMessageInput(),
        ],
      ),
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
            backgroundImage: CachedNetworkImageProvider(widget.userAvatar),
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
                  widget.isGroup ? 'Group · tap for info' : (_online ? 'Online' : 'Offline'),
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
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Video calling coming soon!"), backgroundColor: Colors.orange),
            );
          },
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
              color: const Color(0xFF1A1A1A).withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(LucideIcons.messageSquare, size: 60, color: Color(0xFF1A1A1A)),
          ),
          const SizedBox(height: 20),
          Text(
            widget.isGroup ? 'No messages yet in ${widget.userName}' : 'Say Hello to ${widget.userName}!',
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 8),
          const Text(
            'Messages are secured with Supabase.',
            style: TextStyle(color: Colors.grey, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildChatBubble(ChatMessage msg) {
    return ChatBubble(
      msg: msg,
      isGroup: widget.isGroup,
      formatTime: _formatTime,
      senderColor: _senderColor,
      onLongPress: _showMessageActions,
    );
  }

  void _showMessageActions(ChatMessage msg) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("React", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildReactionButton(ctx, msg, '👍'),
                _buildReactionButton(ctx, msg, '❤️'),
                _buildReactionButton(ctx, msg, '🙏'),
                _buildReactionButton(ctx, msg, '😂'),
                _buildReactionButton(ctx, msg, '🔥'),
                _buildReactionButton(ctx, msg, '😢'),
              ],
            ),
            const Divider(height: 30),
            ListTile(
              leading: const Icon(LucideIcons.reply, color: Color(0xFF1A1A1A)),
              title: const Text("Reply"),
              onTap: () {
                Navigator.pop(ctx);
                _replyToMessage(msg);
              },
            ),
            if (msg.isMe)
              ListTile(
                leading: const Icon(LucideIcons.trash2, color: Colors.red),
                title: const Text("Delete", style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteMessage(msg.id);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildReactionButton(BuildContext ctx, ChatMessage msg, String emoji) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(ctx);
        _sendReaction(msg, emoji);
      },
      child: CircleAvatar(
        radius: 22,
        backgroundColor: msg.reaction == emoji
            ? const Color(0xFF1A1A1A).withValues(alpha: 0.15)
            : Colors.grey.shade100,
        child: Text(emoji, style: const TextStyle(fontSize: 22)),
      ),
    );
  }

  void _sendReaction(ChatMessage msg, String emoji) async {
    final newReaction = msg.reaction == emoji ? null : emoji;
    await Supabase.instance.client
        .from('messages')
        .update({'reaction': newReaction})
        .eq('id', msg.id);
  }

  ChatMessage? _replyingTo;

  void _replyToMessage(ChatMessage msg) {
    setState(() => _replyingTo = msg);
    _messageController.text = '';
    _messageController.selection = TextSelection.fromPosition(
      TextPosition(offset: 0),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Replying to ${msg.senderName}", style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1A1A1A),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _deleteMessage(String messageId) async {
    await Supabase.instance.client
        .from('messages')
        .update({'content': '[This message was deleted]', 'media_type': 'text', 'media_url': null})
        .eq('id', messageId);
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
    return StickerPanel(
      onSendSticker: (url) {
        _sendProtocol(content: '[Sticker]', type: 'sticker', mediaUrl: url);
        setState(() => _showStickers = false);
      },
    );
  }

  void _showAttachmentMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => AttachmentMenu(
        onDocument: () {
          Navigator.pop(context);
          _pickAndSendFile();
        },
        onGallery: () {
          Navigator.pop(context);
          _pickAndSendImage();
        },
        onLocation: () {
          Navigator.pop(context);
          _showLocationDialog();
        },
        onAudio: () {
          Navigator.pop(context);
          _pickAndSendAudio();
        },
      ),
    );
  }

  Widget _buildReplyPreview() {
    return ReplyPreviewWidget(
      senderName: _replyingTo!.senderName,
      text: _replyingTo!.text.isNotEmpty ? _replyingTo!.text : (_replyingTo!.mediaType == 'image' ? '📷 Photo' : '📎 File'),
      onDismiss: () => setState(() => _replyingTo = null),
    );
  }

  Widget _buildMessageInput() {
    return ChatInputWidget(
      controller: _messageController,
      isTyping: _isTyping && !_isSending,
      showStickers: _showStickers,
      onToggleStickers: () => setState(() => _showStickers = !_showStickers),
      onToggleAttachment: _showAttachmentMenu,
      onSend: _isSending ? () {} : _sendMessage,
      onSendProtocol: (content, type, {mediaUrl, stickerId, fileName}) {
        _sendProtocol(content: content, type: type, mediaUrl: mediaUrl, stickerId: stickerId, fileName: fileName);
      },
    );
  }
}
