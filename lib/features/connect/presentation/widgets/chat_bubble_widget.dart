import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../data/chat_service.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage msg;
  final bool isGroup;
  final String Function(DateTime) formatTime;
  final Color Function(String) senderColor;
  final void Function(ChatMessage) onLongPress;

  const ChatBubble({
    super.key,
    required this.msg,
    required this.isGroup,
    required this.formatTime,
    required this.senderColor,
    required this.onLongPress,
  });

  static const Color _myBubble = Color(0xFFDCF8C6);
  static const Color _theirBubble = Colors.white;

  @override
  Widget build(BuildContext context) {
    final isMe = msg.isMe;
    final time = formatTime(msg.createdAt);
    final showAvatar = isGroup && !isMe;

    return GestureDetector(
      onLongPress: () => onLongPress(msg),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: 6,
            left: isMe ? 60 : 0,
            right: isMe ? 0 : 60,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (showAvatar)
                Padding(
                  padding: const EdgeInsets.only(right: 6, bottom: 2),
                  child: CircleAvatar(
                    radius: 14,
                    backgroundColor: const Color(0xFF1A1A1A),
                    backgroundImage: msg.senderAvatar != null && msg.senderAvatar!.isNotEmpty
                        ? CachedNetworkImageProvider(msg.senderAvatar!)
                        : null,
                    child: msg.senderAvatar == null || msg.senderAvatar!.isEmpty
                        ? Text(
                            (msg.senderName.isNotEmpty ? msg.senderName[0] : 'M').toUpperCase(),
                            style: const TextStyle(color: Colors.white, fontSize: 11),
                          )
                        : null,
                  ),
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
                        if (!isMe)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(
                              msg.senderName,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: senderColor(msg.senderId),
                              ),
                            ),
                          ),
                        if (msg.replyToText != null && msg.replyToText!.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.all(6),
                            margin: const EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(8),
                              border: Border(
                                left: BorderSide(
                                  color: isMe ? const Color(0xFF1A1A1A) : Colors.amber,
                                  width: 3,
                                ),
                              ),
                            ),
                            child: Text(
                              msg.replyToText!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ),
                        if (msg.mediaType == 'image' && msg.mediaUrl != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: CachedNetworkImage(
                              imageUrl: msg.mediaUrl!,
                              fit: BoxFit.cover,
                              width: 220,
                              memCacheWidth: 220,
                              placeholder: (context, url) => Container(
                                width: 220,
                                height: 160,
                                color: Colors.grey[200],
                                child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                              ),
                              errorWidget: (context, url, error) => Container(
                                width: 220,
                                height: 160,
                                color: Colors.grey[200],
                                child: const Icon(LucideIcons.imageOff, color: Colors.grey),
                              ),
                            ),
                          ),
                        if (msg.mediaType == 'sticker' && msg.mediaUrl != null)
                          CachedNetworkImage(
                            imageUrl: msg.mediaUrl!,
                            width: 120,
                            height: 120,
                            memCacheWidth: 120,
                            memCacheHeight: 120,
                            errorWidget: (context, url, error) => const Icon(LucideIcons.smile, size: 60),
                          ),
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
                        if (msg.reaction != null && msg.reaction!.isNotEmpty)
                          Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 3)],
                              ),
                              child: Text(msg.reaction!, style: const TextStyle(fontSize: 16)),
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
                              Icon(
                                msg.readCount > 0
                                    ? LucideIcons.checkCheck
                                    : LucideIcons.check,
                                size: 14,
                                color: msg.readCount > 0
                                    ? const Color(0xFF34B7F1)
                                    : Colors.grey,
                              ),
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
      ),
    );
  }
}
