import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:church_on_app/features/modules/bible_quiz/data/quiz_tournament_admin_service.dart';

/// A promoted ("featured") platform tournament surfaced on the quiz hub.
///
/// Staff promote a tournament via the Tournament Control screen; it then shows
/// here for every user with a live JOIN action (`join_quiz_tournament`).
class FeaturedTournamentsBanner extends ConsumerStatefulWidget {
  const FeaturedTournamentsBanner({super.key});

  @override
  ConsumerState<FeaturedTournamentsBanner> createState() =>
      _FeaturedTournamentsBannerState();
}

class _FeaturedTournamentsBannerState
    extends ConsumerState<FeaturedTournamentsBanner> {
  String? _joiningId;

  Future<void> _join(TournamentAdmin t) async {
    if (_joiningId != null) return;
    setState(() => _joiningId = t.id);
    final ok = await ref
        .read(quizTournamentAdminServiceProvider)
        .joinTournament(t.id);
    if (!mounted) return;
    setState(() => _joiningId = null);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'You are registered for "${t.title}".'
          : 'Could not join — the tournament may be full or closed.'),
      backgroundColor: ok ? Colors.green : Colors.redAccent,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(featuredTournamentsProvider);

    return async.maybeWhen(
      data: (tournaments) {
        if (tournaments.isEmpty) return const SizedBox.shrink();
        final df = DateFormat('d MMM · HH:mm');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.star, size: 16, color: theme.primaryColor),
                const SizedBox(width: 6),
                const Text('FEATURED TOURNAMENTS',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0)),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: tournaments.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final t = tournaments[i];
                  final busy = _joiningId == t.id;
                  return Container(
                    width: 280,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          theme.primaryColor.withValues(alpha: 0.22),
                          theme.primaryColor.withValues(alpha: 0.06),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                          color: theme.primaryColor.withValues(alpha: 0.45)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(
                          [
                            if (t.startsAt != null) df.format(t.startsAt!),
                            t.isFree ? 'Free entry' : '${t.entryFeeCc} CC',
                            '${t.maxParticipants} slots',
                          ].join(' · '),
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 11),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '🏆 ${t.prize1stCc} · ${t.prize2ndCc} · ${t.prize3rdCc} CC',
                          style: TextStyle(
                              color: theme.primaryColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        SizedBox(
                          width: double.infinity,
                          height: 34,
                          child: FilledButton(
                            onPressed: busy ? null : () => _join(t),
                            style: FilledButton.styleFrom(
                              backgroundColor: theme.primaryColor,
                              foregroundColor: Colors.black,
                            ),
                            child: busy
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child:
                                        CircularProgressIndicator(strokeWidth: 2))
                                : const Text('JOIN NOW',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900)),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}
