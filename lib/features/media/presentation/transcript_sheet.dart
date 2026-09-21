import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/transcript_service.dart';

/// Opens the full transcript panel: timestamped cues (tap to seek), detected
/// Bible verse markers, COPY and a `.vtt` share/download.
Future<void> showTranscriptSheet(
  BuildContext context, {
  required MediaTranscript transcript,
  ValueChanged<Duration>? onSeek,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _TranscriptSheet(transcript: transcript, onSeek: onSeek),
  );
}

class _TranscriptSheet extends StatelessWidget {
  final MediaTranscript transcript;
  final ValueChanged<Duration>? onSeek;

  const _TranscriptSheet({required this.transcript, this.onSeek});

  @override
  Widget build(BuildContext context) {
    final hasText = transcript.transcript.trim().isNotEmpty;
    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(LucideIcons.subtitles, color: Theme.of(context).primaryColor),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Transcript',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              IconButton(
                tooltip: 'Copy',
                icon: const Icon(LucideIcons.copy, size: 18),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: transcript.transcript));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Transcript copied')),
                    );
                  }
                },
              ),
              IconButton(
                tooltip: 'Download .vtt',
                icon: const Icon(LucideIcons.download, size: 18),
                onPressed: () => _shareVtt(context),
              ),
            ],
          ),
          if (transcript.language != null) ...[
            const SizedBox(height: 2),
            Text(
              'Language: ${transcript.language} • ${transcript.wordCount} words'
              '${transcript.model != null ? ' • ${transcript.model}' : ''}',
              style: const TextStyle(color: Colors.grey, fontSize: 11),
            ),
          ],
          const SizedBox(height: 8),
          if (transcript.verseMarkers.isNotEmpty)
            SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: transcript.verseMarkers.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final m = transcript.verseMarkers[i];
                  return ActionChip(
                    avatar: const Icon(LucideIcons.bookOpen, size: 14),
                    label: Text(m.reference,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    onPressed: m.start == null || onSeek == null
                        ? null
                        : () => onSeek!(m.start!),
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: hasText
                ? (transcript.segments.isEmpty
                    ? SingleChildScrollView(
                        child: SelectableText(
                          transcript.transcript,
                          style: const TextStyle(height: 1.7),
                        ),
                      )
                    : ListView.builder(
                        itemCount: transcript.segments.length,
                        itemBuilder: (context, i) {
                          final s = transcript.segments[i];
                          return InkWell(
                            onTap: onSeek == null ? null : () => onSeek!(s.start),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 52,
                                    child: Text(
                                      _mmss(s.start),
                                      style: TextStyle(
                                        color: Theme.of(context).primaryColor,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(s.text,
                                        style: const TextStyle(height: 1.5, fontSize: 14)),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ))
                : Center(
                    child: Text(
                      transcript.isFailed
                          ? (transcript.error ?? 'Transcription failed.')
                          : 'This recording has not been transcribed yet.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _shareVtt(BuildContext context) async {
    try {
      final bytes = utf8.encode(
        transcript.vtt.trim().isNotEmpty
            ? transcript.vtt
            : _buildVttFallback(transcript),
      );
      final XFile file;
      if (kIsWeb) {
        file = XFile.fromData(bytes,
            mimeType: 'text/vtt', name: 'transcript.vtt');
      } else {
        final dir = await getTemporaryDirectory();
        file = XFile.fromData(
          bytes,
          path: '${dir.path}/transcript.vtt',
          mimeType: 'text/vtt',
          name: 'transcript.vtt',
        );
      }
      await SharePlus.instance.share(ShareParams(files: [file]));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  static String _buildVttFallback(MediaTranscript t) {
    final buf = StringBuffer('WEBVTT\n\n');
    for (final s in t.segments) {
      buf.writeln('${_vtt(s.start)} --> ${_vtt(s.end)}');
      buf.writeln(s.text);
      buf.writeln();
    }
    return buf.toString();
  }

  static String _mmss(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  static String _vtt(Duration d) {
    String p(int n, [int w = 2]) => n.toString().padLeft(w, '0');
    return '${p(d.inHours)}:${p(d.inMinutes % 60)}:${p(d.inSeconds % 60)}.${p(d.inMilliseconds % 1000, 3)}';
  }
}
