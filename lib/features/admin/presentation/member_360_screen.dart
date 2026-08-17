import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/widgets/app_error_view.dart';
import 'package:church_on_app/core/widgets/profile_avatar.dart';
import 'package:church_on_app/features/admin/data/pastoral_followup_service.dart';
import 'pastoral_followup_screen.dart';

/// Member 360° — one screen with attendance, giving, prayers, study streak
/// and pastoral follow-ups for a single member.
class Member360Screen extends ConsumerStatefulWidget {
  final String memberId;
  final String initialName;
  final String? initialAvatar;

  const Member360Screen({
    super.key,
    required this.memberId,
    required this.initialName,
    this.initialAvatar,
  });

  @override
  ConsumerState<Member360Screen> createState() => _Member360ScreenState();
}

class _Member360ScreenState extends ConsumerState<Member360Screen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _profile;
  int _attendanceCount = 0;
  String? _lastAttendance;
  double _confirmedGiving = 0;
  int _prayerCount = 0;
  List<Map<String, dynamic>> _prayers = [];
  int _streak = 0;
  int _longestStreak = 0;
  List<PastoralFollowup> _followups = [];
  final _currency = NumberFormat.currency(symbol: 'K ', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      final results = await Future.wait<dynamic>([
        client
            .from('profiles')
            .select('id, full_name, avatar_url, email, phone_number, role, created_at, coins')
            .eq('id', widget.memberId)
            .maybeSingle(),
        client
            .from('attendance_logs')
            .select('id, created_at')
            .eq('user_id', widget.memberId)
            .order('created_at', ascending: false)
            .limit(200),
        client
            .from('coa_payments')
            .select('amount, status, created_at, payment_type')
            .eq('user_id', widget.memberId)
            .order('created_at', ascending: false)
            .limit(200),
        client
            .from('prayers')
            .select('content, status, created_at')
            .eq('user_id', widget.memberId)
            .order('created_at', ascending: false)
            .limit(50),
        client
            .from('user_study_streaks')
            .select('current_streak, longest_streak')
            .eq('user_id', widget.memberId)
            .maybeSingle(),
        client
            .from('pastoral_followups')
            .select()
            .eq('member_id', widget.memberId)
            .order('created_at', ascending: false)
            .limit(50),
      ]);
      if (!mounted) return;

      final profile = results[0] as Map<String, dynamic>?;
      final attendance = results[1] as List;
      final payments = results[2] as List;
      final prayers = results[3] as List;
      final streak = results[4] as Map<String, dynamic>?;
      final followups = results[5] as List;

      double confirmed = 0;
      for (final p in payments) {
        if ((p['status'] as String? ?? '') == 'confirmed') {
          confirmed += (p['amount'] as num?)?.toDouble() ?? 0;
        }
      }

      setState(() {
        _profile = profile;
        _attendanceCount = attendance.length;
        _lastAttendance = attendance.isNotEmpty
            ? attendance.first['created_at'] as String?
            : null;
        _confirmedGiving = confirmed;
        _prayerCount = prayers.length;
        _prayers = prayers.cast<Map<String, dynamic>>();
        _streak = (streak?['current_streak'] as num?)?.toInt() ?? 0;
        _longestStreak = (streak?['longest_streak'] as num?)?.toInt() ?? 0;
        _followups = followups
            .cast<Map<String, dynamic>>()
            .map(PastoralFollowup.fromMap)
            .toList();
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load member data. ${e.toString()}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Member Profile', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: theme.scaffoldBackgroundColor,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? AppErrorView(error: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                    children: [
                      _buildHeader(theme),
                      const SizedBox(height: 16),
                      _buildStatsGrid(theme),
                      if (_followups.any((f) => f.isOpen)) ...[
                        const SizedBox(height: 20),
                        _buildOpenFollowupsCard(theme),
                      ],
                      const SizedBox(height: 20),
                      _buildActivityCard(theme),
                    ],
                  ),
                ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final name = _profile?['full_name'] as String? ?? widget.initialName;
    final role = (_profile?['role'] as String? ?? '').replaceAll('_', ' ');
    final email = _profile?['email'] as String? ?? '—';
    final phone = _profile?['phone_number'] as String? ?? '—';
    final memberSince = _profile?['created_at'] != null
        ? _fmtDate(DateTime.tryParse(_profile!['created_at'] as String) ?? DateTime.now())
        : '—';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [theme.colorScheme.primary, theme.colorScheme.tertiary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          ProfileAvatar(
            name: name,
            avatarUrl: _profile?['avatar_url'] as String? ?? widget.initialAvatar,
            radius: 32,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 19),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(role, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(LucideIcons.mail, size: 13, color: Colors.white70),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(email, style: const TextStyle(color: Colors.white70, fontSize: 11), overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(LucideIcons.phone, size: 13, color: Colors.white70),
                    const SizedBox(width: 4),
                    Text(phone, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 2),
                Text('Member since $memberSince', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid(ThemeData theme) {
    final lastAtt = _lastAttendance != null
        ? _fmtDate(DateTime.tryParse(_lastAttendance!) ?? DateTime.now())
        : '—';
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _statCard(theme, LucideIcons.calendarCheck, '$_attendanceCount', 'Attendances')),
            const SizedBox(width: 10),
            Expanded(child: _statCard(theme, LucideIcons.trendingUp, _currency.format(_confirmedGiving), 'Confirmed giving')),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _statCard(theme, LucideIcons.bookOpen, '$_streak days', 'Study streak (best $_longestStreak)')),
            const SizedBox(width: 10),
            Expanded(child: _statCard(theme, LucideIcons.helpingHand, '$_prayerCount', 'Prayers')),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _statCard(theme, LucideIcons.clock, lastAtt, 'Last attended')),
            const SizedBox(width: 10),
            Expanded(
              child: _statCard(
                theme,
                LucideIcons.heartHandshake,
                '${_followups.where((f) => f.isOpen).length} open',
                'Follow-ups',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _statCard(ThemeData theme, IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildOpenFollowupsCard(ThemeData theme) {
    final open = _followups.where((f) => f.isOpen).toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.heartHandshake, size: 18, color: Colors.amber),
              const SizedBox(width: 8),
              Text('${open.length} open follow-up${open.length == 1 ? '' : 's'}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PastoralFollowupScreen()),
                ),
                child: const Text('Manage'),
              ),
            ],
          ),
          for (final f in open.take(3))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '• ${_typeLabel(f.followupType)}${f.followUpAt != null ? ' — due ${_fmtDate(f.followUpAt!)}' : ''}',
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActivityCard(ThemeData theme) {
    final items = <Widget>[];
    if (_prayers.isNotEmpty) {
      items.add(const _SectionTitle('Recent prayers'));
      for (final p in _prayers.take(3)) {
        items.add(
          _activityTile(
            theme,
            icon: LucideIcons.helpingHand,
            iconColor: Colors.purple,
            title: (p['content'] as String? ?? '').trim(),
            subtitle: '${p['status'] as String? ?? 'pending'} • ${_fmtDate(DateTime.tryParse(p['created_at'] as String? ?? '') ?? DateTime.now())}',
            maxLines: 2,
          ),
        );
      }
    }
    if (_followups.isNotEmpty) {
      items.add(const _SectionTitle('Follow-up history'));
      for (final f in _followups.take(3)) {
        items.add(
          _activityTile(
            theme,
            icon: LucideIcons.heartHandshake,
            iconColor: Colors.deepOrange,
            title: '${_typeLabel(f.followupType)} — ${f.status}',
            subtitle: f.notes.isNotEmpty ? f.notes : 'Logged ${_fmtDate(f.createdAt)}',
            maxLines: 2,
          ),
        );
      }
    }
    if (items.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          'No activity recorded yet. Attendance, giving, prayers and follow-ups will appear here.',
          textAlign: TextAlign.center,
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: items);
  }

  Widget _activityTile(
    ThemeData theme, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    int maxLines = 1,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), maxLines: maxLines, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant), maxLines: maxLines, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'phone':
        return 'Phone call';
      case 'whatsapp':
        return 'WhatsApp';
      case 'sms':
        return 'SMS';
      case 'email':
        return 'Email';
      case 'in_church':
        return 'In-church visit';
      case 'visit':
      default:
        return 'Home visit';
    }
  }

  String _fmtDate(DateTime d) {
    final local = d.toLocal();
    return '${local.day} ${_months[local.month - 1]} ${local.year}';
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 10),
      child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
    );
  }
}
