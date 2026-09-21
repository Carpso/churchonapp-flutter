import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:church_on_app/core/providers/profile_provider.dart';
import '../data/transcript_service.dart';
import 'transcript_sheet.dart';

/// Leadership-only "Transcribe" action for a sermon or live-stream recording.
///
/// Reflects the real server state (pending / processing / ready / failed) and
/// offers a retry when a run failed. Non-leaders see only the transcript view
/// once one exists.
class TranscribeAction extends ConsumerStatefulWidget {
  final String? sermonId;
  final String? liveStreamId;
  final ValueChanged<Duration>? onSeek;

  const TranscribeAction({
    super.key,
    this.sermonId,
    this.liveStreamId,
    this.onSeek,
  }) : assert(sermonId != null || liveStreamId != null,
            'Provide sermonId or liveStreamId');

  @override
  ConsumerState<TranscribeAction> createState() => _TranscribeActionState();
}

class _TranscribeActionState extends ConsumerState<TranscribeAction> {
  bool _busy = false;

  static const _leaderRoles = {
    'superadmin', 'super_admin', 'coa_employee', 'employee',
    'bishop', 'apostle', 'prophet', 'general_secretary', 'general_treasurer',
    'pastor', 'admin', 'leader', 'department_leader', 'treasurer',
  };

  bool _isLeader(UserProfile? p) => p != null && _leaderRoles.contains(p.role);

  @override
  Widget build(BuildContext context) {
    final async = widget.sermonId != null
        ? ref.watch(sermonTranscriptProvider(widget.sermonId!))
        : ref.watch(liveStreamTranscriptProvider(widget.liveStreamId!));
    final transcript = async.value;
    final profile = ref.watch(profileProvider).value;
    final isLeader = _isLeader(profile);

    if (transcript != null && transcript.isReady) {
      return _pill(
        context,
        icon: LucideIcons.subtitles,
        label: 'TRANSCRIPT',
        onTap: () => showTranscriptSheet(
          context,
          transcript: transcript,
          onSeek: widget.onSeek,
        ),
      );
    }

    if (!isLeader) return const SizedBox.shrink();

    if (_busy || (transcript?.isWorking ?? false)) {
      return _pill(
        context,
        icon: null,
        label: transcript != null && transcript.chunkTotal > 1
            ? 'TRANSCRIBING ${transcript.chunkIndex}/${transcript.chunkTotal}…'
            : 'TRANSCRIBING…',
        busy: true,
      );
    }

    final failed = transcript?.isFailed ?? false;
    return _pill(
      context,
      icon: failed ? LucideIcons.refreshCw : LucideIcons.sparkles,
      label: failed ? 'RETRY TRANSCRIPTION' : 'TRANSCRIBE',
      onTap: _start,
    );
  }

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      await ref.read(transcriptServiceProvider).requestTranscription(
            sermonId: widget.sermonId,
            liveStreamId: widget.liveStreamId,
            force: true,
          );
      if (widget.sermonId != null) {
        ref.invalidate(sermonTranscriptProvider(widget.sermonId!));
      } else {
        ref.invalidate(liveStreamTranscriptProvider(widget.liveStreamId!));
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Transcription queued — it finishes in the background.'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not start transcription: $e'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _pill(
    BuildContext context, {
    required IconData? icon,
    required String label,
    VoidCallback? onTap,
    bool busy = false,
  }) {
    final primary = Theme.of(context).primaryColor;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: primary.withValues(alpha: busy ? 0.25 : 0.14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: primary.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2, color: primary),
              )
            else if (icon != null)
              Icon(icon, size: 14, color: primary),
            if (busy || icon != null) const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
                color: primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
