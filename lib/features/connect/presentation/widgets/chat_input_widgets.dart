import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ChatInputWidget extends StatelessWidget {
  final TextEditingController controller;
  final bool isTyping;
  final bool showStickers;
  final VoidCallback onToggleStickers;
  final VoidCallback onToggleAttachment;
  final VoidCallback onSend;
  final void Function(String content, String type, {String? mediaUrl, String? stickerId, String? fileName}) onSendProtocol;

  const ChatInputWidget({
    super.key,
    required this.controller,
    required this.isTyping,
    required this.showStickers,
    required this.onToggleStickers,
    required this.onToggleAttachment,
    required this.onSend,
    required this.onSendProtocol,
  });

  @override
  Widget build(BuildContext context) {
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
                        showStickers ? LucideIcons.keyboard : LucideIcons.smile,
                        color: Colors.grey,
                      ),
                      onPressed: onToggleStickers,
                    ),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        maxLines: null,
                        textCapitalization: TextCapitalization.sentences,
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
                      onPressed: onToggleAttachment,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: isTyping ? onSend : null,
              child: Container(
                padding: const EdgeInsets.all(13),
                decoration: const BoxDecoration(
                  color: Color(0xFF075E54),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.send,
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

class StickerPanel extends StatelessWidget {
  final void Function(String url) onSendSticker;

  const StickerPanel({super.key, required this.onSendSticker});

  static const List<String> _stickers = [
    'https://media.giphy.com/media/l0MYt5jPR6QX5pnqM/giphy.gif',
    'https://media.giphy.com/media/3oz8xGme7vEndhrsly/giphy.gif',
    'https://media.giphy.com/media/l2JehQ2GitHGdVG9a/giphy.gif',
    'https://media.giphy.com/media/xT0xeJpnrWC4XWblEk/giphy.gif',
    'https://media.giphy.com/media/l0HlBO7eyXzSZkJri/giphy.gif',
    'https://media.giphy.com/media/xT9IgG50Lg7rusNZ68/giphy.gif',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Stickers', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF075E54))),
          const SizedBox(height: 10),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4, crossAxisSpacing: 10, mainAxisSpacing: 10),
              itemCount: _stickers.length,
              itemBuilder: (context, index) => InkWell(
                onTap: () => onSendSticker(_stickers[index]),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: _stickers[index],
                    fit: BoxFit.cover,
                    memCacheWidth: 120,
                    memCacheHeight: 120,
                    errorWidget: (context, url, error) => const Icon(LucideIcons.smile),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ReplyPreviewWidget extends StatelessWidget {
  final String senderName;
  final String text;
  final VoidCallback onDismiss;

  const ReplyPreviewWidget({
    super.key,
    required this.senderName,
    required this.text,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.white,
      child: Row(
        children: [
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF075E54),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Replying to $senderName',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF075E54)),
                ),
                Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(LucideIcons.x, size: 18, color: Colors.grey),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

class AttachmentMenu extends StatelessWidget {
  final VoidCallback onDocument;
  final VoidCallback onGallery;
  final VoidCallback onLocation;
  final VoidCallback onAudio;

  const AttachmentMenu({
    super.key,
    required this.onDocument,
    required this.onGallery,
    required this.onLocation,
    required this.onAudio,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildOption(LucideIcons.fileText, 'Document', Colors.indigo, onDocument),
          _buildOption(LucideIcons.image, 'Gallery', Colors.purple, onGallery),
          _buildOption(LucideIcons.mapPin, 'Location', Colors.orange, onLocation),
          _buildOption(LucideIcons.headphones, 'Audio', Colors.green, onAudio),
        ],
      ),
    );
  }

  Widget _buildOption(IconData icon, String label, Color color, VoidCallback onTap) {
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
}
