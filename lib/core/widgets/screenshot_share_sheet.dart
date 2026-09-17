import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

/// Bottom sheet shown right after the user takes a screenshot: instead of a
/// plain screenshot, nudge them to share the actual in-app content.
Future<void> showScreenshotShareSheet(
  BuildContext context, {
  required String shareText,
  String? shareUrl,
  String? title,
}) {
  final url = (shareUrl == null || shareUrl.isEmpty)
      ? 'https://churchonapp.com'
      : shareUrl;
  final theme = Theme.of(context);

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: theme.colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.primaryColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(LucideIcons.share2, color: theme.primaryColor, size: 26),
          ),
          const SizedBox(height: 10),
          Text(
            'Nice shot!',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              title ?? 'Share ${shareText.isNotEmpty ? shareText : 'this'} with your church instead.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(LucideIcons.share2),
            title: const Text('Share'),
            subtitle: Text(url, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () async {
              Navigator.pop(ctx);
              try {
                await SharePlus.instance.share(
                  ShareParams(text: '$shareText\n$url'.trim()),
                );
              } catch (_) {
                await Clipboard.setData(ClipboardData(text: url));
              }
            },
          ),
          ListTile(
            leading: const Icon(LucideIcons.link),
            title: const Text('Copy link'),
            onTap: () async {
              Navigator.pop(ctx);
              await Clipboard.setData(ClipboardData(text: url));
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
