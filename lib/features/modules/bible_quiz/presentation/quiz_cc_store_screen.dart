import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/remote_config.dart';
import '../../../../core/providers/profile_provider.dart';
import '../../../finance/presentation/buy_coins_screen.dart';
import '../data/quiz_event_service.dart';
import 'quiz_event_lobby_screen.dart';

/// All quiz-linked Church Coin transaction types.
const List<String> kQuizCoinTypes = [
  'quiz_tournament_wager',
  'quiz_tournament_pass',
  'quiz_engine_lease',
  'pvp_wager',
  'pvp_wager_refund',
];

/// History of this user's quiz CC activity (redemptions only).
final quizCcHistoryProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final uid = Supabase.instance.client.auth.currentUser?.id;
  if (uid == null) return const [];
  final res = await Supabase.instance.client
      .from('coin_redemptions')
      .select('amount, redemption_type, description, status, created_at')
      .eq('user_id', uid)
      .inFilter('redemption_type', kQuizCoinTypes)
      .order('created_at', ascending: false)
      .limit(50);
  return (res as List).cast<Map<String, dynamic>>();
});

class QuizCcStoreScreen extends ConsumerStatefulWidget {
  const QuizCcStoreScreen({super.key});

  @override
  ConsumerState<QuizCcStoreScreen> createState() => _QuizCcStoreScreenState();
}

class _QuizCcStoreScreenState extends ConsumerState<QuizCcStoreScreen> {
  bool _leasing = false;

  RemoteConfig get _rc => widgetRemoteConfig(ref);

  Future<void> _leaseEngine() async {
    if (_leasing) return;
    setState(() => _leasing = true);
    final ok = await ref
        .read(quizEventServiceProvider)
        .leaseQuizEngineCc();
    if (!mounted) return;
    setState(() => _leasing = false);
    ref.invalidate(profileProvider);
    ref.invalidate(quizCcHistoryProvider);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Quiz Engine leased! Host tournaments from the hub Events tab.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      showBuyCoinsSheet(
        context,
        reason: 'Not enough Church Coins to lease the Quiz Engine.',
      );
    }
  }

  void _buyCoins() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BuyCoinsScreen()),
    );
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'quiz_tournament_wager':
        return 'Tournament wager staked';
      case 'quiz_tournament_pass':
        return 'Tournament pass (CC)';
      case 'quiz_engine_lease':
        return 'Quiz Engine lease';
      case 'pvp_wager':
        return 'PvP wager / winnings';
      case 'pvp_wager_refund':
        return 'PvP wager refund';
      default:
        return type;
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).value;
    final coins = profile?.coins ?? 0;
    final prize1 = _rc.getInt('quiz_prize_1st_cc', 500);
    final prize2 = _rc.getInt('quiz_prize_2nd_cc', 300);
    final prize3 = _rc.getInt('quiz_prize_3rd_cc', 150);
    final leaseFee = _rc.getInt('quiz_lease_fee_cc', 1500);
    final history = ref.watch(quizCcHistoryProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(
          "QUIZ CC STORE",
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(profileProvider);
          ref.invalidate(quizCcHistoryProvider);
          await Future<void>.delayed(const Duration(milliseconds: 300));
        },
        color: Theme.of(context).primaryColor,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _balanceCard(coins, prize1, prize2, prize3),
            const SizedBox(height: 20),
            _sectionHeader(LucideIcons.shoppingCart, "BUY CC",
                "Get Church Coins with Mobile Money (MTN / Airtel / Zamtel) or card."),
            const SizedBox(height: 10),
            _buyCard(),
            const SizedBox(height: 24),
            _sectionHeader(LucideIcons.coins, "SPEND CC",
                "Everything bible quiz runs on Church Coins."),
            const SizedBox(height: 10),
            _spendCard(
              LucideIcons.crown,
              "Lease the Quiz Engine",
              "$leaseFee CC · host church yearly tournaments or personal events",
              "Lease now",
              onTap: _leaseEngine,
              busy: _leasing,
            ),
            _spendCard(
              LucideIcons.trophy,
              "Tournament wager",
              "Stake CC at join — 1st 50% · 2nd 30% · 3rd 20% of the pot",
              "Browse events",
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const QuizEventLobbyScreen()),
              ),
            ),
            _spendCard(
              LucideIcons.ticket,
              "Tournament pass (CC)",
              "Paid events: pay in CC from your wallet (1 CC ≈ K1) or Mobile Money",
              "Browse events",
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const QuizEventLobbyScreen()),
              ),
            ),
            _spendCard(
              LucideIcons.swords,
              "1v1 friend wagers",
              "Challenge a friend free or for 10–100 CC — winner takes 90%",
              "Go to hub",
              onTap: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 24),
            _sectionHeader(LucideIcons.gift, "EARN CC",
                "Play, win and get rewarded in Church Coins."),
            const SizedBox(height: 10),
            _earnRow('🥇', 'COA weekly 1st place', '$prize1 CC'),
            _earnRow('🥈', 'COA weekly 2nd place', '$prize2 CC'),
            _earnRow('🥉', 'COA weekly 3rd place', '$prize3 CC'),
            _earnRow('⚔️', 'PvP wager winnings', '90% of the pot'),
            _earnRow('📅', 'Daily challenge', '+10 CC per win'),
            _earnRow('📖', 'Daily open, streak & reading rewards', '5–30 CC'),
            const SizedBox(height: 24),
            _sectionHeader(LucideIcons.history, "MY QUIZ CC HISTORY",
                "All quiz wagers, passes, leases and winnings."),
            const SizedBox(height: 10),
            history.when(
              data: (rows) => rows.isEmpty
                  ? const _EmptyRow("No quiz CC transactions yet — play to start.")
                  : Column(
                      children: rows
                          .map((r) => _historyRow(r))
                          .toList(),
                    ),
              loading: () => Padding(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: Theme.of(context).primaryColor,
                        strokeWidth: 2),
                  ),
                ),
              ),
              error: (e, _) => _EmptyRow("Could not load history."),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _balanceCard(int coins, int prize1, int prize2, int prize3) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2A2F45), Color(0xFF151A2E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: Theme.of(context).primaryColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.coins,
                  color: Theme.of(context).primaryColor, size: 26),
              const SizedBox(width: 8),
              const Text(
                "CHURCH COIN BALANCE",
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$coins',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  "CC",
                  style: TextStyle(
                    color: Theme.of(context).primaryColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  "≈ K$coins",
                  style: const TextStyle(color: Colors.white38, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            "Weekly COA tournament: 1st $prize1 CC · 2nd $prize2 CC · 3rd $prize3 CC",
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _buyCoins,
              icon: const Icon(LucideIcons.smartphone, size: 16),
              label: const Text(
                "BUY CC",
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(IconData icon, String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Theme.of(context).primaryColor, size: 18),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                fontSize: 14,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buyCard() {
    final accent = Theme.of(context).primaryColor;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  "Packages from 100 to 2500 CC",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              TextButton(
                onPressed: _buyCoins,
                child: Text(
                  "OPEN BUY COINS",
                  style: TextStyle(
                    color: Theme.of(context).primaryColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            "Top up instantly, then use CC for engine leases, tournament passes, "
            "wagers and friend challenges.",
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _spendCard(
    IconData icon,
    String title,
    String subtitle,
    String action, {
    VoidCallback? onTap,
    bool busy = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Theme.of(context).primaryColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          busy
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      color: Theme.of(context).primaryColor, strokeWidth: 2),
                )
              : TextButton(
                  onPressed: onTap,
                  child: Text(
                    action,
                    style: TextStyle(
                      color: Theme.of(context).primaryColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _earnRow(String emoji, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: Theme.of(context).primaryColor,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyRow(Map<String, dynamic> r) {
    final amount = (r['amount'] as num?)?.toInt() ?? 0;
    final isCredit = amount > 0;
    final created = r['created_at']?.toString();
    final time = created != null
        ? DateFormat('dd MMM, HH:mm')
            .format(DateTime.tryParse(created) ?? DateTime.now())
        : '';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _typeLabel(r['redemption_type']?.toString() ?? ''),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  r['description']?.toString() ?? '',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isCredit ? '+' : ''}$amount CC',
                style: TextStyle(
                  color:
                      isCredit ? Colors.greenAccent : Theme.of(context).primaryColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
              Text(time,
                  style: const TextStyle(color: Colors.white38, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyRow extends StatelessWidget {
  final String message;
  const _EmptyRow(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
      ),
    );
  }
}
