import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:church_on_app/features/modules/bible_quiz/data/quiz_hosting_service.dart';

/// Bracket / spectator view for a hosted tournament.
///
/// Hosts can record match scores (which advance winners); everyone can watch
/// and see the live spectator count (presence heartbeat via
/// `quiz_tournament_watch`).
class QuizBracketScreen extends ConsumerStatefulWidget {
  const QuizBracketScreen({
    super.key,
    required this.tournamentId,
    required this.title,
    this.isHost = false,
  });

  final String tournamentId;
  final String title;
  final bool isHost;

  @override
  ConsumerState<QuizBracketScreen> createState() => _QuizBracketScreenState();
}

class _QuizBracketScreenState extends ConsumerState<QuizBracketScreen> {
  Timer? _heartbeat;
  int _viewers = 0;
  final Map<String, String> _names = {};  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tick();
    _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    super.dispose();
  }

  Future<void> _tick() async {
    try {
      final n = await ref
          .read(quizHostingServiceProvider)
          .watch(widget.tournamentId);
      if (mounted) setState(() => _viewers = n);
    } catch (_) {}
  }

  Future<void> _loadNames(List<QuizTournamentMatch> matches) async {
    final ids = <String>{};
    for (final m in matches) {
      if (m.homeUserId != null) ids.add(m.homeUserId!);
      if (m.awayUserId != null) ids.add(m.awayUserId!);
    }
    final missing = ids.where((id) => !_names.containsKey(id)).toList();
    if (missing.isEmpty) return;
    try {
      final rows = await Supabase.instance.client
          .from('profiles')
          .select('id, full_name')
          .inFilter('id', missing);
      if (!mounted) return;
      setState(() {
        for (final r in (rows as List)) {
          _names[r['id'].toString()] = r['full_name']?.toString() ?? 'Player';
        }
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bracketAsync = ref.watch(quizBracketProvider(widget.tournamentId));

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Icon(LucideIcons.eye, size: 16),
                const SizedBox(width: 4),
                Text('$_viewers',
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async =>
            ref.invalidate(quizBracketProvider(widget.tournamentId)),
        child: bracketAsync.when(
          data: (matches) {
            if (matches.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: 120),
                  const Icon(LucideIcons.network, size: 48, color: Colors.grey),
                  const SizedBox(height: 12),
                  const Center(
                      child: Text('No bracket generated yet',
                          style: TextStyle(color: Colors.grey))),
                  if (widget.isHost) ...[
                    const SizedBox(height: 16),
                    Center(
                      child: FilledButton.icon(
                        onPressed: () async {
                          await ref
                              .read(quizHostingServiceProvider)
                              .generateBracket(widget.tournamentId);
                          ref.invalidate(
                              quizBracketProvider(widget.tournamentId));
                        },
                        icon: const Icon(LucideIcons.shuffle),
                        label: const Text('GENERATE BRACKET'),
                      ),
                    ),
                  ],
                ],
              );
            }
            _loadNames(matches);
            final rounds = <int, List<QuizTournamentMatch>>{};
            for (final m in matches) {
              rounds.putIfAbsent(m.round, () => []).add(m);
            }
            final sortedRounds = rounds.keys.toList()..sort();
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ...sortedRounds.map((r) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ROUND $r',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.5))),
                        const SizedBox(height: 8),
                        ...rounds[r]!.map((m) => _matchCard(theme, m)),
                        const SizedBox(height: 16),
                      ],
                    )),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Could not load bracket: $e')),
        ),
      ),
    );
  }

  String _name(String? id) =>
      id == null ? '—' : (_names[id] ?? 'Player');

  Widget _matchCard(ThemeData theme, QuizTournamentMatch m) {
    final isBye = m.status == 'bye';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: m.status == 'live'
            ? Border.all(color: Colors.red, width: 1.5)
            : null,
      ),
      child: Column(
        children: [
          _playerRow(theme, _name(m.homeUserId), m.homeScore,
              winner: m.winnerUserId != null && m.winnerUserId == m.homeUserId),
          const SizedBox(height: 6),
          _playerRow(theme, _name(m.awayUserId), m.awayScore,
              winner: m.winnerUserId != null && m.winnerUserId == m.awayUserId),
          if (!isBye && widget.isHost && m.status != 'completed') ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _record(m),
                icon: const Icon(LucideIcons.pencil, size: 16),
                label: const Text('RECORD RESULT'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _playerRow(ThemeData theme, String name, int? score,
      {required bool winner}) {
    return Row(
      children: [
        Icon(
          winner ? LucideIcons.crown : LucideIcons.user,
          size: 16,
          color: winner ? theme.primaryColor : Colors.grey,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(name,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: winner ? FontWeight.w900 : FontWeight.w600)),
        ),
        Text(score?.toString() ?? '—',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
      ],
    );
  }

  Future<void> _record(QuizTournamentMatch m) async {
    final homeCtrl = TextEditingController(text: (m.homeScore ?? 0).toString());
    final awayCtrl = TextEditingController(text: (m.awayScore ?? 0).toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Record result'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: homeCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: _name(m.homeUserId)),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: awayCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: _name(m.awayUserId)),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCEL')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('SAVE')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(quizHostingServiceProvider).recordResult(
            m.id,
            int.tryParse(homeCtrl.text) ?? 0,
            int.tryParse(awayCtrl.text) ?? 0,
          );
      ref.invalidate(quizBracketProvider(widget.tournamentId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      homeCtrl.dispose();
      awayCtrl.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }
}
