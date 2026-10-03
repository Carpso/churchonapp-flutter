import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:church_on_app/core/config/app_constants.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/theme/app_theme.dart';
import 'package:church_on_app/features/finance/data/church_payment_accounts_service.dart';

/// Where a church's donations are actually PAID TO.
///
/// Until a church records at least one number here, the Give tab cannot collect
/// anything: `giving_screen.dart` resolves the recipient from the `churches`
/// columns (`treasurerPhone ?? contactPhone ?? pastorPhone`) and shows "No
/// payment recipient configured for this church" when they are all empty. 21 of
/// 32 churches were in exactly that state.
///
/// Leadership adds the numbers; members see them read-only (they are told who
/// receives the money, which is the point of publishing them).
///
/// Saving the primary account mirrors it back into the matching `churches`
/// column via `ChurchPaymentAccountsService.syncPrimaryToChurchesRow` and via the
/// `sync_church_payment_account_to_churches` DB trigger, so the existing giving
/// chain starts working with no change to `giving_screen.dart`.
class ChurchPaymentAccountsScreen extends ConsumerStatefulWidget {
  const ChurchPaymentAccountsScreen({super.key, this.churchId});

  /// Optional explicit church/tenant id. Falls back to the signed-in user's
  /// current church.
  final String? churchId;

  @override
  ConsumerState<ChurchPaymentAccountsScreen> createState() =>
      _ChurchPaymentAccountsScreenState();
}

class _ChurchPaymentAccountsScreenState
    extends ConsumerState<ChurchPaymentAccountsScreen> {
  /// Mirrors `can_manage_church_payment_accounts` in the migration. The server
  /// enforces it too — this only decides whether to show the controls.
  static const _staffRoles = {
    'superadmin',
    'super_admin',
    'coa_employee',
    'employee',
  };

  static const _leaderRoles = {
    'pastor',
    'bishop',
    'apostle',
    'prophet',
    'admin',
    'general_secretary',
    'general_treasurer',
    'treasurer',
    'leader',
  };

  bool _busy = false;
  String? _error;

  ChurchPaymentAccountsService get _service =>
      ref.read(churchPaymentAccountsServiceProvider);

  /// The church this screen manages. A router caller can pin it; otherwise it is
  /// the user's current church.
  String? get _churchId {
    final explicit = (widget.churchId ?? '').trim();
    if (explicit.isNotEmpty) return explicit;
    return ref.read(currentTenantProvider)?.id;
  }

  /// Mirrors `can_manage_church_payment_accounts` in the migration. The server
  /// enforces it too — this only decides whether to show the controls.
  static bool canManageRole(String role) =>
      _staffRoles.contains(role) || _leaderRoles.contains(role);
Future<void> _reload() async {
    if (!mounted) return;
    setState(() => _error = null);
    try {
      // `ref.invalidate` (not `ref.refresh(x.future)`): in Riverpod 3 the
      // latter returns void because it only signals a rebuild, so awaiting it
      // discards the result and trips `unused_result`. `invalidate` is the
      // lint-clean way to force a rebuild; errors then surface through the
      // provider's AsyncValue and are rendered by the normal builders.
      ref.invalidate(currentChurchPaymentAccountsProvider);
      _invalidateReaders();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  /// Drop every cached read of the register so the Give tab's recipient chain
  /// picks up a change without an app restart.
  void _invalidateReaders() {
    ref.invalidate(currentChurchPaymentAccountsProvider);
    ref.invalidate(churchGivingRecipientPhoneProvider);
    final id = _churchId;
    if (id != null && id.isNotEmpty) {
      ref.invalidate(churchPaymentAccountsProvider(id));
    }
    // `currentTenantProvider.reload()` — NOT `ref.invalidate(...)`. Invalidating a
    // NotifierProvider resets its state to null, and the router's redirect then
    // bounces the user to /select-church. `reload()` re-reads the row in place
    // while the old tenant stays visible, which is how the mirrored
    // `churches.treasurer_phone` reaches giving_screen.dart.
    ref.read(currentTenantProvider.notifier).reload();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      _invalidateReaders();
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openForm({ChurchPaymentAccount? existing}) async {
    final churchId = _churchId;
    if (churchId == null || churchId.isEmpty) {
      _snack('Select a church first.');
      return;
    }

    final result = await showModalBottomSheet<_AccountFormResult>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _AccountFormSheet(existing: existing),
    );
    if (result == null || !mounted) return;

    await _run(() async {
      await _service.saveAccount(
        id: existing?.id,
        churchId: churchId,
        purpose: result.purpose,
        label: result.label,
        phone: result.phone,
        network: result.network,
        isPrimary: result.isPrimary,
        isActive: result.isActive,
      );
      _snack(existing == null ? 'Payment account added.' : 'Payment account updated.');
    });
  }

  Future<void> _setPrimary(ChurchPaymentAccount account) async {
    await _run(() async {
      final updated = await _service.setPrimary(account.id);
      // Belt-and-braces: the DB trigger already mirrors this, but the client
      // write keeps the Give tab correct even if the trigger is ever dropped.
      await _service.syncPrimaryToChurchesRow(
          account.churchId, updated.copyWith(isPrimary: true, isActive: true));
      _snack('${account.purposeLabel} number set as the primary.');
    });
  }

  Future<void> _toggleActive(ChurchPaymentAccount account) async {
    await _run(() async {
      final updated = await _service.setActive(account.id, !account.isActive);
      if (!updated.isActive) {
        // Retire the number the Give tab was pointing at: mirror whatever is now
        // the primary for this purpose (usually nothing).
        final remaining = await _service.fetchAccounts(account.churchId);
        final replacements = <ChurchPaymentAccount>[];
        for (final a in remaining) {
          if (a.purpose == account.purpose && a.isPrimary && a.isActive) {
            replacements.add(a);
          }
        }
        await _service.syncPrimaryToChurchesRow(
            account.churchId,
            replacements.isEmpty ? null : replacements.first);
      }
      _snack(updated.isActive ? 'Account reactivated.' : 'Account deactivated.');
    });
  }

  Future<void> _delete(ChurchPaymentAccount account) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this number?'),
        content: Text(
          '${account.phone} will be removed from this church. '
          'If it is the primary ${account.purposeLabel.toLowerCase()} number, '
          'the church may not be able to receive giving until another is set.',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCEL')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('REMOVE'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() async {
      await _service.deleteAccount(account.id);
      _snack('Payment account removed.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final accountsAsync = ref.watch(currentChurchPaymentAccountsProvider);
    final tenant = ref.watch(currentTenantProvider);
    // Watched (not `read`) so the FAB and the edit menus appear as soon as the
    // profile resolves, and disappear again on a role change.
    final canManage = canManageRole(ref.watch(profileProvider).value?.role ?? '');

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Payment Accounts'),
        actions: [
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(LucideIcons.rotateCcw),
            onPressed: _busy ? null : _reload,
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ],
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : () => _openForm(),
              backgroundColor: AppTheme.platformPrimary,
              foregroundColor: AppTheme.onPlatformPrimary,
              icon: const Icon(LucideIcons.plus),
              label: const Text('ADD NUMBER',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
            )
          : null,
      body: accountsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _errorView(theme, e.toString()),
        data: (accounts) => RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
            children: [
              _recipientCard(theme, accounts, tenant?.name,
                  canManage: canManage),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _banner(LucideIcons.alertTriangle, _error!, Colors.red),
              ],
              const SizedBox(height: 20),
              if (accounts.isEmpty)
                _emptyState(theme, canManage: canManage)
              else
                ..._grouped(theme, accounts, canManage),
              if (accounts.isNotEmpty) ...[
                const SizedBox(height: 18),
                _explainer(theme),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── The "can we collect money at all?" banner ──────────────────────────
  Widget _recipientCard(
    ThemeData theme,
    List<ChurchPaymentAccount> accounts,
    String? churchName, {
    required bool canManage,
  }) {
    final phone = resolveGivingPhone(accounts);
    final ok = phone != null && phone.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: ok
              ? [
                  AppConstants.sunflowerYellow,
                  AppConstants.sunflowerYellow.withValues(alpha: 0.7),
                ]
              : [
                  theme.colorScheme.error.withValues(alpha: 0.12),
                  theme.colorScheme.errorContainer.withValues(alpha: 0.55),
                ],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ok ? LucideIcons.badgeCheck : LucideIcons.shieldAlert,
                size: 18,
                color: ok ? AppConstants.primaryDark : theme.colorScheme.error,
              ),
              const SizedBox(width: 8),
              Text(
                ok ? 'GIVING RECIPIENT' : 'NO PAYMENT RECIPIENT',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                  color: ok ? AppConstants.primaryDark : theme.colorScheme.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (ok)
            Text(
              phone,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: AppConstants.primaryDark,
              ),
            )
          else
            Text(
              'Mobile-money gifts to this church cannot be completed yet.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          if ((churchName ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                churchName!,
                style: TextStyle(
                  fontSize: 11,
                  color: ok
                      ? AppConstants.primaryDark.withValues(alpha: 0.7)
                      : theme.colorScheme.onErrorContainer.withValues(alpha: 0.7),
                ),
              ),
            ),
          if (ok)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Gifts are sent to this number.',
                style: TextStyle(
                  fontSize: 11,
                  color: AppConstants.primaryDark.withValues(alpha: 0.75),
                ),
              ),
            ),
          if (!ok && canManage)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : () => _openForm(),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppConstants.primaryDark,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(LucideIcons.plus),
                  label: const Text('ADD THE FIRST NUMBER'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Accounts grouped by purpose ─────────────────────────────────────────
  List<Widget> _grouped(
    ThemeData theme,
    List<ChurchPaymentAccount> accounts,
    bool canManage,
  ) {
    final widgets = <Widget>[];
    for (final purpose in kPaymentAccountPurposes) {
      final rows = accounts.where((a) => a.purpose == purpose).toList();
      final meta = purposeTitle(purpose);

      widgets.add(const SizedBox(height: 14));
      widgets.add(
        Row(
          children: [
            Icon(_iconForPurpose(purpose),
                size: 16, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
            const SizedBox(width: 6),
            Text(
              meta.title.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              rows.isEmpty ? 'NOT SET' : '${rows.length}',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
                color: rows.isEmpty
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurface.withValues(alpha: 0.35),
              ),
            ),
          ],
        ),
      );
      widgets.add(const SizedBox(height: 4));
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            meta.hint,
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ),
      );

      if (rows.isEmpty) {
        widgets.add(_placeholder(theme, canManage: canManage));
      } else {
        widgets.addAll(rows.map((a) => _accountTile(theme, a, canManage)));
      }
    }
    return widgets;
  }

  Widget _placeholder(ThemeData theme, {required bool canManage}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.smartphone,
              size: 18, color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              canManage
                  ? 'No number set. Tap + to add one.'
                  : 'Not configured yet.',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _accountTile(
      ThemeData theme, ChurchPaymentAccount account, bool canManage) {
    final active = account.isActive;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: account.isPrimary && active
              ? AppConstants.sunflowerYellow
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: account.isPrimary && active ? 1.6 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (account.isPrimary && active
                      ? AppConstants.sunflowerYellow
                      : theme.colorScheme.onSurface)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _iconForPurpose(account.purpose),
              size: 20,
              color: account.isPrimary && active
                  ? AppConstants.primaryDark
                  : theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.phone,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                    color: active
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurface.withValues(alpha: 0.45),
                    decoration: active ? null : TextDecoration.lineThrough,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _chip(networkLabel(account.network),
                        AppConstants.sunflowerYellow),
                    if (account.isPrimary && active)
                      _chip('PRIMARY', AppConstants.accentGreen,
                          dark: true),
                    _chip(
                      active ? 'ACTIVE' : 'INACTIVE',
                      active
                          ? theme.colorScheme.onSurface.withValues(alpha: 0.5)
                          : theme.colorScheme.error,
                      dark: !active,
                    ),
                  ],
                ),
                if ((account.label ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    account.label!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (canManage)
            PopupMenuButton<String>(
              enabled: !_busy,
              tooltip: 'Manage',
              icon: const Icon(LucideIcons.chevronRight, size: 18),
              onSelected: (v) {
                switch (v) {
                  case 'edit':
                    _openForm(existing: account);
                    break;
                  case 'primary':
                    _setPrimary(account);
                    break;
                  case 'toggle':
                    _toggleActive(account);
                    break;
                  case 'delete':
                    _delete(account);
                    break;
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                    value: 'edit', child: Text('Edit number')),
                if (!(account.isPrimary && account.isActive))
                  const PopupMenuItem(
                      value: 'primary', child: Text('Make primary')),
                PopupMenuItem(
                  value: 'toggle',
                  child: Text(account.isActive ? 'Deactivate' : 'Reactivate'),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Remove', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color, {bool dark = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: dark ? 1.0 : 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 8.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.6,
          color: dark ? Colors.white : color,
        ),
      ),
    );
  }

  // ── Empty / explainer / error ───────────────────────────────────────────
  Widget _emptyState(ThemeData theme, {required bool canManage}) {
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
              Icon(LucideIcons.wallet,
                  size: 20, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
              const SizedBox(width: 8),
              const Text('NO PAYMENT ACCOUNTS YET',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Without a payment account your church cannot receive mobile money gifts. '
            'Add the number of the person who holds the church money — usually the '
            'treasurer — and every gift collected in the app is sent there.',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            canManage
                ? 'Tap ADD NUMBER to record the first one.'
                : 'Only your church leadership can add one. Please ask your treasurer or pastor.',
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

  Widget _explainer(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppConstants.surfaceWarm.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(LucideIcons.info, size: 16, color: AppConstants.primaryDark),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Each role can hold several numbers, but only one PRIMARY number '
              'receives money. The primary is what members are shown, so keep it '
              'to a number someone answers on every service day.',
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
        Center(
          child: FilledButton(onPressed: _reload, child: const Text('RETRY')),
        ),
      ],
    );
  }

  IconData _iconForPurpose(String purpose) {
    switch (purpose) {
      case 'pastor':
        return LucideIcons.landmark;
      case 'bishop':
        return LucideIcons.crown;
      case 'organization':
        return LucideIcons.building2;
      case 'treasurer':
      default:
        return LucideIcons.wallet;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Create / edit form
// ═══════════════════════════════════════════════════════════════════════════

class _AccountFormResult {
  final String purpose;
  final String? label;
  final String phone;
  final String? network;
  final bool isPrimary;
  final bool isActive;

  const _AccountFormResult({
    required this.purpose,
    this.label,
    required this.phone,
    this.network,
    required this.isPrimary,
    required this.isActive,
  });
}

class _AccountFormSheet extends StatefulWidget {
  const _AccountFormSheet({this.existing});

  final ChurchPaymentAccount? existing;

  @override
  State<_AccountFormSheet> createState() => _AccountFormSheetState();
}

class _AccountFormSheetState extends State<_AccountFormSheet> {
  late final TextEditingController _phone;
  late final TextEditingController _label;

  late String _purpose;
  late String? _network;
  bool _isPrimary = false;
  bool _isActive = true;

  /// Set only when SAVE is pressed, so nobody is shouted at mid-typing.
  String? _phoneError;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _purpose = e?.purpose ?? 'treasurer';
    _phone = TextEditingController(text: e?.phone ?? '');
    _label = TextEditingController(text: e?.label ?? '');
    _network = e?.network;
    _isPrimary = e?.isPrimary ?? false;
    _isActive = e?.isActive ?? true;
  }

  @override
  void dispose() {
    _phone.dispose();
    _label.dispose();
    super.dispose();
  }

  /// Live network detection — but only ever over a value WE chose.
  ///
  /// Never defaults from a half-typed prefix (`detectNetworkFromPhone` returns
  /// null below 3 digits), and once the number is complete a detected change is
  /// applied so correcting a digit re-labels the operator, while an incomplete
  /// number never overwrites a selection the user already made.
  void _onPhoneChanged(String _) {
    final detected = detectNetworkFromPhone(_phone.text);
    final complete = validateZambianPhone(_phone.text) == null;

    var next = _network;
    if (detected != null &&
        detected != _network &&
        (_network == null || complete)) {
      next = detected;
    }
    // Re-validate live only once an error is showing; stay quiet until SAVE.
    final nextError = _phoneError == null ? null : complete ? null : _phoneError;

    setState(() {
      _network = next;
      _phoneError = nextError;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.existing != null;
    final meta = purposeTitle(_purpose);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEdit ? 'Edit payment account' : 'New payment account',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _purpose,
              decoration: const InputDecoration(
                labelText: 'Who receives the money',
                border: OutlineInputBorder(),
              ),
              items: kPaymentAccountPurposes
                  .map((p) => DropdownMenuItem(
                        value: p,
                        child: Text(purposeTitle(p).title,
                            style: const TextStyle(fontSize: 14)),
                      ))
                  .toList(),
              onChanged: (v) => setState(() {
                _purpose = v ?? _purpose;
              }),
            ),
            const SizedBox(height: 6),
            Text(
              meta.hint,
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              autofocus: !isEdit,
              onChanged: _onPhoneChanged,
              decoration: InputDecoration(
                labelText: 'Mobile money number',
                hintText: '0971 234 567',
                border: const OutlineInputBorder(),
                helperText: 'MTN 096/076 · Airtel 097/077 · Zamtel 095/075',
                helperMaxLines: 2,
                errorText: _phoneError,
                prefixIcon: const Icon(LucideIcons.smartphone, size: 18),
                suffixIcon: _network == null
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppConstants.sunflowerYellow
                                .withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            networkLabel(_network),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: AppConstants.primaryDark,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            if (_network == null && _phone.text.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'We could not recognise this prefix — you can still save it, '
                  'but check the number carefully.',
                  style: TextStyle(
                      fontSize: 11, color: theme.colorScheme.error),
                ),
              ),
            const SizedBox(height: 14),
            TextField(
              controller: _label,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Label (optional)',
                hintText: 'e.g. Deputy treasurer',
                border: OutlineInputBorder(),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isPrimary,
              onChanged: (v) => setState(() => _isPrimary = v),
              title: const Text('Make this the primary number',
                  style: TextStyle(fontSize: 13)),
              subtitle: Text(
                'Only one number per role can be primary, and it is the one '
                'members are shown when they give.',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
              title: const Text('Active', style: TextStyle(fontSize: 13)),
              subtitle: Text(
                'Turn off to retire a number without deleting its history.',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  backgroundColor: AppConstants.sunflowerYellow,
                  foregroundColor: AppConstants.primaryDark,
                ),
                onPressed: () {
                  final error = validateZambianPhone(_phone.text);
                  if (error != null) {
                    setState(() => _phoneError = error);
                    return;
                  }
                  Navigator.of(context).pop(_AccountFormResult(
                    purpose: _purpose,
                    label: _label.text.trim().isEmpty
                        ? null
                        : _label.text.trim(),
                    phone: _phone.text.trim(),
                    network: _network ?? detectNetworkFromPhone(_phone.text),
                    isPrimary: _isPrimary,
                    isActive: _isActive,
                  ));
                },
                child: Text(
                  isEdit ? 'SAVE CHANGES' : 'SAVE NUMBER',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}