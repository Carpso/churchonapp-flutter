import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:church_on_app/core/config/remote_config.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/features/finance/presentation/lipila_payment_gateway.dart';
import 'package:church_on_app/features/modules/bible_quiz/data/quiz_event_service.dart';
import 'package:church_on_app/features/modules/bible_quiz/data/quiz_hosting_service.dart';

/// Church Quiz Hosting console.
///
/// Lets a church leadership team (a) lease the Quiz Engine, (b) upload their
/// own question paper and extract it into a set, and (c) create / run
/// tournaments (bracket, invites, spectator count). All server rules
/// (lease gating, tenant scoping, question-set ownership) live in the
/// SECURITY DEFINER RPCs — this screen is only the operator UI.
class QuizHostingScreen extends ConsumerStatefulWidget {
  const QuizHostingScreen({super.key});

  @override
  ConsumerState<QuizHostingScreen> createState() => _QuizHostingScreenState();
}

class _QuizHostingScreenState extends ConsumerState<QuizHostingScreen> {
  bool _busy = false;

  QuizHostingService get _service => ref.read(quizHostingServiceProvider);

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
        appBar: AppBar(title: const Text('Quiz Hosting')),
        body: const Center(child: Text('Church leadership only.')),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        appBar: AppBar(
          title: const Text('Quiz Hosting'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'LEASE', icon: Icon(LucideIcons.keyRound, size: 18)),
              Tab(text: 'SETS', icon: Icon(LucideIcons.fileText, size: 18)),
              Tab(text: 'TOURNEYS', icon: Icon(LucideIcons.trophy, size: 18)),
            ],
          ),
          actions: [
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
        body: TabBarView(
          children: [
            _leaseTab(theme),
            _setsTab(theme),
            _tournamentsTab(theme),
          ],
        ),
      ),
    );
  }

  // ── Lease tab ─────────────────────────────────────────────────────────────
  Widget _leaseTab(ThemeData theme) {
    final leaseAsync = ref.watch(quizLeaseProvider);
    final canHostAsync = ref.watch(quizCanHostProvider);
    final feeKwacha = widgetRemoteConfig(ref).getInt('quiz_engine_lease_kwacha', 1500);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(quizLeaseProvider);
        ref.invalidate(quizCanHostProvider);
      },
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          leaseAsync.when(
            data: (lease) {
              if (lease != null && lease.isActive) {
                final days = lease.endsAt.difference(DateTime.now()).inDays;
                return Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      theme.primaryColor,
                      theme.primaryColor.withValues(alpha: 0.75),
                    ]),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(LucideIcons.shieldCheck,
                              color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Text('QUIZ ENGINE LEASED',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                  letterSpacing: 1)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(lease.seasonLabel ?? 'Active season',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      Text('$days day(s) left · renews on '
                          '${lease.endsAt.day}/${lease.endsAt.month}/${lease.endsAt.year}',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                );
              }
              return Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(LucideIcons.lock,
                            size: 18, color: theme.colorScheme.onSurface),
                        const SizedBox(width: 8),
                        const Text('NO ACTIVE LEASE',
                            style: TextStyle(
                                fontWeight: FontWeight.w900, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Hosting requires an active Quiz Engine lease. '
                      'Members may still compete in other churches\' tournaments.',
                      style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6)),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _leaseWithCc,
                        icon: const Icon(LucideIcons.coins),
                        label: Text('LEASE WITH $feeKwacha CC'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _leaseWithKwacha,
                        icon: const Icon(LucideIcons.banknote),
                        label: Text('I PAID K$feeKwacha — ACTIVATE'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _payAndLease(feeKwacha.toDouble()),
                        icon: const Icon(LucideIcons.creditCard),
                        label: Text('PAY K$feeKwacha (Mobile Money / Card)'),
                      ),
                    ),
                  ],
                ),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('Could not load lease: $e'),
          ),
          const SizedBox(height: 16),
          canHostAsync.when(
            data: (can) => Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: (can ? Colors.green : Colors.orange).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(can ? LucideIcons.checkCircle2 : LucideIcons.alertTriangle,
                      size: 18,
                      color: can ? Colors.green : Colors.orange),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      can
                          ? 'Your church can host tournaments.'
                          : 'Lease the engine to create tournaments.',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            loading: () => const SizedBox.shrink(),
            error: (e, _) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Future<void> _leaseWithCc() async {
    setState(() => _busy = true);
    try {
      final ok = await ref.read(quizEventServiceProvider).leaseQuizEngineCc();
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Not enough Church Coins. Top up from the CC Store.'),
            backgroundColor: Colors.orange));
        return;
      }
      // Record the lease row so hosting works from both payment paths.
      await _service.leaseWithKwacha(seasonLabel: 'Church Coins season');
      ref.invalidate(quizLeaseProvider);
      ref.invalidate(quizCanHostProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Quiz Engine leased!'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Lease failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leaseWithKwacha() async {
    setState(() => _busy = true);
    try {
      final res = await _service.leaseWithKwacha();
      if (!mounted) return;
      if (res['leased'] == true) {
        ref.invalidate(quizLeaseProvider);
        ref.invalidate(quizCanHostProvider);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Quiz Engine activated!'),
            backgroundColor: Colors.green));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(res['reason'] == 'payment_required'
                ? 'No confirmed K${res['fee_kwacha'] ?? ''} payment found yet. '
                    'It activates automatically once payment is confirmed.'
                : 'Could not activate: ${res['reason'] ?? 'unknown'}')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Collects the lease fee in-app (MTN/Airtel/Zamtel MoMo or card) via the
  /// Lipila gateway. `lipila-collect` pre-creates the pending `coa_payments`
  /// row for this user, and confirms it on the provider callback — at which
  /// point `lease_quiz_engine` (below) records the lease row. No operator
  /// action and no payment made "elsewhere" are required.
  Future<void> _payAndLease(double fee) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => LipilaPaymentGateway(
        amount: fee,
        description: 'Quiz Engine season lease',
        category: 'quiz_engine_lease',
        recipientName: 'Church On App',
        paymentReason: 'Quiz Engine lease',
        onComplete: (success, txId) async {
          Navigator.pop(sheetCtx);
          if (!success || txId == null) return;
          setState(() => _busy = true);
          try {
            final res = await _service.leaseWithKwacha(
              paymentRef: txId,
              seasonLabel: 'Season ${DateTime.now().year}',
            );
            ref.invalidate(quizLeaseProvider);
            ref.invalidate(quizCanHostProvider);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(res['leased'] == true
                  ? 'Quiz Engine leased!'
                  : 'Payment received — activating… pull to refresh in a moment.'),
              backgroundColor:
                  res['leased'] == true ? Colors.green : Colors.orange,
            ));
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text('Activation failed: $e')));
            }
          } finally {
            if (mounted) setState(() => _busy = false);
          }
        },
      ),
    );
  }

  // ── Sets tab ──────────────────────────────────────────────────────────────
  Widget _setsTab(ThemeData theme) {
    final setsAsync = ref.watch(quizSetsProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'newSetFab',
        onPressed: _busy ? null : _createSet,
        backgroundColor: theme.primaryColor,
        foregroundColor: Colors.black,
        icon: const Icon(LucideIcons.plus),
        label: const Text('NEW SET',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(quizSetsProvider),
        child: setsAsync.when(
          data: (sets) {
            if (sets.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: 100),
                  const Icon(LucideIcons.fileText,
                      size: 48, color: Colors.grey),
                  const SizedBox(height: 12),
                  const Center(
                      child: Text('No question sets yet',
                          style: TextStyle(color: Colors.grey))),
                  const SizedBox(height: 16),
                  Center(
                    child: FilledButton.icon(
                      onPressed: _createSet,
                      icon: const Icon(LucideIcons.plus),
                      label: const Text('UPLOAD YOUR FIRST PAPER'),
                    ),
                  ),
                ],
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              itemCount: sets.length,
              itemBuilder: (_, i) => _setCard(theme, sets[i]),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Could not load sets: $e')),
        ),
      ),
    );
  }

  Widget _setCard(ThemeData theme, QuizQuestionSet s) {
    final (color, label) = switch (s.extractStatus) {
      'ready' => (Colors.green, 'READY'),
      'processing' => (Colors.orange, 'PROCESSING'),
      'failed' => (Colors.red, 'FAILED'),
      _ => (Colors.grey, 'PENDING'),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
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
              Expanded(
                child: Text(s.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(label,
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        color: color)),
              ),
              PopupMenuButton<String>(
                icon: const Icon(LucideIcons.moreVertical, size: 18),
                onSelected: (v) => _setAction(s, v),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'upload', child: Text('Upload paper')),
                  PopupMenuItem(value: 'questions', child: Text('View questions')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          Text('${s.extractedCount} questions'
              '${(s.sourceFileName ?? '').isNotEmpty ? ' · ${s.sourceFileName}' : ''}',
              style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55))),
          if ((s.extractError ?? '').isNotEmpty)
            Text(s.extractError!,
                style: const TextStyle(fontSize: 10, color: Colors.red),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(LucideIcons.bookOpen,
                  size: 14,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
              const SizedBox(width: 6),
              const Expanded(
                  child: Text('Study pack visible to participants',
                      style: TextStyle(fontSize: 11))),
              Switch(
                value: s.studyPackOpen,
                onChanged: (v) async {
                  await _service.updateStudyPack(s.id, v);
                  ref.invalidate(quizSetsProvider);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _setAction(QuizQuestionSet s, String action) async {
    if (action == 'upload') {
      await _uploadPaper(s);
    } else if (action == 'questions') {
      context.push('/quiz-hosting/questions/${s.id}', extra: s.title);
    } else if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Delete "${s.title}"?'),
          content: const Text('Its questions will be removed.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('CANCEL')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child:
                    const Text('DELETE', style: TextStyle(color: Colors.red))),
          ],
        ),
      );
      if (ok == true) {
        await _service.deleteSet(s.id);
        ref.invalidate(quizSetsProvider);
      }
    }
  }

  Future<void> _createSet() async {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New question set'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                    labelText: 'Title', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(
                controller: descCtrl,
                decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          FilledButton(
            onPressed: () {
              if (titleCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, titleCtrl.text.trim());
            },
            child: const Text('CREATE'),
          ),
        ],
      ),
    );
    titleCtrl.dispose();
    descCtrl.dispose();
    if (title == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final id = await _service.createSet(title);
      ref.invalidate(quizSetsProvider);
      if (id == null || !mounted) return;
      final fresh = await _service.fetchSets();
      final created = fresh.where((s) => s.id == id).firstOrNull;
      if (created != null) await _uploadPaper(created);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uploadPaper(QuizQuestionSet s) async {
    final textCtrl = TextEditingController();
    Uint8List? bytes;
    String? fileName;
    var useText = true;

    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Import into "${s.title}"',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text(
                  'Upload a PDF, DOCX, TXT or CSV paper — text is extracted '
                  'automatically. Scanned/image PDFs must be pasted as text.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 14),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Paste text')),
                    ButtonSegment(value: false, label: Text('Upload file')),
                  ],
                  selected: {useText},
                  onSelectionChanged: (v) => setLocal(() => useText = v.first),
                ),
                const SizedBox(height: 14),
                if (useText)
                  TextField(
                    controller: textCtrl,
                    maxLines: 8,
                    decoration: const InputDecoration(
                        hintText: 'Paste your questions here…',
                        border: OutlineInputBorder()),
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          final res = await FilePicker.pickFiles(
                            type: FileType.custom,
                            allowedExtensions: [
                              'txt',
                              'csv',
                              'md',
                              'pdf',
                              'doc',
                              'docx',
                            ],
                            withData: true,
                          );
                          if (res == null || res.files.isEmpty) return;
                          final f = res.files.single;
                          setLocal(() {
                            bytes = f.bytes;
                            fileName = f.name;
                          });
                        },
                        icon: const Icon(LucideIcons.upload),
                        label: Text(fileName ?? 'CHOOSE FILE'),
                      ),
                      const SizedBox(height: 6),
                      const Text('Supported: txt, csv, md, pdf, doc, docx',
                          style: TextStyle(fontSize: 10, color: Colors.grey)),
                    ],
                  ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      if (useText && textCtrl.text.trim().isEmpty) return;
                      if (!useText && bytes == null) return;
                      Navigator.pop(ctx, true);
                    },
                    style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 52)),
                    child: const Text('EXTRACT QUESTIONS'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final text = textCtrl.text.trim();
    textCtrl.dispose();
    if (go != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final res = await _service.uploadAndExtract(
        setId: s.id,
        pastedText: useText ? text : null,
        bytes: useText ? null : bytes,
        fileName: useText ? null : fileName,
      );
      ref.invalidate(quizSetsProvider);
      final inserted = res['inserted'] ?? 0;
      final errors = (res['errors'] as List?)?.isNotEmpty == true
          ? '\n${(res['errors'] as List).first}'
          : '';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Extracted $inserted question(s).$errors'),
          backgroundColor: inserted == 0 ? Colors.orange : Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Import failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Tournaments tab ───────────────────────────────────────────────────────
  Widget _tournamentsTab(ThemeData theme) {
    final tAsync = ref.watch(quizTournamentsProvider);
    final invitesAsync = ref.watch(quizTournamentInvitesProvider);
    final canHost = ref.watch(quizCanHostProvider).value ?? false;
    final myTid = ref.watch(profileProvider).value?.tenantId;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'newTourneyFab',
        onPressed: (!canHost || _busy)
            ? null
            : () => _createTournament(theme),
        backgroundColor: canHost ? theme.primaryColor : Colors.grey,
        foregroundColor: Colors.black,
        icon: const Icon(LucideIcons.plus),
        label: const Text('NEW TOURNEY',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(quizTournamentsProvider);
          ref.invalidate(quizTournamentInvitesProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            invitesAsync.maybeWhen(
              data: (inv) {
                if (inv.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('INVITATIONS',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                            color: Colors.grey)),
                    const SizedBox(height: 8),
                    ...inv.map((i) => _inviteCard(theme, i)),
                    const SizedBox(height: 18),
                  ],
                );
              },
              orElse: () => const SizedBox.shrink(),
            ),
            tAsync.when(
              data: (list) {
                if (list.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 60),
                    child: Center(
                        child: Text('No tournaments yet',
                            style: TextStyle(color: Colors.grey))),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('TOURNAMENTS',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                            color: Colors.grey)),
                    const SizedBox(height: 8),
                    ...list.map((t) => _tournamentCard(theme, t, myTid)),
                  ],
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text('Could not load tournaments: $e'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _inviteCard(ThemeData theme, QuizTournamentInvite i) {
    if (i.status == 'declined') return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.mail, size: 18, color: Colors.orange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Invited to ${i.tournamentTitle ?? 'a tournament'} (${i.status})',
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          if (i.status == 'invited') ...[
            TextButton(
                onPressed: () => _respondInvite(i, false),
                child: const Text('DECLINE')),
            FilledButton(
                onPressed: () => _respondInvite(i, true),
                child: const Text('ACCEPT')),
          ],
        ],
      ),
    );
  }

  Future<void> _respondInvite(QuizTournamentInvite i, bool accept) async {
    setState(() => _busy = true);
    try {
      await _service.respondInvite(i.tournamentId, accept);
      if (accept) await _service.joinTournament(i.tournamentId);
      ref.invalidate(quizTournamentInvitesProvider);
      ref.invalidate(quizTournamentsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _tournamentCard(
      ThemeData theme, QuizTournament t, String? myTid) {
    final isHost = t.hostTenantId == myTid;
    final (color, label) = switch (t.status) {
      'live' => (Colors.red, 'LIVE'),
      'scheduled' => (Colors.blue, 'SCHEDULED'),
      'completed' => (Colors.green, 'COMPLETED'),
      'cancelled' => (Colors.grey, 'CANCELLED'),
      _ => (Colors.orange, 'DRAFT'),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
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
              Expanded(
                child: Text(t.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14)),
              ),
              if (isHost)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                      color: theme.primaryColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6)),
                  child: Text('HOST',
                      style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          color: theme.primaryColor)),
                ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(label,
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        color: color)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${t.visibility.toUpperCase()} · ${t.questionCount} Qs · '
            '${t.timePerQuestion}s',
            style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (isHost && (t.status == 'draft' || t.status == 'scheduled'))
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : () => _startTournament(t),
                  icon: const Icon(LucideIcons.play, size: 16),
                  label: const Text('START'),
                ),
              if (isHost &&
                  (t.status == 'live' || t.status == 'scheduled'))
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _generateBracket(t),
                  icon: const Icon(LucideIcons.network, size: 16),
                  label: const Text('BRACKET'),
                ),
              OutlinedButton.icon(
                onPressed: () => context.push(
                    '/quiz-hosting/bracket/${t.id}',
                    extra: {'title': t.title, 'isHost': isHost}),
                icon: const Icon(LucideIcons.eye, size: 16),
                label: const Text('VIEW'),
              ),
              if (!isHost && t.status != 'completed')
                FilledButton.tonalIcon(
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          try {
                            await _service.joinTournament(t.id);
                            ref.invalidate(quizTournamentsProvider);
                          } finally {
                            if (mounted) setState(() => _busy = false);
                          }
                        },
                  icon: const Icon(LucideIcons.userPlus, size: 16),
                  label: const Text('JOIN'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _startTournament(QuizTournament t) async {
    setState(() => _busy = true);
    try {
      await _service.startTournament(t.id);
      await _service.generateBracket(t.id);
      ref.invalidate(quizTournamentsProvider);
      ref.invalidate(quizBracketProvider(t.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tournament is live!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not start: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _generateBracket(QuizTournament t) async {
    setState(() => _busy = true);
    try {
      final n = await _service.generateBracket(t.id);
      ref.invalidate(quizBracketProvider(t.id));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Bracket: $n match(es)')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createTournament(ThemeData theme) async {
    final sets = ref.read(quizSetsProvider).value ?? const <QuizQuestionSet>[];
    final tenants =
        await ref.read(quizHostingServiceProvider).fetchInvitableTenants();
    if (!mounted) return;

    final titleCtrl = TextEditingController();
    String? setId = sets.isNotEmpty ? sets.first.id : null;
    var visibility = 'tenant';
    var format = 'knockout';
    var questionCount = 10;
    var timePerQuestion = 15;
    final invited = <String>{};

    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('New tournament',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 14),
                TextField(
                  controller: titleCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                      labelText: 'Title', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                if (sets.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: setId,
                    decoration: const InputDecoration(
                        labelText: 'Question set',
                        border: OutlineInputBorder()),
                    items: sets
                        .map((s) => DropdownMenuItem(
                              value: s.id,
                              child: Text('${s.title} (${s.extractedCount})'),
                            ))
                        .toList(),
                    onChanged: (v) => setLocal(() => setId = v),
                  )
                else
                  const Text('Create a question set first.',
                      style: TextStyle(fontSize: 12, color: Colors.orange)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: visibility,
                        decoration: const InputDecoration(
                            labelText: 'Who can see',
                            border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(
                              value: 'tenant', child: Text('My church')),
                          DropdownMenuItem(
                              value: 'invited', child: Text('Invited')),
                          DropdownMenuItem(
                              value: 'public', child: Text('Public')),
                        ],
                        onChanged: (v) =>
                            setLocal(() => visibility = v ?? 'tenant'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: format,
                        decoration: const InputDecoration(
                            labelText: 'Format',
                            border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(
                              value: 'knockout', child: Text('Knockout')),
                          DropdownMenuItem(
                              value: 'roundRobin', child: Text('Round robin')),
                          DropdownMenuItem(
                              value: 'single', child: Text('Single')),
                        ],
                        onChanged: (v) =>
                            setLocal(() => format = v ?? 'knockout'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: questionCount.toString(),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Questions',
                            border: OutlineInputBorder()),
                        onChanged: (v) => questionCount =
                            int.tryParse(v) ?? questionCount,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        initialValue: timePerQuestion.toString(),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Seconds/question',
                            border: OutlineInputBorder()),
                        onChanged: (v) => timePerQuestion =
                            int.tryParse(v) ?? timePerQuestion,
                      ),
                    ),
                  ],
                ),
                if (visibility == 'invited' && tenants.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text('Invite churches',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: SingleChildScrollView(
                      child: Column(
                        children: tenants.map((t) {
                          final id = t['id'].toString();
                          return CheckboxListTile(
                            dense: true,
                            value: invited.contains(id),
                            title: Text(t['name']?.toString() ?? 'Church',
                                style: const TextStyle(fontSize: 13)),
                            onChanged: (v) => setLocal(() {
                              if (v == true) {
                                invited.add(id);
                              } else {
                                invited.remove(id);
                              }
                            }),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      if (titleCtrl.text.trim().isEmpty) return;
                      Navigator.pop(ctx, true);
                    },
                    style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 52)),
                    child: const Text('CREATE TOURNAMENT'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final title = titleCtrl.text.trim();
    titleCtrl.dispose();
    if (created != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await _service.createTournament(
        title: title,
        questionSetId: setId,
        visibility: visibility,
        format: format,
        questionCount: questionCount,
        timePerQuestion: timePerQuestion,
        invitedTenants: visibility == 'invited' ? invited.toList() : null,
      );
      ref.invalidate(quizTournamentsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tournament created')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not create: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
