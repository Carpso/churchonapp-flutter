import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../finance/presentation/lipila_payment_gateway.dart';
import '../data/quiz_event_service.dart';
import 'bible_quiz_arena_screen.dart';

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
        loading: () => const Center(child: CircularProgressIndicator(color: Colors.amber)),
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
                    // Price
                    if (!event.isFree)
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
                          color: Colors.blueAccent.withAlpha(20),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'FREE',
                          style: TextStyle(
                            color: Colors.blueAccent,
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
      _showPayment(ctx: context);
      return;
    }

    setState(() => _isJoining = true);
    final svc = ref.read(quizEventServiceProvider);
    final ok = await svc.joinEvent(widget.event.id);
    if (mounted) {
      setState(() {
        _isJoining = false;
        _isJoined = ok;
      });
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Joined event!')),
        );
      }
    }
  }

  void _showPayment({required BuildContext ctx}) {
    Navigator.of(ctx).pop(); // close sheet
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
                      backgroundColor: Colors.greenAccent,
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
