import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:church_on_app/core/widgets/premium_toast.dart';
import 'package:church_on_app/features/admin/data/promo_code_service.dart';
import 'package:church_on_app/features/modules/bible_quiz/data/quiz_tournament_admin_service.dart';

/// Superadmin / COA tournament control.
///
/// Full scheduling (custom start/end, duration in weeks/months, recurrence,
/// registration windows), prize configuration, entry fees, visibility and
/// capacity — plus publish / feature / duplicate / cancel and the rewards
/// ledger (auto-award, manual award, revoke).
class QuizTournamentAdminScreen extends ConsumerStatefulWidget {
  const QuizTournamentAdminScreen({super.key});

  @override
  ConsumerState<QuizTournamentAdminScreen> createState() =>
      _QuizTournamentAdminScreenState();
}

class _QuizTournamentAdminScreenState
    extends ConsumerState<QuizTournamentAdminScreen> {
  String _filter = 'all'; // all | featured | open | completed | draft
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) ref.invalidate(adminTournamentsProvider);
    } catch (e) {
      if (mounted) PremiumToast.showError(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<TournamentAdmin> _apply(List<TournamentAdmin> all) {
    switch (_filter) {
      case 'featured':
        return all.where((t) => t.isFeatured).toList();
      case 'open':
        return all.where((t) => t.isOpen).toList();
      case 'completed':
        return all.where((t) => t.status == 'completed').toList();
      case 'draft':
        return all.where((t) => t.status == 'draft').toList();
      default:
        return all;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(adminTournamentsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0E1A),
        title: const Text('Quiz Tournaments',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(LucideIcons.refreshCw, color: Colors.white, size: 18),
            onPressed: () => ref.invalidate(adminTournamentsProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: theme.primaryColor,
        foregroundColor: Colors.black,
        onPressed: () => _openEditor(),
        icon: const Icon(LucideIcons.plus),
        label: const Text('New Tournament'),
      ),
      body: async.when(
        data: (all) {
          final rows = _apply(all);
          return Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Row(
                  children: [
                    for (final f in const ['all', 'featured', 'open', 'draft', 'completed'])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(f.toUpperCase()),
                          selected: _filter == f,
                          onSelected: (_) => setState(() => _filter = f),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: rows.isEmpty
                    ? const Center(
                        child: Text('No tournaments match this filter.',
                            style: TextStyle(color: Colors.white54)),
                      )
                    : RefreshIndicator(
                        onRefresh: () async =>
                            ref.invalidate(adminTournamentsProvider),
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                          itemCount: rows.length,
                          itemBuilder: (context, i) =>
                              _TournamentCard(t: rows[i], busy: _busy, run: _run),
                        ),
                      ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not load tournaments.\n$e',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54)),
          ),
        ),
      ),
    );
  }

  void _openEditor([TournamentAdmin? existing]) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => QuizTournamentAdminEditScreen(existing: existing),
    ));
  }
}

class _TournamentCard extends ConsumerWidget {
  final TournamentAdmin t;
  final bool busy;
  final Future<void> Function(Future<void> Function()) run;

  const _TournamentCard({required this.t, required this.busy, required this.run});

  Color _statusColor() {
    switch (t.status) {
      case 'live':
        return Colors.redAccent;
      case 'scheduled':
      case 'published':
        return Colors.orangeAccent;
      case 'completed':
        return Colors.greenAccent;
      case 'cancelled':
        return Colors.grey;
      default:
        return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final df = DateFormat('d MMM y · HH:mm');

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF151A2E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: t.isFeatured
              ? theme.primaryColor.withValues(alpha: 0.7)
              : Colors.white12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(t.title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ),
              if (t.isFeatured)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: theme.primaryColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('FEATURED',
                      style: TextStyle(
                          color: Colors.black,
                          fontSize: 9,
                          fontWeight: FontWeight.w900)),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor().withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(t.status.toUpperCase(),
                    style: TextStyle(
                        color: _statusColor(),
                        fontSize: 9,
                        fontWeight: FontWeight.w900)),
              ),
            ],
          ),
          if (t.description != null && t.description!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(t.description!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ],
          const SizedBox(height: 10),
          Wrap(spacing: 12, runSpacing: 4, children: [
            _meta(LucideIcons.globe, t.visibility),
            _meta(LucideIcons.trophy, t.format),
            _meta(LucideIcons.users, '${t.maxParticipants} max'),
            _meta(LucideIcons.coins,
                t.isFree ? 'Free entry' : '${t.entryFeeCc} CC entry'),
            if (t.startsAt != null) _meta(LucideIcons.calendar, df.format(t.startsAt!)),
            if (t.seasonLabel != null && t.seasonLabel!.isNotEmpty)
              _meta(LucideIcons.flag, t.seasonLabel!),
            if (t.recurrence != 'none')
              _meta(LucideIcons.repeat, '${t.recurrence} ×${t.recurrenceInterval}'),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: Text(
                'Prizes: ${t.prize1stCc} / ${t.prize2ndCc} / ${t.prize3rdCc} CC'
                '${t.participationRewardCc > 0 ? ' · +${t.participationRewardCc} participation' : ''}',
                style: TextStyle(
                    color: theme.primaryColor, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
            if (busy)
              const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            PopupMenuButton<String>(
              icon: const Icon(LucideIcons.moreVertical,
                  color: Colors.white54, size: 18),
              color: const Color(0xFF1E293B),
              onSelected: (v) => _onAction(context, ref, v),
              itemBuilder: (_) => [
                _item('edit', 'Edit', LucideIcons.pencil),
                _item('awards', 'Rewards & awards', LucideIcons.gift),
                _item('publish', t.publishedAt != null ? 'Unpublish' : 'Publish',
                    LucideIcons.uploadCloud),
                _item('feature', t.isFeatured ? 'Unfeature' : 'Promote (feature)',
                    LucideIcons.star),
                _item('duplicate', 'Duplicate', LucideIcons.copy),
                if (t.recurrence != 'none')
                  _item('spawn', 'Spawn occurrences', LucideIcons.repeat),
                _item('cancel', 'Cancel tournament', LucideIcons.xCircle,
                    danger: true),
              ],
            ),
          ]),
        ],
      ),
    );
  }

  PopupMenuItem<String> _item(String value, String label, IconData icon,
      {bool danger = false}) {
    return PopupMenuItem(
      value: value,
      child: Row(children: [
        Icon(icon, size: 16, color: danger ? Colors.redAccent : Colors.white70),
        const SizedBox(width: 10),
        Text(label,
            style: TextStyle(
                color: danger ? Colors.redAccent : Colors.white70, fontSize: 13)),
      ]),
    );
  }

  Widget _meta(IconData icon, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white38),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ],
      );

  Future<void> _onAction(
      BuildContext context, WidgetRef ref, String action) async {
    final svc = ref.read(quizTournamentAdminServiceProvider);
    switch (action) {
      case 'edit':
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => QuizTournamentAdminEditScreen(existing: t),
        ));
        return;
      case 'awards':
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TournamentAwardsScreen(tournament: t),
        ));
        return;
      case 'publish':
        await run(() => svc.publish(t.id, t.publishedAt == null));
        break;
      case 'feature':
        await run(() => svc.setFeatured(t.id, !t.isFeatured));
        break;
      case 'duplicate':
        await run(() async => svc.duplicate(t.id));
        break;
      case 'spawn':
        await run(() async => svc.spawnOccurrences(t.id, 3));
        break;
      case 'cancel':
        final reason = await _promptReason(context, 'Cancel tournament',
            'Reason (optional)');
        await run(() => svc.cancel(t.id, reason: reason));
        break;
    }
    if (context.mounted) PremiumToast.showSuccess(context, 'Updated.');
  }
}

/// Create / edit a tournament with full scheduling + prize configuration.
class QuizTournamentAdminEditScreen extends ConsumerStatefulWidget {
  final TournamentAdmin? existing;
  const QuizTournamentAdminEditScreen({super.key, this.existing});

  @override
  ConsumerState<QuizTournamentAdminEditScreen> createState() =>
      _QuizTournamentAdminEditScreenState();
}

class _QuizTournamentAdminEditScreenState
    extends ConsumerState<QuizTournamentAdminEditScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _seasonLabel;
  late final TextEditingController _questionCount;
  late final TextEditingController _timePerQuestion;
  late final TextEditingController _maxParticipants;
  late final TextEditingController _entryFeeCc;
  late final TextEditingController _entryFeeKwacha;
  late final TextEditingController _durationWeeks;
  late final TextEditingController _durationMonths;
  late final TextEditingController _recurrenceInterval;
  late final TextEditingController _prize1;
  late final TextEditingController _prize2;
  late final TextEditingController _prize3;
  late final TextEditingController _participation;
  late final TextEditingController _streak;
  late final TextEditingController _bannerUrl;
  late final TextEditingController _entryPromoCode;

  String _format = 'knockout';
  String _visibility = 'public';
  String _recurrence = 'none';
  bool _isPromo = false;
  bool _isFeatured = false;
  bool _publish = false;

  DateTime? _startsAt;
  DateTime? _endsAt;
  DateTime? _regOpens;
  DateTime? _regCloses;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final t = widget.existing;
    _title = TextEditingController(text: t?.title ?? '');
    _description = TextEditingController(text: t?.description ?? '');
    _seasonLabel = TextEditingController(text: t?.seasonLabel ?? '');
    _questionCount =
        TextEditingController(text: (t?.questionCount ?? 10).toString());
    _timePerQuestion =
        TextEditingController(text: (t?.timePerQuestion ?? 15).toString());
    _maxParticipants =
        TextEditingController(text: (t?.maxParticipants ?? 32).toString());
    _entryFeeCc = TextEditingController(text: (t?.entryFeeCc ?? 0).toString());
    _entryFeeKwacha = TextEditingController(
        text: (t?.entryFeeKwacha ?? 0).toStringAsFixed(0));
    _durationWeeks = TextEditingController(
        text: t?.durationWeeks == null ? '' : '${t!.durationWeeks}');
    _durationMonths = TextEditingController(
        text: t?.durationMonths == null ? '' : '${t!.durationMonths}');
    _recurrenceInterval =
        TextEditingController(text: (t?.recurrenceInterval ?? 1).toString());
    _prize1 = TextEditingController(text: (t?.prize1stCc ?? 0).toString());
    _prize2 = TextEditingController(text: (t?.prize2ndCc ?? 0).toString());
    _prize3 = TextEditingController(text: (t?.prize3rdCc ?? 0).toString());
    _participation =
        TextEditingController(text: (t?.participationRewardCc ?? 0).toString());
    _streak = TextEditingController(text: (t?.streakRewardCc ?? 0).toString());
    _bannerUrl = TextEditingController(text: t?.bannerUrl ?? '');
    _entryPromoCode = TextEditingController(text: t?.entryPromoCode ?? '');
    _format = t?.format ?? 'knockout';
    _visibility = t?.visibility ?? 'public';
    _recurrence = t?.recurrence ?? 'none';
    _isPromo = t?.isPromo ?? false;
    _isFeatured = t?.isFeatured ?? false;
    _publish = t?.publishedAt != null;
    _startsAt = t?.startsAt;
    _endsAt = t?.endsAt;
    _regOpens = t?.registrationOpensAt;
    _regCloses = t?.registrationClosesAt;
  }

  @override
  void dispose() {
    for (final c in [
      _title, _description, _seasonLabel, _questionCount, _timePerQuestion,
      _maxParticipants, _entryFeeCc, _entryFeeKwacha, _durationWeeks,
      _durationMonths, _recurrenceInterval, _prize1, _prize2, _prize3,
      _participation, _streak, _bannerUrl, _entryPromoCode,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  int _int(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  Map<String, dynamic> _payload() => {
        'title': _title.text.trim(),
        'description': _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        'format': _format,
        'visibility': _visibility,
        'question_count': _int(_questionCount),
        'time_per_question': _int(_timePerQuestion),
        'max_participants': _int(_maxParticipants),
        'entry_fee_cc': _int(_entryFeeCc),
        'entry_fee_kwacha': double.tryParse(_entryFeeKwacha.text.trim()) ?? 0,
        'season_label':
            _seasonLabel.text.trim().isEmpty ? null : _seasonLabel.text.trim(),
        'duration_weeks':
            _durationWeeks.text.trim().isEmpty ? null : _int(_durationWeeks),
        'duration_months':
            _durationMonths.text.trim().isEmpty ? null : _int(_durationMonths),
        'recurrence': _recurrence,
        'recurrence_interval': _int(_recurrenceInterval),
        'prize_1st_cc': _int(_prize1),
        'prize_2nd_cc': _int(_prize2),
        'prize_3rd_cc': _int(_prize3),
        'participation_reward_cc': _int(_participation),
        'streak_reward_cc': _int(_streak),
        'prize_config': {
          'streak_min_correct': 1,
        },
        'is_promo': _isPromo,
        'is_featured': _isFeatured,
        'banner_url': _bannerUrl.text.trim().isEmpty ? null : _bannerUrl.text.trim(),
        'entry_promo_code':
            _entryPromoCode.text.trim().isEmpty ? null : _entryPromoCode.text.trim(),
        'starts_at': _startsAt?.toIso8601String(),
        'ends_at': _endsAt?.toIso8601String(),
        'registration_opens_at': _regOpens?.toIso8601String(),
        'registration_closes_at': _regCloses?.toIso8601String(),
        'publish': _publish,
      };

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final svc = ref.read(quizTournamentAdminServiceProvider);
      if (_isEdit) {
        await svc.updateTournament(widget.existing!.id, _payload());
      } else {
        await svc.createTournament(_payload());
      }
      ref.invalidate(adminTournamentsProvider);
      ref.invalidate(featuredTournamentsProvider);
      if (mounted) {
        PremiumToast.showSuccess(context, _isEdit ? 'Tournament updated.' : 'Tournament created.');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) PremiumToast.showError(context, '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<DateTime?> _pickDateTime(DateTime? initial) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial ?? now),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _pickStart() async {
    final v = await _pickDateTime(_startsAt);
    if (v != null && mounted) setState(() => _startsAt = v);
  }

  Future<void> _pickEnd() async {
    final v = await _pickDateTime(_endsAt);
    if (v != null && mounted) setState(() => _endsAt = v);
  }

  Future<void> _pickRegOpens() async {
    final v = await _pickDateTime(_regOpens);
    if (v != null && mounted) setState(() => _regOpens = v);
  }

  Future<void> _pickRegCloses() async {
    final v = await _pickDateTime(_regCloses);
    if (v != null && mounted) setState(() => _regCloses = v);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0E1A),
        title: Text(_isEdit ? 'Edit Tournament' : 'New Tournament',
            style: const TextStyle(color: Colors.white)),
        actions: [
          _saving
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)))
              : IconButton(
                  icon: const Icon(LucideIcons.check, color: Colors.white),
                  onPressed: _save,
                ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 60),
          children: [
            _section('Basics'),
            _text('Title', _title, required: true),
            _text('Description', _description, maxLines: 3),
            _text('Season label (e.g. "2026 Season A")', _seasonLabel),
            Row(children: [
              Expanded(child: _dropdown('Format', _format, const {
                'knockout': 'Knockout',
                'roundRobin': 'Round Robin',
                'single': 'Single round',
              }, (v) => setState(() => _format = v))),
              const SizedBox(width: 12),
              Expanded(child: _dropdown('Visibility', _visibility, const {
                'public': 'Public',
                'invited': 'Invited',
                'tenant': 'Tenant only',
              }, (v) => setState(() => _visibility = v))),
            ]),
            Row(children: [
              Expanded(child: _text('Questions', _questionCount, number: true)),
              const SizedBox(width: 12),
              Expanded(child: _text('Seconds/question', _timePerQuestion, number: true)),
              const SizedBox(width: 12),
              Expanded(child: _text('Capacity', _maxParticipants, number: true)),
            ]),
            _section('Scheduling'),
            _dateRow('Starts at', _startsAt, _pickStart),
            _dateRow('Ends at', _endsAt, _pickEnd),
            const Text(
              'Or set a duration (weeks / months) — used when no explicit end is set.',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _text('Duration (weeks)', _durationWeeks, number: true)),
              const SizedBox(width: 12),
              Expanded(child: _text('Duration (months)', _durationMonths, number: true)),
            ]),
            const SizedBox(height: 12),
            _dropdown('Recurrence', _recurrence, const {
              'none': 'None',
              'daily': 'Daily',
              'weekly': 'Weekly',
              'monthly': 'Monthly',
              'yearly': 'Yearly',
            }, (v) => setState(() => _recurrence = v)),
            if (_recurrence != 'none')
              _text('Repeat every N ${_recurrence == 'daily' ? 'days' : _recurrence == 'weekly' ? 'weeks' : 'months'}',
                  _recurrenceInterval, number: true),
            const SizedBox(height: 6),
            _dateRow('Registration opens', _regOpens, _pickRegOpens),
            _dateRow('Registration closes', _regCloses, _pickRegCloses),
            _section('Entry & Promotion'),
            Row(children: [
              Expanded(child: _text('Entry fee (CC)', _entryFeeCc, number: true)),
              const SizedBox(width: 12),
              Expanded(child: _text('Entry fee (K)', _entryFeeKwacha, number: true)),
            ]),
            _text('Entry promo code (optional)', _entryPromoCode),
            _text('Banner image URL', _bannerUrl),
            SwitchListTile(
              value: _isPromo,
              onChanged: (v) => setState(() => _isPromo = v),
              title: const Text('Promo / open event',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              activeThumbColor: theme.primaryColor,
            ),
            SwitchListTile(
              value: _isFeatured,
              onChanged: (v) => setState(() => _isFeatured = v),
              title: const Text('Promote on the hub (featured)',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              activeThumbColor: theme.primaryColor,
            ),
            SwitchListTile(
              value: _publish,
              onChanged: (v) => setState(() => _publish = v),
              title: const Text('Published',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              activeThumbColor: theme.primaryColor,
            ),
            _section('Rewards'),
            const Text(
              'Leave at 0 to use the platform default prize amounts.',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _text('1st (CC)', _prize1, number: true)),
              const SizedBox(width: 12),
              Expanded(child: _text('2nd (CC)', _prize2, number: true)),
              const SizedBox(width: 12),
              Expanded(child: _text('3rd (CC)', _prize3, number: true)),
            ]),
            Row(children: [
              Expanded(child: _text('Participation (CC)', _participation, number: true)),
              const SizedBox(width: 12),
              Expanded(child: _text('Streak reward (CC)', _streak, number: true)),
            ]),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(LucideIcons.save),
                label: Text(_isEdit ? 'Save changes' : 'Create tournament'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String label) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 10),
        child: Text(label.toUpperCase(),
            style: TextStyle(
                color: Theme.of(context).primaryColor,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.1)),
      );

  Widget _text(String label, TextEditingController c,
      {bool number = false, bool required = false, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        maxLines: maxLines,
        style: const TextStyle(color: Colors.white),
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
            : null,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _dropdown(String label, String value, Map<String, String> options,
      ValueChanged<String> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: options.containsKey(value) ? value : options.keys.first,
        dropdownColor: const Color(0xFF1E293B),
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
          border: const OutlineInputBorder(),
        ),
        items: options.entries
            .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
            .toList(),
        onChanged: (v) => v == null ? null : onChanged(v),
      ),
    );
  }

  Widget _dateRow(String label, DateTime? value, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white24),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(children: [
            Icon(LucideIcons.calendar, size: 15, color: Colors.white38),
            const SizedBox(width: 10),
            Expanded(
              child: Text('$label: ${value == null ? 'Not set' : DateFormat('d MMM y HH:mm').format(value)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Rewards ledger for one tournament: auto-award, manual award, revoke.
class TournamentAwardsScreen extends ConsumerStatefulWidget {
  final TournamentAdmin tournament;
  const TournamentAwardsScreen({super.key, required this.tournament});

  @override
  ConsumerState<TournamentAwardsScreen> createState() =>
      _TournamentAwardsScreenState();
}

class _TournamentAwardsScreenState
    extends ConsumerState<TournamentAwardsScreen> {
  bool _busy = false;

  Future<void> _autoAward() async {
    setState(() => _busy = true);
    try {
      final res = await ref
          .read(quizTournamentAdminServiceProvider)
          .awardPrizes(widget.tournament.id);
      ref.invalidate(tournamentAwardsProvider(widget.tournament.id));
      ref.invalidate(adminTournamentsProvider);
      if (mounted) {
        PremiumToast.showSuccess(
            context, 'Awarded ${res['awarded'] ?? 0} rewards (${res['total_cc'] ?? 0} CC).');
      }
    } catch (e) {
      if (mounted) PremiumToast.showError(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(tournamentAwardsProvider(widget.tournament.id));
    final t = widget.tournament;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0E1A),
        title: const Text('Rewards & Awards',
            style: TextStyle(color: Colors.white)),
        actions: [
          if (_busy)
            const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)))
          else
            IconButton(
              tooltip: 'Auto-award prizes',
              icon: const Icon(LucideIcons.award, color: Colors.amber),
              onPressed: _autoAward,
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: theme.primaryColor,
        foregroundColor: Colors.black,
        onPressed: () => _manualAward(),
        icon: const Icon(LucideIcons.gift),
        label: const Text('Manual award'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF151A2E),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.title,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(
                  '1st: ${t.prize1stCc} · 2nd: ${t.prize2ndCc} · 3rd: ${t.prize3rdCc} CC'
                  '${t.participationRewardCc > 0 ? ' · Participation: ${t.participationRewardCc} CC' : ''}'
                  '${t.streakRewardCc > 0 ? ' · Streak: ${t.streakRewardCc} CC' : ''}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ]),
            ),
          ),
          Expanded(
            child: async.when(
              data: (awards) => awards.isEmpty
                  ? const Center(
                      child: Text('No awards yet. Use auto-award or manual award.',
                          style: TextStyle(color: Colors.white54)))
                  : RefreshIndicator(
                      onRefresh: () async => ref
                          .invalidate(tournamentAwardsProvider(widget.tournament.id)),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                        itemCount: awards.length,
                        separatorBuilder: (_, __) => const Divider(color: Colors.white12),
                        itemBuilder: (context, i) {
                          final a = awards[i];
                          final revoked = a.status == 'revoked';
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor:
                                  theme.primaryColor.withValues(alpha: 0.15),
                              child: Text(
                                a.rank != null ? '#${a.rank}' : a.awardType[0].toUpperCase(),
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: theme.primaryColor),
                              ),
                            ),
                            title: Text(a.fullName ?? a.userId,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 13)),
                            subtitle: Text(
                              '${a.awardType} · ${a.ccAmount} CC'
                              '${a.promoCode != null ? ' · ${a.promoCode}' : ''}'
                              '${revoked ? ' · REVOKED' : ''}',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: revoked ? Colors.redAccent : Colors.white54),
                            ),
                            trailing: revoked
                                ? null
                                : IconButton(
                                    icon: const Icon(LucideIcons.undo2,
                                        size: 16, color: Colors.redAccent),
                                    tooltip: 'Revoke',
                                    onPressed: () async {
                                      await ref
                                          .read(quizTournamentAdminServiceProvider)
                                          .revokeAward(a.id);
                                      ref.invalidate(
                                          tournamentAwardsProvider(widget.tournament.id));
                                    },
                                  ),
                          );
                        },
                      ),
                    ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                  child: Text('$e', style: const TextStyle(color: Colors.white54))),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _manualAward() async {
    final user = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF151A2E),
      builder: (_) => const _UserPickerSheet(),
    );
    if (user == null || !mounted) return;

    final cc = TextEditingController(text: '0');
    final promo = TextEditingController();
    final label = TextEditingController(text: 'Manual reward');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text('Award ${user['full_name'] ?? 'user'}',
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: cc,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(labelText: 'Church Coins'),
          ),
          TextField(
            controller: promo,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(labelText: 'Promo code (optional)'),
          ),
          TextField(
            controller: label,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(labelText: 'Label'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Award')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final res = await ref.read(quizTournamentAdminServiceProvider).awardManual(
            tournamentId: widget.tournament.id,
            userId: user['id'].toString(),
            cc: int.tryParse(cc.text.trim()) ?? 0,
            promoCode: promo.text.trim().isEmpty ? null : promo.text.trim(),
            label: label.text.trim().isEmpty ? 'Manual reward' : label.text.trim(),
          );
      ref.invalidate(tournamentAwardsProvider(widget.tournament.id));
      if (mounted && res['ok'] == true) {
        PremiumToast.showSuccess(context, 'Reward recorded.');
      }
    } catch (e) {
      if (mounted) PremiumToast.showError(context, '$e');
    }
  }
}

class _UserPickerSheet extends ConsumerStatefulWidget {
  const _UserPickerSheet();

  @override
  ConsumerState<_UserPickerSheet> createState() => _UserPickerSheetState();
}

class _UserPickerSheetState extends ConsumerState<_UserPickerSheet> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  Future<void> _load(String q) async {
    setState(() => _loading = true);
    final rows = await ref.read(promoCodeServiceProvider).searchUsers(q);
    if (!mounted) return;
    setState(() {
      _users = rows;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(children: [
          const Text('Choose a user',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          TextField(
            controller: _search,
            style: const TextStyle(color: Colors.white),
            onChanged: (v) => _load(v),
            decoration: const InputDecoration(
              hintText: 'Search name or email',
              prefixIcon: Icon(LucideIcons.search, color: Colors.white38),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _users.length,
                    itemBuilder: (context, i) {
                      final u = _users[i];
                      return ListTile(
                        title: Text((u['full_name'] ?? 'Unnamed').toString(),
                            style: const TextStyle(color: Colors.white, fontSize: 13)),
                        subtitle: Text((u['email'] ?? '').toString(),
                            style: const TextStyle(color: Colors.white54, fontSize: 11)),
                        onTap: () => Navigator.pop(context, u),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}

Future<String?> _promptReason(
    BuildContext context, String title, String hint) async {
  final c = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16)),
      content: TextField(
        controller: c,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
      ],
    ),
  );
  return ok == true ? c.text.trim() : null;
}
