import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/utils/money.dart';
import 'package:church_on_app/features/finance/data/offering_basket_service.dart';
import 'widgets/basket_visuals.dart';

/// Leader-facing offering basket manager.
///
/// Lets church leadership define the baskets they actually take (Tithe, Sunday
/// Offering, Missions, Building Fund…), start/stop a LIVE offering time, and
/// open the pastor/bishop basket report. Organisation-wide baskets can only be
/// created by organisation owners (bishop & co) — enforced server-side too.
class OfferingBasketManagerScreen extends ConsumerStatefulWidget {
  const OfferingBasketManagerScreen({super.key});

  @override
  ConsumerState<OfferingBasketManagerScreen> createState() =>
      _OfferingBasketManagerScreenState();
}

class _OfferingBasketManagerScreenState
    extends ConsumerState<OfferingBasketManagerScreen> {
  static const _orgRoles = {
    'bishop',
    'apostle',
    'prophet',
    'general_secretary',
    'general_treasurer',
    'superadmin',
    'super_admin',
    'coa_employee',
    'employee',
  };

  List<OfferingBasket> _baskets = [];
  List<OfferingSession> _sessions = [];
  OfferingSession? _active;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  OfferingBasketService get _service => ref.read(offeringBasketServiceProvider);

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
      final results = await Future.wait([
        _service.fetchBaskets(activeOnly: false),
        _service.fetchSessions(days: 30),
      ]);
      if (!mounted) return;
      final sessions = results[1] as List<OfferingSession>;
      setState(() {
        _baskets = results[0] as List<OfferingBasket>;
        _sessions = sessions;
        _active = sessions.where((s) => s.isOpen).firstOrNull;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  bool get _canCreateOrgWide {
    final role = ref.read(profileProvider).value?.role ?? '';
    return _orgRoles.contains(role);
  }

  Future<void> _startOffering() async {
    final active = _baskets.where((b) => b.isActive).toList();
    if (active.isEmpty) {
      _snack('Add a basket first.');
      return;
    }
    final picked = await showModalBottomSheet<OfferingBasket>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _BasketPickerSheet(baskets: active),
    );
    if (picked == null || !mounted) return;

    final title = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          title: Text('Open ${picked.name}'),
          content: TextField(
            controller: c,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Label (optional)',
              hintText: 'e.g. Sunday Morning Service',
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('OPEN OFFERING'),
            ),
          ],
        );
      },
    );
    if (title == null || !mounted) return; // cancelled

    await _run(() async {
      await _service.openSession(
        basketTypeId: picked.id,
        title: title.isEmpty ? null : title,
      );
      await _load();
      _snack('${picked.name} offering is live.');
    });
  }

  Future<void> _closeOffering() async {
    final session = _active;
    if (session == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Close offering?'),
        content: Text(
          '${session.basketName ?? 'Offering'} has ${formatKwacha(session.totalAmount)} '
          'from ${session.contributionCount} gift(s). Members will no longer be able '
          'to give into it.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCEL')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('CLOSE'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() async {
      await _service.closeSession(session.id);
      await _load();
      _snack('Offering closed.');
    });
  }

  Future<void> _createOrEdit({OfferingBasket? basket}) async {
    final result = await showModalBottomSheet<_BasketFormResult>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _BasketFormSheet(
        existing: basket,
        allowOrgWide: _canCreateOrgWide && basket == null,
      ),
    );
    if (result == null || !mounted) return;

    await _run(() async {
      if (basket == null) {
        await _service.createBasket(
          name: result.name,
          code: result.code,
          description: result.description,
          icon: result.icon,
          color: result.color,
          sortOrder: result.sortOrder,
          orgWide: result.orgWide,
        );
      } else {
        await _service.updateBasket(
          basketId: basket.id,
          name: result.name,
          code: result.code,
          sortOrder: result.sortOrder,
        );
      }
      await _load();
      _snack(basket == null ? 'Basket added.' : 'Basket updated.');
    });
  }

  Future<void> _toggleActive(OfferingBasket b) async {
    await _run(() async {
      await _service.updateBasket(basketId: b.id, isActive: !b.isActive);
      await _load();
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      _refreshGiveTab();
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Keep the (kept-alive) Give tab in sync with basket/session changes.
  void _refreshGiveTab() {
    ref.invalidate(offeringBasketsProvider);
    ref.invalidate(activeOfferingSessionProvider);
    ref.invalidate(offeringSessionsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = ref.watch(profileProvider).value;
    final allowed = profile != null &&
        (profile.isLeadershipTeam ||
            profile.isLedgerManager ||
            profile.isSuperadmin);

    if (!allowed) {
      return Scaffold(
        appBar: AppBar(title: const Text('Offering Baskets')),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.shieldOff, size: 48, color: Colors.grey),
              SizedBox(height: 12),
              Text('Leadership only.',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Offering Baskets'),
        actions: [
          IconButton(
            tooltip: 'Basket report',
            icon: const Icon(LucideIcons.barChart3),
            onPressed: () => context.push('/offering-baskets-summary'),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : () => _createOrEdit(),
        backgroundColor: theme.primaryColor,
        foregroundColor: Colors.black,
        icon: const Icon(LucideIcons.plus),
        label: const Text('NEW BASKET',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _errorView(theme)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
                    children: [
                      _liveCard(theme),
                      const SizedBox(height: 18),
                      Text('BASKETS',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.5))),
                      const SizedBox(height: 8),
                      if (_baskets.isEmpty)
                        _empty(theme, 'No baskets yet. Add the first one.')
                      else
                        ..._baskets.map((b) => _basketTile(theme, b)),
                      const SizedBox(height: 24),
                      Text('RECENT OFFERINGS',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.5))),
                      const SizedBox(height: 8),
                      if (_sessions.isEmpty)
                        _empty(theme, 'No offerings taken yet.')
                      else
                        ..._sessions.take(12).map((s) => _sessionRow(theme, s)),
                    ],
                  ),
                ),
    );
  }

  Widget _liveCard(ThemeData theme) {
    final session = _active;
    if (session == null) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.circleDot, size: 18, color: theme.primaryColor),
                const SizedBox(width: 8),
                const Text('NO LIVE OFFERING',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 6),
            Text('Start an offering so members can give into a specific basket.',
                style: TextStyle(
                    fontSize: 12,
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.6))),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _startOffering,
                icon: const Icon(LucideIcons.play),
                label: const Text('START OFFERING'),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.primaryColor,
            theme.primaryColor.withValues(alpha: 0.75),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  children: [
                    Icon(LucideIcons.radio, size: 12, color: Colors.white),
                    SizedBox(width: 4),
                    Text('LIVE',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1)),
                  ],
                ),
              ),
              const Spacer(),
              Text(_since(session.openedAt),
                  style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 12),
          Text(session.basketName ?? 'Offering',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900)),
          if ((session.title ?? '').isNotEmpty)
            Text(session.title!,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatKwacha(session.totalAmount),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w900)),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('${session.contributionCount} gift(s)',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _closeOffering,
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white),
              icon: const Icon(LucideIcons.square),
              label: const Text('CLOSE OFFERING'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _basketTile(ThemeData theme, OfferingBasket b) {
    final color = BasketVisuals.colorFor(b.color);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: b.isActive
                ? color.withValues(alpha: 0.25)
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(BasketVisuals.iconFor(b.icon), size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(b.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: theme.colorScheme.onSurface)),
                    ),
                    if (b.isOrgWide) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.primaryColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('ORG',
                            style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w900,
                                color: theme.primaryColor)),
                      ),
                    ],
                  ],
                ),
                Text(
                  [
                    if ((b.code ?? '').isNotEmpty) b.code!,
                    if ((b.description ?? '').isNotEmpty) b.description!,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.55)),
                ),
              ],
            ),
          ),
          if (!b.isOrgWide)
            IconButton(
              tooltip: b.isActive ? 'Deactivate' : 'Activate',
              icon: Icon(
                b.isActive
                    ? LucideIcons.toggleRight
                    : LucideIcons.toggleLeft,
                color: b.isActive ? color : Colors.grey,
              ),
              onPressed: _busy ? null : () => _toggleActive(b),
            ),
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(LucideIcons.pencil, size: 18),
            onPressed: _busy ? null : () => _createOrEdit(basket: b),
          ),
        ],
      ),
    );
  }

  Widget _sessionRow(ThemeData theme, OfferingSession s) {
    final open = s.isOpen;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(open ? LucideIcons.radio : LucideIcons.checkCircle2,
              size: 16, color: open ? Colors.red : Colors.green),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.basketName ?? 'Offering',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                Text(
                  '${_date(s.openedAt)}${s.title != null && s.title!.isNotEmpty ? ' · ${s.title}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 10,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.55)),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatKwacha(s.totalAmount),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: theme.primaryColor)),
              Text('${s.contributionCount} gift(s)',
                  style: TextStyle(
                      fontSize: 9,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.5))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _empty(ThemeData theme, String text) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
      );

  Widget _errorView(ThemeData theme) => ListView(
        children: [
          const SizedBox(height: 80),
          Icon(LucideIcons.alertTriangle, size: 48, color: Colors.red.shade300),
          const SizedBox(height: 12),
          Center(child: Text('Error: $_error')),
          const SizedBox(height: 12),
          Center(
            child: FilledButton(onPressed: _load, child: const Text('RETRY')),
          ),
        ],
      );

  String _since(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }

  String _date(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

// ── Basket picker ────────────────────────────────────────────────────────────
class _BasketPickerSheet extends StatelessWidget {
  const _BasketPickerSheet({required this.baskets});
  final List<OfferingBasket> baskets;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Choose a basket',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: baskets.length,
              itemBuilder: (c, i) {
                final b = baskets[i];
                final color = BasketVisuals.colorFor(b.color);
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.15),
                    child: Icon(BasketVisuals.iconFor(b.icon),
                        size: 18, color: color),
                  ),
                  title: Text(b.name),
                  subtitle: Text(
                    [if (b.isOrgWide) 'Organisation-wide',
                     if ((b.code ?? '').isNotEmpty) b.code!].join(' · '),
                    style: const TextStyle(fontSize: 11),
                  ),
                  onTap: () => Navigator.of(context).pop(b),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Create / edit form ───────────────────────────────────────────────────────
class _BasketFormResult {
  final String name;
  final String? code;
  final String? description;
  final String icon;
  final String color;
  final int sortOrder;
  final bool orgWide;

  const _BasketFormResult({
    required this.name,
    this.code,
    this.description,
    required this.icon,
    required this.color,
    required this.sortOrder,
    required this.orgWide,
  });
}

class _BasketFormSheet extends StatefulWidget {
  const _BasketFormSheet({this.existing, this.allowOrgWide = false});
  final OfferingBasket? existing;
  final bool allowOrgWide;

  @override
  State<_BasketFormSheet> createState() => _BasketFormSheetState();
}

class _BasketFormSheetState extends State<_BasketFormSheet> {
  late final TextEditingController _name;
  late final TextEditingController _code;
  late final TextEditingController _desc;
  late final TextEditingController _sort;
  late String _icon;
  late Color _color;
  bool _orgWide = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _code = TextEditingController(text: e?.code ?? '');
    _desc = TextEditingController(text: e?.description ?? '');
    _sort = TextEditingController(text: (e?.sortOrder ?? 0).toString());
    _icon = e?.icon ?? 'hand-heart';
    _color = BasketVisuals.colorFor(e?.color);
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _desc.dispose();
    _sort.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.existing != null;
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
            Text(isEdit ? 'Edit basket' : 'New basket',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Basket name',
                hintText: 'e.g. Building Fund',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _code,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'GL code (optional)',
                      hintText: 'BLD',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: _sort,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Order',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _desc,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 18),
            const Text('Icon',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: BasketVisuals.icons.entries.map((e) {
                final selected = _icon == e.key;
                return GestureDetector(
                  onTap: () => setState(() => _icon = e.key),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: selected
                          ? _color.withValues(alpha: 0.2)
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: selected ? _color : Colors.transparent,
                          width: 2),
                    ),
                    child: Icon(e.value, size: 18),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 18),
            const Text('Colour',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: BasketVisuals.palette.map((c) {
                final selected = _color.toARGB32() == c.toARGB32();
                return GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? Colors.black : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                    child: selected
                        ? const Icon(LucideIcons.check,
                            size: 16, color: Colors.black)
                        : null,
                  ),
                );
              }).toList(),
            ),
            if (widget.allowOrgWide) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _orgWide,
                onChanged: (v) => setState(() => _orgWide = v),
                title: const Text('Share with my whole organisation',
                    style: TextStyle(fontSize: 13)),
                subtitle: const Text(
                    'Every branch in your organisation will see this basket.',
                    style: TextStyle(fontSize: 11)),
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  final name = _name.text.trim();
                  if (name.isEmpty) return;
                  Navigator.of(context).pop(_BasketFormResult(
                    name: name,
                    code: _code.text.trim().isEmpty ? null : _code.text.trim(),
                    description:
                        _desc.text.trim().isEmpty ? null : _desc.text.trim(),
                    icon: _icon,
                    color: BasketVisuals.toHex(_color),
                    sortOrder: int.tryParse(_sort.text.trim()) ?? 0,
                    orgWide: _orgWide,
                  ));
                },
                style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52)),
                child: Text(isEdit ? 'SAVE CHANGES' : 'CREATE BASKET'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
