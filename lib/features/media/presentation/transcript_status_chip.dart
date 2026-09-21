import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:church_on_app/core/providers/profile_provider.dart';
import '../data/transcript_service.dart';
import 'transcript_sheet.dart';

/// Compact transcription status chip for sermon / recording lists.
///
/// Leaders see the real job state — Queued / Transcribing N% / Transcript
/// (ready) / Failed · retry — and can open the transcript or retry a failed
/// run. Regular members only ever see a subtle "CC" badge once a transcript is
/// ready; otherwise the chip renders nothing.
class TranscriptStatusChip extends ConsumerWidget {
  final String? sermonId;
  final String? liveStreamId;
  final ValueChanged<Duration>? onSeek;
  final bool compact;

  const TranscriptStatusChip({
    super.key,
    this.sermonId,
    this.liveStreamId,
    this.onSeek,
    this.compact = true,
  }) : assert(sermonId != null || liveStreamId != null,
            'Provide sermonId or liveStreamId');

  static const _leaderRoles = {
    'superadmin', 'super_admin', 'coa_employee', 'employee',
    'bishop', 'apostle', 'prophet', 'general_secretary', 'general_treasurer',
    'pastor', 'admin', 'leader', 'department_leader', 'treasurer',
  };

  TranscriptKey get _key => (sermonId: sermonId, liveStreamId: liveStreamId);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transcript = ref.watch(transcriptPollProvider(_key)).value;
    if (transcript == null) return const SizedBox.shrink();

    final profile = ref.watch(profileProvider).value;
    final isLeader = profile != null && _leaderRoles.contains(profile.role);

    if (transcript.isReady) {
      return _chip(
        context,
        icon: LucideIcons.subtitles,
        label: isLeader ? 'TRANSCRIPT' : 'CC',
        onTap: () => showTranscriptSheet(
          context,
          transcript: transcript,
          onSeek: onSeek,
        ),
      );
    }

    // In-progress / failed states are only meaningful to leaders.
    if (!isLeader) return const SizedBox.shrink();

    if (transcript.isFailed) {
      return _chip(
        context,
        icon: LucideIcons.refreshCw,
        label: 'FAILED · RETRY',
        onTap: () => _retry(context, ref),
        danger: true,
      );
    }

    final pct = transcript.chunkTotal > 1
        ? ((transcript.chunkIndex / transcript.chunkTotal) * 100)
            .clamp(0, 100)
            .round()
        : null;
    return _chip(
      context,
      icon: transcript.status == 'pending' ? LucideIcons.clock : null,
      label: transcript.status == 'pending'
          ? 'QUEUED'
          : (pct != null ? 'TRANSCRIBING $pct%' : 'TRANSCRIBING…'),
      busy: transcript.status == 'processing',
    );
  }

  Future<void> _retry(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(transcriptServiceProvider).requestTranscription(
            sermonId: sermonId,
            liveStreamId: liveStreamId,
            force: true,
          );
      ref.invalidate(transcriptPollProvider(_key));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not start transcription: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Widget _chip(
    BuildContext context, {
    required IconData? icon,
    required String label,
    VoidCallback? onTap,
    bool busy = false,
    bool danger = false,
  }) {
    final primary = Theme.of(context).primaryColor;
    final color = danger ? Colors.red : primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 12,
          vertical: compact ? 4 : 7,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: busy ? 0.25 : 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            else if (icon != null)
              Icon(icon, size: compact ? 11 : 14, color: color),
            if (busy || icon != null) const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: compact ? 9 : 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
