import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/member_transfer_service.dart';

/// Raise a transfer: who is moving, which way, and to where.
class MemberTransferRequestSheet extends StatefulWidget {
  final String tenantId;
  final String churchName;
  final MemberTransferService service;

  const MemberTransferRequestSheet({
    super.key,
    required this.tenantId,
    required this.churchName,
    required this.service,
  });

  @override
  State<MemberTransferRequestSheet> createState() => _RequestTransferRequestSheetState();
}

class _RequestTransferRequestSheetState extends State<MemberTransferRequestSheet> {
  final _client = Supabase.instance.client;
  final _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _members = const [];
  List<Map<String, String>> _churches = const [];
  bool _loadingMembers = true;
  bool _saving = false;
  String? _error;

  TransferDirection _direction = TransferDirection.outbound;
  Map<String, dynamic>? _member;
  String? _destinationId;
  final _reasonCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadMembers();
    _loadChurches();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _reasonCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    try {
      final rows = await _client
          .from('profiles')
          .select('id, full_name, phone_number, role')
          .eq('tenant_id', widget.tenantId)
          .order('full_name')
          .limit(300);
      if (!mounted) return;
      setState(() {
        _members = rows;
        _loadingMembers = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load members.';
        _loadingMembers = false;
      });
    }
  }

  Future<void> _loadChurches() async {
    try {
      final list = await widget.service.destinationChurches(widget.tenantId);
      if (!mounted) return;
      setState(() => _churches = list);
    } catch (_) {
      // Non-fatal: an inbound transfer can still be raised with a typed name.
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _members;
    return _members
        .where((m) =>
            (m['full_name']?.toString().toLowerCase().contains(q) ?? false) ||
            (m['phone_number']?.toString().contains(q) ?? false))
        .toList();
  }

  String? get _destinationName => _churches
      .where((c) => c['id'] == _destinationId)
      .map((c) => c['name'])
      .firstOrNull;

  Future<void> _submit() async {
    if (_member == null) {
      setState(() => _error = 'Choose the member who is moving.');
      return;
    }
    if (_direction == TransferDirection.outbound && _destinationId == null) {
      setState(() => _error = 'Choose the church they are moving to.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.service.request(
        memberId: _member!['id'].toString(),
        direction: _direction,
        toTenantId: _destinationId,
        toChurchName: _destinationName,
        reason: _reasonCtrl.text.trim(),
        notes: _notesCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on TransferException catch (e) {
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
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Center(
              child: Container(
                width: 46,
                height: 5,
                decoration: BoxDecoration(
                  color: theme.disabledColor,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text('New transfer',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            SegmentedButton<TransferDirection>(
              segments: const [
                ButtonSegment(
                  value: TransferDirection.outbound,
                  label: Text('Leaving'),
                  icon: Icon(Icons.logout, size: 16),
                ),
                ButtonSegment(
                  value: TransferDirection.inbound,
                  label: Text('Joining'),
                  icon: Icon(Icons.login, size: 16),
                ),
                ButtonSegment(
                  value: TransferDirection.internal,
                  label: Text('Cell move'),
                  icon: Icon(Icons.swap_horiz, size: 16),
                ),
              ],
              selected: {_direction},
              onSelectionChanged: (s) =>
                  setState(() => _direction = s.first),
            ),
            const SizedBox(height: 18),

            Text('MEMBER', style: _labelStyle),
            const SizedBox(height: 6),
            if (_member != null)
              InputDecorator(
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.person),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear),
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
                  hintText: 'Search member name or phone',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 8),
              if (_loadingMembers)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _filtered.length,
                    itemBuilder: (_, i) {
                      final m = _filtered[i];
                      return ListTile(
                        dense: true,
                        title: Text(m['full_name']?.toString() ?? 'Unnamed'),
                        subtitle: m['phone_number'] == null
                            ? null
                            : Text(m['phone_number'].toString()),
                        onTap: () => setState(() => _member = m),
                      );
                    },
                  ),
                ),
            ],
            const SizedBox(height: 18),

            if (_direction == TransferDirection.outbound) ...[
              Text('MOVING TO', style: _labelStyle),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _destinationId,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.church),
                ),
                items: [
                  for (final c in _churches)
                    DropdownMenuItem(value: c['id'], child: Text(c['name']!)),
                ],
                onChanged: (v) => setState(() => _destinationId = v),
              ),
              const SizedBox(height: 18),
            ],

            Text('REASON', style: _labelStyle),
            const SizedBox(height: 6),
            TextField(
              controller: _reasonCtrl,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'e.g. relocating for work, joining family church',
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _notesCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Notes (optional)',
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(color: theme.colorScheme.error, fontSize: 13)),
            ],

            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : _submit,
              icon: _saving
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
              label: Text(_saving ? 'Saving...' : 'Raise transfer'),
            ),
          ],
        ),
      ),
    );
  }

  static const _labelStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.bold,
    letterSpacing: 1.2,
  );
}