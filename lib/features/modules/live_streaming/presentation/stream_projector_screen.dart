import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:church_on_app/core/widgets/app_image.dart';
import 'package:church_on_app/core/widgets/marquee_ticker.dart';
import 'package:church_on_app/features/modules/live_streaming/data/live_stream_overlay_service.dart';

/// Projector / Big-screen mode — designed to be cast, screen-mirrored or thrown
/// to a second display (projector, TV, laptop). Shows the public HLS link, a QR
/// to share it, the realtime "verse of the moment" in large type and the live
/// news ticker. Provider-neutral: it is just a web/ HLS link.
class StreamProjectorScreen extends ConsumerWidget {
  final String title;
  final String? hlsUrl;
  final String? streamId;
  final String? tenantName;
  final String? logoUrl;
  final String shareUrl;

  const StreamProjectorScreen({
    super.key,
    required this.title,
    this.hlsUrl,
    this.streamId,
    this.tenantName,
    this.logoUrl,
    this.shareUrl = 'https://churchonapp.com/live-streaming',
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overlay = streamId == null || streamId!.isEmpty
        ? const AsyncValue<LiveStreamOverlay?>.data(null)
        : ref.watch(liveStreamOverlayProvider(streamId!));

    final data = overlay.value;
    final verseText = data?.verseText?.trim();
    final verseRef = data?.verseRef?.trim();
    final hasVerse = (verseText != null && verseText.isNotEmpty) ||
        (verseRef != null && verseRef.isNotEmpty);
    final speakerName = data?.speakerName?.trim();
    final speakerTitle = data?.speakerTitle?.trim();
    final speakerChurch = data?.speakerChurch?.trim();
    final hasSpeaker = (speakerName != null && speakerName.isNotEmpty) ||
        (speakerTitle != null && speakerTitle.isNotEmpty) ||
        (speakerChurch != null && speakerChurch.isNotEmpty);
    final caption = data?.caption?.trim();
    final hasCaption = caption != null && caption.isNotEmpty;

    final tickerItems = <String>[
      if (data?.tickerEnabled != false && (data?.tickerMessage ?? '').trim().isNotEmpty)
        data!.tickerMessage!.trim(),
      if (hasVerse) [verseRef, verseText].whereType<String>().where((e) => e.isNotEmpty).join(' — '),
      if (hasSpeaker)
        [speakerName, speakerTitle, speakerChurch]
            .whereType<String>()
            .where((e) => e.isNotEmpty)
            .join(' · '),
      if (tenantName != null && tenantName!.isNotEmpty) '$tenantName · $title',
    ];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Projector / Big Screen'),
        actions: [
          IconButton(
            tooltip: 'Copy HLS link',
            icon: const Icon(LucideIcons.link),
            onPressed: (hlsUrl == null || hlsUrl!.isEmpty)
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: hlsUrl!));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Playback link copied')),
                    );
                  },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (logoUrl != null && logoUrl!.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: AppImage(logoUrl!, width: 96, height: 96, fit: BoxFit.cover),
                      )
                    else
                      const Icon(LucideIcons.church, color: Color(0xFFFFD700), size: 64),
                    const SizedBox(height: 16),
                    Text(
                      tenantName ?? 'Church On App',
                      style: const TextStyle(
                        color: Color(0xFFFFD700),
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontSize: 15),
                    ),
                    if (hasCaption) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          caption,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                    if (hasSpeaker) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(16),
                          border: Border(
                            left: BorderSide(color: Color(0xFFFFD700), width: 4),
                          ),
                        ),
                        child: Column(
                          children: [
                            if (speakerName != null && speakerName.isNotEmpty)
                              Text(
                                speakerName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 30,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            if ((speakerTitle ?? '').isNotEmpty ||
                                (speakerChurch ?? '').isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  [speakerTitle, speakerChurch]
                                      .whereType<String>()
                                      .where((e) => e.isNotEmpty)
                                      .join(' · '),
                                  style: const TextStyle(
                                    color: Color(0xFFFFD700),
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 32),
                    if (hasVerse)
                      Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: const Color(0xFFFFD700), width: 1.5),
                        ),
                        child: Column(
                          children: [
                            if (verseRef != null && verseRef.isNotEmpty)
                              Text(
                                verseRef.toUpperCase(),
                                style: const TextStyle(
                                  color: Color(0xFFFFD700),
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2,
                                  fontSize: 18,
                                ),
                              ),
                            if (verseRef != null && verseRef.isNotEmpty)
                              const SizedBox(height: 14),
                            if (verseText != null && verseText.isNotEmpty)
                              Text(
                                '"$verseText"',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 34,
                                  height: 1.35,
                                  fontStyle: FontStyle.italic,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                      )
                    else
                      const Text(
                        'The verse of the moment will appear here.',
                        style: TextStyle(color: Colors.white38, fontSize: 16),
                      ),
                    const SizedBox(height: 40),
                    _linkCard(context, hlsUrl),
                  ],
                ),
              ),
            ),
          ),
          if (tickerItems.isNotEmpty)
            MarqueeTicker(
              items: tickerItems,
              pixelsPerSecond: (data?.tickerSpeed ?? 40).toDouble(),
              height: 40,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
              background: const Color(0xFF111111),
            ),
        ],
      ),
    );
  }

  Widget _linkCard(BuildContext context, String? url) {
    final hasUrl = url != null && url.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: QrImageView(
              data: shareUrl,
              version: QrVersions.auto,
              size: 120,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'WATCH ON ANY SCREEN',
                  style: TextStyle(
                    color: Color(0xFFFFD700),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  hasUrl ? url : 'Playback link appears once the stream is live.',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace'),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Scan the QR, or open the link on any phone, tablet, laptop or TV. '
                  'Cast it from your browser/OS (ChromeCast, AirPlay or screen-mirror) — '
                  'no extra setup required.',
                  style: TextStyle(color: Colors.white38, fontSize: 10.5, height: 1.35),
                ),
                if (hasUrl) ...[
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: url));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Playback link copied')),
                      );
                    },
                    icon: const Icon(LucideIcons.copy, size: 14),
                    label: const Text('COPY LINK'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
