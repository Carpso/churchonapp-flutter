import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/providers/profile_provider.dart';
import '../../../../core/services/tenant_service.dart';
import '../data/bible_quiz_service.dart';
import '../data/daily_challenge_service.dart';
import '../data/xp_service.dart';
import 'bible_quiz_arena_screen.dart';
import 'quiz_event_lobby_screen.dart';


class BibleQuizHubScreen extends ConsumerStatefulWidget {
  const BibleQuizHubScreen({super.key});

  @override
  ConsumerState<BibleQuizHubScreen> createState() => _BibleQuizHubScreenState();
}

class _BibleQuizHubScreenState extends ConsumerState<BibleQuizHubScreen> {
  String _trophyTitle = 'THE CHURCH ON APP TROPHY';
  String _trophySubtitle = 'Weekly Global Bible Contest — Win Glory & Rewards';
  String _currentSeason = 'SEASON 2026: THE GOSPELS';
  int _weekNumber = 1;

  @override
  void initState() {
    super.initState();
    _loadTrophyConfig();
  }

  Future<void> _loadTrophyConfig() async {
    try {
      final res = await Supabase.instance.client
          .from('app_config')
          .select('value')
          .eq('key', 'trophy_config')
          .maybeSingle();
      if (res != null && mounted) {
        final config = res['value'] as Map<String, dynamic>?;
        if (config != null) {
          setState(() {
            _trophyTitle = config['title'] ?? _trophyTitle;
            _trophySubtitle = config['subtitle'] ?? _trophySubtitle;
            _currentSeason = config['season'] ?? _currentSeason;
            _weekNumber = config['week'] ?? _weekNumber;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading quiz config: $e');
    }
  }

  void _startP2P(String mode) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => BibleQuizArenaScreen(mode: mode)));
  }

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(currentTenantProvider);
    if (tenant != null && tenant.isSubscriptionExpired) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0E1A),
        appBar: AppBar(title: const Text("Global Bible Quiz"), centerTitle: true),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.lock, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                const Text("Church Subscription Expired", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text("Your church's subscription has expired. Contact your church admin to renew.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
              ],
            ),
          ),
        ),
      );
    }

    // Wire XP service into bible quiz feature lifecycle
    ref.watch(xpServiceProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1117),
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text("Global Bible Quiz", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5, color: Colors.white)),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(quizLeaderboardProvider);
          await _loadTrophyConfig();
        },
        child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(25),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF6A11CB), Color(0xFF2575FC)]),
                borderRadius: BorderRadius.circular(25),
                boxShadow: [BoxShadow(color: const Color(0xFF2575FC).withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 10))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)),
                        child: const Text("WORLD-CLASS STANDARD", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                      ),
                      const Spacer(),
                      const Icon(LucideIcons.globe, color: Colors.white70, size: 20),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text("International\nBible Quizzing", style: TextStyle(color: Colors.white, fontSize: 32, height: 1.1, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  const Text("Play individually, join global arenas, or host church tournaments.", style: TextStyle(color: Colors.white70, fontSize: 14)),
                  const SizedBox(height: 25),
                  ElevatedButton.icon(
                    onPressed: _showJoinLiveModal,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF2575FC),
                      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                    icon: const Icon(LucideIcons.radioTower, size: 18),
                    label: const Text("JOIN LIVE EVENT", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                  )
                ],
              ),
            ),
            const SizedBox(height: 30),

            const Text("GAME MODES", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 1.5, fontSize: 12)),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(child: _buildModeCard("Solo Play", "Engine Generated", LucideIcons.smartphone, Colors.orangeAccent, _startSoloPlay)),
                const SizedBox(width: 15),
                Expanded(child: _buildModeCard("World Rank", "Global Leaderboard", LucideIcons.trophy, Colors.amber, _showLeaderboard)),
              ],
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(child: _buildModeCard("Learning Mode", "No Timer, Study", LucideIcons.bookOpen, Colors.greenAccent, _startLearningMode)),
                const SizedBox(width: 15),
                Expanded(child: _buildModeCard("Daily Challenge", "Daily Questions", LucideIcons.calendar, Colors.pinkAccent, _startDailyChallenge)),
              ],
            ),
            const SizedBox(height: 30),

            const Text("P2P MULTIPLAYER ARENA", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 1.5, fontSize: 12)),
            const SizedBox(height: 15),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 15,
              crossAxisSpacing: 15,
              childAspectRatio: 1.5,
              children: [
                _buildP2PCard("Any User", "Global Match", LucideIcons.users, Colors.blueAccent, () => _startP2P("Global")),
                _buildP2PCard("My Church", "Local Members", LucideIcons.home, Colors.greenAccent, () => _startP2P("Church")),
                _buildP2PCard("Random", "Instant Play", LucideIcons.shuffle, Colors.purpleAccent, () => _startP2P("Random")),
                _buildP2PCard("Any COA User", "Public Match", LucideIcons.globe, Colors.pinkAccent, () => _startP2P("Any COA")),
              ],
            ),
            const SizedBox(height: 15),
            GestureDetector(
              onTap: _showInviteFriend,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withAlpha(20),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.blueAccent.withAlpha(50)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LucideIcons.userPlus, color: Colors.blueAccent, size: 20),
                    const SizedBox(width: 10),
                    Text("Invite a Friend to PvP", style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
              ),
            ),

            // UPCI-style question formats (anonymized)
            const SizedBox(height: 30),
            // Premium Events
            const SizedBox(height: 24),
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const QuizEventLobbyScreen()),
                );
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.greenAccent.withAlpha(30),
                      Colors.tealAccent.withAlpha(15),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.greenAccent.withAlpha(50)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withAlpha(25),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(LucideIcons.trophy, color: Colors.greenAccent, size: 24),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Premium Quiz Events',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Compete for prizes • Hosted by churches • Buy a pass & play',
                            style: TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    Icon(LucideIcons.chevronRight, color: Colors.greenAccent, size: 20),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),

            const Text("STANDARDIZED QUESTION FORMATS", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 1.5, fontSize: 12)),
            const SizedBox(height: 15),
            SizedBox(
              height: 140,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildFormatCard("Interrogative", "According to...", LucideIcons.helpCircle, Colors.blueAccent),
                  const SizedBox(width: 15),
                  _buildFormatCard("Quotation", "Quote...", LucideIcons.quote, Colors.greenAccent),
                  const SizedBox(width: 15),
                  _buildFormatCard("Chapter & Verse", "In what chapter...", LucideIcons.bookOpen, Colors.purpleAccent),
                  const SizedBox(width: 15),
                  _buildFormatCard("Multiple Answer", "Give a complete answer...", LucideIcons.listOrdered, Colors.orangeAccent),
                ],
              ),
            ),

            const SizedBox(height: 30),
            const Text("ENTERPRISE & HOSTING", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 1.5, fontSize: 12)),
            const SizedBox(height: 15),
            
            // Leasing Card
            _buildActionTile(
              "Host a Quiz Tournament",
              "Lease the engine to host a live church event.",
              LucideIcons.presentation,
              Colors.tealAccent,
              _showLeaseModal,
            ),
            
            // Admin Question Seeding (Restricted)
            if (ref.watch(profileProvider).value?.isEmployee == true) ...[
                  const SizedBox(height: 15),
                  _buildActionTile(
                    "Superadmin: AI Question Seeding",
                    "Extract canonical questions via AI",
                    LucideIcons.sparkles,
                    Colors.pinkAccent,
                    _showAiSeedingModal,
                  ),
                ],
                const SizedBox(height: 30),
                _buildTournamentBanner(context),
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildTournamentBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFFFD700), Color(0xFFFF8C00)]),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Colors.amber.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Icon(LucideIcons.crown, color: Colors.white, size: 40),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)),
                child: Text(_currentSeason, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(_trophyTitle, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
            child: Text("Week $_weekNumber — 12 weeks remaining", style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 8),
          Text(_trophySubtitle, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 25),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const BibleQuizArenaScreen(mode: 'Solo', questionCount: 20),
                    ));
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.deepOrange,
                    minimumSize: const Size(double.infinity, 55),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  child: const Text("ENTER THE ARENA", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _showLeaderboard,
                  icon: const Icon(LucideIcons.barChart3, size: 16, color: Colors.white),
                  label: const Text("LEADERBOARD", style: TextStyle(color: Colors.white)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white38),
                    minimumSize: const Size(double.infinity, 55),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                onPressed: () => _showTrophyInfo(context),
                icon: const Icon(LucideIcons.info, color: Colors.white54, size: 20),
              ),
            ],
          ),
          // Superadmin edit button
          if (ref.watch(profileProvider).value?.isEmployee == true) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _showEditTrophyDialog,
              icon: const Icon(LucideIcons.settings, color: Colors.white54, size: 16),
              label: const Text("Edit Trophy Settings", style: TextStyle(color: Colors.white54, fontSize: 12)),
            ),
          ],
        ],
      ),
    );
  }

  void _showEditTrophyDialog() {
    final titleCtrl = TextEditingController(text: _trophyTitle);
    final subtitleCtrl = TextEditingController(text: _trophySubtitle);
    final seasonCtrl = TextEditingController(text: _currentSeason);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Trophy Settings"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: "Trophy Title", border: OutlineInputBorder()), style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(controller: subtitleCtrl, decoration: const InputDecoration(labelText: "Subtitle", border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: seasonCtrl, decoration: const InputDecoration(labelText: "Season Label", border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final newTitle = titleCtrl.text.trim();
              final newSub = subtitleCtrl.text.trim();
              final newSeason = seasonCtrl.text.trim();
              if (newTitle.isEmpty) return;
              await Supabase.instance.client.from('app_config').upsert({
                'key': 'trophy_config',
                'value': {
                  'title': newTitle,
                  'subtitle': newSub,
                  'season': newSeason,
                  'week': _weekNumber,
                },
              });
              if (mounted) {
                setState(() {
                  _trophyTitle = newTitle;
                  _trophySubtitle = newSub;
                  _currentSeason = newSeason;
                });
              }
            },
            child: const Text("SAVE"),
          ),
        ],
      ),
    );
  }

  void _showTrophyInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.trophy, color: Colors.amber, size: 60),
            const SizedBox(height: 20),
            const Text("Church On App Trophy", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
            const SizedBox(height: 8),
            const Text("Weekly prizes await the top contenders!\nAnswer fast, answer right, climb the ranks.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(15)),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Column(children: [Text("🥇", style: TextStyle(fontSize: 28)), Text("K500", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold))]),
                  Column(children: [Text("🥈", style: TextStyle(fontSize: 28)), Text("K300", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold))]),
                  Column(children: [Text("🥉", style: TextStyle(fontSize: 28)), Text("K150", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold))]),
                ],
              ),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("CLOSE", style: TextStyle(color: Colors.white54)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildP2PCard(String title, String subtitle, IconData icon, Color iconColor, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: iconColor.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(height: 10),
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildModeCard(String title, String subtitle, IconData icon, Color iconColor, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: iconColor)),
            const SizedBox(height: 15),
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _buildFormatCard(String title, String subtitle, IconData icon, Color iconColor) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: iconColor.withValues(alpha: 0.2)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 10, offset: const Offset(0, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 28),
          const Spacer(),
          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildActionTile(String title, String subtitle, IconData icon, Color iconColor, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(15)), child: Icon(icon, color: iconColor, size: 24)),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
            const Icon(LucideIcons.chevronRight, color: Colors.white24)
          ],
        ),
      ),
    );
  }

  void _showJoinLiveModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: EdgeInsets.only(left: 25, right: 25, top: 30, bottom: MediaQuery.of(context).viewInsets.bottom + 30),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.radioTower, color: Colors.white, size: 50),
            const SizedBox(height: 15),
            const Text("Enter Match PIN", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
            const Text("Join a live tournament hosted by a church.", style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 30),
            TextField(
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 32, letterSpacing: 10, fontWeight: FontWeight.w900),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: "000000",
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: Colors.black26,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2575FC),
                minimumSize: const Size(double.infinity, 60),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              child: const Text("ENTER ARENA", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
            )
          ],
        ),
      )
    );
  }

  void _showLeaseModal() {
    bool isUsd = false;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return Container(
            padding: const EdgeInsets.all(25),
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(child: Text("Lease Quizzing Engine", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900))),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text("ZMW", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                        Switch(value: isUsd, activeThumbColor: Colors.green, onChanged: (v) => setState(() => isUsd = v)),
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Text("USD", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                        ),
                      ],
                    )
                  ],
                ),
                const Text("Pay Church On App to host an internationally standardized Bible Quiz for your church. Supports 500+ live mobile players.", style: TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 25),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.blue.shade100)),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.crown, color: Colors.blue, size: 30),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Premium Event Pass", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            const Text("1 Live Event • Active Leaderboard • Custom Questions", style: TextStyle(color: Colors.grey, fontSize: 11)),
                            const SizedBox(height: 5),
                            Text(isUsd ? "\$ 50.00 USD" : "K 1,500.00 ZMW", style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.blue, fontSize: 18)),
                          ],
                        ),
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Processing Lease Payment...")));
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    minimumSize: const Size(double.infinity, 60),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  child: const Text("PROCEED TO CHECKOUT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                )
              ],
            ),
          );
        }
      )
    );
  }

  void _showAiSeedingModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(LucideIcons.brainCircuit, color: Colors.pinkAccent),
                SizedBox(width: 10),
                Text("AI Question Seeding", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
              ],
            ),
            const Text("Only Superadmins and COA Employees", style: TextStyle(color: Colors.white54, fontSize: 12)),
            const Divider(color: Colors.white10, height: 30),
            
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10, style: BorderStyle.none)),
              child: const Column(
                children: [
                  Icon(LucideIcons.fileText, size: 40, color: Colors.white54),
                  SizedBox(height: 10),
                  Text("Upload Theological Documents (PDF/Docx)", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                  Text("AI will extract and format into interogative, quotation, and multiple answer standards.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white30, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text("OR Generate From Database", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            TextField(
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "e.g. Generate 50 questions on the Book of Acts...",
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: Colors.black26,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("AI Engine Processing & Seeding DB...")));
                await ref.read(bibleQuizServiceProvider).seedQuestions();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Database seeded with 200+ canonical questions! 🚀")));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.pinkAccent,
                minimumSize: const Size(double.infinity, 60),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              icon: const Icon(LucideIcons.sparkles, color: Colors.white),
              label: const Text("GENERATE & SEED DB", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            )
          ],
        ),
      )
    );
  }

  void _startSoloPlay() {
    Navigator.push(context, MaterialPageRoute(builder: (context) => const BibleQuizArenaScreen(mode: "Solo")));
  }

  void _startLearningMode() {
    Navigator.push(context, MaterialPageRoute(
      builder: (context) => const BibleQuizArenaScreen(
        mode: "Solo",
        timePerQuestionSec: 999,
        questionCount: 15,
      ),
    ));
  }

  void _startDailyChallenge() async {
    final dcService = DailyChallengeService();
    final challenge = await dcService.getTodaysChallenge();
    if (!mounted) return;

    if (challenge != null) {
      Navigator.push(context, MaterialPageRoute(
        builder: (context) => BibleQuizArenaScreen(
          mode: "Solo",
          questionCount: challenge.questionCount,
          categoryFilter: challenge.category,
          difficultyFilter: challenge.difficulty,
        ),
      ));
    } else {
      // Fallback: no challenge configured in DB
      Navigator.push(context, MaterialPageRoute(
        builder: (context) => const BibleQuizArenaScreen(
          mode: "Solo",
          questionCount: 5,
          categoryFilter: 'Daily',
        ),
      ));
    }
  }

  void _showInviteFriend() {
    final profile = ref.read(profileProvider).value;
    if (profile == null) return;

    final refCode = profile.walletId ?? "COA-ZM-REF-${profile.id.substring(0, 6).toUpperCase()}";
    final inviteText =
        'Join me on Church On App for a Bible Quiz PvP match!\n\n'
        'Download the app and challenge me: https://churchonapp.com/quiz/invite\n'
        'My referral code: $refCode';
    SharePlus.instance.share(ShareParams(text: inviteText, subject: 'Bible Quiz Invitation'));
  }

  void _showLeaderboard() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Consumer(
        builder: (context, ref, child) {
          final leaderboardAsync = ref.watch(quizLeaderboardProvider);
          final top3 = ['K500', 'K300', 'K150'];
          return Container(
            height: MediaQuery.of(context).size.height * 0.75,
            padding: const EdgeInsets.all(25),
            decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            child: Column(
              children: [
                const Icon(LucideIcons.trophy, color: Colors.amber, size: 36),
                const SizedBox(height: 6),
                Text("$_trophyTitle — Week $_weekNumber", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const Text("Weekly rewards: K500 | K300 | K150", style: TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                  child: const Text("Lasts 12 weeks — New winners every Monday!", style: TextStyle(color: Colors.amber, fontSize: 10)),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: leaderboardAsync.when(
                    data: (users) => ListView.builder(
                      itemCount: users.length,
                      itemBuilder: (context, index) {
                        final user = users[index];
                        final rank = index + 1;
                        final isTop3 = rank <= 3;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: isTop3 ? Colors.amber.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: isTop3 ? Border.all(color: Colors.amber.withValues(alpha: 0.3)) : null,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36, height: 36,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isTop3 ? Colors.amber : Colors.white10,
                                ),
                                child: Center(
                                  child: isTop3
                                      ? Text(['🥇', '🥈', '🥉'][index], style: const TextStyle(fontSize: 18))
                                      : Text("$rank", style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(user['full_name'] ?? 'Anonymous', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                                    if (isTop3)
                                      Text("Reward: ${top3[index]}", style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.greenAccent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text("${user['coins']} CC", style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    loading: () => Shimmer.fromColors(
                      baseColor: Colors.white.withValues(alpha: 0.08),
                      highlightColor: Colors.white.withValues(alpha: 0.15),
                      child: ListView.builder(
                        itemCount: 5,
                        itemBuilder: (_, __) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                    error: (_, __) => const Center(child: Text("Error loading leaderboard", style: TextStyle(color: Colors.red))),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

