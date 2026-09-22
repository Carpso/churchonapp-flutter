import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:just_audio/just_audio.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/features/modules/events/data/meeting_room_controller.dart';
import 'package:church_on_app/features/modules/events/data/meeting_service.dart';

/// Real Pro Business Meeting: lobby -> live WebRTC room -> records.
///
/// Resolve the meeting by [meetingId], [meetingCode], or pass [initialMeeting]
/// directly (used by the host sheet right after creation).
class BusinessMeetingsScreen extends ConsumerStatefulWidget {
  final String? meetingId;
  final String? meetingCode;
  final BusinessMeeting? initialMeeting;

  const BusinessMeetingsScreen({
    super.key,
    this.meetingId,
    this.meetingCode,
    this.initialMeeting,
  });

  @override
  ConsumerState<BusinessMeetingsScreen> createState() =>
      _BusinessMeetingsScreenState();
}

class _BusinessMeetingsScreenState
    extends ConsumerState<BusinessMeetingsScreen> {
  BusinessMeeting? _meeting;
  MeetingRoomController? _room;
  StreamSubscription<BusinessMeeting>? _meetingSub;

  bool _loading = true;
  String? _error;
  bool _joining = false;
  bool _left = false;
  int _elapsed = 0;
  Timer? _timer;

  final _noteCtrl = TextEditingController();
  final _agendaCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialMeeting != null) {
      _meeting = widget.initialMeeting;
      _loading = false;
      _listenMeeting();
    } else {
      _resolve();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _meetingSub?.cancel();
    _room?.removeListener(_onRoomChanged);
    _room?.dispose();
    _noteCtrl.dispose();
    _agendaCtrl.dispose();
    super.dispose();
  }

  Future<void> _resolve() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final svc = ref.read(meetingServiceProvider);
      BusinessMeeting? m;
      if (widget.meetingId != null && widget.meetingId!.isNotEmpty) {
        m = await svc.fetchMeeting(widget.meetingId!);
      } else if (widget.meetingCode != null && widget.meetingCode!.isNotEmpty) {
        m = await svc.fetchMeetingByCode(widget.meetingCode!);
      }
      if (m == null) {
        throw MeetingException(
            'Meeting not found. Check the code and try again.');
      }
      if (!mounted) return;
      setState(() => _meeting = m);
      _listenMeeting();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _listenMeeting() {
    final m = _meeting;
    if (m == null) return;
    _meetingSub?.cancel();
    _meetingSub = ref.read(meetingServiceProvider).streamMeeting(m.id).listen((updated) {
      if (!mounted) return;
      setState(() => _meeting = updated);
      if (updated.isEnded && _room != null && !_left) {
        _room?.leave();
        setState(() => _left = true);
      }
    });
  }

  void _onRoomChanged() {
    if (mounted) setState(() {});
  }

  void _showSnack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red.shade700 : null,
    ));
  }

  String? get _uid => ref.read(meetingServiceProvider).currentUserId;

  bool get _isHost => _meeting != null && _meeting!.hostId == _uid;

  // ── Join / start ──────────────────────────────────────────────────────────
  Future<void> _join({bool startIfHost = false}) async {
    final m = _meeting;
    final uid = _uid;
    if (m == null || uid == null) {
      _showSnack('You need to be signed in to join.', error: true);
      return;
    }
    setState(() {
      _joining = true;
      _error = null;
    });
    final profile = ref.read(profileProvider).value;
    final svc = ref.read(meetingServiceProvider);
    final room = MeetingRoomController(
      client: svc.client,
      service: svc,
      selfId: uid,
      selfName: profile?.name ?? 'You',
      selfAvatar: profile?.avatarUrl,
      isHost: m.hostId == uid,
    );
    try {
      if (startIfHost && m.hostId == uid && !m.isLive) {
        await svc.startMeeting(m.id);
      }
      await room.init(m.id);
      if (!mounted) return;
      room.addListener(_onRoomChanged);
      setState(() {
        _room = room;
        _left = false;
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _elapsed++);
      });
    } catch (e) {
      room.dispose();
      _showSnack(e.toString(), error: true);
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _leave({bool endForAll = false}) async {
    final room = _room;
    if (room == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    _timer?.cancel();
    await room.leave(endForAll: endForAll);
    room.removeListener(_onRoomChanged);
    if (!mounted) return;
    setState(() {
      _left = true;
      _elapsed = 0;
    });
  }

  // ── Recording ─────────────────────────────────────────────────────────────
  Future<void> _toggleRecording() async {
    final room = _room;
    if (room == null) return;
    if (room.isRecording) {
      final url = await room.stopRecording();
      _showSnack(url != null
          ? 'Recording saved to the meeting.'
          : 'Recording could not be saved.',
          error: url == null);
    } else {
      try {
        await room.startRecording();
        _showSnack('Recording started.');
      } catch (e) {
        _showSnack(e.toString(), error: true);
      }
    }
  }

  void _playRecording(String url) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _RecordingPlayerSheet(url: url),
    );
  }

  // ── Export ────────────────────────────────────────────────────────────────
  String _buildMinutesText() {
    final m = _meeting;
    if (m == null) return '';
    final notes = ref.read(meetingNotesProvider(m.id)).value ?? const <MeetingNote>[];
    final parts =
        ref.read(meetingParticipantsProvider(m.id)).value ?? const <MeetingParticipant>[];
    final agenda =
        ref.read(meetingAgendaProvider(m.id)).value ?? const <MeetingAgendaItem>[];

    final buf = StringBuffer()
      ..writeln('MINUTES — ${m.title}')
      ..writeln('Code: ${m.meetingCode}')
      ..writeln('Status: ${m.status}')
      ..writeln('Scheduled: ${m.scheduledAt ?? m.createdAt ?? '-'}')
      ..writeln('Duration: ${m.durationMinutes} min (${m.timezone})')
      ..writeln();

    buf.writeln('AGENDA');
    if (agenda.isEmpty) {
      buf.writeln('  (none)');
    } else {
      for (var i = 0; i < agenda.length; i++) {
        buf.writeln('  ${i + 1}. [${agenda[i].isDone ? 'x' : ' '}] ${agenda[i].title}');
      }
    }
    buf.writeln();

    buf.writeln('ATTENDANCE');
    if (parts.isEmpty) {
      buf.writeln('  (none)');
    } else {
      for (final p in parts) {
        buf.writeln(
            '  ${p.fullName ?? p.userId} (${p.role}) joined ${p.joinedAt ?? '-'}'
            '${p.leftAt != null ? ' — left ${p.leftAt}' : ''}');
      }
    }
    buf.writeln();

    buf.writeln('MINUTES / NOTES');
    if (notes.isEmpty) {
      buf.writeln('  (none)');
    } else {
      for (final n in notes.reversed) {
        buf.writeln('  [${n.createdAt}] ${n.content}');
      }
    }
    return buf.toString();
  }

  Future<void> _copyMinutes() async {
    final text = _buildMinutesText();
    await Clipboard.setData(ClipboardData(text: text));
    _showSnack('Minutes copied to clipboard.');
  }

  Future<void> _shareMinutes() async {
    final text = _buildMinutesText();
    final m = _meeting;
    final csv = _buildAttendanceCsv();
    try {
      final file = XFile.fromData(
        Uint8List.fromList(utf8.encode(csv)),
        name: 'meeting_minutes_${m?.meetingCode ?? 'export'}.csv',
        mimeType: 'text/csv',
      );
      await SharePlus.instance.share(
        ShareParams(files: [file], text: text, subject: m?.title ?? 'Meeting minutes'),
      );
    } catch (e) {
      debugPrint('file share failed, sharing text: $e');
      await SharePlus.instance.share(ShareParams(text: text));
    }
  }

  String _buildAttendanceCsv() {
    final m = _meeting;
    if (m == null) return '';
    final parts =
        ref.read(meetingParticipantsProvider(m.id)).value ?? const <MeetingParticipant>[];
    final buf = StringBuffer()..writeln('name,role,joined_at,left_at');
    for (final p in parts) {
      final name = (p.fullName ?? p.userId).replaceAll(',', ' ');
      buf.writeln('$name,${p.role},${p.joinedAt ?? ''},${p.leftAt ?? ''}');
    }
    return buf.toString();
  }

  // ── Invites ───────────────────────────────────────────────────────────────
  void _openInviteSheet() {
    final m = _meeting;
    if (m == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _InviteSheet(meeting: m),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F172A),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null && _meeting == null) {
      return _ErrorScaffold(message: _error!, onRetry: _resolve);
    }
    final m = _meeting;
    if (m == null) {
      return _ErrorScaffold(
        message: 'Meeting not found.',
        onRetry: _resolve,
      );
    }

    final room = _room;
    if (room != null && !_left) {
      return _buildRoom(m, room);
    }
    if (_left) {
      return _buildEnded(m);
    }
    return _buildLobby(m);
  }

  // ── Lobby ─────────────────────────────────────────────────────────────────
  Widget _buildLobby(BusinessMeeting m) {
    final uid = _uid;
    final isHost = m.hostId == uid;
    final entitlement = ref.watch(meetingEntitlementProvider);
    final rsvps = ref.watch(meetingRsvpsProvider(m.id)).value ?? const <MeetingRsvp>[];
    final agenda = ref.watch(meetingAgendaProvider(m.id)).value ?? const <MeetingAgendaItem>[];
    final myRsvp = rsvps.where((r) => r.userId == uid).toList();
    final canJoin = m.isLive || isHost;
    final rsvpStatus = myRsvp.isEmpty ? null : myRsvp.first.status;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(m.title,
            style: const TextStyle(color: Colors.white, fontSize: 16)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          _statusChip(m),
          const SizedBox(height: 16),
          _infoRow(LucideIcons.hash, 'Meeting code', m.meetingCode),
          _infoRow(LucideIcons.calendar,
              'Scheduled', _formatDateTime(m.scheduledAt)),
          _infoRow(LucideIcons.clock, 'Duration', '${m.durationMinutes} min · ${m.timezone}'),
          _infoRow(LucideIcons.users, 'Capacity',
              '${m.maxParticipants} participants${entitlement.value?.pro == true ? ' (Pro)' : ' (Free)'}'),
          if (m.isRecurring)
            _infoRow(LucideIcons.repeat, 'Recurring', m.recurrenceRule ?? 'yes'),
          if ((m.description ?? '').isNotEmpty)
            _infoRow(LucideIcons.fileText, 'Description', m.description!),
          const SizedBox(height: 20),
          if (agenda.isNotEmpty) ...[
            const _SectionTitle('AGENDA'),
            ...agenda.map((a) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    a.isDone ? LucideIcons.checkCircle2 : LucideIcons.circle,
                    color: a.isDone ? Colors.greenAccent : Colors.white38,
                    size: 18,
                  ),
                  title: Text(a.title,
                      style: const TextStyle(color: Colors.white70, fontSize: 13)),
                )),
            const SizedBox(height: 12),
          ],
          if (rsvpStatus == 'invited') ...[
            const _SectionTitle('YOUR RSVP'),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _respondRsvp(m, 'accepted'),
                    icon: const Icon(LucideIcons.check, color: Colors.greenAccent),
                    label: const Text('Accept',
                        style: TextStyle(color: Colors.greenAccent)),
                    style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.greenAccent)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _respondRsvp(m, 'declined'),
                    icon: const Icon(LucideIcons.x, color: Colors.redAccent),
                    label: const Text('Decline',
                        style: TextStyle(color: Colors.redAccent)),
                    style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.redAccent)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          if ((m.recordingUrl ?? '').isNotEmpty) ...[
            _SectionTitle('RECORDING · ${m.recordingStatus.toUpperCase()}'),
            OutlinedButton.icon(
              onPressed: () => _playRecording(m.recordingUrl!),
              icon: const Icon(LucideIcons.play, color: Colors.amber),
              label: const Text('Play recording',
                  style: TextStyle(color: Colors.amber)),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  side: const BorderSide(color: Colors.amber)),
            ),
            const SizedBox(height: 16),
          ],
          if (!canJoin)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'The host has not started this meeting yet. You can join once it goes live.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _joining || !canJoin ? null : () => _join(startIfHost: true),
            icon: _joining
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(isHost ? LucideIcons.play : LucideIcons.logIn,
                    color: Colors.black),
            label: Text(
              isHost ? 'START / JOIN MEETING' : 'JOIN MEETING',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.black,
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
          ),
          if (isHost) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _openInviteSheet,
              icon: const Icon(LucideIcons.userPlus, color: Colors.white70),
              label: const Text('Invite participants',
                  style: TextStyle(color: Colors.white70)),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48)),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => _cancelMeeting(m),
              icon: const Icon(LucideIcons.trash2, color: Colors.redAccent),
              label: const Text('Cancel meeting',
                  style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _respondRsvp(BusinessMeeting m, String status) async {
    try {
      await ref.read(meetingServiceProvider).respondRsvp(m.id, status);
      _showSnack('RSVP updated.');
    } catch (e) {
      _showSnack(e.toString(), error: true);
    }
  }

  Future<void> _cancelMeeting(BusinessMeeting m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Cancel meeting?', style: TextStyle(color: Colors.white)),
        content: const Text('Invitees will no longer be able to join.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cancel meeting')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(meetingServiceProvider).cancelMeeting(m.id);
      _showSnack('Meeting cancelled.');
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _showSnack(e.toString(), error: true);
    }
  }

  // ── Live room ─────────────────────────────────────────────────────────────
  Widget _buildRoom(BusinessMeeting m, MeetingRoomController room) {
    final peers = room.peers;
    final tiles = 1 + peers.length;
    final crossAxis = tiles <= 1 ? 1 : 2;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft, color: Colors.white),
          onPressed: () => _leave(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(m.title,
                style: const TextStyle(color: Colors.white, fontSize: 15)),
            Row(
              children: [
                Icon(
                  room.state == MeetingRoomState.reconnecting
                      ? LucideIcons.wifiOff
                      : LucideIcons.radio,
                  color: room.state == MeetingRoomState.reconnecting
                      ? Colors.amber
                      : Colors.greenAccent,
                  size: 10,
                ),
                const SizedBox(width: 5),
                Text(
                  room.state == MeetingRoomState.reconnecting
                      ? 'Reconnecting…'
                      : 'Live · ${_formatDuration(_elapsed)} · $tiles in room',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
        actions: [
          if (room.isRecording)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(
                child: Icon(LucideIcons.circle, color: Colors.redAccent, size: 14),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          if (room.state == MeetingRoomState.error && room.error != null)
            Container(
              width: double.infinity,
              color: Colors.red.shade900,
              padding: const EdgeInsets.all(10),
              child: Text(room.error!,
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
          Expanded(
            child: GridView.count(
              padding: const EdgeInsets.all(12),
              crossAxisCount: crossAxis,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: crossAxis == 1 ? 3 / 4 : 3 / 4,
              children: [
                _buildTile(
                  name: '${ref.read(profileProvider).value?.name ?? 'You'} (You)',
                  avatar: ref.read(profileProvider).value?.avatarUrl,
                  renderer: room.localRenderer,
                  ready: room.localRendererReady && !room.isVideoOff,
                  muted: room.isMuted,
                  isMe: true,
                ),
                ...peers.map((p) => _buildTile(
                      name: p.name ?? 'Participant',
                      avatar: p.avatar,
                      renderer: p.renderer,
                      ready: p.remoteReady && !p.videoOff,
                      muted: p.muted,
                      isMe: false,
                    )),
              ],
            ),
          ),
          _buildControlBar(room, m),
        ],
      ),
    );
  }

  Widget _buildTile({
    required String name,
    String? avatar,
    RTCVideoRenderer? renderer,
    required bool ready,
    required bool muted,
    required bool isMe,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        color: Colors.white.withValues(alpha: 0.05),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (ready && renderer != null)
              RTCVideoView(
                renderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                mirror: isMe,
              )
            else
              Center(
                child: CircleAvatar(
                  radius: 34,
                  backgroundColor: Colors.white10,
                  backgroundImage: (avatar ?? '').isNotEmpty
                      ? NetworkImage(avatar!)
                      : null,
                  child: (avatar ?? '').isEmpty
                      ? Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 26),
                        )
                      : null,
                ),
              ),
            Positioned(
              bottom: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (muted)
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(LucideIcons.micOff,
                            color: Colors.redAccent, size: 12),
                      ),
                    Text(name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlBar(MeetingRoomController room, BusinessMeeting m) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 28),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _ctrl(
            room.isMuted ? LucideIcons.micOff : LucideIcons.mic,
            room.isMuted ? Colors.redAccent : Colors.white,
            room.toggleMic,
            tooltip: room.isMuted ? 'Unmute' : 'Mute',
          ),
          _ctrl(
            room.isVideoOff ? LucideIcons.videoOff : LucideIcons.video,
            room.isVideoOff ? Colors.redAccent : Colors.white,
            room.audioOnly ? null : room.toggleVideo,
            tooltip: 'Camera',
          ),
          _ctrl(LucideIcons.switchCamera, Colors.white, room.switchCamera,
              tooltip: 'Flip camera'),
          _ctrl(LucideIcons.users, Colors.white, _openParticipantsSheet,
              tooltip: 'Participants'),
          _ctrl(LucideIcons.listChecks, Colors.white, _openAgendaSheet,
              tooltip: 'Agenda'),
          _ctrl(LucideIcons.messageSquare, Theme.of(context).primaryColor,
              _openRecordsSheet,
              tooltip: 'Minutes & votes'),
          if (_isHost)
            _ctrl(
              room.isRecording ? LucideIcons.stopCircle : LucideIcons.circle,
              room.isRecording ? Colors.redAccent : Colors.white,
              _toggleRecording,
              tooltip: room.isRecording ? 'Stop recording' : 'Record',
            ),
          Container(
            height: 46,
            width: 64,
            decoration: BoxDecoration(
                color: Colors.red, borderRadius: BorderRadius.circular(14)),
            child: IconButton(
              tooltip: _isHost ? 'End for all' : 'Leave',
              icon: Icon(_isHost ? LucideIcons.phoneOff : LucideIcons.logOut,
                  color: Colors.white),
              onPressed: () => _confirmLeave(m),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ctrl(IconData icon, Color color, VoidCallback? onTap,
      {required String tooltip}) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, color: color, size: 22),
      onPressed: onTap,
    );
  }

  Future<void> _confirmLeave(BusinessMeeting m) async {
    if (!_isHost) {
      await _leave();
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Leave meeting', style: TextStyle(color: Colors.white)),
        content: const Text('End it for everyone, or just leave?',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'leave'),
              child: const Text('Just me')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, 'end'),
              child: const Text('End for all')),
        ],
      ),
    );
    if (choice == 'end') {
      await _leave(endForAll: true);
    } else if (choice == 'leave') {
      await _leave();
    }
  }

  // ── Sheets ────────────────────────────────────────────────────────────────
  void _openParticipantsSheet() {
    final m = _meeting;
    if (m == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _ParticipantsSheet(
        meeting: m,
        isHost: _isHost,
        selfId: _uid,
        onInvite: () {
          Navigator.pop(context);
          _openInviteSheet();
        },
      ),
    );
  }

  void _openAgendaSheet() {
    final m = _meeting;
    if (m == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _AgendaSheet(meeting: m, isHost: _isHost),
    );
  }

  void _openRecordsSheet() {
    final m = _meeting;
    if (m == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => _RecordsPanel(
        meeting: m,
        noteCtrl: _noteCtrl,
        onCopy: _copyMinutes,
        onShare: _shareMinutes,
      ),
    );
  }

  // ── Ended ─────────────────────────────────────────────────────────────────
  Widget _buildEnded(BusinessMeeting m) {
    final recording = m.recordingUrl;
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.checkCircle2,
                  color: Colors.greenAccent, size: 56),
              const SizedBox(height: 16),
              Text(
                m.isEnded ? 'Meeting ended' : 'You left the meeting',
                style: const TextStyle(
                    color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(m.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54)),
              const SizedBox(height: 24),
              if (recording != null && recording.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => _playRecording(recording),
                  icon: const Icon(LucideIcons.play, color: Colors.amber),
                  label: const Text('Play recording',
                      style: TextStyle(color: Colors.amber)),
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50)),
                ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () {
                  setState(() {
                    _left = false;
                    _elapsed = 0;
                  });
                },
                icon: const Icon(LucideIcons.refreshCw, size: 18),
                label: const Text('Back to meeting'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50)),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: _copyMinutes,
                icon: const Icon(LucideIcons.copy, color: Colors.white54, size: 16),
                label: const Text('Copy minutes',
                    style: TextStyle(color: Colors.white54)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Small helpers ─────────────────────────────────────────────────────────
  Widget _statusChip(BusinessMeeting m) {
    final (label, color) = switch (m.status) {
      'live' || 'active' => ('LIVE', Colors.greenAccent),
      'scheduled' => ('SCHEDULED', Colors.amber),
      'cancelled' => ('CANCELLED', Colors.redAccent),
      _ => ('ENDED', Colors.white54),
    };
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Text(label,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.bold)),
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Copy code',
          icon: const Icon(LucideIcons.copy, color: Colors.white54, size: 18),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: m.meetingCode));
            _showSnack('Meeting code copied.');
          },
        ),
      ],
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white38, size: 16),
          const SizedBox(width: 12),
          SizedBox(
            width: 90,
            child: Text(label,
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return 'Not scheduled';
    final local = dt.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  String _formatDuration(int sec) {
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

// ============================================================================
// Helper widgets
// ============================================================================

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1)),
      );
}

class _ErrorScaffold extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorScaffold({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.alertTriangle,
                  color: Colors.amber, size: 48),
              const SizedBox(height: 16),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(LucideIcons.refreshCw, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ParticipantsSheet extends ConsumerWidget {
  final BusinessMeeting meeting;
  final bool isHost;
  final String? selfId;
  final VoidCallback onInvite;

  const _ParticipantsSheet({
    required this.meeting,
    required this.isHost,
    required this.selfId,
    required this.onInvite,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partsAsync = ref.watch(meetingParticipantsProvider(meeting.id));
    final rsvpsAsync = ref.watch(meetingRsvpsProvider(meeting.id));

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: Text('PARTICIPANTS',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1)),
          ),
          const SizedBox(height: 16),
          partsAsync.when(
            data: (parts) {
              final active = parts.where((p) => p.isActive).toList();
              if (active.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text('No one has joined yet.',
                        style: TextStyle(color: Colors.white38)),
                  ),
                );
              }
              return ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.4),
                child: ListView(
                  shrinkWrap: true,
                  children: active
                      .map((p) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor: Colors.white10,
                              backgroundImage: (p.avatarUrl ?? '').isNotEmpty
                                  ? NetworkImage(p.avatarUrl!)
                                  : null,
                              child: (p.avatarUrl ?? '').isEmpty
                                  ? Text(
                                      (p.fullName ?? '?')[0].toUpperCase(),
                                      style: const TextStyle(color: Colors.white))
                                  : null,
                            ),
                            title: Text(
                              '${p.fullName ?? p.userId}${p.userId == selfId ? ' (You)' : ''}',
                              style: const TextStyle(color: Colors.white),
                            ),
                            subtitle: Text(
                              '${p.role}${p.isMuted ? ' · muted' : ''}${p.isVideoOff ? ' · camera off' : ''}',
                              style: const TextStyle(color: Colors.white38, fontSize: 12),
                            ),
                          ))
                      .toList(),
                ),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text('Could not load participants: $e',
                  style: const TextStyle(color: Colors.redAccent)),
            ),
          ),
          const SizedBox(height: 12),
          if (isHost) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        await ref.read(meetingServiceProvider).muteAll(meeting.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('All participants muted.')));
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('$e')));
                        }
                      }
                    },
                    icon: const Icon(LucideIcons.micOff, color: Colors.white70),
                    label: const Text('Mute all',
                        style: TextStyle(color: Colors.white70)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onInvite,
                    icon: const Icon(LucideIcons.userPlus, size: 18),
                    label: const Text('Invite'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          rsvpsAsync.when(
            data: (rsvps) {
              final pending = rsvps.where((r) => r.status != 'accepted').toList();
              if (pending.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionTitle('INVITED'),
                  ...pending.map((r) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(LucideIcons.mail,
                            color: Colors.white38, size: 18),
                        title: Text(r.fullName ?? r.userId,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13)),
                        trailing: Text(r.status.toUpperCase(),
                            style: const TextStyle(
                                color: Colors.amber, fontSize: 10)),
                      )),
                ],
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _AgendaSheet extends ConsumerStatefulWidget {
  final BusinessMeeting meeting;
  final bool isHost;
  const _AgendaSheet({required this.meeting, required this.isHost});

  @override
  ConsumerState<_AgendaSheet> createState() => _AgendaSheetState();
}

class _AgendaSheetState extends ConsumerState<_AgendaSheet> {
  final _ctrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(meetingServiceProvider)
          .addAgendaItem(widget.meeting.id, text);
      _ctrl.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final agendaAsync = ref.watch(meetingAgendaProvider(widget.meeting.id));
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: Text('AGENDA',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1)),
          ),
          const SizedBox(height: 16),
          agendaAsync.when(
            data: (items) {
              if (items.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('No agenda items yet.',
                      style: TextStyle(color: Colors.white38)),
                );
              }
              return ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.4),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final a = items[i];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: IconButton(
                        icon: Icon(
                          a.isDone
                              ? LucideIcons.checkCircle2
                              : LucideIcons.circle,
                          color: a.isDone ? Colors.greenAccent : Colors.white38,
                          size: 20,
                        ),
                        onPressed: () => ref
                            .read(meetingServiceProvider)
                            .updateAgendaItem(a.id, isDone: !a.isDone),
                      ),
                      title: Text(
                        a.title,
                        style: TextStyle(
                          color: a.isDone ? Colors.white38 : Colors.white,
                          decoration:
                              a.isDone ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      trailing: widget.isHost
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(LucideIcons.arrowUp,
                                      color: Colors.white38, size: 18),
                                  onPressed: i == 0
                                      ? null
                                      : () {
                                          final ids = items
                                              .map((e) => e.id)
                                              .toList();
                                          final tmp = ids[i - 1];
                                          ids[i - 1] = ids[i];
                                          ids[i] = tmp;
                                          ref
                                              .read(meetingServiceProvider)
                                              .reorderAgenda(
                                                  widget.meeting.id, ids);
                                        },
                                ),
                                IconButton(
                                  icon: const Icon(LucideIcons.trash2,
                                      color: Colors.redAccent, size: 18),
                                  onPressed: () => ref
                                      .read(meetingServiceProvider)
                                      .deleteAgendaItem(a.id),
                                ),
                              ],
                            )
                          : null,
                    );
                  },
                ),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('Could not load agenda: $e',
                style: const TextStyle(color: Colors.redAccent)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Add agenda item…',
                    hintStyle: const TextStyle(color: Colors.white24),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _busy ? null : _add,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(LucideIcons.plus, color: Colors.amber),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecordsPanel extends ConsumerWidget {
  final BusinessMeeting meeting;
  final TextEditingController noteCtrl;
  final VoidCallback onCopy;
  final VoidCallback onShare;

  const _RecordsPanel({
    required this.meeting,
    required this.noteCtrl,
    required this.onCopy,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(meetingNotesProvider(meeting.id));
    final votesAsync = ref.watch(meetingVotesProvider(meeting.id));

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: EdgeInsets.fromLTRB(
          24, 20, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Leadership Records',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
              ),
              IconButton(
                tooltip: 'Copy minutes',
                icon: const Icon(LucideIcons.copy, color: Colors.white54, size: 20),
                onPressed: onCopy,
              ),
              IconButton(
                tooltip: 'Export minutes',
                icon: const Icon(LucideIcons.share2, color: Colors.white54, size: 20),
                onPressed: onShare,
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('MOTION: "Approve the proposal on the table"',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Row(
            children: [
              _voteBtn(ref, 'YES', Colors.green),
              const SizedBox(width: 10),
              _voteBtn(ref, 'NO', Colors.red),
              const Spacer(),
              votesAsync.when(
                data: (results) => Text(
                    'Results: ${results['YES'] ?? 0}Y | ${results['NO'] ?? 0}N',
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ],
          ),
          const Divider(height: 32, color: Colors.white10),
          const Text('Live Minutes',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Expanded(
            child: notesAsync.when(
              data: (notes) {
                if (notes.isEmpty) {
                  return const Center(
                    child: Text('No minutes recorded yet.',
                        style: TextStyle(color: Colors.white38)),
                  );
                }
                return ListView.builder(
                  itemCount: notes.length,
                  itemBuilder: (context, i) => Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(14)),
                    child: Text(notes[i].content,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13)),
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                  child: Text('Sync error: $e',
                      style: const TextStyle(color: Colors.redAccent))),
            ),
          ),
          TextField(
            controller: noteCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Type a minute or motion…',
              hintStyle: const TextStyle(color: Colors.white24),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none),
              suffixIcon: IconButton(
                icon: const Icon(LucideIcons.send, color: Colors.amber),
                onPressed: () {
                  if (noteCtrl.text.trim().isEmpty) return;
                  ref
                      .read(meetingServiceProvider)
                      .saveNote(meeting.id, noteCtrl.text.trim());
                  noteCtrl.clear();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _voteBtn(WidgetRef ref, String label, Color color) {
    return ElevatedButton(
      onPressed: () => ref.read(meetingServiceProvider).castVote(meeting.id, label),
      style: ElevatedButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.2),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10))),
      child: Text(label,
          style: TextStyle(color: color, fontWeight: FontWeight.bold)),
    );
  }
}

class _InviteSheet extends ConsumerStatefulWidget {
  final BusinessMeeting meeting;
  const _InviteSheet({required this.meeting});

  @override
  ConsumerState<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends ConsumerState<_InviteSheet> {
  final _searchCtrl = TextEditingController();
  final Set<String> _selected = {};
  List<Map<String, dynamic>> _users = const [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load(String query) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tenantId = ref.read(currentTenantProvider)?.id;
      final users = await ref
          .read(meetingServiceProvider)
          .searchUsers(query, tenantId: tenantId);
      if (!mounted) return;
      setState(() {
        _users = users.where((u) => u['id'].toString() != widget.meeting.hostId).toList();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _load(value));
  }

  Future<void> _send() async {
    if (_selected.isEmpty) return;
    setState(() => _sending = true);
    try {
      final count = await ref
          .read(meetingServiceProvider)
          .inviteParticipants(widget.meeting.id, _selected.toList());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invited $count participant(s).')));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: Text('INVITE PARTICIPANTS',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1)),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchCtrl,
            onChanged: _onSearchChanged,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search by name…',
              hintStyle: const TextStyle(color: Colors.white24),
              prefixIcon: const Icon(LucideIcons.search, color: Colors.white38),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Text('Could not load people: $_error',
                style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
          ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.42),
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 30),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _users.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 30),
                        child: Center(
                          child: Text('No members found.',
                              style: TextStyle(color: Colors.white38)),
                        ),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: _users.map((u) {
                          final id = u['id'].toString();
                          final name =
                              (u['full_name'] ?? 'Member').toString();
                          final avatar = u['avatar_url']?.toString();
                          return CheckboxListTile(
                            value: _selected.contains(id),
                            onChanged: (v) => setState(() {
                              if (v == true) {
                                _selected.add(id);
                              } else {
                                _selected.remove(id);
                              }
                            }),
                            activeColor: Colors.amber,
                            contentPadding: EdgeInsets.zero,
                            secondary: CircleAvatar(
                              backgroundColor: Colors.white10,
                              backgroundImage:
                                  (avatar ?? '').isNotEmpty ? NetworkImage(avatar!) : null,
                              child: (avatar ?? '').isEmpty
                                  ? Text(name[0].toUpperCase(),
                                      style: const TextStyle(color: Colors.white))
                                  : null,
                            ),
                            title: Text(name,
                                style: const TextStyle(color: Colors.white)),
                            subtitle: Text((u['role'] ?? '').toString(),
                                style: const TextStyle(
                                    color: Colors.white38, fontSize: 12)),
                          );
                        }).toList(),
                      ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _sending || _selected.isEmpty ? null : _send,
            icon: _sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(LucideIcons.send, size: 18),
            label: Text('Invite ${_selected.length} selected'),
            style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 50)),
          ),
        ],
      ),
    );
  }
}

class _RecordingPlayerSheet extends StatefulWidget {
  final String url;
  const _RecordingPlayerSheet({required this.url});

  @override
  State<_RecordingPlayerSheet> createState() => _RecordingPlayerSheetState();
}

class _RecordingPlayerSheetState extends State<_RecordingPlayerSheet> {
  late final AudioPlayer _player;
  String? _error;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _player.setUrl(widget.url).catchError((e) {
      if (mounted) setState(() => _error = e.toString());
      return null;
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Meeting recording',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          if (_error != null)
            Text('Could not load recording: $_error',
                style: const TextStyle(color: Colors.redAccent))
          else ...[
            StreamBuilder<PlayerState>(
              stream: _player.playerStateStream,
              builder: (context, snapshot) {
                final playing = snapshot.data?.playing ?? false;
                return IconButton(
                  iconSize: 56,
                  icon: Icon(
                    playing
                        ? LucideIcons.pauseCircle
                        : LucideIcons.playCircle,
                    color: Colors.amber,
                  ),
                  onPressed: () => playing ? _player.pause() : _player.play(),
                );
              },
            ),
            StreamBuilder<Duration>(
              stream: _player.positionStream,
              builder: (context, snapshot) {
                final pos = snapshot.data ?? Duration.zero;
                final total = _player.duration ?? Duration.zero;
                return Slider(
                  value: total.inMilliseconds == 0
                      ? 0
                      : pos.inMilliseconds
                          .clamp(0, total.inMilliseconds)
                          .toDouble(),
                  max: total.inMilliseconds == 0
                      ? 1
                      : total.inMilliseconds.toDouble(),
                  onChanged: (v) => _player.seek(Duration(milliseconds: v.toInt())),
                );
              },
            ),
          ],
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: widget.url));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Recording link copied.')));
              }
            },
            icon: const Icon(LucideIcons.link, color: Colors.white54, size: 16),
            label: const Text('Copy link',
                style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }
}
