import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:church_on_app/core/services/unified_stream_service.dart';

/// ONE active stream per church — client hand-off.
///
/// A church (tenant) may have at most one `live_streams` row with
/// `status = 'live'` (enforced by a partial unique index server-side). When a
/// permitted user taps "Start Stream" and another stream is already live, offer
/// to stop the other broadcast and start theirs.
///
/// On confirm this calls the `stop_other_streams` RPC (which ends every other
/// live row for the church) and then disables each stopped Cloudflare live
/// input, so the old ingest can no longer publish. Returns `true` when the
/// caller may proceed to create its own stream, `false` to abort.
Future<bool> confirmReplaceActiveStream(
  BuildContext context,
  WidgetRef ref,
  String tenantId,
) async {
  if (tenantId.isEmpty) return true;
  final service = ref.read(unifiedStreamServiceProvider);

  Map<String, dynamic>? existing;
  try {
    existing = await service.findActiveStreamForChurch(tenantId);
  } catch (e) {
    debugPrint('[Stream] active-stream check failed (non-fatal): $e');
    return true; // Never block starting on a check failure.
  }

  final existingId = existing?['id']?.toString();
  if (existing == null || existingId == null || existingId.isEmpty) return true;
  if (!context.mounted) return false;

  final rawTitle = existing['title']?.toString().trim() ?? '';
  final title = rawTitle.isNotEmpty ? rawTitle : 'Another service';

  final proceed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Another stream is already live'),
      content: Text(
        '"$title" is currently live for this church. Only one stream can be '
        'live at a time.\n\nStop it and start yours?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('CANCEL'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          child: const Text('STOP & START'),
        ),
      ],
    ),
  );
  if (proceed != true) return false;

  try {
    await service.stopOtherStreams(churchId: tenantId);
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not stop the other stream: $e')),
      );
    }
    return false;
  }
}
