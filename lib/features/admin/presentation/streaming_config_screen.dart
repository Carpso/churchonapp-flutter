import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/config/remote_config.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import 'package:church_on_app/core/widgets/premium_toast.dart';

/// Streaming configuration for a church.
///
/// Two tiers of control, deliberately separated:
///  - **Church leaders** get the safe, functional switches (auto-record, live
///    chat, prayer requests). Capacity/cost/pricing fields are READ-ONLY —
///    they are commercial platform settings, not church settings.
///  - **COA / superadmin staff** additionally get the platform-level controls
///    (tier, weekly minutes, viewers, quality, retention, storage).
///
/// Cloudflare Account ID / API token are PLATFORM SECRETS held server-side in
/// the Edge Function environment — they are never shown, entered, or stored by
/// a tenant (the "Managed automatically" card explains this).
class StreamingConfigScreen extends ConsumerStatefulWidget {
  final String tenantId;

  const StreamingConfigScreen({super.key, required this.tenantId});

  @override
  ConsumerState<StreamingConfigScreen> createState() => _StreamingConfigScreenState();
}

class _StreamingConfigScreenState extends ConsumerState<StreamingConfigScreen> {
  // Platform-level (COA) values — read-only for leaders.
  bool _isPaid = true;
  int _maxMinutesPerWeek = 480;
  int _maxViewers = 1000;
  int _retentionDays = 90;
  double _maxStorageGb = 10.0;
  int _maxStreamDuration = 240; // minutes
  int _maxQuality = 1080;

  // Church-level values — editable by leadership.
  bool _autoRecord = true;
  bool _enableChat = true;
  bool _enablePrayerRequests = true;

  bool _loading = true;
  bool _saving = false;
  bool _hasRow = false;

  /// True once a church-level preference has been changed since load. Drives
  /// the SAVE affordance: when there is nothing tenant-editable left to save,
  /// tenants should not see a SAVE button at all.
  bool _prefsDirty = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  bool get _isPlatformStaff {
    final profile = ref.read(profileProvider).value;
    return profile?.isEmployee == true || profile?.isSuperadmin == true;
  }

  Future<void> _loadConfig() async {
    try {
      final result = await Supabase.instance.client
          .from('church_stream_config')
          .select()
          .eq('church_id', widget.tenantId)
          .maybeSingle();

      if (result != null) {
        setState(() {
          _hasRow = true;
          _isPaid = result['is_paid'] ?? true;
          _maxMinutesPerWeek = result['max_minutes_per_week'] ?? 480;
          _maxViewers = result['max_viewers'] ?? 1000;
          _retentionDays = result['retention_days'] ?? 90;
          _maxStorageGb = (result['max_storage_gb'] ?? 10.0).toDouble();
          _maxStreamDuration = ((result['max_stream_duration_sec'] ?? 14400) as num) ~/ 60;
          _maxQuality = result['max_quality'] ?? 1080;
          _autoRecord = result['auto_record'] ?? true;
          _enableChat = result['enable_chat'] ?? true;
          _enablePrayerRequests = result['enable_prayer_requests'] ?? true;
          _prefsDirty = false;
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      debugPrint('Streaming config load failed: $e');
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Streaming Config')),
        body: const Center(child: ListSkeleton()),
      );
    }

    final rc = widgetRemoteConfig(ref);
    final staff = _isPlatformStaff;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Streaming Config'),
        actions: [
          if (staff || _prefsDirty)
            TextButton(
              onPressed: _saving ? null : _saveConfig,
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('SAVE', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Plan benefits (tenants see plans, never infrastructure) ─────
          const Text('Church On App Streaming', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _buildPlanBenefitsCard(),
          const SizedBox(height: 24),

          // ── Managed automatically (no tenant credentials) ───────────────
          _buildSection('Streaming Service', [
            _buildHelpBox(
              'Managed for you',
              const [
                'There is nothing to configure here.',
                'Church On App authorises your account and starts your broadcasts automatically.',
                'No technical keys are ever shown, entered, or stored in the app.',
              ],
              Theme.of(context).primaryColor,
            ),
          ]),

          // ── Plan / capacity ─────────────────────────────────────────────
          _buildSection('Your Streaming Plan', [
            _planCard(staff),
          ]),

          if (staff) ...[
            const SizedBox(height: 24),
            _buildSection('Platform Limits (COA)', [
              _buildSlider('Minutes/Week', _maxMinutesPerWeek.toDouble(), 10, 1440, '$_maxMinutesPerWeek min',
                  (v) => setState(() => _maxMinutesPerWeek = v.round())),
              _buildSlider('Max Viewers', _maxViewers.toDouble(), 10, 5000, '$_maxViewers',
                  (v) => setState(() => _maxViewers = v.round()), divisions: 50),
              _buildSlider('Max Duration (min)', _maxStreamDuration.toDouble(), 15, 480, '$_maxStreamDuration min',
                  (v) => setState(() => _maxStreamDuration = v.round())),
              _buildSlider('Max Quality', _maxQuality.toDouble(), 360, 1080, '${_maxQuality}p',
                  (v) => setState(() => _maxQuality = v.round()), divisions: 4),
              _buildSlider('Retention (days)', _retentionDays.toDouble(), 1, 365, '$_retentionDays days',
                  (v) => setState(() => _retentionDays = v.round()), divisions: 60),
              _buildSlider('Max Storage', _maxStorageGb, 1, 100, '${_maxStorageGb.toStringAsFixed(0)} GB',
                  (v) => setState(() => _maxStorageGb = v), divisions: 99),
              _tierSwitch(),
            ]),
            const SizedBox(height: 24),
            _buildSection('Platform Rates (COA only)', [
              _rateRow('Stream delivery', rc.getDouble('cf_stream_delivery_usd_per_1000_min', 1.0)),
              _rateRow('Recording storage', rc.getDouble('cf_stream_storage_usd_per_1000_min', 5.0)),
              _rateRowFx('Exchange rate (USD→ZMW)', rc.getDouble('cf_stream_usd_to_zmw', 18.0)),
              const SizedBox(height: 8),
              Text(
                'Church On App covers these costs — churches are never billed usage rates directly.',
                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55)),
              ),
            ]),
          ],

          // ── Church settings (leadership-editable) ───────────────────────
          _buildSection('Stream Settings', [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Auto-Record'),
              subtitle: const Text('Save services as replays (archived to Church On storage)'),
              value: _autoRecord,
              onChanged: (v) => setState(() {
                _autoRecord = v;
                _prefsDirty = true;
              }),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Live Chat'),
              subtitle: const Text('Allow viewers to chat during the service'),
              value: _enableChat,
              onChanged: (v) => setState(() {
                _enableChat = v;
                _prefsDirty = true;
              }),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Prayer Requests'),
              subtitle: const Text('Allow the prayer request button during a stream'),
              value: _enablePrayerRequests,
              onChanged: (v) => setState(() {
                _enablePrayerRequests = v;
                _prefsDirty = true;
              }),
            ),
          ]),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  /// Tenant-facing plan benefits. Deliberately contains NO provider,
  /// infrastructure or cost wording — the streaming backend is an internal
  /// implementation detail owned by Church On App.
  Widget _buildPlanBenefitsCard() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.primaryColor.withValues(alpha: 0.05),
        border: Border.all(color: theme.primaryColor, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.video, color: theme.primaryColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Standard Streaming',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold, color: theme.primaryColor)),
                    Text('Live video, viewer chat & recordings',
                        style: TextStyle(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                            fontSize: 13)),
                  ],
                ),
              ),
              Icon(Icons.check_circle, color: theme.primaryColor),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: theme.primaryColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8)),
            child: Text(
              'Your plan includes live video, viewer chat, recordings and multi-device '
              'delivery. Church On App manages everything for you — nothing to set up.',
              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.75)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _planCard(bool staff) {
    final theme = Theme.of(context);
    final rows = <String>[
      '$_maxMinutesPerWeek streaming minutes / week',
      '$_maxViewers concurrent viewers',
      '$_retentionDays-day recording retention',
      '${_maxStorageGb.toStringAsFixed(0)} GB storage included',
      'Up to ${_maxQuality}p HD quality',
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isPaid ? Colors.green.withValues(alpha: 0.08) : Colors.orange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _isPaid ? Colors.green.withValues(alpha: 0.4) : Colors.orange.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_isPaid ? Icons.verified : Icons.lock, color: _isPaid ? Colors.green : Colors.orange),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _isPaid ? 'STANDARD STREAMING' : 'TRIAL (LIMITED)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _isPaid ? Colors.green[800] : Colors.orange[800],
                  ),
                ),
              ),
              if (staff)
                const Text('Editable', style: TextStyle(fontSize: 11, color: Colors.grey))
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline, size: 13, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                    const SizedBox(width: 4),
                    const Text('Set by Church On App', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 10),
          ...rows.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, size: 15, color: Colors.green[600]),
                    const SizedBox(width: 8),
                    Text(r, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _tierSwitch() {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Paid tier'),
      subtitle: const Text('Off = trial limits (COA only)'),
      value: _isPaid,
      activeThumbColor: Colors.green,
      onChanged: (v) => setState(() {
        _isPaid = v;
        if (v) {
          _maxMinutesPerWeek = 480;
          _maxViewers = 1000;
          _retentionDays = 90;
          _maxStorageGb = 10.0;
          _maxStreamDuration = 240;
          _maxQuality = 1080;
        } else {
          _maxMinutesPerWeek = 10;
          _maxViewers = 25;
          _retentionDays = 7;
          _maxStorageGb = 1.0;
          _maxStreamDuration = 60;
          _maxQuality = 720;
        }
      }),
    );
  }

  Widget _rateRow(String label, double usdPer1000) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 13)),
            Text('\$${usdPer1000.toStringAsFixed(2)} / 1000 min',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
      );

  Widget _rateRowFx(String label, double rate) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 13)),
            Text('K${rate.toStringAsFixed(2)} / \$1',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
      );

  int _computeDivisions(double min, double max) {
    if (min <= 0 || !(max - min).isFinite) return 2;
    return ((max - min) / min).round().clamp(2, 100);
  }

  Widget _buildSlider(String label, double value, double min, double max, String display,
      ValueChanged<double> onChanged, {int? divisions}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            Text(display,
                style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor, fontSize: 13)),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions ?? _computeDivisions(min, max),
          onChanged: onChanged,
          activeColor: Theme.of(context).primaryColor,
        ),
      ],
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface)),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildHelpBox(String title, List<String> steps, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.shieldCheck, size: 16, color: color),
              const SizedBox(width: 6),
              Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
            ],
          ),
          const SizedBox(height: 4),
          Text(steps.join('\n'), style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }

  Future<void> _saveConfig() async {
    setState(() => _saving = true);
    try {
      final staff = _isPlatformStaff;
      final payload = <String, dynamic>{
        'church_id': widget.tenantId,
        'backend': 'cloudflare',
        'auto_record': _autoRecord,
        'enable_chat': _enableChat,
        'enable_prayer_requests': _enablePrayerRequests,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (staff) {
        payload.addAll({
          'is_paid': _isPaid,
          'max_minutes_per_week': _maxMinutesPerWeek,
          'max_viewers': _maxViewers,
          'retention_days': _retentionDays,
          'max_storage_gb': _maxStorageGb,
          'max_stream_duration_sec': _maxStreamDuration * 60,
          'max_quality': _maxQuality,
        });
      } else if (!_hasRow) {
        // First-ever write by a church leader: seed the paid baseline so the
        // insert can never silently downgrade the church to trial limits.
        // (A DB trigger also enforces this server-side.)
        payload.addAll({
          'is_paid': true,
          'max_minutes_per_week': 480,
          'max_viewers': 1000,
          'retention_days': 90,
          'max_storage_gb': 10.0,
          'max_stream_duration_sec': 14400,
          'max_quality': 1080,
        });
      }

      await Supabase.instance.client
          .from('church_stream_config')
          .upsert(payload, onConflict: 'church_id');

      await _loadConfig();
      if (mounted) PremiumToast.showSuccess(context, 'Streaming settings saved');
    } catch (e) {
      debugPrint('Streaming config save failed: $e');
      if (mounted) {
        final raw = e.toString();
        final friendly = raw.contains('row-level security') ||
                raw.contains('permission denied') ||
                raw.contains('42501')
            ? 'You do not have permission to change those settings.'
            : 'Could not save the streaming settings. Please try again.';
        PremiumToast.showError(context, friendly);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
