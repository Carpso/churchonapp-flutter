import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:church_on_app/core/config/app_constants.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/theme/app_theme.dart';
import 'package:church_on_app/features/church/data/church_governance_service.dart';

/// Ministerial ordination and credentialing.
///
/// THE AUTHORITY RULE, MADE VISIBLE
/// A local pastor can APPOINT a deacon (see Church Officers). A local pastor
/// CANNOT ORDAIN one — ordination is conferred by the conference, in practice by the
/// bishop, or an apostle, prophet, or the conference general secretary or treasurer.
/// The server refuses anyone else, so the screen hides the controls rather than
/// offering a button that would only fail.
///
/// A credential can be REVOKED years after the person served — in another church,
/// with a number quoted on a letter somebody relies on. So nothing is deleted: the
/// row survives with its number, the reason is mandatory, and the full trail of
/// grant → renew → revoke is kept underneath. A revocation does NOT remove somebody
/// from their church's officers board; the church ends that appointment itself.
class OrdinationScreen extends ConsumerStatefulWidget {
  const OrdinationScreen({super.key, this.churchId});

  /// Optional explicit church/tenant id. Falls back to the signed-in user's church.
  final String? churchId;

  @override
  ConsumerState<OrdinationScreen> createState() => _OrdinationScreenState();
}

class _OrdinationScreenState extends ConsumerState<OrdinationScreen> {
  bool _busy = false;
  String? _error;

  ChurchGovernanceService get _service =>
      ref.read(churchGovernanceServiceProvider);

  String get _churchId {
    final explicit = (widget.churchId ?? '').trim();
    if (explicit.isNotEmpty) return explicit;
    return ref.read(currentTenantProvider)?.id ?? '';
  }

  /// Mirrors `can_issue_ordination` in the migration. Note `pastor` is absent — on
  /// purpose, and not by oversight.
  bool get _canIssue {
    final role = ref.watch(profileProvider).value?.role ?? '';
    return GovernanceRoles.canIssueCredentials(role);
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() => _error = null);
    final id = _churchId;
    try {
      await Future.wait([
        ref.refresh(churchCredentialsProvider(id).future),
        ref.refresh(churchCredentialEventsProvider(id).future),
      ]);
    } catch (e) {
      if (mounted) setState(() => _error = _friendly(e));
    }
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
      await _reload();
    } on GovernanceException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _grant() async {
    final id = _churchId;
    if (id.isEmpty) {
      setState(() => _error = 'Select a church first.');
      return;
    }

    List<Map<String, dynamic>> members;
    try {
      members = await _service.fetchMembers(id);
    } catch (e) {
      if (mounted) setState(() => _error = _friendly(e));
      return;
    }
    if (!mounted) return;
    if (members.isEmpty) {
      setState(() => _error =
          'No members found for this church yet. Ordination is recorded for a '
          'person, so pick somebody on the roll.');
      return;
    }

    final result = await showModalBottomSheet<_GrantResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _GrantCredentialSheet(members: members),
    );
    if (result == null) return;

    await _run(
      () => _service.grantCredential(
        holderUserId: result.holderUserId,
        credentialType: result.credentialType,
        ministryRole: result.ministryRole,
        // Leaving the church blank records a CONFERENCE-WIDE ordination, which is
        // the normal case for somebody ordained to the denomination rather than to
        // one local church.
        churchId: result.conferenceWide ? null : id,
        credentialNumber: result.credentialNumber,
        issuedOn: result.issuedOn,
        expiresOn: result.expiresOn,
        issuingAuthority: result.issuingAuthority,
        notes: result.notes,
      ),
      '${result.credentialType.label} ${result.ministryRole.label} recorded',
    );
  }

  Future<void> _revoke(MinisterialCredential credential) async {
    final status = await showDialog<CredentialStatus>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Withdraw ${credential.displayName}\'s credential?'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text(
              'Nothing is deleted. The credential keeps its number and its whole '
              'history, a reason is required, and the holder stays on the church\'s '
              'officers board until that church ends the appointment itself.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          for (final s in const [
            CredentialStatus.revoked,
            CredentialStatus.suspended,
            CredentialStatus.expired,
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, s),
              child: Text('Mark as ${s.label.toLowerCase()}'),
            ),
        ],
      ),
    );
    if (status == null || !mounted) return;

    final reason = await _askReason(
      title: 'Reason (required)',
      hint: status == CredentialStatus.suspended
          ? 'e.g. under review by the conference'
          : 'e.g. ordination withdrawn by the conference on 12/03/2026',
    );
    if (reason == null) return;

    await _run(
      () => _service.revokeCredential(
        credentialId: credential.id,
        status: status,
        reason: reason,
      ),
      'Credential marked ${status.label.toLowerCase()}',
    );
  }

  Future<void> _reinstate(MinisterialCredential credential) async {
    final reason = await _askReason(
      title: 'Why is the suspension being lifted?',
      hint: 'e.g. conference review concluded, good standing restored',
    );
    if (reason == null) return;
    await _run(
      () => _service.reinstateCredential(
        credentialId: credential.id,
        reason: reason,
      ),
      'Credential reinstated',
    );
  }

  Future<void> _renew(MinisterialCredential credential) async {
    final until = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      helpText: 'Valid until',
    );
    if (until == null) return;
    await _run(
      () => _service.renewCredential(
        credentialId: credential.id,
        expiresOn: until,
      ),
      'Credential renewed',
    );
  }

  Future<String?> _askReason({
    required String title,
    required String hint,
  }) async {
    final ctrl = TextEditingController();
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(hint, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                maxLines: 3,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  errorText: error,
                ),
                onChanged: (_) {
                  if (error != null) setLocal(() => error = null);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
            FilledButton(
              onPressed: () {
                if (ctrl.text.trim().length < 3) {
                  setLocal(() => error = 'Please write the reason.');
                  return;
                }
                Navigator.pop(ctx, ctrl.text.trim());
              },
              child: const Text('SAVE'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final churchId = _churchId;
    final credentialsAsync = ref.watch(churchCredentialsProvider(churchId));
    final canIssue = _canIssue;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Ordination'),
        actions: [
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(LucideIcons.rotateCcw),
            onPressed: _busy ? null : _reload,
          ),
        ],
      ),
      floatingActionButton: canIssue
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : _grant,
              backgroundColor: AppTheme.platformPrimary,
              foregroundColor: AppTheme.onPlatformPrimary,
              icon: const Icon(LucideIcons.award),
              label: const Text(
                'RECORD CREDENTIAL',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
              ),
            )
          : null,
      body: credentialsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _errorView(theme, _friendly(e)),
        data: (credentials) => RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
            children: [
              _authorityBanner(theme, canIssue),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _banner(LucideIcons.alertTriangle, _error!, Colors.red),
              ],
              const SizedBox(height: 20),
              if (credentials.isEmpty)
                _emptyState(theme, canIssue)
              else ...[
                ..._credentials(theme, credentials, canIssue),
                const SizedBox(height: 22),
                _historySection(theme, churchId),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// States the rule out loud, for the person who does have the authority and for
  /// the person who is about to wonder why they cannot do it.
  Widget _authorityBanner(ThemeData theme, bool canIssue) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: canIssue
              ? [
                  AppConstants.sunflowerYellow,
                  AppConstants.sunflowerYellow.withValues(alpha: 0.7)
                ]
              : [
                  theme.colorScheme.surfaceContainerHighest,
                  theme.colorScheme.surfaceContainerHighest,
                ],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            canIssue ? LucideIcons.shieldCheck : LucideIcons.lock,
            size: 20,
            color: canIssue
                ? AppConstants.primaryDark
                : theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  canIssue
                      ? 'CONFERRED BY THE CONFERENCE'
                      : 'CONFERRED BY THE CONFERENCE, NOT THE CHURCH',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                    color: canIssue
                        ? AppConstants.primaryDark
                        : theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  canIssue
                      ? 'You may ordain, license, suspend and revoke. Every change '
                          'is kept with its reason, and nothing is ever deleted.'
                      : 'Ordination is conferred by a bishop or conference officer, '
                          'so this view is read-only. A church can APPOINT a deacon '
                          '— that is on the Church Officers register — but it cannot '
                          'ordain one.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: canIssue
                        ? AppConstants.primaryDark.withValues(alpha: 0.85)
                        : theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _credentials(
    ThemeData theme,
    List<MinisterialCredential> credentials,
    bool canIssue,
  ) {
    final valid = credentials.where((c) => c.isActive).toList();
    final withdrawn = credentials.where((c) => !c.isActive).toList();

    final widgets = <Widget>[];

    widgets.add(_header(theme, LucideIcons.badgeCheck, 'VALID', '${valid.length}'));
    widgets.add(const SizedBox(height: 6));
    if (valid.isEmpty) {
      widgets.add(_muted(theme, 'Nobody in this church holds a live credential.'));
    } else {
      widgets.addAll(valid.map((c) => _credentialTile(theme, c, canIssue)));
    }

    if (withdrawn.isNotEmpty) {
      widgets.add(const SizedBox(height: 20));
      widgets.add(_header(
          theme, LucideIcons.circleSlash, 'WITHDRAWN', '${withdrawn.length}'));
      widgets.add(const SizedBox(height: 6));
      widgets.addAll(withdrawn.map((c) => _credentialTile(theme, c, canIssue)));
    }

    return widgets;
  }

  Widget _credentialTile(
      ThemeData theme, MinisterialCredential c, bool canIssue) {
    final lapsed = c.hasLapsed;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: !c.isActive
              ? theme.colorScheme.outlineVariant.withValues(alpha: 0.4)
              : lapsed
                  ? Colors.orange.withValues(alpha: 0.6)
                  : AppConstants.sunflowerYellow,
          width: c.isActive ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (c.isActive
                          ? AppConstants.sunflowerYellow
                          : theme.colorScheme.onSurface)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_iconForType(c.credentialType),
                    size: 20,
                    color: c.isActive
                        ? AppConstants.primaryDark
                        : theme.colorScheme.onSurface.withValues(alpha: 0.6)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: c.isActive
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(c.certificateTitle,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.7),
                        )),
                  ],
                ),
              ),
              _statusChip(theme, c, lapsed),
            ],
          ),
          const SizedBox(height: 10),
          _detail(theme, LucideIcons.hash, c.credentialNumber ?? 'number pending'),
          _detail(theme, LucideIcons.landmark,
              c.isConferenceWide ? 'Conference-wide' : c.churchName ?? 'This church'),
          _detail(theme, LucideIcons.scrollText, c.issuingAuthority),
          _detail(
            theme,
            LucideIcons.calendar,
            'Issued ${_fmt(c.issuedOn)}'
            '${c.expiresOn == null ? ' · no expiry' : ' · expires ${_fmt(c.expiresOn)}'}',
          ),
          if (!c.isActive && (c.revocationReason ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Reason recorded: ${c.revocationReason}',
                  style: TextStyle(
                      fontSize: 11.5, color: theme.colorScheme.error, height: 1.3),
                ),
              ),
            ),
          if (canIssue) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (c.isActive)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    onPressed: _busy ? null : () => _renew(c),
                    icon: const Icon(LucideIcons.calendarCheck, size: 16),
                    label: const Text('RENEW'),
                  ),
                if (c.isActive)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    onPressed: _busy ? null : () => _revoke(c),
                    icon: const Icon(LucideIcons.ban, size: 16),
                    label: const Text('WITHDRAW'),
                  ),
                if (c.status == CredentialStatus.suspended)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    onPressed: _busy ? null : () => _reinstate(c),
                    icon: const Icon(LucideIcons.refreshCw, size: 16),
                    label: const Text('REINSTATE'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusChip(
      ThemeData theme, MinisterialCredential c, bool lapsed) {
    // A credential whose date has simply passed still reads as VALID here — expiry
    // is derived, never written by a trigger — so the lapse is surfaced separately
    // rather than by quietly rewriting the stored status.
    var label = c.status.label.toUpperCase();
    var color = switch (c.status) {
      CredentialStatus.active => lapsed ? Colors.orange : Colors.green,
      CredentialStatus.suspended => Colors.amber,
      CredentialStatus.revoked => theme.colorScheme.error,
      CredentialStatus.expired => Colors.grey,
    };
    if (c.status == CredentialStatus.active && lapsed) {
      label = 'LAPSED';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w900, color: color)),
    );
  }

  Widget _detail(ThemeData theme, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 13, color: theme.colorScheme.onSurface.withValues(alpha: 0.45)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The append-only trail, so a revocation can always be explained years later.
  Widget _historySection(ThemeData theme, String churchId) {
    final events = ref.watch(churchCredentialEventsProvider(churchId)).value ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(theme, LucideIcons.history, 'FULL HISTORY', '${events.length}'),
        const SizedBox(height: 6),
        if (events.isEmpty)
          _muted(theme, 'Every grant, renewal, suspension and revocation is kept '
              'here permanently. Nothing is ever deleted.')
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                for (final e in events.take(25)) _eventRow(theme, e),
              ],
            ),
          ),
      ],
    );
  }

  Widget _eventRow(ThemeData theme, CredentialEvent e) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 4),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _colorForEvent(e.eventType),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${e.eventType.label} · ${_fmtDate(e.createdAt)}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
                if ((e.reason ?? '').isNotEmpty)
                  Text(e.reason!,
                      style: TextStyle(
                          fontSize: 11.5,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.7))),
                if ((e.actorName ?? '').isNotEmpty)
                  Text('by ${e.actorName}',
                      style: TextStyle(
                          fontSize: 10.5,
                          color:
                              theme.colorScheme.onSurface.withValues(alpha: 0.5))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _colorForEvent(CredentialEventType type) => switch (type) {
        CredentialEventType.granted => Colors.green,
        CredentialEventType.renewed => Colors.blue,
        CredentialEventType.suspended => Colors.amber,
        CredentialEventType.revoked => Colors.red,
        CredentialEventType.expired => Colors.grey,
        CredentialEventType.reinstated => AppConstants.accentGreen,
      };

  // ── Chrome ──────────────────────────────────────────────────────────────
  Widget _header(ThemeData theme, IconData icon, String title, String count) {
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ),
        Text(
          count,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
          ),
        ),
      ],
    );
  }

  Widget _muted(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(text,
          style: TextStyle(
              fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.55))),
    );
  }

  Widget _emptyState(ThemeData theme, bool canIssue) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.award,
                  size: 20,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
              const SizedBox(width: 8),
              const Text('NO CREDENTIALS RECORDED',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'A credential answers one question: is this person actually ordained, '
            'or did a church simply give them the title? A certificate that any '
            'pastor could issue would be worth nothing, so this register is '
            'written only by a bishop or conference officer — and a credential can '
            'be withdrawn later without the record ever being erased.',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            canIssue
                ? 'Tap RECORD CREDENTIAL to enter the first one.'
                : 'Only a bishop, apostle, prophet or conference officer can record '
                    'a credential. A local appointment is on the Church Officers '
                    'register instead.',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _banner(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 12, color: color, height: 1.3)),
          ),
        ],
      ),
    );
  }

  Widget _errorView(ThemeData theme, String message) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 70),
        Icon(LucideIcons.alertTriangle,
            size: 46, color: theme.colorScheme.error.withValues(alpha: 0.6)),
        const SizedBox(height: 12),
        Center(
          child: Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13)),
        ),
        const SizedBox(height: 14),
        Center(child: FilledButton(onPressed: _reload, child: const Text('RETRY'))),
      ],
    );
  }

  String _friendly(Object e) {
    final s = e.toString();
    if (s.contains('42501') || s.contains('permission denied')) {
      return 'You do not have permission to view this register.';
    }
    return 'Could not load the credential register.';
  }

  String _fmt(DateTime? d) {
    if (d == null) return '—';
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$day/$m/${d.year}';
  }

  String _fmtDate(DateTime d) => _fmt(d);

  IconData _iconForType(CredentialType t) => switch (t) {
        CredentialType.ordained => LucideIcons.award,
        CredentialType.licensed => LucideIcons.scrollText,
        CredentialType.accredited => LucideIcons.graduationCap,
      };
}

// ===========================================================================
// Grant sheet
// ===========================================================================

class _GrantResult {
  final String holderUserId;
  final CredentialType credentialType;
  final MinistryRole ministryRole;
  final bool conferenceWide;
  final String? credentialNumber;
  final DateTime? issuedOn;
  final DateTime? expiresOn;
  final String? issuingAuthority;
  final String? notes;

  const _GrantResult({
    required this.holderUserId,
    required this.credentialType,
    required this.ministryRole,
    required this.conferenceWide,
    this.credentialNumber,
    this.issuedOn,
    this.expiresOn,
    this.issuingAuthority,
    this.notes,
  });
}

class _GrantCredentialSheet extends StatefulWidget {
  final List<Map<String, dynamic>> members;

  const _GrantCredentialSheet({required this.members});

  @override
  State<_GrantCredentialSheet> createState() => _GrantCredentialSheetState();
}

class _GrantCredentialSheetState extends State<_GrantCredentialSheet> {
  final _searchCtrl = TextEditingController();
  final _numberCtrl = TextEditingController();
  final _authorityCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  Map<String, dynamic>? _member;
  CredentialType _type = CredentialType.ordained;
  late MinistryRole _role = MinistryRole.deacon;
  bool _conferenceWide = false;
  bool _hasExpiry = false;
  DateTime _expires = DateTime.now().add(const Duration(days: 365));
  String? _error;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _numberCtrl.dispose();
    _authorityCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return widget.members;
    return widget.members
        .where((m) =>
            (m['full_name']?.toString().toLowerCase().contains(q) ?? false) ||
            (m['phone_number']?.toString().contains(q) ?? false))
        .toList();
  }

  Future<void> _pickExpiry() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expires,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null) setState(() => _expires = picked);
  }

  void _save() {
    if (_member == null) {
      setState(() => _error = 'Choose who the credential is for.');
      return;
    }
    final number = _numberCtrl.text.trim();
    if (number.isNotEmpty && number.length < 4) {
      setState(() => _error = 'A credential number that short looks like a typo.');
      return;
    }
    Navigator.of(context).pop(_GrantResult(
      holderUserId: _member!['id'].toString(),
      credentialType: _type,
      ministryRole: _role,
      conferenceWide: _conferenceWide,
      credentialNumber: number.isEmpty ? null : number,
      issuedOn: DateTime.now(),
      expiresOn: _hasExpiry ? _expires : null,
      issuingAuthority: _authorityCtrl.text.trim().isEmpty
          ? null
          : _authorityCtrl.text.trim(),
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Text('Record a credential',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              'Conferred by the conference. Leave the number blank and one is '
              'minted for you.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),

            Text('HOLDER',
                style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.2, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            if (_member != null)
              InputDecorator(
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(LucideIcons.user),
                  suffixIcon: IconButton(
                    icon: const Icon(LucideIcons.x),
                    onPressed: () => setState(() => _member = null),
                  ),
                ),
                child: Text(_member!['full_name']?.toString() ?? ''),
              )
            else ...[
              TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Search member',
                  prefixIcon: Icon(LucideIcons.search),
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 190),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _filtered.length,
                  itemBuilder: (_, i) {
                    final m = _filtered[i];
                    return ListTile(
                      dense: true,
                      title: Text(m['full_name']?.toString() ?? 'Unnamed'),
                      subtitle: m['role'] == null
                          ? null
                          : Text(m['role'].toString()),
                      onTap: () => setState(() => _member = m),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 18),

            Text('GRADE',
                style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.2, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            SegmentedButton<CredentialType>(
              segments: const [
                ButtonSegment(
                    value: CredentialType.ordained, label: Text('Ordained')),
                ButtonSegment(
                    value: CredentialType.licensed, label: Text('Licensed')),
                ButtonSegment(
                    value: CredentialType.accredited, label: Text('Accredited')),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() {
                _type = s.first;
                // The offices available depend on the grade: a deacon is ordained,
                // a local preacher is licensed.
                _role = MinistryRole.forType(_type).first;
              }),
            ),
            const SizedBox(height: 14),

            Text('OFFICE',
                style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.2, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in MinistryRole.forType(_type))
                  ChoiceChip(
                    label: Text(r.label),
                    selected: _role == r,
                    onSelected: (_) => setState(() => _role = r),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _numberCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Credential number (optional)',
                hintText: 'Leave blank to auto-generate',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _authorityCtrl,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Issuing authority (optional)',
                hintText: 'e.g. Zambia Conference of the UPC',
                helperText: 'Defaults to your organisation or church name',
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _conferenceWide,
              onChanged: (v) => setState(() => _conferenceWide = v),
              title: const Text('Conference-wide credential',
                  style: TextStyle(fontSize: 13)),
              subtitle: Text(
                'Records the ordination to the DENOMINATION rather than to this one '
                'church. Use it when the person has never been placed in a church, or '
                'when the ordination belongs to the conference.',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _hasExpiry,
              onChanged: (v) => setState(() => _hasExpiry = v),
              title: const Text('Set an expiry', style: TextStyle(fontSize: 13)),
              subtitle: Text(
                'Off by default: ordination is normally for life. Turn it on only if '
                'your conference renews it.',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
            if (_hasExpiry)
              OutlinedButton.icon(
                onPressed: _pickExpiry,
                icon: const Icon(LucideIcons.calendar, size: 16),
                label: Text('Valid until ${_short(_expires)}'),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Notes (optional)',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style:
                      TextStyle(color: theme.colorScheme.error, fontSize: 13)),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                backgroundColor: AppConstants.sunflowerYellow,
                foregroundColor: AppConstants.primaryDark,
              ),
              icon: const Icon(LucideIcons.award),
              label: const Text('RECORD CREDENTIAL',
                  style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ],
        ),
      ),
    );
  }

  String _short(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$day/$m/${d.year}';
  }
}