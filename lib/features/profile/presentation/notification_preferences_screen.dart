import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shimmer/shimmer.dart';

class NotificationPreferencesScreen extends ConsumerStatefulWidget {
  const NotificationPreferencesScreen({super.key});
  @override
  ConsumerState<NotificationPreferencesScreen> createState() => _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState extends ConsumerState<NotificationPreferencesScreen> {
  Map<String, bool> _prefs = {};
  bool _loading = true;

  static const _channels = [
    {'id': 'coa_announcements', 'name': 'Announcements', 'icon': LucideIcons.megaphone, 'desc': 'Church-wide announcements and alerts'},
    {'id': 'coa_chat', 'name': 'Chat Messages', 'icon': LucideIcons.messageCircle, 'desc': 'Direct messages and group chats'},
    {'id': 'coa_posts', 'name': 'Social Posts', 'icon': LucideIcons.users, 'desc': 'New posts from church community'},
    {'id': 'coa_payments', 'name': 'Payments', 'icon': LucideIcons.wallet, 'desc': 'Payment confirmations and receipts'},
    {'id': 'coa_events', 'name': 'Events', 'icon': LucideIcons.calendar, 'desc': 'Event reminders and updates'},
    {'id': 'coa_prayers', 'name': 'Prayers', 'icon': LucideIcons.heart, 'desc': 'Prayer request notifications'},
    {'id': 'coa_testimonies', 'name': 'Testimonies', 'icon': LucideIcons.star, 'desc': 'New testimonies shared'},
    {'id': 'coa_klips', 'name': 'Klips', 'icon': LucideIcons.video, 'desc': 'New video clip uploads'},
    {'id': 'coa_fasting', 'name': 'Fasting', 'icon': LucideIcons.clock, 'desc': 'Fasting reminders and updates'},
  ];

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) { setState(() => _loading = false); return; }
    try {
      final data = await Supabase.instance.client
          .from('notification_preferences')
          .select('channel_id, enabled')
          .eq('user_id', user.id);
      final map = <String, bool>{};
      for (final row in data) {
        map[row['channel_id'] as String] = row['enabled'] as bool;
      }
      setState(() { _prefs = map; _loading = false; });
    } catch (e) {
      debugPrint('Failed to load prefs: $e');
      setState(() => _loading = false);
    }
  }

  Future<void> _toggle(String channelId, bool value) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    setState(() => _prefs[channelId] = value);
    try {
      await Supabase.instance.client.from('notification_preferences').upsert({
        'user_id': user.id,
        'channel_id': channelId,
        'enabled': value,
      }, onConflict: 'user_id,channel_id');
    } catch (e) {
      debugPrint('Failed to update pref: $e');
      setState(() => _prefs[channelId] = !value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return Scaffold(
      appBar: AppBar(title: const Text('Notification Preferences')),
      body: Shimmer.fromColors(
        baseColor: Colors.grey.shade300,
        highlightColor: Colors.grey.shade100,
        child: const Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            children: [
              SizedBox(width: double.infinity, height: 60, child: DecoratedBox(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.all(Radius.circular(16))))),
              SizedBox(height: 12),
              SizedBox(width: double.infinity, height: 60, child: DecoratedBox(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.all(Radius.circular(16))))),
              SizedBox(height: 12),
              SizedBox(width: double.infinity, height: 60, child: DecoratedBox(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.all(Radius.circular(16))))),
            ],
          ),
        ),
      ),
    );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Notification Preferences')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [theme.primaryColor, theme.primaryColor.withValues(alpha: 0.7)]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.bell, color: Colors.white, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Notification Preferences', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text('Control which notifications you receive', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          ..._channels.map((ch) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(ch['icon'] as IconData, color: theme.primaryColor, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ch['name'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      Text(ch['desc'] as String, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                    ],
                  ),
                ),
                Switch(
                  value: _prefs[ch['id'] as String] ?? true,
                  onChanged: (v) => _toggle(ch['id'] as String, v),
                  activeThumbColor: theme.primaryColor,
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }
}
