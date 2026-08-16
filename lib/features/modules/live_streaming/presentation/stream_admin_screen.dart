import 'dart:math' as dart_math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shimmer/shimmer.dart';
import 'package:go_router/go_router.dart';
import 'package:church_on_app/features/modules/live_streaming/data/live_stream_service.dart';
import 'package:church_on_app/core/services/subscription_service.dart';
import 'package:church_on_app/core/widgets/premium_toast.dart';

/// Church admin streaming dashboard with trial limits
/// Shows usage, stream key, go live, and upgrade prompt
class StreamAdminScreen extends ConsumerStatefulWidget {
  final String tenantId;

  const StreamAdminScreen({super.key, required this.tenantId});

  @override
  ConsumerState<StreamAdminScreen> createState() => _StreamAdminScreenState();
}

class _StreamAdminScreenState extends ConsumerState<StreamAdminScreen> {
  String? _streamKey;
  String? _rtmpUrl;
  bool _loading = true;
  StreamingUsage? _usage;
  bool _isTrial = true;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      // Load stream config
      final result = await Supabase.instance.client
          .from('church_stream_config')
          .select()
          .eq('church_id', widget.tenantId)
          .maybeSingle();

      // Load streaming usage
      final subService = ref.read(subscriptionServiceProvider);
      final usage = await subService.getStreamingUsage(widget.tenantId);

      // Check if church is on trial
      final church = await Supabase.instance.client
          .from('churches')
          .select('subscription_status')
          .eq('id', widget.tenantId)
          .maybeSingle();

      setState(() {
        if (result != null) {
          _streamKey = result['stream_key'];
          _rtmpUrl = result['rtmp_url'] ?? 'rtmp://stream.churchonapp.com/live';
        }
        _usage = usage;
        _isTrial = church?['subscription_status'] == 'trial';
        _loading = false;
      });

      // Create default config if none exists
      if (result == null) {
        final rng = dart_math.Random.secure();
        final chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
        final key = 'coa_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}_${List.generate(8, (_) => chars[rng.nextInt(chars.length)]).join()}';
        await Supabase.instance.client
            .from('church_stream_config')
            .insert({
              'church_id': widget.tenantId,
              'stream_key': key,
              'rtmp_url': 'rtmp://stream.churchonapp.com/live',
            });

        setState(() {
          _streamKey = key;
          _rtmpUrl = 'rtmp://stream.churchonapp.com/live';
        });
      }
    } catch (e) {
      debugPrint('Failed to load stream config: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text('Streaming Dashboard')),
        body: Shimmer.fromColors(
          baseColor: Colors.grey[300]!,
          highlightColor: Colors.grey[100]!,
          child: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Streaming Dashboard'),
      ),
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          // Usage meter (trial only)
          if (_isTrial) _buildUsageMeter(),
          if (_isTrial) SizedBox(height: 16),

          // Trial banner
          if (_isTrial) _buildTrialBanner(),

          // How it works
          _buildHowItWorks(),
          SizedBox(height: 24),

          // Stream Key
          _buildStreamKeySection(),
          SizedBox(height: 16),

          // RTMP URL
          _buildRTMPSection(),
          SizedBox(height: 24),

          // Go live button (respects limits)
          _buildGoLiveButton(),
          SizedBox(height: 16),

          // Schedule stream
          _buildScheduleButton(),
          SizedBox(height: 24),

          // Tips
          _buildTips(),
        ],
      ),
    );
  }

  Widget _buildUsageMeter() {
    final usage = _usage ?? StreamingUsage.defaultUsage();
    final percentage = usage.usagePercentage;
    final remaining = usage.minutesRemaining;

    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: usage.canStream
              ? [Colors.green.shade100, Colors.green.shade200]
              : [Colors.red[50]!, Colors.orange[50]!],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                usage.canStream ? Icons.timer : Icons.timer_off,
                color: usage.canStream ? Colors.green : Colors.red,
              ),
              SizedBox(width: 8),
              Text(
                'Weekly Streaming Usage',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          SizedBox(height: 12),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: percentage / 100,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(
                usage.canStream ? Colors.green : Colors.red,
              ),
              minHeight: 12,
            ),
          ),
          SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${usage.minutesUsed.toStringAsFixed(1)} / ${usage.isUnlimited ? "∞" : usage.minutesLimit.toStringAsFixed(0)} min used',
                style: TextStyle(
                  color: usage.canStream ? Colors.green[800] : Colors.red[800],
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                usage.isUnlimited
                    ? 'Unlimited'
                    : '${remaining.toStringAsFixed(1)} min remaining',
                style: TextStyle(
                  color: usage.canStream ? Colors.green[800] : Colors.red[800],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          if (!usage.canStream) ...[
            SizedBox(height: 8),
            Text(
              'Weekly limit reached. Upgrade for unlimited streaming.',
              style: TextStyle(color: Colors.red[800], fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTrialBanner() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.star, color: Colors.amber),
              SizedBox(width: 8),
              Text(
                'Free Trial',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            'Your church is on a 30-day free trial with:',
            style: TextStyle(fontSize: 13),
          ),
          SizedBox(height: 4),
          _buildLimitRow('10 minutes streaming per week', true),
          _buildLimitRow('25 viewers max', true),
          _buildLimitRow('7-day recording storage', true),
          _buildLimitRow('Unlimited streaming', false),
          _buildLimitRow('Permanent recordings', false),
          SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _showUpgradeSheet(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.white,
              ),
              child: const Text('Upgrade Plan'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLimitRow(String text, bool included) {
    return Padding(
      padding: EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            included ? Icons.check_circle : Icons.lock,
            size: 16,
            color: included ? Colors.green : Colors.grey,
          ),
          SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: included ? Colors.black87 : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHowItWorks() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Theme.of(context).primaryColor.withValues(alpha: 0.1), Theme.of(context).primaryColor.withValues(alpha: 0.05)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Theme.of(context).primaryColor),
              SizedBox(width: 8),
              Text(
                'How to Stream',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          SizedBox(height: 12),
          _Step(number: '1', text: 'Use the Church On App or OBS on your computer'),
          _Step(number: '2', text: 'Enter the RTMP URL and Stream Key below'),
          _Step(number: '3', text: 'Click "Start Streaming" in OBS or "Go Live" in the app'),
          _Step(number: '4', text: 'Your stream appears in the Church On App automatically'),
        ],
      ),
    );
  }

  Widget _buildStreamKeySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Stream Key',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 8),
        Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _streamKey ?? '',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 14),
                ),
              ),
              IconButton(
                icon: Icon(Icons.copy),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _streamKey ?? ''));
                  PremiumToast.showSuccess(context, 'Stream key copied!');
                },
              ),
              IconButton(
                icon: Icon(Icons.refresh),
                onPressed: _regenerateKey,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: () {
            final obsConfig = "Server: ${_rtmpUrl ?? 'rtmp://stream.churchonapp.com/live'}\nStream Key: ${_streamKey ?? ''}";
            Clipboard.setData(ClipboardData(text: obsConfig));
            PremiumToast.showSuccess(context, "Copied OBS Server & Stream Key!");
          },
          icon: const Icon(Icons.content_copy, color: Colors.white, size: 18),
          label: const Text("COPY ALL FOR OBS STUDIO", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.amber.shade800,
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    );
  }

  Widget _buildRTMPSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'RTMP Server URL',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 8),
        Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _rtmpUrl ?? '',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 14),
                ),
              ),
              IconButton(
                icon: Icon(Icons.copy),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _rtmpUrl ?? ''));
                  PremiumToast.showSuccess(context, 'RTMP URL copied!');
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGoLiveButton() {
    final canStream = _usage?.canStream ?? true;

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: canStream ? _startStream : () => _showUpgradeSheet(),
        icon: Icon(
          canStream ? Icons.play_arrow : Icons.lock,
          size: 28,
        ),
        label: Text(
          canStream ? 'Go Live Now' : 'Upgrade to Go Live',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: canStream ? Colors.red : Colors.grey,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildScheduleButton() {
    final canStream = _usage?.canStream ?? true;

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton.icon(
        onPressed: canStream ? _scheduleStream : null,
        icon: Icon(Icons.schedule),
        label: Text('Schedule a Stream'),
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildTips() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb, color: Colors.amber),
              SizedBox(width: 8),
              Text(
                'Streaming Tips',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            '• Use a stable WiFi connection for best quality\n'
            '• 720p is recommended for most viewers\n'
            '• Test your stream before going live\n'
            '• Keep the app open during the entire service\n'
            '• The app adapts quality to each viewer\'s speed',
            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }

  void _regenerateKey() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Regenerate Stream Key?'),
        content: Text('This will invalidate your current stream key. Update it in OBS.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text('Regenerate')),
        ],
      ),
    );

    if (confirm != true) return;

    final newKey = 'coa_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
    await Supabase.instance.client
        .from('church_stream_config')
        .update({'stream_key': newKey})
        .eq('church_id', widget.tenantId);

    if (mounted) {
      setState(() => _streamKey = newKey);
      PremiumToast.showSuccess(context, 'New stream key generated!');
    }
  }

  void _startStream() async {
    final titleController = TextEditingController(text: 'Sunday Service');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Go Live'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Stream Title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Stream Key', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _streamKey ?? '',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _streamKey ?? ''));
                      PremiumToast.showSuccess(ctx, 'Copied!');
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text('RTMP URL', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _rtmpUrl ?? '',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _rtmpUrl ?? ''));
                      PremiumToast.showSuccess(ctx, 'Copied!');
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              if (titleController.text.trim().isEmpty) return;
              final service = ref.read(liveStreamServiceProvider);
              final hlsUrl = 'https://stream.churchonapp.com/$_streamKey/index.m3u8';
              await service.createStream(
                title: titleController.text.trim(),
                tenantId: widget.tenantId,
                streamKey: _streamKey,
                hlsUrl: hlsUrl,
                rtmpUrl: _rtmpUrl,
              );
              if (mounted) {
                PremiumToast.showSuccess(context, 'Stream started! Open OBS and click Start Streaming.');
              }
            },
            icon: const Icon(Icons.videocam, size: 18),
            label: const Text('Start with OBS'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              if (titleController.text.trim().isEmpty) return;
              context.push('/live-studio', extra: {'tenantId': widget.tenantId, 'streamTitle': titleController.text.trim()});
            },
            icon: const Icon(Icons.camera_alt, size: 18),
            label: const Text('Start Studio Stream'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _scheduleStream() async {
    final titleController = TextEditingController();
    DateTime selectedDate = DateTime.now().add(Duration(days: 1));
    TimeOfDay selectedTime = TimeOfDay(hour: 9, minute: 0);

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Schedule a Stream'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: InputDecoration(
                  hintText: 'Stream title',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 16),
              ListTile(
                leading: Icon(Icons.calendar_today),
                title: Text('Date'),
                subtitle: Text('${selectedDate.day}/${selectedDate.month}/${selectedDate.year}'),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(Duration(days: 90)),
                  );
                  if (date != null) setDialogState(() => selectedDate = date);
                },
              ),
              ListTile(
                leading: Icon(Icons.access_time),
                title: Text('Time'),
                subtitle: Text(selectedTime.format(context)),
                onTap: () async {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: selectedTime,
                  );
                  if (time != null) setDialogState(() => selectedTime = time);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
            TextButton(
              onPressed: () {
                final scheduledAt = DateTime(
                  selectedDate.year,
                  selectedDate.month,
                  selectedDate.day,
                  selectedTime.hour,
                  selectedTime.minute,
                );
                Navigator.pop(context, {
                  'title': titleController.text,
                  'scheduledAt': scheduledAt,
                });
              },
              child: Text('Schedule'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;

    final service = ref.read(liveStreamServiceProvider);
    final hlsUrl = 'https://stream.churchonapp.com/$_streamKey/index.m3u8';

    await service.createStream(
      title: result['title'],
      tenantId: widget.tenantId,
      scheduledAt: result['scheduledAt'],
      streamKey: _streamKey,
      hlsUrl: hlsUrl,
      rtmpUrl: _rtmpUrl,
    );

    if (mounted) {
      PremiumToast.showSuccess(context, 'Stream scheduled!');
    }
  }

  void _showUpgradeSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.5,
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.workspace_premium, size: 48, color: Colors.amber),
                    SizedBox(height: 16),
                    Text(
                      'Unlock Unlimited Streaming',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Upgrade your church to stream unlimited hours, reach unlimited viewers, and keep recordings forever.',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                    Spacer(),
                    _UpgradeFeature('Unlimited streaming minutes', Icons.all_inclusive),
                    _UpgradeFeature('Unlimited concurrent viewers', Icons.people),
                    _UpgradeFeature('Permanent recording storage', Icons.cloud_done),
                    _UpgradeFeature('Multi-camera support', Icons.videocam),
                    _UpgradeFeature('Custom branding', Icons.palette),
                    SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Upgrade Plan'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final String number;
  final String text;

  const _Step({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }
}

class _UpgradeFeature extends StatelessWidget {
  final String text;
  final IconData icon;

  const _UpgradeFeature(this.text, this.icon);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.green, size: 20),
          SizedBox(width: 12),
          Text(text, style: TextStyle(fontSize: 15)),
        ],
      ),
    );
  }
}
