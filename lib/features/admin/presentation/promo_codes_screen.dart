import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:church_on_app/core/widgets/premium_toast.dart';
import 'package:church_on_app/features/admin/data/promo_code_service.dart';

/// Superadmin / COA promo-code control centre.
///
/// Create codes (CC / quiz pass / subscription discount / event entry), list
/// them with usage counts, award a code to a specific user via a searchable
/// picker, inspect redemptions and export the ledger.
class PromoCodesScreen extends ConsumerStatefulWidget {
  const PromoCodesScreen({super.key});

  @override
  ConsumerState<PromoCodesScreen> createState() => _PromoCodesScreenState();
}

class _PromoCodesScreenState extends ConsumerState<PromoCodesScreen> {
  bool _busy = false;

  Future<T?> _guard<T>(Future<T> Function() action) async {
    if (_busy) return null;
    setState(() => _busy = true);
    try {
      return await action();
    } catch (e) {
      if (mounted) PremiumToast.showError(context, '$e');
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(promoCodesProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0E1A),
        title: const Text('Promo Codes',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Export CSV',
            icon: const Icon(LucideIcons.download, color: Colors.white, size: 18),
            onPressed: () => _export(),
          ),
          IconButton(
            icon: const Icon(LucideIcons.refreshCw, color: Colors.white, size: 18),
            onPressed: () => ref.invalidate(promoCodesProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: theme.primaryColor,
        foregroundColor: Colors.black,
        onPressed: _create,
        icon: const Icon(LucideIcons.plus),
        label: const Text('New code'),
      ),
      body: async.when(
        data: (codes) => codes.isEmpty
            ? const Center(
                child: Text('No promo codes yet.',
                    style: TextStyle(color: Colors.white54)))
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(promoCodesProvider),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  itemCount: codes.length,
                  itemBuilder: (context, i) => _PromoCard(
                    code: codes[i],
                    busy: _busy,
                    onAward: _award,
                    onToggle: _toggle,
                    onView: _viewRedemptions,
                  ),
                ),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('$e', style: const TextStyle(color: Colors.white54)),
        ),
      ),
    );
  }

  Future<void> _create() async {
    final created = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _CreatePromoSheet(),
    );
    if (created == null || !mounted) return;
    await _guard(() async {
      await ref.read(promoCodeServiceProvider).createPromoCode(
            code: created['code'] as String?,
            kind: created['kind'] as String,
            value: created['value'] as double,
            description: created['description'] as String?,
            maxUses: created['maxUses'] as int?,
            perUserLimit: created['perUserLimit'] as int,
            expiresAt: created['expiresAt'] as DateTime?,
          );
      ref.invalidate(promoCodesProvider);
      if (mounted) PremiumToast.showSuccess(context, 'Promo code created.');
    });
  }

  Future<void> _award(PromoCode code) async {
    final user = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF151A2E),
      builder: (_) => const _UserPickerSheet(),
    );
    if (user == null || !mounted) return;
    await _guard(() async {
      final res = await ref
          .read(promoCodeServiceProvider)
          .awardToUser(userId: user['id'].toString(), code: code.code);
      ref.invalidate(promoCodesProvider);
      if (!mounted) return;
      if (res['ok'] == true) {
        PremiumToast.showSuccess(context, 'Awarded ${code.code}.');
      } else {
        PremiumToast.showError(context, 'Failed: ${res['reason'] ?? 'unknown'}');
      }
    });
  }

  Future<void> _toggle(PromoCode code) async {
    await _guard(() async {
      await ref.read(promoCodeServiceProvider).setActive(code.id, !code.active);
      ref.invalidate(promoCodesProvider);
    });
  }

  Future<void> _viewRedemptions(PromoCode code) async {
    final rows = await _guard(
        () => ref.read(promoCodeServiceProvider).listRedemptions(code: code.code));
    if (rows == null || !mounted) return;
    final df = DateFormat('d MMM y HH:mm');
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF151A2E),
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.all(16),
          children: [
            Text('Redemptions · ${code.code}',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (rows.isEmpty)
              const Text('No redemptions yet.',
                  style: TextStyle(color: Colors.white54)),
            for (final r in rows)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(LucideIcons.user, size: 16, color: Colors.white38),
                title: Text(r.fullName ?? r.userId,
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
                subtitle: Text(
                  '${df.format(r.redeemedAt ?? DateTime.now())}'
                  '${r.awardedBy != null ? ' · awarded by staff' : ' · self-redeemed'}',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _export() async {
    final result = await _guard(() async {
      final codes = await ref.read(promoCodeServiceProvider).listPromoCodes();
      final buffer = StringBuffer('code,kind,value,used_count,unique_users,active,expires_at\n');
      for (final c in codes) {
        buffer.writeln('${c.code},${c.kind},${c.value},${c.usedCount},'
            '${c.uniqueUsers},${c.active},${c.expiresAt?.toIso8601String() ?? ''}');
      }
      return buffer.toString();
    });
    if (result == null) return;
    await Clipboard.setData(ClipboardData(text: result));
    if (mounted) PremiumToast.showSuccess(context, 'CSV copied to clipboard.');
  }
}

class _PromoCard extends StatelessWidget {
  final PromoCode code;
  final bool busy;
  final Future<void> Function(PromoCode) onAward;
  final Future<void> Function(PromoCode) onToggle;
  final Future<void> Function(PromoCode) onView;

  const _PromoCard({
    required this.code,
    required this.busy,
    required this.onAward,
    required this.onToggle,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final invalid = !code.active || code.isExpired || code.isExhausted;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF151A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: invalid ? Colors.white12 : theme.primaryColor.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(code.code,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5)),
          ),
          if (_flag(code, 'expired', Colors.grey)) _chip('EXPIRED', Colors.grey),
          if (_flag(code, 'exhausted', Colors.orangeAccent))
            _chip('EXHAUSTED', Colors.orangeAccent),
          if (!code.active) _chip('INACTIVE', Colors.redAccent),
          if (invalid == false)
            _chip('ACTIVE', theme.primaryColor),
        ]),
        const SizedBox(height: 6),
        Text(
          '${code.kindLabel} · ${code.value.toStringAsFixed(0)}'
          '${code.description != null ? ' · ${code.description}' : ''}',
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          'Used ${code.usedCount}${code.maxUses != null ? '/${code.maxUses}' : ''}'
          ' · ${code.uniqueUsers} unique'
          '${code.expiresAt != null ? ' · expires ${DateFormat('d MMM y').format(code.expiresAt!)}' : ''}',
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
        const SizedBox(height: 8),
        Row(children: [
          TextButton.icon(
            onPressed: busy ? null : () => onAward(code),
            icon: const Icon(LucideIcons.send, size: 15),
            label: const Text('Award user'),
          ),
          TextButton.icon(
            onPressed: busy ? null : () => onView(code),
            icon: const Icon(LucideIcons.list, size: 15),
            label: const Text('Redemptions'),
          ),
          const Spacer(),
          Switch(
            value: code.active,
            activeThumbColor: theme.primaryColor,
            onChanged: busy ? null : (_) => onToggle(code),
          ),
        ]),
      ]),
    );
  }

  bool _flag(PromoCode c, String which, Color _) {
    if (which == 'expired') return c.isExpired && c.active;
    if (which == 'exhausted') return c.isExhausted && c.active && !c.isExpired;
    return false;
  }

  Widget _chip(String label, Color color) => Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                color: color, fontSize: 9, fontWeight: FontWeight.w900)),
      );
}

class _CreatePromoSheet extends StatefulWidget {
  const _CreatePromoSheet();

  @override
  State<_CreatePromoSheet> createState() => _CreatePromoSheetState();
}

class _CreatePromoSheetState extends State<_CreatePromoSheet> {
  final _code = TextEditingController();
  final _value = TextEditingController(text: '0');
  final _description = TextEditingController();
  final _maxUses = TextEditingController();
  final _perUser = TextEditingController(text: '1');

  String _kind = 'cc';
  DateTime? _expiresAt;

  @override
  void dispose() {
    for (final c in [_code, _value, _description, _maxUses, _perUser]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      title: const Text('New promo code',
          style: TextStyle(color: Colors.white, fontSize: 16)),
      content: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: _code,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                  labelText: 'Code (blank = auto-generate)'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _kind,
              dropdownColor: const Color(0xFF1E293B),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(labelText: 'Kind'),
              items: const [
                DropdownMenuItem(value: 'cc', child: Text('Church Coins')),
                DropdownMenuItem(value: 'quiz_pass', child: Text('Quiz pass')),
                DropdownMenuItem(
                    value: 'subscription_discount',
                    child: Text('Subscription discount')),
                DropdownMenuItem(value: 'event_entry', child: Text('Event entry')),
              ],
              onChanged: (v) => setState(() => _kind = v ?? 'cc'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _value,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                  labelText: 'Value (CC amount / % discount)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _description,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _maxUses,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Max uses (blank=∞)'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _perUser,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Per user'),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            InkWell(
              onTap: () async {
                final now = DateTime.now();
                final date = await showDatePicker(
                  context: context,
                  initialDate: now.add(const Duration(days: 30)),
                  firstDate: now,
                  lastDate: DateTime(now.year + 5),
                );
                if (date != null) setState(() => _expiresAt = date);
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white24),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _expiresAt == null
                      ? 'Expiry: never'
                      : 'Expires ${DateFormat('d MMM y').format(_expiresAt!)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, {
            'code': _code.text.trim().isEmpty ? null : _code.text.trim(),
            'kind': _kind,
            'value': double.tryParse(_value.text.trim()) ?? 0,
            'description':
                _description.text.trim().isEmpty ? null : _description.text.trim(),
            'maxUses': int.tryParse(_maxUses.text.trim()),
            'perUserLimit': int.tryParse(_perUser.text.trim()) ?? 1,
            'expiresAt': _expiresAt,
          }),
          child: const Text('Create'),
        ),
      ],
    );
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
          const Text('Award to user',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          TextField(
            controller: _search,
            style: const TextStyle(color: Colors.white),
            onChanged: _load,
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
