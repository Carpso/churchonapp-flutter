import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../finance/presentation/lipila_payment_gateway.dart';
import '../../../finance/presentation/buy_coins_screen.dart';
import '../../../../core/config/remote_config.dart';
import '../data/quiz_event_service.dart';
import 'bible_quiz_arena_screen.dart';

/// Bottom sheet prompting the player to buy Church Coins when their wallet
/// runs dry (wager stake, CC pass, engine lease, paid invite).
void showBuyCoinsSheet(BuildContext context,
    {String reason = 'Not enough Church Coins.'}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF151A2E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Icon(LucideIcons.coins, color: Colors.white, size: 28),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  "Insufficient Church Coins",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            reason,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 6),
          const Text(
            "Top up instantly with Mobile Money (MTN / Airtel / Zamtel) or card.",
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const BuyCoinsScreen(),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                "BUY CHURCH COINS",
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class QuizEventLobbyScreen extends ConsumerWidget {
  const QuizEventLobbyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(upcomingEventsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Premium Quiz Events',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: eventsAsync.when(
        data: (events) {
          if (events.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.calendarX, size: 64, color: Colors.white24),
                  const SizedBox(height: 16),
                  const Text('No upcoming events',
                      style: TextStyle(color: Colors.white54, fontSize: 16)),
                  const SizedBox(height: 8),
                  const Text('Check back later for premium Bible quizzing events',
                      style: TextStyle(color: Colors.white38, fontSize: 13)),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: events.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) => _EventCard(event: events[i]),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: Colors.white)),
        error: (e, _) => Center(
          child: Text('Could not load events: $e',
              style: const TextStyle(color: Colors.white54)),
        ),
      ),
    );
  }
}

class _EventCard extends ConsumerWidget {
  final QuizEvent event;
  const _EventCard({required this.event});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dateStr = DateFormat('MMM d, yyyy · h:mm a').format(event.startTime.toLocal());

    return Container(
      decoration: BoxDecoration(
        gradient: event.isFeatured
            ? LinearGradient(colors: [
                theme.primaryColor.withAlpha(25),
                const Color(0xFF0A0E1A),
              ], begin: Alignment.topLeft, end: Alignment.bottomRight)
            : null,
        color: event.isFeatured ? null : const Color(0xFF151A2E),
        borderRadius: BorderRadius.circular(18),
        border: event.isFeatured
            ? Border.all(color: theme.primaryColor.withAlpha(60))
            : Border.all(color: Colors.white.withAlpha(12)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _showEventDetail(context, ref),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row
                Row(
                  children: [
                    // Status badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: event.isActive
                            ? Colors.greenAccent.withAlpha(30)
                            : Colors.amber.withAlpha(30),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        event.statusLabel,
                        style: TextStyle(
                          color: event.isActive ? Colors.greenAccent : Colors.amberAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (event.isFeatured) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: theme.primaryColor.withAlpha(40),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'FEATURED',
                          style: TextStyle(
                            color: theme.primaryColor,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    // Price / wager
                    if (event.hasWager)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.primaryColor.withAlpha(20),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: theme.primaryColor.withAlpha(50)),
                        ),
                        child: Text(
                          '${event.wagerCoins} CC wager',
                          style: TextStyle(
                            color: theme.primaryColor,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    else if (!event.isFree)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.greenAccent.withAlpha(20),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.greenAccent.withAlpha(50)),
                        ),
                        child: Text(
                          'K${event.passPriceZmw.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.primaryColor.withAlpha(20),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'FREE',
                          style: TextStyle(
                            color: theme.primaryColor,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                // Title
                Text(
                  event.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (event.description != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    event.description!,
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 10),
                // Meta row
                Row(
                  children: [
                    Icon(LucideIcons.calendar, size: 14, color: Colors.white38),
                    const SizedBox(width: 4),
                    Text(dateStr, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                    const SizedBox(width: 16),
                    Icon(LucideIcons.helpCircle, size: 14, color: Colors.white38),
                    const SizedBox(width: 4),
                    Text('${event.questionCount} Qs',
                        style: const TextStyle(color: Colors.white38, fontSize: 12)),
                    const SizedBox(width: 16),
                    Icon(LucideIcons.clock, size: 14, color: Colors.white38),
                    const SizedBox(width: 4),
                    Text('${event.timePerQuestionSec}s',
                        style: const TextStyle(color: Colors.white38, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showEventDetail(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF151A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _EventDetailSheet(event: event),
    );
  }
}

class _EventDetailSheet extends ConsumerStatefulWidget {
  final QuizEvent event;
  const _EventDetailSheet({required this.event});

  @override
  ConsumerState<_EventDetailSheet> createState() => _EventDetailSheetState();
}

class _EventDetailSheetState extends ConsumerState<_EventDetailSheet> {
  bool _isJoining = false;
  bool _isJoined = false;
  bool _hasPass = false;

  RemoteConfig get _rc => widgetRemoteConfig(ref);

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    final svc = ref.read(quizEventServiceProvider);
    final joined = await svc.isUserInEvent(widget.event.id);
    final paid = widget.event.isFree ? true : await svc.hasUserPaidPass(widget.event.id);
    if (mounted) {
      setState(() {
        _isJoined = joined;
        _hasPass = paid || widget.event.isFree;
      });
    }
  }

  Future<void> _joinEvent() async {
    if (_isJoined) return;

    if (!widget.event.isFree && !_hasPass) {
      _showPaymentChoice();
      return;
    }

    await _performJoin(payCc: false);
  }

  /// Paid events: player picks Mobile Money or Church Coins from the wallet.
  void _showPaymentChoice() {
    final rate = _rc.getDouble('quiz_pass_cc_per_zmw', 1.0);
    final ccCost = (widget.event.passPriceZmw * rate).ceil();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF151A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              "Buy a Tournament Pass",
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.event.title} — K${widget.event.passPriceZmw.toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _showPayment();
                },
                icon: const Icon(LucideIcons.smartphone,
                    color: Colors.black, size: 18),
                label: Text(
                  'Pay K${widget.event.passPriceZmw.toStringAsFixed(2)} (Mobile Money)',
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _performJoin(payCc: true);
                },
                icon: const Icon(LucideIcons.coins,
                    color: Colors.black, size: 18),
                label: Text(
                  'Pay $ccCost CC from my wallet',
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  minimumSize: const Size(double.infinity, 54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '1 CC ≈ K1 · Or buy CC with Mobile Money, then join with CC.',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _performJoin({required bool payCc}) async {
    setState(() => _isJoining = true);
    final svc = ref.read(quizEventServiceProvider);
    final outcome = await svc.joinEvent(widget.event.id, payCc: payCc);
    if (!mounted) return;
    setState(() {
      _isJoining = false;
      _isJoined = outcome == JoinOutcome.joined;
    });
    switch (outcome) {
      case JoinOutcome.joined:
        ScaffoldMessenger.of(context).showSnackBar(
          widget.event.hasWager
              ? SnackBar(
                  content: Text(
                      'Joined! ${widget.event.wagerCoins} CC staked. Good luck!'),
                  backgroundColor: Colors.green,
                )
              : const SnackBar(content: Text('Joined event!')),
        );
      case JoinOutcome.insufficientCoins:
        showBuyCoinsSheet(
          context,
          reason: widget.event.hasWager
              ? 'You need ${widget.event.wagerCoins} CC to stake this wager.'
              : 'You need Church Coins to buy this pass.',
        );
      case JoinOutcome.failed:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not join this event.'),
            backgroundColor: Colors.orange,
          ),
        );
    }
  }

  void _showPayment() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LipilaPaymentGateway(
        amount: widget.event.passPriceZmw,
        description: 'Premium Quiz Pass: ${widget.event.title}',
        category: 'game_pass',
        recipientName: 'Church On App',
        recipientAccount: null,
        paymentReason: 'Quiz Event Pass',
        onComplete: (success, refId) async {
          if (success && refId != null) {
            final svc = ref.read(quizEventServiceProvider);
            await svc.purchasePass(
              widget.event.id,
              paymentRef: refId,
              amountZmw: widget.event.passPriceZmw,
            );
            await svc.joinEvent(widget.event.id);
            if (mounted) {
              setState(() {
                _hasPass = true;
                _isJoined = true;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Pass purchased! You are registered.'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          }
        },
      ),
    );
  }

  void _startQuiz() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BibleQuizArenaScreen(
          mode: 'Event',
          questionCount: widget.event.questionCount,
          eventId: widget.event.id,
          timePerQuestionSec: widget.event.timePerQuestionSec,
          categoryFilter: widget.event.categoryFilter,
          difficultyFilter: widget.event.difficultyFilter,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateStr = DateFormat('MMM d, yyyy · h:mm a').format(widget.event.startTime.toLocal());

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Title
          Text(widget.event.title,
              style: const TextStyle(
                  color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          if (widget.event.description != null) ...[
            const SizedBox(height: 8),
            Text(widget.event.description!,
                style: const TextStyle(color: Colors.white54, fontSize: 14)),
          ],
          const SizedBox(height: 16),
          // Detail rows
          _detailRow(LucideIcons.calendar, dateStr),
          const SizedBox(height: 6),
          _detailRow(LucideIcons.helpCircle, '${widget.event.questionCount} questions'),
          const SizedBox(height: 6),
          _detailRow(
              LucideIcons.clock, '${widget.event.timePerQuestionSec}s per question'),
          if (widget.event.categoryFilter != null) ...[
            const SizedBox(height: 6),
            _detailRow(LucideIcons.tag, 'Category: ${widget.event.categoryFilter}'),
          ],
          if (widget.event.difficultyFilter != null) ...[
            const SizedBox(height: 6),
            _detailRow(LucideIcons.barChart3, 'Difficulty: ${widget.event.difficultyFilter}'),
          ],
          if (!widget.event.isFree) ...[
            const SizedBox(height: 6),
            _detailRow(LucideIcons.creditCard,
                'Pass: K${widget.event.passPriceZmw.toStringAsFixed(2)}'),
          ],
          if (widget.event.hasWager) ...[
            const SizedBox(height: 6),
            _detailRow(
                LucideIcons.coins,
                'Stake: ${widget.event.wagerCoins} CC/player — 1st 50% · 2nd 30% · 3rd 20% of pot'),
          ],
          const SizedBox(height: 24),
          // Action buttons
          Row(
            children: [
              if (_isJoined || _hasPass)
                Expanded(
                  child: FilledButton.icon(
                    onPressed: widget.event.isActive ? _startQuiz : _joinEvent,
                    icon: Icon(widget.event.isActive
                        ? LucideIcons.play
                        : LucideIcons.calendarCheck,
                        size: 18),
                    label: Text(widget.event.isActive ? 'Play Now' : 'Registered'),
                    style: FilledButton.styleFrom(
                      backgroundColor: widget.event.isActive
                          ? Colors.greenAccent
                          : theme.primaryColor,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                )
              else
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isJoining ? null : _joinEvent,
                    icon: _isJoining
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.black))
                        : Icon(LucideIcons.ticket, size: 18),
                    label: Text(widget.event.isFree ? 'Join Free' : 'Buy Pass'),
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.primaryColor,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.white38),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(color: Colors.white60, fontSize: 14)),
      ],
    );
  }
}
