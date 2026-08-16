import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import 'package:church_on_app/core/services/unified_stream_service.dart';
import 'package:church_on_app/core/widgets/premium_toast.dart';

/// Streaming configuration screen for church admins
/// Cloudflare Stream + R2 only. No third-party CDNs.
class StreamingConfigScreen extends ConsumerStatefulWidget {
  final String tenantId;

  const StreamingConfigScreen({super.key, required this.tenantId});

  @override
  ConsumerState<StreamingConfigScreen> createState() => _StreamingConfigScreenState();
}

class _StreamingConfigScreenState extends ConsumerState<StreamingConfigScreen> {
  StreamingBackend _selectedBackend = StreamingBackend.cloudflare;
  final _hostController = TextEditingController(text: 'stream.churchonapp.com');
  final _cloudflareAccountIdController = TextEditingController();
  final _cloudflareApiTokenController = TextEditingController();
  final _mediamtxSecretController = TextEditingController();
  // Cost control state
  bool _isPaid = false;
  int _maxMinutesPerWeek = 10;
  int _maxViewers = 25;
  int _retentionDays = 7;
  double _maxStorageGb = 1.0;
  int _maxStreamDuration = 60; // minutes
  int _maxQuality = 720;
  bool _autoRecord = true;
  bool _enableChat = true;
  bool _enablePrayerRequests = true;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
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
          _selectedBackend = StreamingBackend.values.firstWhere(
            (b) => b.name == (result['backend'] ?? 'cloudflare'),
            orElse: () => StreamingBackend.cloudflare,
          );
          _hostController.text = result['mediamtx_host'] ?? 'stream.churchonapp.com';
          _cloudflareAccountIdController.text = result['cloudflare_account_id'] ?? '';
          _cloudflareApiTokenController.text = result['cloudflare_api_token'] ?? '';
          _mediamtxSecretController.text = result['mediamtx_secret'] ?? '';
          _isPaid = result['is_paid'] ?? false;
          _maxMinutesPerWeek = result['max_minutes_per_week'] ?? 10;
          _maxViewers = result['max_viewers'] ?? 25;
          _retentionDays = result['retention_days'] ?? 7;
          _maxStorageGb = (result['max_storage_gb'] ?? 1.0).toDouble();
          _maxStreamDuration = (result['max_stream_duration_sec'] ?? 3600) ~/ 60;
          _maxQuality = result['max_quality'] ?? 720;
          _autoRecord = result['auto_record'] ?? true;
          _enableChat = result['enable_chat'] ?? true;
          _enablePrayerRequests = result['enable_prayer_requests'] ?? true;
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text('Streaming Config')),
        body: const Center(child: ListSkeleton()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Streaming Config'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _saveConfig,
            child: _saving
                ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('SAVE', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          // Backend selection
          Text('Streaming Backend', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SizedBox(height: 12),
          _BackendCard(
            title: 'Cloudflare Stream',
            subtitle: 'Ingest + delivery — scales with usage',
            icon: Icons.cloud,
            isSelected: _selectedBackend == StreamingBackend.cloudflare,
            onTap: () => setState(() => _selectedBackend = StreamingBackend.cloudflare),
            children: [
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(color: Theme.of(context).primaryColor.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                child: Text(
                  'Cloudflare handles everything: RTMP ingest, transcoding, HLS delivery, and DDoS protection. \$5/mo base + usage.',
                  style: TextStyle(fontSize: 12, color: const Color(0xFF7A5C00)),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          _BackendCard(
            title: 'MediaMTX (Self-Hosted)',
            subtitle: 'Flat \$5/mo, unlimited streams',
            icon: Icons.dns,
            isSelected: _selectedBackend == StreamingBackend.mediamtx,
            onTap: () => setState(() => _selectedBackend = StreamingBackend.mediamtx),
            children: [
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(8)),
                child: Text(
                  'One \$5 VPS handles unlimited streams. No per-minute charges. Requires server setup.',
                  style: TextStyle(color: Colors.green[800], fontSize: 13),
                ),
              ),
            ],
          ),
          SizedBox(height: 24),

          // Backend config
          if (_selectedBackend == StreamingBackend.cloudflare) ...[
            _buildSection('Cloudflare Config', [
              _buildTextField('Account ID', _cloudflareAccountIdController),
              _buildTextField('API Token', _cloudflareApiTokenController, obscure: true),
              SizedBox(height: 8),
              _buildHelpBox('Setup:', [
                '1. dash.cloudflare.com → Stream → Overview',
                '2. Copy Account ID',
                '3. My Profile → API Tokens → Create Stream token',
              ], Theme.of(context).primaryColor),
            ]),
          ] else ...[
            _buildSection('MediaMTX Config', [
              _buildTextField('Server Host', _hostController),
              _buildTextField('Stream Secret', _mediamtxSecretController, obscure: true),
              SizedBox(height: 8),
              _buildHelpBox('VPS Setup:', [
                '1. Buy VPS (Hetzner \$4.50/mo)',
                '2. Install: curl -s https://get.mediamtx.dev | sh',
                '3. Run: mediamtx',
                '4. Point stream.churchonapp.com → VPS IP',
              ], Colors.green),
            ]),
          ],

          SizedBox(height: 24),

          // Subscription tier toggle
          _buildSection('Subscription Tier', [
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _isPaid ? Colors.green[50] : Colors.orange[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _isPaid ? Colors.green[200]! : Colors.orange[200]!),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(_isPaid ? Icons.verified : Icons.lock, color: _isPaid ? Colors.green : Colors.orange),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_isPaid ? 'PAID SUBSCRIBER' : 'TRIAL (FREE)',
                                style: TextStyle(fontWeight: FontWeight.bold, color: _isPaid ? Colors.green[800] : Colors.orange[800])),
                            Text(_isPaid ? 'Paid plan — Full access' : '30-day trial with limits',
                                style: TextStyle(fontSize: 12, color: _isPaid ? Colors.green[600] : Colors.orange[600])),
                          ],
                        ),
                      ),
                      Switch(
                        value: _isPaid,
                        onChanged: (v) => setState(() {
                          _isPaid = v;
                          if (v) {
                            _maxMinutesPerWeek = 480;
                            _maxViewers = 1000;
                            _retentionDays = 90;
                            _maxStorageGb = 10.0;
                            _maxStreamDuration = 240;
                          } else {
                            _maxMinutesPerWeek = 10;
                            _maxViewers = 25;
                            _retentionDays = 7;
                            _maxStorageGb = 1.0;
                            _maxStreamDuration = 60;
                          }
                        }),
                        activeThumbColor: Colors.green,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ]),

          SizedBox(height: 24),

          // Cost controls
          _buildSection('Streaming Limits', [
            _buildSlider('Minutes/Week', _maxMinutesPerWeek.toDouble(), 10, 480, '$_maxMinutesPerWeek min', (v) {
              setState(() => _maxMinutesPerWeek = v.round());
            }),
            _buildSlider('Max Viewers', _maxViewers.toDouble(), 10, 1000, '$_maxViewers', (v) {
              setState(() => _maxViewers = v.round());
            }, divisions: 20),
            _buildSlider('Max Duration (min)', _maxStreamDuration.toDouble(), 15, 240, '$_maxStreamDuration min', (v) {
              setState(() => _maxStreamDuration = v.round());
            }),
            _buildSlider('Max Quality', _maxQuality.toDouble(), 360, 1080, '${_maxQuality}p', (v) {
              setState(() => _maxQuality = v.round());
            }, divisions: 4),
            _buildSlider('Retention (days)', _retentionDays.toDouble(), 1, 365, '$_retentionDays days', (v) {
              setState(() => _retentionDays = v.round());
            }, divisions: 12),
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Overage Pricing:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange[800], fontSize: 13)),
                  SizedBox(height: 4),
                  Text(
                    'Viewers above $_maxViewers: K5/viewer extra\n'
                    'Storage above ${_maxStorageGb.toStringAsFixed(1)}GB: K50/GB extra\n'
                    'All overages billed monthly via MoMo',
                    style: TextStyle(fontSize: 12, color: Colors.orange[700]),
                  ),
                ],
              ),
            ),
          ]),

          SizedBox(height: 24),

          // Storage gating
          _buildSection('Storage (R2)', [
            _buildSlider('Max Storage', _maxStorageGb, 1, 50, '${_maxStorageGb.toStringAsFixed(1)} GB', (v) {
              setState(() => _maxStorageGb = double.tryParse(v.toStringAsFixed(1)) ?? 0.0);
            }, divisions: 50),
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.amber[50], borderRadius: BorderRadius.circular(8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Storage Gating:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber[800], fontSize: 13)),
                  SizedBox(height: 4),
                  Text(
                    'Free tier: ${_isPaid ? "10 GB" : "1 GB"} included\n'
                    'Excess: K50/GB/month charged automatically\n'
                    'Recordings auto-deleted after $_retentionDays days\n'
                    'Cloudflare R2 free tier covers first 10 GB',
                    style: TextStyle(fontSize: 12, color: Colors.amber[700]),
                  ),
                ],
              ),
            ),
          ]),

          SizedBox(height: 24),

          // Stream settings
          _buildSection('Stream Settings', [
            SwitchListTile(
              title: Text('Auto-Record'),
              subtitle: Text('Save live streams as VOD'),
              value: _autoRecord,
              onChanged: (v) => setState(() => _autoRecord = v),
            ),
            SwitchListTile(
              title: Text('Live Chat'),
              subtitle: Text('Allow viewers to chat'),
              value: _enableChat,
              onChanged: (v) => setState(() => _enableChat = v),
            ),
            SwitchListTile(
              title: Text('Prayer Requests'),
              subtitle: Text('Allow prayer request button'),
              value: _enablePrayerRequests,
              onChanged: (v) => setState(() => _enablePrayerRequests = v),
            ),
          ]),

          SizedBox(height: 24),

          // Cost breakdown
          _buildCostEstimate(),
          SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildCostEstimate() {
    // Rough cost estimate based on config
    final cfBaseFee = 5.0;
    // Assume 4hrs/week streaming, 50 viewers avg, 2Mbps = ~36GB/month per church
    final estimatedBandwidthGb = 36.0;
    final cfUsageFee = estimatedBandwidthGb * 0.10; // $0.10/GB delivery
    final r2StorageFee = _maxStorageGb > 10 ? (_maxStorageGb - 10) * 0.015 : 0; // Free first 10GB
    final totalCost = cfBaseFee + cfUsageFee + r2StorageFee;

    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Estimated Monthly Cost', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          SizedBox(height: 12),
          _buildCostRow('Cloudflare Stream base', '\$${cfBaseFee.toStringAsFixed(2)}'),
          _buildCostRow('Bandwidth (${estimatedBandwidthGb.toStringAsFixed(0)} GB)', '\$${cfUsageFee.toStringAsFixed(2)}'),
          if (r2StorageFee > 0) _buildCostRow('R2 storage excess', '\$${r2StorageFee.toStringAsFixed(2)}'),
          Divider(),
          _buildCostRow('TOTAL PER CHURCH', '\$${totalCost.toStringAsFixed(2)}', bold: true),
          SizedBox(height: 8),
          Text(
            'With $_maxViewers viewers, $_maxMinutesPerWeek min/week, $_retentionDays-day retention',
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildCostRow(String label, String amount, {bool bold = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal, fontSize: bold ? 15 : 13)),
          Text(amount, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.w600, fontSize: bold ? 15 : 13)),
        ],
      ),
    );
  }

  int _computeDivisions(double min, double max) {
    if (min <= 0 || !(max - min).isFinite) return 2;
    final d = ((max - min) / min).round().clamp(2, 50);
    return d;
  }

  Widget _buildSlider(String label, double value, double min, double max, String display, ValueChanged<double> onChanged, {int? divisions}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            Text(display, style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor, fontSize: 13)),
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
      margin: EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey[800])),
          SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {bool obscure = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _buildHelpBox(String title, List<String> steps, Color color) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
          SizedBox(height: 4),
          Text(steps.join('\n'), style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }

  Future<void> _saveConfig() async {
    setState(() => _saving = true);

    try {
      final config = {
        'church_id': widget.tenantId,
        'backend': _selectedBackend.name,
        'cloudflare_account_id': _cloudflareAccountIdController.text.trim(),
        'cloudflare_api_token': _cloudflareApiTokenController.text.trim(),
        'mediamtx_host': _hostController.text.trim(),
        'mediamtx_secret': _mediamtxSecretController.text.trim(),
        'is_paid': _isPaid,
        'max_minutes_per_week': _maxMinutesPerWeek,
        'max_viewers': _maxViewers,
        'retention_days': _retentionDays,
        'max_storage_gb': _maxStorageGb,
        'max_stream_duration_sec': _maxStreamDuration * 60,
        'max_quality': _maxQuality,
        'auto_record': _autoRecord,
        'enable_chat': _enableChat,
        'enable_prayer_requests': _enablePrayerRequests,
        'updated_at': DateTime.now().toIso8601String(),
      };

      await Supabase.instance.client
          .from('church_stream_config')
          .upsert(config, onConflict: 'church_id');

      if (mounted) {
        PremiumToast.showSuccess(context, 'Streaming config saved!');
      }
    } catch (e) {
      if (mounted) {
        PremiumToast.showError(context, 'Error: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _hostController.dispose();
    _cloudflareAccountIdController.dispose();
    _cloudflareApiTokenController.dispose();
    _mediamtxSecretController.dispose();
    super.dispose();
  }
}

class _BackendCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final List<Widget> children;

  const _BackendCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).primaryColor.withValues(alpha: 0.05) : Colors.white,
          border: Border.all(
            color: isSelected ? Theme.of(context).primaryColor : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: isSelected ? Theme.of(context).primaryColor : Colors.grey),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isSelected ? Theme.of(context).primaryColor : null)),
                      Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                    ],
                  ),
                ),
                if (isSelected) Icon(Icons.check_circle, color: Theme.of(context).primaryColor),
              ],
            ),
            if (children.isNotEmpty && isSelected) ...[
              SizedBox(height: 12),
              ...children,
            ],
          ],
        ),
      ),
    );
  }
}
