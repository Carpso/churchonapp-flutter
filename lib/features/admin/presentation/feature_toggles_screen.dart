import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';

class FeatureTogglesScreen extends ConsumerStatefulWidget {
  const FeatureTogglesScreen({super.key});

  @override
  ConsumerState<FeatureTogglesScreen> createState() => _FeatureTogglesScreenState();
}

class _FeatureTogglesScreenState extends ConsumerState<FeatureTogglesScreen> {
  String _search = '';
  String? _selectedTenantId;

  static final _featureGroups = <String, List<_FeatureItem>>{
    '💰 Giving & Finance': [
      _FeatureItem('Tithes & Offerings', 'giving_tithes', 'Digital giving via Mobile Money', LucideIcons.banknote, true),
      _FeatureItem('Missions Giving', 'giving_missions', 'Missions and outreach donations', LucideIcons.globe, true),
      _FeatureItem('Building Fund', 'giving_building', 'Building fund contributions', LucideIcons.home, true),
      _FeatureItem('Pledges', 'giving_pledges', 'Pledge commitments and tracking', LucideIcons.heartHandshake, true),
      _FeatureItem('QR Payment', 'giving_qr', 'QR code payment for quick giving', LucideIcons.qrCode, true),
      _FeatureItem('Card Payments', 'giving_card', 'Credit/Debit card via Lipila', LucideIcons.creditCard, false),
      _FeatureItem('Church Wallet', 'giving_wallet', 'Church treasury wallet management', LucideIcons.wallet, true),
    ],
    '📖 Bible & Study': [
      _FeatureItem('Bible Reader', 'bible_reader', 'Full Bible with KJV/NKJV/NLT + local languages', LucideIcons.bookOpen, true),
      _FeatureItem('Bible Versions', 'bible_versions', '18 translations — English + African languages', LucideIcons.languages, true),
      _FeatureItem('Reading Plans', 'bible_reading_plans', 'Daily/weekly reading plans', LucideIcons.calendar, true),
      _FeatureItem('Study Plans', 'bible_study_plans', 'Tenant leader-created study plans', LucideIcons.penTool, true),
      _FeatureItem('Verse Notes', 'bible_verse_notes', 'Personal notes on verses', LucideIcons.stickyNote, true),
      _FeatureItem('Cross References', 'bible_cross_refs', 'Related verses across Scripture', LucideIcons.gitBranch, true),
      _FeatureItem('Chapter Summaries', 'bible_chapter_summaries', 'AI-powered chapter overviews', LucideIcons.sparkles, true),
      _FeatureItem('Kael Bible Tools', 'bible_kael', 'Exegesis, concordance, cross-ref AI', LucideIcons.brain, true),
    ],
    '🎥 Media & Streaming': [
      _FeatureItem('Live Streaming', 'media_live_stream', 'Church service live streaming', LucideIcons.radio, true),
      _FeatureItem('Sermon Library', 'media_sermons', 'Sermon recordings and playback', LucideIcons.play, true),
      _FeatureItem('Kingdom Radio', 'media_radio', '24/7 Kingdom Radio broadcast', LucideIcons.radioTower, true),
      _FeatureItem('Kingdom Klips', 'media_klips', 'Short-form video posts', LucideIcons.video, true),
      _FeatureItem('Audio Bible', 'media_audio_bible', 'Audio narration of Scripture', LucideIcons.headphones, true),
    ],
    '🎪 Events & Community': [
      _FeatureItem('Events Management', 'events_management', 'Create and manage church events', LucideIcons.calendarDays, true),
      _FeatureItem('Event Ticketing', 'events_ticketing', 'Paid event passes and tickets', LucideIcons.ticket, true),
      _FeatureItem('RSVP System', 'events_rsvp', 'Attendee RSVP and check-in', LucideIcons.userCheck, true),
      _FeatureItem('QR Check-in', 'events_checkin', 'QR code event check-in', LucideIcons.scan, true),
      _FeatureItem('Inter-Tenant Events', 'events_inter_tenant', 'Cross-church event visibility', LucideIcons.network, false),
      _FeatureItem('Prayer Wall', 'community_prayer', 'Shared prayer requests', LucideIcons.heart, true),
      _FeatureItem('Testimonies', 'community_testimonies', 'Share testimonies of faith', LucideIcons.messageCircle, true),
    ],
    '💬 Communication': [
      _FeatureItem('Direct Chat', 'comm_direct_chat', '1-on-1 messaging between members', LucideIcons.messageSquare, true),
      _FeatureItem('Community Chat', 'comm_community_chat', 'Group chat in communities', LucideIcons.users, true),
      _FeatureItem('Audio/Video Calls', 'comm_calls', 'Voice and video calls', LucideIcons.phone, true),
      _FeatureItem('SMS Broadcasts', 'comm_sms', 'SMS blasts to congregation', LucideIcons.send, false),
      _FeatureItem('Push Notifications', 'comm_notifications', 'App push notifications', LucideIcons.bell, true),
    ],
    '🚗 Carpso Ride': [
      _FeatureItem('Ride Request', 'carpso_ride', 'Request rides within church network', LucideIcons.car, true),
      _FeatureItem('Cargo Delivery', 'carpso_cargo', 'Cargo and parcel delivery', LucideIcons.package, true),
      _FeatureItem('Driver Portal', 'carpso_driver', 'Driver acceptance and tracking', LucideIcons.car, true),
      _FeatureItem('Fare Negotiation', 'carpso_negotiation', 'Passenger-driver fare negotiation', LucideIcons.messageCircle, true),
    ],
    '🧒 Kids & Games': [
      _FeatureItem('Kids Zone', 'kids_zone', 'Bible stories and activities', LucideIcons.gamepad2, true),
      _FeatureItem('Bible Quiz', 'quiz_bible', 'Solo and PvP Bible quiz', LucideIcons.helpCircle, true),
      _FeatureItem('Quiz Events', 'quiz_events', 'Premium quiz events and tournaments', LucideIcons.trophy, false),
      _FeatureItem('Game Arena', 'game_arena', 'Trivia and community games', LucideIcons.gamepad, true),
    ],
    '🛒 Marketplace': [
      _FeatureItem('Marketplace', 'marketplace_shop', 'Buy and sell within church', LucideIcons.shoppingBag, true),
      _FeatureItem('Bookshop', 'marketplace_bookshop', 'Bookshop tenant operations', LucideIcons.bookOpen, true),
    ],
    '📊 Admin Tools': [
      _FeatureItem('Attendance Scanner', 'admin_attendance', 'QR attendance scanning', LucideIcons.scan, true),
      _FeatureItem('Member Directory', 'admin_members', 'Member management directory', LucideIcons.users, true),
      _FeatureItem('Finance Dashboard', 'admin_finance', 'Church financial reports', LucideIcons.barChart3, true),
      _FeatureItem('Service Reports', 'admin_reports', 'Service attendance and offerings', LucideIcons.clipboardList, true),
      _FeatureItem('Data Import', 'admin_data_import', 'CSV/JSON import from other ChMS', LucideIcons.fileInput, false),
      _FeatureItem('Export Data', 'admin_export', 'Export church data', LucideIcons.fileDown, true),
    ],
  };

  Future<void> _applyTenantWide(String tenantId) async {
    final tenant = await Supabase.instance.client
        .from('churches').select('settings').eq('id', tenantId).maybeSingle();
    final settings = Map<String, dynamic>.from((tenant?['settings'] as Map?) ?? {});
    for (final group in _featureGroups.values) {
      for (final f in group) {
        settings[f.key] = f.defaultEnabled;
      }
    }
    await Supabase.instance.client.from('churches')
        .update({'settings': settings}).eq('id', tenantId);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = ref.watch(profileProvider).value;
    final tenant = ref.watch(currentTenantProvider);
    final isSuper = profile?.isSuperadmin == true || profile?.isEmployee == true;

    if (!isSuper) {
      return Scaffold(appBar: AppBar(title: const Text('Feature Toggles')), body: const Center(child: Text('Superadmin / COA Employee access required')));
    }

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Feature Toggles'),
        actions: [
          if (tenant != null)
            IconButton(icon: const Icon(LucideIcons.rotateCcw), tooltip: 'Reset to defaults', onPressed: () => _applyTenantWide(tenant.id)),
        ],
      ),
      body: Column(
        children: [
          if (tenant == null)
            const Padding(padding: EdgeInsets.all(20), child: Text('Select a tenant to manage features', style: TextStyle(color: Colors.grey)))
          else ...[
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(LucideIcons.search, size: 18),
                  hintText: 'Search features...',
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onChanged: (v) => setState(() => _search = v.toLowerCase()),
              ),
            ),
            Expanded(child: _buildFeatureList(tenant, theme)),
          ],
        ],
      ),
    );
  }

  Widget _buildFeatureList(Tenant tenant, ThemeData theme) {
    final settings = tenant.settings ?? {};
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      children: _featureGroups.entries.expand((entry) {
        final items = _search.isEmpty
            ? entry.value
            : entry.value.where((f) => f.label.toLowerCase().contains(_search) || f.description.toLowerCase().contains(_search)).toList();
        if (items.isEmpty) return <Widget>[];
        final allEnabled = items.every((f) => settings[f.key] ?? f.defaultEnabled);
        return [
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 4, left: 4),
            child: Row(
              children: [
                Text(entry.key, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                const Spacer(),
                GestureDetector(
                  onTap: () async {
                    for (final f in items) {
                      await _toggleFeature(tenant, f.key, !allEnabled);
                    }
                    setState(() {});
                  },
                  child: Text(allEnabled ? 'Disable All' : 'Enable All', style: TextStyle(fontSize: 11, color: allEnabled ? Colors.red : Colors.green, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          ...items.map((f) => _buildFeatureTile(tenant, f, settings, theme)),
        ];
      }).toList(),
    );
  }

  Widget _buildFeatureTile(Tenant tenant, _FeatureItem feature, Map<String, dynamic> settings, ThemeData theme) {
    final isEnabled = settings[feature.key] ?? feature.defaultEnabled;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SwitchListTile(
        dense: true,
        secondary: Icon(feature.icon, color: isEnabled ? theme.primaryColor : Colors.grey, size: 20),
        title: Text(feature.label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isEnabled ? null : Colors.grey)),
        subtitle: Text(feature.description, style: const TextStyle(fontSize: 11)),
        value: isEnabled,
        activeTrackColor: theme.primaryColor,
        onChanged: (v) => _toggleFeature(tenant, feature.key, v),
      ),
    );
  }

  Future<void> _toggleFeature(Tenant tenant, String key, bool value) async {
    final updatedSettings = Map<String, dynamic>.from(tenant.settings ?? {});
    updatedSettings[key] = value;
    try {
      await Supabase.instance.client.from('churches').update({'settings': updatedSettings}).eq('id', tenant.id);
      ref.invalidate(currentTenantProvider);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red));
      }
    }
  }
}

class _FeatureItem {
  final String label;
  final String key;
  final String description;
  final IconData icon;
  final bool defaultEnabled;
  const _FeatureItem(this.label, this.key, this.description, this.icon, this.defaultEnabled);
}
