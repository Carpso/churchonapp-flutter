import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/reporting_chain_service.dart';

/// The reporting chain in one screen, split by the role that acts at each step.
///
///   MY RETURN      the secretary files this church's monthly/quarterly return
///   TO REVIEW      the pastor sees what is waiting for them, across branches
///   CONFERENCE     the bishop sees compliance and tithes across the whole
///                  conference, and MAY send a period to HQ
///
/// The chain ENDS in the church. `approved` is a decision, `local_complete` is
/// a closed period: the return is final and stays with the church. Sending to
/// conference is an OPTIONAL escalation from there, not the mandatory next
/// step - so the screen never presents HQ as the only way to be finished.
///
/// Keeping it in one screen means a pastor who is also a secretary does not
/// learn two different vocabularies for the same month.
class ReportingScreen extends StatefulWidget {
  final String tenantId;
  final String? organizationId;

  const ReportingScreen({
    super.key,
    required this.tenantId,
    this.organizationId,
  });

  @override
  State<ReportingScreen> createState() => _ReportingScreenState();
}

class _ReportingScreenState extends State<ReportingScreen>
    with SingleTickerProviderStateMixin {
  late final ReportingChainService _service =
      ReportingChainService(Supabase.instance.client);

  /// Created in `initState` rather than as a field initialiser because the tab
  /// count depends on `widget`, and a `State`'s field initialisers run before
  /// `widget` is assigned.
  late final TabController _tabs;

  List<ReportSubmission> _mine = const [];
  List<ReportSubmission> _queue = const [];
  List<ReportSubmission> _conference = const [];
  List<RemittanceRecord> _remittances = const [];

  /// Which conference period the HQ buttons act on. The `send_reports_to_hq` /
  /// `acknowledge_reports` RPCs move a whole period, not a single return, so
  /// the conference tab has to name a period instead of implying a per-row
  /// action. Index rather than a key: clamped on read, so it can never fall out
  /// of range when the list reloads.
  int _periodIndex = 0;

  bool _loading = true;
  bool _working = false;
  String? _error;

  /// The admin hub links in with `?org=` - an EMPTY value - for a church in no
  /// organization, so a blank string must mean "no conference" everywhere.
  /// Treating it as a real id produced two bugs at once: a template query for a
  /// non-existent organization, and a `TabController(length: 3)` driving a
  /// two-tab `TabBar` (a hard assertion at runtime).
  String? get _orgId {
    final raw = widget.organizationId?.trim();
    return (raw == null || raw.isEmpty) ? null : raw;
  }

  int get _tabCount => _orgId == null ? 2 : 3;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _tabCount, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final org = _orgId;
      final results = await Future.wait([
        _service.fetchForTenant(widget.tenantId),
        _service.fetchReviewQueue(widget.tenantId),
        if (org != null) _service.fetchForOrganization(org),
        _service.fetchRemittances(
          organizationId: org,
          tenantId: org == null ? widget.tenantId : null,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _mine = results[0] as List<ReportSubmission>;
        _queue = results[1] as List<ReportSubmission>;
        _conference = org == null
            ? const <ReportSubmission>[]
            : results[2] as List<ReportSubmission>;
        _remittances = results.last as List<RemittanceRecord>;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[reporting] load failed: $e');
      if (!mounted) return;
      setState(() {
        _error = 'Could not load reporting.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasOrg = _orgId != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reporting',
            style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        bottom: TabBar(
          controller: _tabs,
          labelColor: theme.primaryColor,
          unselectedLabelColor: theme.disabledColor,
          tabs: [
            const Tab(text: 'My return'),
            Tab(text: _queue.isEmpty ? 'To review' : 'To review (${_queue.length})'),
            if (hasOrg) const Tab(text: 'Conference'),
          ],
        ),
      ),
      floatingActionButton: _tabs.index == 0
          ? FloatingActionButton.extended(
              onPressed: _loading ? null : _openReturnForm,
              icon: const Icon(Icons.edit_note),
              label: const Text('File return'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _myReturnTab(theme),
                    _reviewTab(theme),
                    if (hasOrg)
                      _conferenceTab(theme)
                    else
                      const SizedBox.shrink(),
                  ],
                ),
    );
  }

  // ------------------------------------------------------------ my return

  Widget _myReturnTab(ThemeData theme) {
    if (_mine.isEmpty) {
      return _empty(
        theme,
        'No returns filed yet',
        'File this church''s monthly or quarterly return. The form is set '
            'by your conference, so the questions match what HQ asks for.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        itemCount: _mine.length,
        itemBuilder: (_, i) => _returnCard(_mine[i], theme, mine: true),
      ),
    );
  }

  Widget _returnCard(
    ReportSubmission r,
    ThemeData theme, {
    bool mine = false,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(r.status.icon, size: 18, color: r.status.color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    mine ? r.periodLabel : '${r.tenantName ?? 'Church'} · ${r.periodLabel}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: r.status.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    r.status.label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: r.status.color,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                _stat(theme, 'Tithe', 'K ${r.titheTotal.toStringAsFixed(0)}'),
                _stat(theme, 'Attendance', '${r.attendanceTotal}'),
                _stat(theme, 'New members', '${r.newMembers}'),
                _stat(theme, 'Baptisms', '${r.baptisms}'),
              ],
            ),
            if (r.status.isFinalisedLocally) ...[
              const SizedBox(height: 8),
              _note(theme, Colors.blueGrey, Icons.lock_outline,
                  'Approved and closed in the church. It was NOT sent to '
                  'conference - reopen it if a figure needs correcting.'),
            ],
            if (r.reviewNote != null && r.reviewNote!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _note(theme, Colors.red, Icons.feedback_outlined,
                  'Pastor: ${r.reviewNote}'),
            ],
            const SizedBox(height: 8),
            // A Wrap, not a Row: an approved return can offer both "FINALISE
            // LOCALLY" and "Remit to HQ" at once, which overflows a Row on a
            // narrow phone.
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                if (mine &&
                    (r.status == ReportStatus.draft ||
                        r.status == ReportStatus.returned))
                  TextButton.icon(
                    onPressed: () => _openReturnForm(existing: r),
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Edit'),
                  ),
                if (!mine)
                  TextButton.icon(
                    onPressed: () => _review(r),
                    icon: const Icon(Icons.fact_check_outlined, size: 16),
                    label: const Text('Review'),
                  ),
                if (mine && r.status.isApproved)
                  FilledButton.icon(
                    onPressed: _working ? null : () => _finalise(r),
                    icon: const Icon(Icons.done_all, size: 16),
                    label: const Text('FINALISE LOCALLY'),
                  ),
                if (mine && r.status.isFinalisedLocally)
                  TextButton.icon(
                    onPressed: _working ? null : () => _reopen(r),
                    icon: const Icon(Icons.restart_alt, size: 16),
                    label: const Text('Reopen'),
                  ),
                if (mine &&
                    r.status == ReportStatus.approved &&
                    _remittances.every((x) => x.id != r.id))
                  TextButton.icon(
                    onPressed: () => _raiseRemittance(r),
                    icon: const Icon(Icons.account_balance, size: 16),
                    label: const Text('Remit to HQ'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// A tinted strip used for the review note and for the finalised-locally
  /// explanation.
  Widget _note(
    ThemeData theme,
    Color color,
    IconData icon,
    String text,
  ) =>
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(text, style: theme.textTheme.bodySmall),
            ),
          ],
        ),
      );

  Widget _stat(ThemeData theme, String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          Text(label, style: theme.textTheme.labelSmall),
        ],
      );

  // ----------------------------------------------------------- review queue

  Widget _reviewTab(ThemeData theme) {
    if (_queue.isEmpty) {
      return _empty(
        theme,
        'Nothing waiting on you',
        'When a secretary submits a return it appears here for you to check '
            'and approve. Once approved the church can finalise it there and '
            'forget about it, or escalate it to conference if it chooses to.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _queue.length,
        itemBuilder: (_, i) =>
            _returnCard(_queue[i], theme),
      ),
    );
  }

  Future<void> _review(ReportSubmission r) async {
    final noteCtrl = TextEditingController();
    final decision = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${r.tenantName ?? 'Church'} · ${r.periodLabel}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tithe K ${r.titheTotal.toStringAsFixed(2)} · '
                'Offering K ${r.offeringTotal.toStringAsFixed(2)}'),
            Text('Attendance ${r.attendanceTotal} · '
                'New members ${r.newMembers} · Baptisms ${r.baptisms}'),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(
                labelText: 'Note to the secretary (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'return'),
            child: const Text('Send back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'approve'),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (decision == null) return;

    try {
      await _service.review(
        reportId: r.id,
        approve: decision == 'approve',
        note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(decision == 'approve'
            ? 'Return approved'
            : 'Return sent back for correction'),
      ));
      await _load();
    } on ReportException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Close the period in the church. This is the END of the chain, so the
  /// dialog says plainly what it does NOT do - otherwise a pastor assumes the
  /// return is on its way somewhere and waits for an acknowledgement that will
  /// never come.
  Future<void> _finalise(ReportSubmission r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finalise this return locally?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You are approving ${r.periodLabel} as final for this church. '
              'The figures cannot be edited afterwards - reopen the return if '
              'something needs correcting.',
              style: Theme.of(ctx).textTheme.bodyMedium,
            ),
            const SizedBox(height: 10),
            Text(
              'It will NOT be sent to conference. Nothing is remitted and '
              'nobody is waiting on a response.',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Finalise locally'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _working = true);
    try {
      await _service.completeReportLocally(reportId: r.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${r.periodLabel} finalised in your church'),
      ));
      await _load();
    } on ReportException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _reopen(ReportSubmission r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reopen this return?'),
        content: Text(
          '${r.periodLabel} goes back to "Approved" so the figures can be '
          'corrected. It is no longer final.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reopen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _working = true);
    try {
      await _service.reopenLocalReport(reportId: r.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Return reopened for correction')));
      await _load();
    } on ReportException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _raiseRemittance(ReportSubmission r) async {
    try {
      final rem = await _service.raiseRemittance(reportId: r.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Remittance ${rem.reference} raised: K ${rem.amount.toStringAsFixed(2)}'),
      ));
      await _load();
    } on ReportException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  // ------------------------------------------------------------- conference

  Widget _conferenceTab(ThemeData theme) {
    final t = _service.totals(_conference);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          Text('CONFERENCE TOTALS',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: theme.disabledColor)),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 20,
                    runSpacing: 10,
                    children: [
                      _stat(theme, 'Tithes',
                          'K ${(t['tithe'] ?? 0).toStringAsFixed(0)}'),
                      _stat(theme, 'Offerings',
                          'K ${(t['offering'] ?? 0).toStringAsFixed(0)}'),
                      _stat(theme, 'Attendance',
                          (t['attendance'] ?? 0).toStringAsFixed(0)),
                      _stat(theme, 'New members',
                          (t['new_members'] ?? 0).toStringAsFixed(0)),
                      _stat(theme, 'Baptisms',
                          (t['baptisms'] ?? 0).toStringAsFixed(0)),
                      _stat(theme, 'Returns filed', '${_conference.length}'),
                    ],
                  ),
                  const Divider(height: 24),
                  _compliance(theme),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          _conferenceActions(theme),
          const SizedBox(height: 18),
          Text('BRANCH RETURNS',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: theme.disabledColor)),
          const SizedBox(height: 8),
          if (_conference.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('No returns filed for this conference yet.',
                    style: theme.textTheme.bodySmall),
              ),
            )
          else
            ..._conference.map((r) => _returnCard(r, theme)),
          const SizedBox(height: 20),
          Text('REMITTANCES',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: theme.disabledColor)),
          const SizedBox(height: 8),
          if (_remittances.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text('No remittances raised.',
                    style: theme.textTheme.bodySmall),
              ),
            )
          else
            ..._remittances.map((r) => _remittanceTile(r, theme)),
        ],
      ),
    );
  }

  /// Every period present in this conference's returns, newest first.
  List<_ReportPeriod> get _conferencePeriods {
    final byKey = <String, _ReportPeriod>{};
    for (final r in _conference) {
      byKey.putIfAbsent(
        _periodKey(r.periodStart, r.periodEnd),
        () => _ReportPeriod(
          r.periodStart,
          r.periodEnd,
          r.periodLabel.isEmpty ? r.periodStart.year.toString() : r.periodLabel,
        ),
      );
    }
    final list = byKey.values.toList()
      ..sort((a, b) => b.start.compareTo(a.start));
    return list;
  }

  static String _periodKey(DateTime start, DateTime end) =>
      '${start.toIso8601String()}|${end.toIso8601String()}';

  List<ReportSubmission> _rowsInPeriod(_ReportPeriod p) => _conference
      .where((r) =>
          r.periodStart == p.start && r.periodEnd == p.end)
      .toList();

  /// The period currently selected, clamped so it can never go out of range when
  /// a reload shrinks the list.
  _ReportPeriod? get _selectedPeriod {
    final periods = _conferencePeriods;
    if (periods.isEmpty) return null;
    return periods[_periodIndex.clamp(0, periods.length - 1)];
  }

  /// SEND TO CONFERENCE / MARK ACKNOWLEDGED.
  ///
  /// These are the only two actions in the whole screen that move returns
  /// upstream, and they are deliberately optional and explicitly labelled: the
  /// chain is already finished for a return in `local_complete`, and pressing
  /// this is the church choosing to escalate a period, not the next step it
  /// owes anybody.
  ///
  /// They act on a WHOLE PERIOD because that is what the RPCs do - the count
  /// each one returns is reported back, so the confirmation states the real
  /// number instead of implying a single card was moved.
  Widget _conferenceActions(ThemeData theme) {
    final period = _selectedPeriod;
    final rows = period == null ? const <ReportSubmission>[] : _rowsInPeriod(period);
    final ready = rows.where((r) => r.status.canEscalateToConference).length;
    final atHq = rows.where((r) => r.status == ReportStatus.submittedHq).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('CONFERENCE HQ (OPTIONAL)',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                color: theme.disabledColor)),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'A return does not need conference. A branch can finalise its '
                  'month locally and that is the end of it. Use these only when '
                  'the conference chooses to take the return up.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                if (period == null)
                  Text('No returns filed for this conference yet.',
                      style: theme.textTheme.bodySmall)
                else ...[
                  DropdownButtonFormField<String>(
                    initialValue: _periodKey(period.start, period.end),
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Period',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final p in _conferencePeriods)
                        DropdownMenuItem(
                          value: _periodKey(p.start, p.end),
                          child: Text(
                              '${p.label} · ${_rowsInPeriod(p).length} return(s)'),
                        ),
                    ],
                    onChanged: (v) {
                      final i = _conferencePeriods
                          .indexWhere((p) => _periodKey(p.start, p.end) == v);
                      if (i >= 0) setState(() => _periodIndex = i);
                    },
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '$ready approved return(s) ready to send — including any '
                    'finalised locally'
                    '${atHq > 0 ? ' · $atHq waiting to be acknowledged' : ''}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _working || ready == 0
                            ? null
                            : () => _sendToHq(period),
                        icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                        label: const Text('SEND TO CONFERENCE'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _working || atHq == 0
                            ? null
                            : () => _acknowledge(period),
                        icon: const Icon(Icons.mark_email_read_outlined,
                            size: 18),
                        label: const Text('MARK ACKNOWLEDGED'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _sendToHq(_ReportPeriod period) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Send ${period.label} to conference?'),
        content: Text(
          'Every approved return for this period will be marked as sent. '
          'Branches that already finalised locally are included - this is '
          'optional, and nothing has to be sent.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _working = true);
    try {
      final n = await _service.sendToHq(
        organizationId: _orgId!,
        periodStart: period.start,
        periodEnd: period.end,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(n == 0
            ? 'Nothing to send - no approved returns for ${period.label}'
            : 'Sent $n return(s) for ${period.label} to conference'),
      ));
      await _load();
    } on ReportException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _acknowledge(_ReportPeriod period) async {
    setState(() => _working = true);
    try {
      final n = await _service.acknowledge(
        organizationId: _orgId!,
        periodStart: period.start,
        periodEnd: period.end,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(n == 0
            ? 'Nothing to acknowledge for ${period.label}'
            : 'Acknowledged $n return(s) for ${period.label}'),
      ));
      await _load();
    } on ReportException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  /// The question a bishop actually asks of a conference: did every branch
  /// file, did the money come up, and how many branches deliberately kept
  /// their return to themselves?
  Widget _compliance(ThemeData theme) {
    if (_conference.isEmpty) return const SizedBox.shrink();
    final filed = _conference.length;
    final acknowledged = _conference
        .where((r) => r.status == ReportStatus.acknowledged)
        .length;
    // Approved and closed in the church, never escalated. Not a failure - the
    // whole point of local completion - so it is reported, not chased.
    final localClosed = _conference
        .where((r) => r.status.isFinalisedLocally)
        .length;
    final received = _remittances
        .where((r) => r.status == 'received')
        .fold<double>(0, (a, r) => a + r.amount);
    final outstanding =
        _remittances.where((r) => r.status != 'received').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Conference compliance',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: filed == 0 ? 0 : acknowledged / filed,
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
        ),
        const SizedBox(height: 8),
        Text(
          '$acknowledged of $filed returns acknowledged by HQ'
          '${outstanding > 0 ? ' · $outstanding remittance(s) outstanding' : ''}',
          style: theme.textTheme.bodySmall,
        ),
        if (localClosed > 0) ...[
          const SizedBox(height: 6),
          Text(
            '$localClosed finalised locally and not sent to conference - '
            'that is a valid outcome, not an outstanding return.',
            style: theme.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 6),
        Text('Received to date: K ${received.toStringAsFixed(2)}',
            style: theme.textTheme.bodySmall
                ?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _remittanceTile(RemittanceRecord r, ThemeData theme) {
    final received = r.status == 'received';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        received ? Icons.check_circle : Icons.schedule_send,
        size: 20,
        color: received ? Colors.green : Colors.orange,
      ),
      title: Text('${r.reference}  ·  K ${r.amount.toStringAsFixed(2)}',
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        '${r.fromChurchName ?? 'Church'} · basis K ${r.basisAmount.toStringAsFixed(0)} '
        'at ${(r.rate * 100).toStringAsFixed(0)}%',
        style: theme.textTheme.bodySmall,
      ),
      trailing: received
          ? Text('Received',
              style: TextStyle(color: Colors.green.shade700, fontSize: 12))
          : TextButton(
              onPressed: () => _settle(r),
              child: const Text('Confirm'),
            ),
    );
  }

  Future<void> _settle(RemittanceRecord r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Confirm ${r.reference}?'),
        content: Text(
          'Confirm that K ${r.amount.toStringAsFixed(2)} from '
          '${r.fromChurchName ?? 'the church'} has been received at conference.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not yet')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Received')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.settleRemittance(remittanceId: r.id, receive: true);
      await _load();
    } on ReportException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Widget _empty(ThemeData theme, String title, String body) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.description_outlined, size: 40, color: theme.disabledColor),
              const SizedBox(height: 12),
              Text(title,
                  style: theme.textTheme.titleSmall,
                  textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text(body,
                  textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      );

  Future<void> _openReturnForm({ReportSubmission? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ReturnFormSheet(
        tenantId: widget.tenantId,
        organizationId: _orgId,
        service: _service,
        existing: existing,
      ),
    );
    if (saved == true) await _load();
  }
}

/// One reporting period, as the conference-wide HQ actions see it: the same
/// start/end pair the `send_reports_to_hq` / `acknowledge_reports` RPCs take,
/// with the human label the secretary typed.
@immutable
class _ReportPeriod {
  final DateTime start;
  final DateTime end;
  final String label;

  const _ReportPeriod(this.start, this.end, this.label);
}

/// The return form itself. Fields come from the conference's template, so a
/// conference can add questions without an app release.
class _ReturnFormSheet extends StatefulWidget {
  final String tenantId;
  final String? organizationId;
  final ReportingChainService service;
  final ReportSubmission? existing;

  const _ReturnFormSheet({
    required this.tenantId,
    required this.organizationId,
    required this.service,
    this.existing,
  });

  @override
  State<_ReturnFormSheet> createState() => _ReturnFormSheetState();
}

class _ReturnFormSheetState extends State<_ReturnFormSheet> {
  ReportTemplate? _template;
  final _fieldControllers = <String, TextEditingController>{};
  final _financial = <String, TextEditingController>{
    'tithe': TextEditingController(),
    'offering': TextEditingController(),
    'other': TextEditingController(),
    'attendance': TextEditingController(),
    'members': TextEditingController(),
    'baptisms': TextEditingController(),
    'salvations': TextEditingController(),
  };
  final _narrativeCtrl = TextEditingController();

  String _reportType = 'monthly';
  late DateTime _periodStart;
  late DateTime _periodEnd;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _periodStart = DateTime(now.year, now.month, 1);
    _periodEnd = DateTime(now.year, now.month + 1, 0);
    _prefill();
    _loadTemplate();
  }

  void _prefill() {
    final e = widget.existing;
    if (e == null) return;
    _reportType = e.reportType;
    _periodStart = e.periodStart;
    _periodEnd = e.periodEnd;
    _financial['tithe']!.text = e.titheTotal == 0 ? '' : '${e.titheTotal}';
    _financial['offering']!.text =
        e.offeringTotal == 0 ? '' : '${e.offeringTotal}';
    _financial['other']!.text =
        e.otherIncomeTotal == 0 ? '' : '${e.otherIncomeTotal}';
    _financial['attendance']!.text =
        e.attendanceTotal == 0 ? '' : '${e.attendanceTotal}';
    _financial['members']!.text =
        e.newMembers == 0 ? '' : '${e.newMembers}';
    _financial['baptisms']!.text =
        e.baptisms == 0 ? '' : '${e.baptisms}';
    _financial['salvations']!.text =
        e.salvations == 0 ? '' : '${e.salvations}';
    _narrativeCtrl.text = e.narrative ?? '';
    e.data.forEach((k, v) {
      final c = TextEditingController(text: v?.toString() ?? '');
      _fieldControllers[k] = c;
    });
  }

  Future<void> _loadTemplate() async {
    try {
      final t = await widget.service.loadTemplate(
        organizationId: widget.organizationId,
        reportType: _reportType,
      );
      if (!mounted) return;
      setState(() {
        _template = t;
        // Add a controller for any field the template declares that we have
        // not already populated from an existing return.
        for (final f in t?.fields ?? const <ReportFieldDef>[]) {
          _fieldControllers.putIfAbsent(
              f.key, () => TextEditingController());
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load the report form.';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    for (final c in _fieldControllers.values) {
      c.dispose();
    }
    for (final c in _financial.values) {
      c.dispose();
    }
    _narrativeCtrl.dispose();
    super.dispose();
  }

  String get _periodLabel {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June', 'July',
      'August', 'September', 'October', 'November', 'December'
    ];
    if (_reportType == 'quarterly') {
      final q = ((_periodStart.month - 1) ~/ 3) + 1;
      return 'Q$q ${_periodStart.year}';
    }
    return '${months[_periodStart.month - 1]} ${_periodStart.year}';
  }

  double _n(String key) =>
      double.tryParse(_financial[key]?.text.trim() ?? '') ?? 0;
  int _i(String key) =>
      int.tryParse(_financial[key]?.text.trim() ?? '') ?? 0;

  /// Live tithe figure, so the remittance preview stays in step with the field.
  double get _tithe => double.tryParse(_financial['tithe']?.text.trim() ?? '') ?? 0;

  Future<void> _save(bool submit) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final data = <String, dynamic>{};
      for (final entry in _fieldControllers.entries) {
        final text = entry.value.text.trim();
        if (text.isNotEmpty) data[entry.key] = text;
      }

      await widget.service.saveDraft(
        tenantId: widget.tenantId,
        reportType: _reportType,
        periodStart: _periodStart,
        periodEnd: _periodEnd,
        periodLabel: _periodLabel,
        data: data,
        titheTotal: _n('tithe'),
        offeringTotal: _n('offering'),
        otherIncomeTotal: _n('other'),
        attendanceTotal: _i('attendance'),
        newMembers: _i('members'),
        baptisms: _i('baptisms'),
        salvations: _i('salvations'),
        narrative: _narrativeCtrl.text.trim(),
        submit: submit,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ReportException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = _template;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        builder: (_, controller) => _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  Text(t?.name ?? 'Church return',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),

                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'monthly', label: Text('Monthly')),
                      ButtonSegment(value: 'quarterly', label: Text('Quarterly')),
                    ],
                    selected: {_reportType},
                    onSelectionChanged: (s) {
                      setState(() => _reportType = s.first);
                      _loadTemplate();
                    },
                  ),
                  const SizedBox(height: 8),
                  Text('Period: $_periodLabel',
                      style: theme.textTheme.bodySmall),

                  if (t != null && t.includeFinancials) ...[
                    const SizedBox(height: 20),
                    _section(theme, 'FINANCIALS'),
                    _money('tithe', 'Tithe total'),
                    _money('offering', 'Offering total'),
                    _money('other', 'Other income'),
                    const SizedBox(height: 8),
                    Text(
                      'Remittance to conference is '
                      '${(t.remittanceRate * 100).toStringAsFixed(0)}% of tithes '
                      'only (K ${(_tithe * t.remittanceRate).toStringAsFixed(2)}). '
                      'Offerings are not remitted.',
                      style: theme.textTheme.labelSmall,
                    ),
                  ],

                  const SizedBox(height: 20),
                  _section(theme, 'CHURCH LIFE'),
                  _number('attendance', 'Total attendance'),
                  _number('members', 'New members'),
                  _number('baptisms', 'Baptisms'),
                  _number('salvations', 'Salvations'),

                  if (t != null && t.fields.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _section(theme, 'CONFERENCE QUESTIONS'),
                    for (final f in t.fields) ...[
                      _customField(f),
                      const SizedBox(height: 10),
                    ],
                  ],

                  const SizedBox(height: 16),
                  _section(theme, 'NOTES FOR THE PASTOR'),
                  TextField(
                    controller: _narrativeCtrl,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'How was the period? Anything the pastor should know.',
                    ),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        style:
                            TextStyle(color: theme.colorScheme.error, fontSize: 13)),
                  ],

                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _saving ? null : () => _save(false),
                          icon: const Icon(Icons.save_outlined, size: 18),
                          label: const Text('Save draft'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _saving ? null : () => _save(true),
                          icon: const Icon(Icons.send, size: 18),
                          label: const Text('To pastor'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _section(ThemeData theme, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(label,
            style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 1.2, fontWeight: FontWeight.bold)),
      );

  Widget _money(String key, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: _financial[key],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: label,
            prefixText: 'K ',
          ),
        ),
      );

  Widget _number(String key, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: _financial[key],
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: label,
          ),
        ),
      );

  Widget _customField(ReportFieldDef f) {
    final ctrl = _fieldControllers[f.key]!;
    if (f.isLong) {
      return TextField(
        controller: ctrl,
        maxLines: 3,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: f.required ? '${f.label} *' : f.label,
          alignLabelWithHint: true,
        ),
      );
    }
    return TextField(
      controller: ctrl,
      keyboardType:
          f.isNumeric ? const TextInputType.numberWithOptions(decimal: true) : null,
      inputFormatters: f.isNumeric
          ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
          : null,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: f.required ? '${f.label} *' : f.label,
      ),
    );
  }
}