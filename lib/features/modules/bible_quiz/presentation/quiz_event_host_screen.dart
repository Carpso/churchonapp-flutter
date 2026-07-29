import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/providers/profile_provider.dart';
import '../data/quiz_event_service.dart';
import 'bible_quiz_arena_screen.dart';

class QuizEventHostScreen extends ConsumerStatefulWidget {
  const QuizEventHostScreen({super.key});

  @override
  ConsumerState<QuizEventHostScreen> createState() => _QuizEventHostScreenState();
}

class _QuizEventHostScreenState extends ConsumerState<QuizEventHostScreen> {
  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).value;
    final isAllowed = profile?.isSuperadmin == true || profile?.isEmployee == true;

    if (!isAllowed) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0E1A),
        appBar: _appBar(context),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.lock, size: 48, color: Colors.white24),
              SizedBox(height: 16),
              Text('Host access restricted',
                  style: TextStyle(color: Colors.white54, fontSize: 16)),
              SizedBox(height: 8),
              Text('Superadmin & Employee only',
                  style: TextStyle(color: Colors.white38, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: _appBar(context),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDialog(context),
        backgroundColor: Colors.greenAccent,
        foregroundColor: Colors.black,
        icon: const Icon(LucideIcons.plus),
        label: const Text('Create Event'),
      ),
      body: _EventsList(),
    );
  }

  AppBar _appBar(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      title: const Text('Quiz Host Control',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      centerTitle: true,
      leading: IconButton(
        icon: const Icon(LucideIcons.chevronLeft, color: Colors.white),
        onPressed: () => Navigator.of(context).pop(),
      ),
    );
  }

  void _showCreateDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _CreateEventDialog(),
    );
  }
}

class _EventsList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(allEventsProvider);

    return eventsAsync.when(
      data: (events) {
        if (events.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.calendarPlus, size: 56, color: Colors.white24),
                SizedBox(height: 16),
                Text('No quiz events yet',
                    style: TextStyle(color: Colors.white54, fontSize: 16)),
                SizedBox(height: 8),
                Text('Tap + to host your first premium quiz',
                    style: TextStyle(color: Colors.white38, fontSize: 13)),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
          itemCount: events.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) => _HostEventCard(event: events[i]),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator(color: Colors.amber)),
      error: (e, _) => Center(
        child: Text('Error: $e', style: const TextStyle(color: Colors.white54)),
      ),
    );
  }
}

class _HostEventCard extends ConsumerStatefulWidget {
  final QuizEvent event;
  const _HostEventCard({required this.event});

  @override
  ConsumerState<_HostEventCard> createState() => _HostEventCardState();
}

class _HostEventCardState extends ConsumerState<_HostEventCard> {
  int _participantCount = 0;

  @override
  void initState() {
    super.initState();
    _loadCount();
  }

  Future<void> _loadCount() async {
    final cnt = await ref.read(quizEventServiceProvider).getParticipantCount(widget.event.id);
    if (mounted) setState(() => _participantCount = cnt);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateStr = DateFormat('MMM d, yyyy · h:mm a').format(widget.event.startTime.toLocal());

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF151A2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withAlpha(10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor().withAlpha(30),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  widget.event.statusLabel,
                  style: TextStyle(
                    color: _statusColor(),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Spacer(),
              // Price
              Text(
                widget.event.isFree ? 'FREE' : 'K${widget.event.passPriceZmw.toStringAsFixed(0)}',
                style: TextStyle(
                  color: widget.event.isFree ? Colors.blueAccent : Colors.greenAccent,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Title
          Text(
            widget.event.title,
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(dateStr, style: const TextStyle(color: Colors.white38, fontSize: 12)),
          const SizedBox(height: 8),
          // Stats row
          Row(
            children: [
              _statChip(LucideIcons.helpCircle, '${widget.event.questionCount} Qs'),
              const SizedBox(width: 8),
              _statChip(LucideIcons.clock, '${widget.event.timePerQuestionSec}s'),
              const SizedBox(width: 8),
              _statChip(LucideIcons.users, '$_participantCount joined'),
            ],
          ),
          const SizedBox(height: 10),
          // Actions
          Row(
            children: [
              if (widget.event.isUpcoming)
                Expanded(
                  child: _actionBtn(
                    'Activate',
                    Colors.greenAccent,
                    () => _updateStatus('active'),
                  ),
                ),
              if (widget.event.isActive) ...[
                Expanded(
                  child: _actionBtn(
                    'View Leaderboard',
                    theme.primaryColor,
                    () => _showLeaderboard(context),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _actionBtn(
                    'End Quiz',
                    Colors.redAccent,
                    () => _updateStatus('completed'),
                  ),
                ),
              ],
              if (widget.event.isUpcoming) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _actionBtn(
                    'Cancel',
                    Colors.redAccent,
                    () => _updateStatus('cancelled'),
                  ),
                ),
              ],
              if (widget.event.isActive)
                Expanded(
                  child: _actionBtn(
                    'Test Run',
                    Colors.blueAccent,
                    () => Navigator.of(context).push(
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
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Color _statusColor() {
    switch (widget.event.status) {
      case 'active':
        return Colors.greenAccent;
      case 'upcoming':
        return Colors.amberAccent;
      case 'completed':
        return Colors.blueGrey;
      case 'cancelled':
        return Colors.redAccent;
      default:
        return Colors.white54;
    }
  }

  Widget _statChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Colors.white38),
        const SizedBox(width: 3),
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
      ],
    );
  }

  Widget _actionBtn(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withAlpha(60)),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  Future<void> _updateStatus(String status) async {
    final svc = ref.read(quizEventServiceProvider);
    final err = await svc.updateEventStatus(widget.event.id, status);
    if (mounted) {
      if (err != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(err)));
      } else {
        ref.invalidate(allEventsProvider);
      }
    }
  }

  void _showLeaderboard(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: const Color(0xFF151A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (_) => _LeaderboardSheet(eventId: widget.event.id),
    );
  }
}

class _LeaderboardSheet extends ConsumerStatefulWidget {
  final String eventId;
  const _LeaderboardSheet({required this.eventId});

  @override
  ConsumerState<_LeaderboardSheet> createState() => _LeaderboardSheetState();
}

class _LeaderboardSheetState extends ConsumerState<_LeaderboardSheet> {
  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            children: [
              Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              const Text('Leaderboard',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: ref.read(quizEventServiceProvider).getLeaderboard(widget.eventId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                          child: CircularProgressIndicator(color: Colors.amber));
                    }
                    final entries = snapshot.data ?? [];
                    if (entries.isEmpty) {
                      return const Center(
                        child: Text('No scores yet',
                            style: TextStyle(color: Colors.white54)),
                      );
                    }
                    return ListView.separated(
                      controller: scrollController,
                      itemCount: entries.length,
                      separatorBuilder: (_, __) => const Divider(
                          color: Colors.white10, height: 1),
                      itemBuilder: (context, i) {
                        final e = entries[i];
                        final profile = e['profiles'] as Map<String, dynamic>?;
                        final name = profile?['full_name'] ?? 'Player ${i + 1}';
                        final score = e['score'] ?? 0;
                        final correct = e['correct_count'] ?? 0;
                        final total = e['total_questions'] ?? 0;
                        final isMe = e['user_id'] ==
                            ref.read(profileProvider).value?.id;

                        return Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          color: isMe
                              ? Colors.amber.withAlpha(15)
                              : Colors.transparent,
                          child: Row(
                            children: [
                              SizedBox(
                                width: 28,
                                child: Text(
                                  '#${i + 1}',
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: Colors.white12,
                                child: Text(
                                  name.isNotEmpty
                                      ? name[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  name,
                                  style: TextStyle(
                                    color: isMe
                                        ? Colors.amberAccent
                                        : Colors.white,
                                    fontSize: 14,
                                    fontWeight: isMe
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                              if (total > 0)
                                Text(
                                  '$correct/$total',
                                  style: const TextStyle(
                                      color: Colors.white38, fontSize: 12),
                                ),
                              const SizedBox(width: 8),
                              Text(
                                '$score',
                                style: const TextStyle(
                                  color: Colors.amberAccent,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CreateEventDialog extends ConsumerStatefulWidget {
  @override
  ConsumerState<_CreateEventDialog> createState() => _CreateEventDialogState();
}

class _CreateEventDialogState extends ConsumerState<_CreateEventDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _qCountCtrl = TextEditingController(text: '10');
  final _timeCtrl = TextEditingController(text: '15');
  final _maxCtrl = TextEditingController();

  DateTime _startTime = DateTime.now().add(const Duration(hours: 2));
  String _category = '';
  String _difficulty = '';
  bool _isFeatured = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _qCountCtrl.dispose();
    _timeCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF151A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Create Quiz Event',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              _field('Event Title', _titleCtrl, 'e.g. Easter Bible Bowl 2026'),
              const SizedBox(height: 12),
              _field('Description (optional)', _descCtrl, 'Details about the event', maxLines: 2),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _field('Questions', _qCountCtrl, '10',
                        keyboardType: TextInputType.number),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _field('Seconds/Q', _timeCtrl, '15',
                        keyboardType: TextInputType.number),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _field('Pass Price (ZMW, 0 = Free)', _priceCtrl, '0',
                  keyboardType: TextInputType.number),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _categoryDropdown()),
                  const SizedBox(width: 12),
                  Expanded(child: _difficultyDropdown()),
                ],
              ),
              const SizedBox(height: 12),
              // Start time picker
              GestureDetector(
                onTap: _pickDateTime,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(8),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withAlpha(20)),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.calendar, size: 16, color: Colors.white54),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('MMM d, yyyy · h:mm a').format(_startTime.toLocal()),
                        style: const TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Featured toggle
              Row(
                children: [
                  const Text('Feature this event',
                      style: TextStyle(color: Colors.white70, fontSize: 14)),
                  const Spacer(),
                  Switch(
                    value: _isFeatured,
                    onChanged: (v) => setState(() => _isFeatured = v),
                    activeThumbColor: Colors.amberAccent,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.greenAccent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black))
                      : const Text('Create Event',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, String hint,
      {int maxLines = 1, TextInputType? keyboardType}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 4),
        TextFormField(
          controller: ctrl,
          maxLines: maxLines,
          keyboardType: keyboardType,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white24),
            filled: true,
            fillColor: Colors.white.withAlpha(8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.white.withAlpha(20)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _categoryDropdown() {
    const cats = ['', 'General', 'People', 'History', 'NT', 'OT', 'Prophecy', 'Miracles', 'Scripture', 'Law'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Category', style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: _category,
          dropdownColor: const Color(0xFF151A2E),
          style: const TextStyle(color: Colors.white),
          items: cats.map((c) => DropdownMenuItem(
            value: c,
            child: Text(c.isEmpty ? 'All' : c),
          )).toList(),
          onChanged: (v) => setState(() => _category = v ?? ''),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white.withAlpha(8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.white.withAlpha(20)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _difficultyDropdown() {
    const diffs = ['', 'Hard'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Difficulty', style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: _difficulty,
          dropdownColor: const Color(0xFF151A2E),
          style: const TextStyle(color: Colors.white),
          items: diffs.map((d) => DropdownMenuItem(
            value: d,
            child: Text(d.isEmpty ? 'Any' : d),
          )).toList(),
          onChanged: (v) => setState(() => _difficulty = v ?? ''),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white.withAlpha(8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.white.withAlpha(20)),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startTime,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: Colors.amberAccent),
        ),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startTime),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: Colors.amberAccent),
        ),
        child: child!,
      ),
    );
    if (time == null || !mounted) return;

    setState(() {
      _startTime = DateTime(
        date.year, date.month, date.day, time.hour, time.minute,
      );
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);

    final svc = ref.read(quizEventServiceProvider);
    final err = await svc.createEvent(
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      passPriceZmw: double.tryParse(_priceCtrl.text) ?? 0,
      questionCount: int.tryParse(_qCountCtrl.text) ?? 10,
      timePerQuestionSec: int.tryParse(_timeCtrl.text) ?? 15,
      startTime: _startTime,
      endTime: _startTime.add(const Duration(hours: 2)),
      maxParticipants: int.tryParse(_maxCtrl.text),
      categoryFilter: _category.isEmpty ? null : _category,
      difficultyFilter: _difficulty.isEmpty ? null : _difficulty,
      isFeatured: _isFeatured,
    );

    if (mounted) {
      setState(() => _isSubmitting = false);
      if (err != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(err)));
      } else {
        Navigator.of(context).pop();
        ref.invalidate(allEventsProvider);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Event created!')));
      }
    }
  }
}
