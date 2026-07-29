import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shimmer/shimmer.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/widgets/premium_toast.dart';
import '../../../finance/data/finance_service.dart';
import '../../../finance/presentation/lipila_payment_gateway.dart';
import '../data/bible_quiz_service.dart';

class ChurchCompetitionLobbyScreen extends ConsumerStatefulWidget {
  final String? competitionId;
  final String? initialPin;

  const ChurchCompetitionLobbyScreen({
    super.key,
    this.competitionId,
    this.initialPin,
  });

  @override
  ConsumerState<ChurchCompetitionLobbyScreen> createState() => _ChurchCompetitionLobbyScreenState();
}

class _ChurchCompetitionLobbyScreenState extends ConsumerState<ChurchCompetitionLobbyScreen> {
  final _pinCtrl = TextEditingController();
  ChurchQuizCompetition? _competition;
  bool _isLoading = true;
  bool _hasPaid = false;
  bool _isVerifying = false;

  @override
  void initState() {
    super.initState();
    if (widget.competitionId != null) {
      _loadCompetition(widget.competitionId!);
    } else {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCompetition(String id) async {
    setState(() => _isLoading = true);
    final comp = await ref.read(bibleQuizServiceProvider).getCompetitionById(id);
    await _checkPayment(id);
    if (mounted) {
      setState(() {
        _competition = comp;
        _isLoading = false;
      });
    }
  }

  Future<void> _checkPayment(String competitionId) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      final existing = await Supabase.instance.client
          .from('quiz_competition_payments')
          .select('id')
          .eq('competition_id', competitionId)
          .eq('user_id', userId)
          .maybeSingle();
      if (existing != null && mounted) {
        setState(() => _hasPaid = true);
      }
    } catch (e) {
      debugPrint('Failed to check payment: $e');
    }
  }

  Future<void> _verifyPin() async {
    final pin = _pinCtrl.text.trim();
    if (pin.length != 6) {
      PremiumToast.showWarning(context, "Please enter a valid 6-digit PIN");
      return;
    }

    setState(() => _isVerifying = true);
    final compId = await ref.read(bibleQuizServiceProvider).verifyCompetitionPin(pin);
    if (compId != null) {
      await _loadCompetition(compId);
      if (!mounted) return;
      PremiumToast.showSuccess(context, "Joined competition successfully!", title: "Welcome");
    } else {
      if (mounted) {
        PremiumToast.showError(context, "Invalid or expired PIN. Please check and try again.");
      }
    }
    if (mounted) setState(() => _isVerifying = false);
  }

  void _payEntryFee() {
    if (_competition == null || _competition!.isFree) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => LipilaPaymentGateway(
        amount: _competition!.entryFee,
        description: "Entry Fee: ${_competition!.title}",
        category: "event",
        onComplete: (success, txId) {
          Navigator.pop(context);
          if (success) {
            _recordPayment(txId);
          }
        },
      ),
    );
  }

  Future<void> _recordPayment(String? txId) async {
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      if (_competition == null || userId == null) return;

      await supabase.from('quiz_competition_payments').insert({
        'competition_id': _competition!.id,
        'user_id': userId,
        'amount': _competition!.entryFee,
        'reference_id': txId,
        'status': 'completed',
      });

      await ref.read(financeServiceProvider).logTransaction(
        _competition!.entryFee,
        'event',
        txId ?? '',
      );

      if (mounted) {
        setState(() => _hasPaid = true);
        PremiumToast.showSuccess(context, "Entry fee paid! You can now join the quiz.", title: "Payment Received");
      }
    } catch (e) {
      debugPrint('Failed to record payment: $e');
      if (mounted) {
        PremiumToast.showError(context, "Payment recorded but failed to save. Contact support.");
      }
    }
  }

  void _startQuiz() {
    if (_competition == null) return;
    if (!_competition!.isFree && !_hasPaid) {
      PremiumToast.showWarning(context, "Please pay the entry fee before starting.");
      return;
    }

      context.push('/quiz/arena', extra: {
        'mode': 'Solo',
        'questionCount': _competition!.questionCount,
      });
  }

  void _shareCompetition() {
    if (_competition == null) return;
    SharePlus.instance.share(ShareParams(
      text: "Join my Church Bible Quiz Competition!\n\nTitle: ${_competition!.title}\nDate: ${DateFormat.yMMMd().add_jm().format(_competition!.date.toLocal())}\n\nDownload Church On App to participate!",
      subject: "Bible Quiz Competition Invitation",
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2C),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(
          _competition != null ? _competition!.title : "Join Competition",
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_competition != null)
            IconButton(
              icon: const Icon(LucideIcons.share2, color: Colors.white70),
              onPressed: _shareCompetition,
            ),
        ],
      ),
      body: _isLoading
          ? Shimmer.fromColors(
              baseColor: Colors.grey[300]!,
              highlightColor: Colors.grey[100]!,
              child: const Center(child: CircularProgressIndicator(color: Colors.amber)),
            )
          : _competition == null
              ? _buildPinEntry()
              : _buildCompetitionDetails(),
    );
  }

  Widget _buildPinEntry() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.greenAccent.withAlpha(15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.greenAccent.withAlpha(40)),
              ),
              child: const Icon(LucideIcons.radioTower, color: Colors.greenAccent, size: 60),
            ),
            const SizedBox(height: 25),
            const Text("Enter Competition PIN", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            const Text("Ask your church host for the 6-digit PIN", style: TextStyle(color: Colors.white54, fontSize: 14)),
            const SizedBox(height: 30),
            TextField(
              controller: _pinCtrl,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 32, letterSpacing: 10, fontWeight: FontWeight.w900),
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: InputDecoration(
                counterText: "",
                hintText: "000000",
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: Colors.white.withAlpha(10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isVerifying ? null : _verifyPin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                icon: _isVerifying
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(LucideIcons.logIn, size: 20),
                label: Text(_isVerifying ? "VERIFYING..." : "JOIN COMPETITION", style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompetitionDetails() {
    final comp = _competition!;
    final needsPayment = !comp.isFree && !_hasPaid;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF6A11CB), Color(0xFF2575FC)]),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: const Color(0xFF2575FC).withAlpha(80), blurRadius: 20, offset: const Offset(0, 10))],
            ),
            child: Column(
              children: [
                const Icon(LucideIcons.trophy, color: Colors.white, size: 48),
                const SizedBox(height: 12),
                Text(comp.title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                const SizedBox(height: 8),
                Text(DateFormat.yMMMd().add_jm().format(comp.date.toLocal()), style: const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 4),
                Text("${comp.questionCount} Questions", style: const TextStyle(color: Colors.white70, fontSize: 13)),
                if (comp.difficulty != null) ...[
                  const SizedBox(height: 4),
                  Text("Difficulty: ${comp.difficulty}", style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 25),

          // Status Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(8),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: comp.status == 'upcoming' ? Colors.amber.withAlpha(25) : Colors.greenAccent.withAlpha(25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    comp.status == 'upcoming' ? LucideIcons.clock : LucideIcons.checkCircle,
                    color: comp.status == 'upcoming' ? Colors.amber : Colors.greenAccent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(comp.status == 'upcoming' ? "Upcoming" : "Active", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                      Text(comp.isFree ? "Free Entry" : "K${comp.entryFee.toStringAsFixed(0)} Entry Fee", style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                ),
                if (comp.isFree)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.greenAccent.withAlpha(25), borderRadius: BorderRadius.circular(8)),
                    child: const Text("FREE", style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 30),

          // Action Buttons
          if (needsPayment) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _payEntryFee,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                icon: const Icon(LucideIcons.banknote, size: 20),
                label: Text("PAY ENTRY FEE (K${comp.entryFee.toStringAsFixed(0)})", style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              ),
            ),
            const SizedBox(height: 15),
          ],

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _startQuiz,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              icon: const Icon(LucideIcons.zap, size: 20),
              label: const Text("START QUIZ", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5)),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
