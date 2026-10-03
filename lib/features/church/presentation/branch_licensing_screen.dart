import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:church_on_app/core/config/app_constants.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/theme/app_theme.dart';
import 'package:church_on_app/features/church/data/church_governance_service.dart';

/// Branch licensing / certification.
///
/// A "branch" is a church linked to an organisation (`churches.organization_id`).
/// The organisation licenses it. Until it does, the branch is RUNNING but not
/// CERTIFIED by its parent — which is exactly what a conference is asked about when
/// it issues a letter of good standing, and a question no church can currently
/// answer from inside the app.
///
/// TWO SEPARATE AUTHORITIES, TWO SEPARATE BUTTONS
///   * the BRANCH applies  (leadership of this church)
///   * the ORGANISATION decides (its bishop, secretary or treasurer)
/// Deliberately stricter than the generic org gate: a branch pastor cannot licence
/// their own branch, even though they belong to the same organisation.
class BranchLicensingScreen extends ConsumerStatefulWidget {
  const BranchLicensingScreen({super.key, this.churchId});

  /// Optional explicit church/tenant id. Falls back to the signed-in user's church.
  final String? churchId;

  @override
  ConsumerState<BranchLicensingScreen> createState() =>
      _BranchLicensingScreenState();
}

class _BranchLicensingScreenState extends ConsumerState<BranchLicensingScreen> {
  /// The default checklist a Zambian conference actually assesses. Kept on the
  /// client so the applicant is not staring at an empty form; the SERVER blocks a
  /// grant while any item is false, which is what makes it a control.
  static const _defaultRequirements = <String, String>{
    'constitution_on_file': 'Written constitution on file',
    'pastor_ordained': 'Pastor holds a valid credential',
    'membership_minimum_met': 'Membership meets the conference minimum',
    'bank_account_open': 'Bank account in the church\'s name',
    'previous_audit_closed': 'Previous year\'s accounts closed',
  };

  bool _busy = false;
  String? _error;

  ChurchGovernanceService get _service =>
      ref.read(churchGovernanceServiceProvider);

  String get _churchId {
    final explicit = (widget.churchId ?? '').trim();
    if (explicit.isNotEmpty) return explicit;
    return ref.read(currentTenantProvider)?.id ?? '';
  }

  /// Is this church linked to a parent organisation at all? Without one there is
  /// nobody who could ever grant a licence.
  bool _hasOrganization(String tenantOrganizationId) =>
      tenantOrganizationId.isNotEmpty;

  bool _canApply(String role) => GovernanceRoles.canApplyForLicense(role);

  bool _canDecide(String role, {required bool hasOrganization}) =>
      GovernanceRoles.canLicenseBranches(role, hasOrganization: hasOrganization);

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() => _error = null);
    try {
      // `ref.invalidate` (not `ref.refresh(x.future)`): in Riverpod 3 the
      // latter returns void because it only signals a rebuild, so awaiting it
      // discards the result and trips `unused_result`. Errors surface through
      // the provider's AsyncValue and are rendered by the normal builders.
      ref.invalidate(currentBranchLicenseProvider);
      return;
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

  Future<void> _apply() async {
    final id = _churchId;
    if (id.isEmpty) {
      setState(() => _error = 'Select a church first.');
      return;
    }

    final answers = await showModalBottomSheet<Map<String, bool>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RequirementsSheet(items: _defaultRequirements),
    );
    if (answers == null) return;

    await _run(
      () => _service.applyForLicense(churchId: id, requirements: answers),
      'Application submitted to your organisation',
    );
  }

  Future<void> _review(BranchLicense license) async {
    await _run(
      () => _service.reviewLicense(license.id),
      'Marked as received — now awaiting a decision',
    );
  }

  Future<void> _decide(BranchLicense license, {required bool grant}) async {
    String? notes;
    DateTime? expires;

    if (grant) {
      // The server refuses a grant while any item is false and names the
      // outstanding ones, so it is worth showing them first.
      final unmet = license.unmetRequirements;
      if (unmet.isNotEmpty) {
        setState(() => _error =
            'The branch has not met these requirements: ${unmet.join(', ')}');
        return;
      }
      final until = await showDatePicker(
        context: context,
        initialDate: DateTime.now().add(const Duration(days: 365)),
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 3650)),
        helpText: 'Licence valid until (or leave the default window)',
      );
      if (until != null) expires = until;
    } else {
      final ctrl = TextEditingController();
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Refuse this licence?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'The branch goes back to "Not licensed" with your reason attached. '
                'They can apply again once it is addressed.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                maxLines: 3,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Reason (required)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('CANCEL')),
            FilledButton(
              onPressed: () {
                if (ctrl.text.trim().length < 3) return;
                Navigator.pop(ctx, ctrl.text.trim());
              },
              child: const Text('REFUSE'),
            ),
          ],
        ),
      );
      ctrl.dispose();
      if (result == null) return;
      notes = result;
    }

    await _run(
      () => _service.decideLicense(
        licenseId: license.id,
        grant: grant,
        notes: notes,
        expiresOn: expires,
      ),
      grant ? 'Branch licensed' : 'Application refused',
    );
  }

  Future<void> _renew(BranchLicense license) async {
    await _run(
      () => _service.renewLicense(licenseId: license.id),
      'Licence renewed — same licence number',
    );
  }

  Future<void> _setStatus(
      BranchLicense license, BranchLicenseStatus status) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${status.label} this licence?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              status == BranchLicenseStatus.revoked
                  ? 'The licence number is kept so the record stays traceable, and '
                      'the reason is kept with it.'
                  : status == BranchLicenseStatus.suspended
                      ? 'A suspension is a temporary withdrawal. The term already '
                          'served is not lost — use Renew for a new term.'
                      : 'The suspension is lifted. The original term dates stand.',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Reason (required)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          FilledButton(
            onPressed: () {
              if (ctrl.text.trim().length < 3) return;
              Navigator.pop(ctx, ctrl.text.trim());
            },
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null) return;

    await _run(
      () => _service.setLicenseStatus(
        licenseId: license.id,
        status: status,
        reason: result,
      ),
      'Licence marked ${status.label.toLowerCase()}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final licenseAsync = ref.watch(currentBranchLicenseProvider);
    final tenant = ref.watch(currentTenantProvider);
    final role = ref.watch(profileProvider).value?.role ?? '';
    final linked = _hasOrganization(tenant?.organizationId ?? '');
    final canApply = _canApply(role);
    final canDecide = _canDecide(role, hasOrganization: linked);
    final license = licenseAsync.value;

    // Hide the FAB while an application is already in flight — the server refuses a
    // second one anyway, and a button that can only fail is worse than no button.
    final canStartApplication =
        canApply && !(license?.status.isOpen ?? false);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Branch Licence'),
        actions: [
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(LucideIcons.rotateCcw),
            onPressed: _busy ? null : _reload,
          ),
        ],
      ),
      floatingActionButton: canStartApplication
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : _apply,
              backgroundColor: AppTheme.platformPrimary,
              foregroundColor: AppTheme.onPlatformPrimary,
              icon: const Icon(LucideIcons.send),
              label: const Text(
                'APPLY FOR LICENCE',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
              ),
            )
          : null,
      body: licenseAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _errorView(theme, _friendly(e)),
        data: (lic) => RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
            children: [
              if (lic == null)
                _emptyState(theme, canApply, linked)
              else ...[
                _statusCard(theme, lic, canDecide),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  _banner(LucideIcons.alertTriangle, _error!, Colors.red),
                ],
                const SizedBox(height: 16),
                if (lic.requirements.isNotEmpty) _requirementsCard(theme, lic),
                if ((lic.decisionNotes ?? '').isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _notesCard(theme, lic.decisionNotes!),
                ],
                const SizedBox(height: 16),
                _authorityNote(theme, canApply, canDecide),
              ],
              if (_error != null && lic == null) ...[
                const SizedBox(height: 12),
                _banner(LucideIcons.alertTriangle, _error!, Colors.red),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The one thing a church leader opens this screen to find out.
  Widget _statusCard(ThemeData theme, BranchLicense lic, bool canDecide) {
    final lapsed = lic.hasLapsed;
    final renewalDue = lic.renewalDue;
    final good = lic.isLicensed && !lapsed;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: good
              ? [
                  AppConstants.sunflowerYellow,
                  AppConstants.sunflowerYellow.withValues(alpha: 0.7)
                ]
              : [
                  theme.colorScheme.error.withValues(alpha: 0.12),
                  theme.colorScheme.errorContainer.withValues(alpha: 0.5)
                ],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(good ? LucideIcons.badgeCheck : LucideIcons.shieldAlert,
                  size: 18,
                  color: good
                      ? AppConstants.primaryDark
                      : theme.colorScheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  good
                      ? 'LICENSED BY ${(lic.organizationName ?? 'THE ORGANISATION').toUpperCase()}'
                      : lic.status.label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                    color: good
                        ? AppConstants.primaryDark
                        : theme.colorScheme.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (lic.licenseNumber != null)
            Text(
              lic.licenseNumber!,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AppConstants.primaryDark,
              ),
            )
          else if (lic.applicationReference != null)
            Text(
              'Application ${lic.applicationReference}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.error,
              ),
            ),
          const SizedBox(height: 8),
          Text(
            good
                ? lapsed
                    ? 'This licence has lapsed. Renew it to stay certified.'
                    : 'Valid until ${_fmt(lic.expiresAt)}.'
                        '${renewalDue ? ' Renewal is due ${_fmt(lic.renewalDueAt)}.' : ''}'
                : lic.status == BranchLicenseStatus.revoked
                    ? 'The licence was withdrawn. The record and its number are kept.'
                    : lic.status == BranchLicenseStatus.suspended
                        ? 'The licence is suspended: ${lic.suspendedReason ?? 'no reason recorded'}'
                        : lic.status == BranchLicenseStatus.underReview
                            ? 'Your organisation has received this application and is reviewing it.'
                            : lic.status == BranchLicenseStatus.applicationSubmitted
                                ? 'Submitted ${_fmt(lic.submittedAt)}. Waiting for your organisation to receive it.'
                                : 'This branch is not certified by its parent organisation.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: good
                      ? AppConstants.primaryDark.withValues(alpha: 0.85)
                      : theme.colorScheme.onErrorContainer.withValues(alpha: 0.9),
                ),
              ),
          if (canDecide) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _actions(theme, lic),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _actions(ThemeData theme, BranchLicense lic) {
    if (lic.status.isOpen) {
      return [
        if (lic.status == BranchLicenseStatus.applicationSubmitted)
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppConstants.primaryDark,
              foregroundColor: Colors.white,
            ),
            onPressed: _busy ? null : () => _review(lic),
            icon: const Icon(LucideIcons.fileCheck, size: 16),
            label: const Text('MARK AS RECEIVED'),
          ),
        if (lic.status == BranchLicenseStatus.underReview) ...[
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppConstants.primaryDark,
              foregroundColor: Colors.white,
            ),
            onPressed: _busy ? null : () => _decide(lic, grant: true),
            icon: const Icon(LucideIcons.badgeCheck, size: 16),
            label: const Text('GRANT LICENCE'),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _decide(lic, grant: false),
            icon: const Icon(LucideIcons.x, size: 16),
            label: const Text('REFUSE'),
          ),
        ],
      ];
    }

    if (lic.isLicensed || lic.hasLapsed) {
      return [
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppConstants.primaryDark,
            foregroundColor: Colors.white,
          ),
          onPressed: _busy ? null : () => _renew(lic),
          icon: const Icon(LucideIcons.refreshCw, size: 16),
          label: const Text('RENEW'),
        ),
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () => _setStatus(lic, BranchLicenseStatus.suspended),
          icon: const Icon(LucideIcons.pause, size: 16),
          label: const Text('SUSPEND'),
        ),
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () => _setStatus(lic, BranchLicenseStatus.revoked),
          icon: const Icon(LucideIcons.ban, size: 16),
          label: const Text('REVOKE'),
        ),
      ];
    }

    if (lic.status == BranchLicenseStatus.suspended) {
      return [
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppConstants.primaryDark,
            foregroundColor: Colors.white,
          ),
          onPressed: _busy
              ? null
              : () => _setStatus(lic, BranchLicenseStatus.licensed),
          icon: const Icon(LucideIcons.refreshCw, size: 16),
          label: const Text('REINSTATE'),
        ),
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () => _setStatus(lic, BranchLicenseStatus.revoked),
          icon: const Icon(LucideIcons.ban, size: 16),
          label: const Text('REVOKE'),
        ),
      ];
    }

    return const [];
  }

  Widget _requirementsCard(ThemeData theme, BranchLicense lic) {
    final unmet = lic.unmetRequirements;
    final ok = unmet.isEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: ok
              ? AppConstants.accentGreen.withValues(alpha: 0.5)
              : Colors.amber.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(ok ? LucideIcons.listChecks : LucideIcons.hourglass,
                  size: 18,
                  color: ok
                      ? AppConstants.accentGreen
                      : Colors.amber.shade800),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ok ? 'ALL REQUIREMENTS MET' : 'REQUIREMENTS OUTSTANDING',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final e in lic.requirements.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(
                    e.value ? LucideIcons.check : LucideIcons.x,
                    size: 14,
                    color: e.value
                        ? AppConstants.accentGreen
                        : theme.colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _labelFor(e.key),
                      style: TextStyle(
                        fontSize: 12,
                        color: e.value
                            ? theme.colorScheme.onSurface.withValues(alpha: 0.7)
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Text(
            ok
                ? 'A licence can be issued.'
                : 'The organisation cannot issue a licence while any item is '
                    'outstanding. This is enforced on the server, not just here.',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  String _labelFor(String key) =>
      _defaultRequirements[key] ?? key.replaceAll('_', ' ');

  Widget _notesCard(ThemeData theme, String notes) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.fileText,
                  size: 16,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
              const SizedBox(width: 8),
              const Text('DECISION NOTES',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 8),
          Text(notes,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
              )),
        ],
      ),
    );
  }

  Widget _authorityNote(ThemeData theme, bool canApply, bool canDecide) {
    final String text;
    if (canDecide) {
      text = 'You can receive, decide, renew, suspend and revoke this branch\'s '
          'licence as an officer of the parent organisation.';
    } else if (canApply) {
      text = 'Your church applies and your organisation decides. A branch cannot '
          'licence itself — only the bishop, secretary or treasurer of the parent '
          'organisation can.';
    } else {
      text = 'A branch applies for a licence and its parent organisation decides. '
          'This view is read-only.';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppConstants.surfaceWarm.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(LucideIcons.info,
              size: 16, color: AppConstants.primaryDark),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.35,
                color: AppConstants.primaryDark.withValues(alpha: 0.85),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(ThemeData theme, bool canApply, bool linked) {
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
              Icon(LucideIcons.building2,
                  size: 20,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
              const SizedBox(width: 8),
              const Text('NO LICENCE ON RECORD',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'A licence is how a parent organisation certifies that one of its '
            'branches is properly constituted, led by an ordained pastor and '
            'accountable to the conference. It is what a conference is asked about '
            'before it issues a letter of good standing — and, until now, something '
            'only a paper file could answer.',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 12),
          if (!linked)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(LucideIcons.alertTriangle, size: 16, color: Colors.amber.shade800),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This church is not linked to an organisation, so there is '
                      'nobody who could licence it. A Church On App administrator can '
                      'attach it to its parent first.',
                      style: TextStyle(
                          fontSize: 12, color: Colors.amber.shade900, height: 1.3),
                    ),
                  ),
                ],
              ),
            )
          else
            Text(
              canApply
                  ? 'Tap APPLY FOR LICENCE to submit the requirements checklist to '
                      'your organisation.'
                  : 'Your church leadership can apply. You will see the outcome here.',
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
    return 'Could not load the branch licence.';
  }

  String _fmt(DateTime? d) {
    if (d == null) return '—';
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$day/$m/${d.year}';
  }
}

// ===========================================================================
// Requirements checklist
// ===========================================================================

class _RequirementsSheet extends StatefulWidget {
  final Map<String, String> items;
  const _RequirementsSheet({required this.items});

  @override
  State<_RequirementsSheet> createState() => _RequirementsSheetState();
}

class _RequirementsSheetState extends State<_RequirementsSheet> {
  /// Anything NOT ticked counts as outstanding — the conservative default, so an
  /// application cannot quietly skip a requirement by leaving it grey.
  final Map<String, bool> _answers = {};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outstanding =
        _answers.entries.where((e) => !e.value).map((e) => e.key).toList();

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Text('Licensing requirements',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              'Tick what this branch has in place. Your organisation decides on the '
              'application, and it cannot issue a licence while any line is '
              'outstanding.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            for (final e in widget.items.entries)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _answers[e.key] ?? false,
                onChanged: (v) => setState(() => _answers[e.key] = v ?? false),
                title: Text(e.value, style: const TextStyle(fontSize: 13)),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            if (outstanding.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(LucideIcons.alertTriangle,
                        size: 16, color: Colors.amber.shade800),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${outstanding.length} requirement'
                        '${outstanding.length == 1 ? '' : 's'} still outstanding. '
                        'You can still submit — the application just cannot be '
                        'approved until they are met.',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.amber.shade900,
                            height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(
                Map<String, bool>.from(_answers),
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                backgroundColor: AppConstants.sunflowerYellow,
                foregroundColor: AppConstants.primaryDark,
              ),
              icon: const Icon(LucideIcons.send),
              label: const Text('SUBMIT APPLICATION',
                  style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ],
        ),
      ),
    );
  }
}