import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/features/navigation/presentation/main_navigation_shell.dart';
import '../../../../core/services/tenant_service.dart';
import '../../../../core/config/remote_config.dart';
import '../data/bible_quiz_service.dart';
import '../data/daily_challenge_service.dart';
import '../data/pvp_service.dart';
import '../data/quiz_event_service.dart';
import '../data/xp_service.dart';
import 'bible_quiz_arena_screen.dart';
import 'church_competition_lobby_screen.dart';
import 'quiz_cc_store_screen.dart';
import 'quiz_event_lobby_screen.dart';
import 'quiz_question_upload_screen.dart';

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
  bool _isConnecting = false;
  String? _connectingMode;

  /// Remote-configurable quiz values (`quiz_*` keys in platform_settings).
  RemoteConfig get _rc => widgetRemoteConfig(ref);

  int get _prize1 => _rc.getInt('quiz_prize_1st_cc', 500);
  int get _prize2 => _rc.getInt('quiz_prize_2nd_cc', 300);
  int get _prize3 => _rc.getInt('quiz_prize_3rd_cc', 150);
  int get _seasonWeeks => _rc.getInt('quiz_season_weeks', 12);

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

  void _startP2P(String mode) async {
    setState(() {
      _isConnecting = true;
      _connectingMode = mode;
    });

    // Intentional delay for "Connecting..." state polish
    await Future.delayed(const Duration(milliseconds: 1500));

    if (!mounted) return;
    setState(() => _isConnecting = false);

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => BibleQuizArenaScreen(mode: mode)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(currentTenantProvider);
    if (tenant != null && tenant.isSubscriptionExpired) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0E1A),
        appBar: AppBar(
          title: const Text("Global Bible Quiz"),
          centerTitle: true,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.lock, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                const Text(
                  "Church Subscription Expired",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  "Your church's subscription has expired. Contact your church admin to renew.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Wire XP service into bible quiz feature lifecycle
    ref.watch(xpServiceProvider);

    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1117),
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text(
          "Global Bible Quiz",
          style: TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: Colors.white,
          ),
        ),
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
                  gradient: LinearGradient(
                    colors: [theme.primaryColor, theme.primaryColor.withValues(alpha: 0.75)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: [
                    BoxShadow(
                      color: theme.primaryColor.withValues(alpha: 0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            "WORLD-CLASS STANDARD",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        const Spacer(),
                        const Icon(
                          LucideIcons.globe,
                          color: Colors.white70,
                          size: 20,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      "International\nBible Quizzing",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        height: 1.1,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      "Play individually, join global arenas, or host church tournaments.",
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 25),
                    ElevatedButton.icon(
                      onPressed: _showJoinLiveModal,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: theme.primaryColor,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 25,
                          vertical: 15,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      icon: const Icon(LucideIcons.radioTower, size: 18),
                      label: const Text(
                        "JOIN LIVE EVENT",
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 15),
              _storeCard(),
              const SizedBox(height: 30),

              const Text(
                "P2P MULTIPLAYER ARENA",
                style: TextStyle(
                  color: Colors.white54,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 15),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 15,
                crossAxisSpacing: 15,
                childAspectRatio: 1.25,
                children: [
                  _buildP2PCard(
                    "Any User",
                    "Global Match",
                    LucideIcons.users,
                    theme.primaryColor,
                    "Global",
                  ),
                  _buildP2PCard(
                    "My Church",
                    "Same Church Only",
                    LucideIcons.home,
                    theme.primaryColor.withValues(alpha: 0.75),
                    "Church",
                  ),
                  _buildP2PCard(
                    "Random",
                    "Instant Play",
                    LucideIcons.shuffle,
                    theme.primaryColor.withValues(alpha: 0.55),
                    "Random",
                  ),
                  _buildP2PCard(
                    "Any COA User",
                    "Play COA Staff",
                    LucideIcons.globe,
                    theme.primaryColor.withValues(alpha: 0.4),
                    "Any COA",
                  ),
                ],
              ),
              const SizedBox(height: 15),
              GestureDetector(
                onTap: _showInviteFriend,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withAlpha(20),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: theme.primaryColor.withAlpha(50)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        LucideIcons.userPlus,
                        color: theme.primaryColor,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        "Invite a Friend to PvP",
                        style: TextStyle(
                          color: theme.primaryColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 15),
              const _IncomingInvitesSection(),
              const SizedBox(height: 30),

              const Text(
                "GAME MODES",
                style: TextStyle(
                  color: Colors.white54,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 15),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildModeCard(
                      "Solo Play",
                      "Engine Generated",
                      LucideIcons.smartphone,
                      theme.primaryColor,
                      _startSoloPlay,
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: _buildModeCard(
                      "World Rank",
                      "Global Leaderboard",
                      LucideIcons.trophy,
                      theme.primaryColor.withValues(alpha: 0.75),
                      _showLeaderboard,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildModeCard(
                      "Learning Mode",
                      "No Timer, Study",
                      LucideIcons.bookOpen,
                      theme.primaryColor.withValues(alpha: 0.55),
                      _startLearningMode,
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: _buildModeCard(
                      "Daily Challenge",
                      "Daily Questions",
                      LucideIcons.calendar,
                      theme.primaryColor.withValues(alpha: 0.4),
                      _startDailyChallenge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),

              const Text(
                "COMPETITIVE STYLES",
                style: TextStyle(
                  color: Colors.white54,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 15),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildModeCard(
                      "Rapid Fire",
                      "8s · 15 Qs · 2× points",
                      LucideIcons.zap,
                      const Color(0xFFFFB020),
                      () => _startStyle(QuizStyle.rapidFire),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: _buildModeCard(
                      "Marathon",
                      "12s · 40 Qs · big streaks",
                      LucideIcons.footprints,
                      const Color(0xFF4FC3F7),
                      () => _startStyle(QuizStyle.marathon),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildModeCard(
                      "Sudden Death",
                      "1 mistake ends the run",
                      LucideIcons.skull,
                      const Color(0xFFFF5A5A),
                      () => _startStyle(QuizStyle.suddenDeath),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: _buildModeCard(
                      "Blitz",
                      "90s total clock",
                      LucideIcons.timer,
                      const Color(0xFFB388FF),
                      () => _startStyle(QuizStyle.blitz),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ref.watch(canManageQuizContentProvider).when(
                data: (canManage) => canManage
                    ? _buildImportTile(theme)
                    : const SizedBox.shrink(),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
              const SizedBox(height: 30),

              // Premium Events
              const SizedBox(height: 24),
              _buildOrganizationQuizSection(ref),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const QuizEventLobbyScreen(),
                    ),
                  );
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        theme.primaryColor.withAlpha(30),
                        theme.primaryColor.withAlpha(15),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: theme.primaryColor.withAlpha(50)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: theme.primaryColor.withAlpha(25),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          LucideIcons.trophy,
                          color: theme.primaryColor,
                          size: 24,
                        ),
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
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        LucideIcons.chevronRight,
                        color: Colors.greenAccent,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 30),

              const Text(
                "STANDARDIZED QUESTION FORMATS",
                style: TextStyle(
                  color: Colors.white54,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 15),
              SizedBox(
                height: 140,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _buildFormatCard(
                      "Interrogative",
                      "According to...",
                      LucideIcons.helpCircle,
                      theme.primaryColor,
                    ),
                    const SizedBox(width: 15),
                    _buildFormatCard(
                      "Quotation",
                      "Quote...",
                      LucideIcons.quote,
                      theme.primaryColor.withValues(alpha: 0.75),
                    ),
                    const SizedBox(width: 15),
                    _buildFormatCard(
                      "Chapter & Verse",
                      "In what chapter...",
                      LucideIcons.bookOpen,
                      theme.primaryColor.withValues(alpha: 0.55),
                    ),
                    const SizedBox(width: 15),
                    _buildFormatCard(
                      "Multiple Answer",
                      "Give a complete answer...",
                      LucideIcons.listOrdered,
                      theme.primaryColor.withValues(alpha: 0.4),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),
              const Text(
                "ENTERPRISE & HOSTING",
                style: TextStyle(
                  color: Colors.white54,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 15),

              // Leasing Card
              _buildActionTile(
                "Host a Quiz Tournament",
                "Lease the engine to host a live church event.",
                LucideIcons.presentation,
                theme.primaryColor,
                _showLeaseModal,
              ),

              // Admin Question Seeding (Restricted)
              if (ref.watch(profileProvider).value?.isEmployee == true) ...[
                const SizedBox(height: 15),
                _buildActionTile(
                  "Superadmin: AI Question Seeding",
                  "Extract canonical questions via AI",
                  LucideIcons.sparkles,
                  theme.primaryColor.withValues(alpha: 0.7),
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
        gradient: const LinearGradient(
          colors: [Color(0xFFFFDA03), Color(0xFFE8A400)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Icon(LucideIcons.crown, color: Colors.black, size: 40),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _currentSeason,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            _trophyTitle,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              "Week $_weekNumber — $_seasonWeeks weeks remaining",
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _trophySubtitle,
            style: const TextStyle(color: Colors.black87, fontSize: 13),
          ),
          const SizedBox(height: 25),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const BibleQuizArenaScreen(
                          mode: 'Solo',
                          questionCount: 20,
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: const Color(0xFFFFDA03),
                    minimumSize: const Size(double.infinity, 55),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: const Text(
                    "ENTER THE ARENA",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _showLeaderboard,
                  icon: const Icon(
                    LucideIcons.barChart3,
                    size: 15,
                    color: Colors.black87,
                  ),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      "LEADERBOARD",
                      style: TextStyle(
                        color: Colors.black87,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.black38),
                    minimumSize: const Size(double.infinity, 55),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                onPressed: () => _showTrophyInfo(context),
                icon: const Icon(
                  LucideIcons.info,
                  color: Colors.black54,
                  size: 20,
                ),
              ),
            ],
          ),
          // Superadmin edit button
          if (ref.watch(profileProvider).value?.isEmployee == true) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _showEditTrophyDialog,
              icon: const Icon(
                LucideIcons.settings,
                color: Colors.black54,
                size: 16,
              ),
              label: const Text(
                "Edit Trophy Settings",
                style: TextStyle(color: Colors.black54, fontSize: 12),
              ),
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
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(
                labelText: "Trophy Title",
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: subtitleCtrl,
              decoration: const InputDecoration(
                labelText: "Subtitle",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: seasonCtrl,
              decoration: const InputDecoration(
                labelText: "Season Label",
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("CANCEL"),
          ),
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
          color: const Color(0xFF151A2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.trophy,
                color: Theme.of(context).primaryColor, size: 60),
            const SizedBox(height: 20),
            const Text(
              "Church On App Trophy",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Weekly prizes await the top contenders!\nAnswer fast, answer right, climb the ranks.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Column(
                    children: [
                      const Text("🥇", style: TextStyle(fontSize: 28)),
                      Text(
                        "$_prize1 CC",
                        style: TextStyle(
                          color: Theme.of(context).primaryColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      const Text("🥈", style: TextStyle(fontSize: 28)),
                      Text(
                        "$_prize2 CC",
                        style: TextStyle(
                          color: Theme.of(context).primaryColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      const Text("🥉", style: TextStyle(fontSize: 28)),
                      Text(
                        "$_prize3 CC",
                        style: TextStyle(
                          color: Theme.of(context).primaryColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "CLOSE",
                style: TextStyle(color: Colors.white54),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildP2PCard(
    String title,
    String subtitle,
    IconData icon,
    Color iconColor,
    String mode,
  ) {
    final isThisConnecting = _isConnecting && _connectingMode == mode;
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: _isConnecting ? null : () => _startP2P(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: isThisConnecting
              ? theme.primaryColor.withValues(alpha: 0.25)
              : Color.lerp(iconColor, const Color(0xFF0D1117), 0.55),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isThisConnecting
                ? theme.primaryColor
                : iconColor.withValues(alpha: 0.4),
            width: isThisConnecting ? 2 : 1,
          ),
        ),
        child: isThisConnecting
            ? const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    "Connecting...",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: iconColor, size: 20),
                  const SizedBox(height: 10),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildModeCard(
    String title,
    String subtitle,
    IconData icon,
    Color iconColor,
    VoidCallback onTap,
  ) {
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
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor),
            ),
            const SizedBox(height: 15),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormatCard(
    String title,
    String subtitle,
    IconData icon,
    Color iconColor,
  ) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: iconColor.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 28),
          const Spacer(),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile(
    String title,
    String subtitle,
    IconData icon,
    Color iconColor,
    VoidCallback onTap,
  ) {
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
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(LucideIcons.chevronRight, color: Colors.white24),
          ],
        ),
      ),
    );
  }

  void _showJoinLiveModal() {
    final pinCtrl = TextEditingController();
    var isVerifying = false;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          padding: EdgeInsets.only(
            left: 25,
            right: 25,
            top: 30,
            bottom: MediaQuery.of(context).viewInsets.bottom + 30,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF151A2E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.radioTower, color: Colors.white, size: 50),
              const SizedBox(height: 15),
              const Text(
                "Enter Match PIN",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Text(
                "Join a live tournament hosted by a church.",
                style: TextStyle(color: Colors.white54),
              ),
              const SizedBox(height: 30),
              TextField(
                controller: pinCtrl,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  letterSpacing: 10,
                  fontWeight: FontWeight.w900,
                ),
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                  hintText: "000000",
                  hintStyle: const TextStyle(color: Colors.white24),
                  filled: true,
                  fillColor: Colors.black26,
                  counterText: "",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: isVerifying
                    ? null
                    : () async {
                        final pin = pinCtrl.text.trim();
                        if (pin.length != 6) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  "Please enter a valid 6-digit PIN",
                                ),
                                backgroundColor: Colors.orange,
                              ),
                            );
                          }
                          return;
                        }
                        setSheetState(() => isVerifying = true);
                        final compId = await ref
                            .read(bibleQuizServiceProvider)
                            .verifyCompetitionPin(pin);
                        if (!context.mounted) return;
                        if (compId != null) {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChurchCompetitionLobbyScreen(
                                competitionId: compId,
                              ),
                            ),
                          );
                        } else {
                          setSheetState(() => isVerifying = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                "Invalid or expired PIN. Please check and try again.",
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 60),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: Text(
                  isVerifying ? "VERIFYING..." : "ENTER ARENA",
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLeaseModal() {
    final leaseFeeCc = _rc.getInt('quiz_lease_fee_cc', 1500);
    final coins = ref.read(profileProvider).value?.coins ?? 0;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              25,
              25,
              25,
              MediaQuery.of(context).padding.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Lease Quizzing Engine",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  "Pay Church On App to host an internationally standardized Bible Quiz — "
                  "for your church's yearly tournament or as an individual hosting a personal "
                  "tournament. Supports 500+ live mobile players.",
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 25),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .primaryColor
                        .withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Theme.of(context)
                          .primaryColor
                          .withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.crown,
                        color: Theme.of(context).primaryColor,
                        size: 30,
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Premium Engine Lease",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const Text(
                              "1 Live Event • Active Leaderboard • Custom Questions",
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              "$leaseFeeCc CC",
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: Theme.of(context).primaryColor,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(LucideIcons.wallet,
                        color: Colors.grey, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Your balance: $coins CC',
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 30),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _payQuizLease();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    minimumSize: const Size(double.infinity, 60),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: Text(
                    "PAY $leaseFeeCc CC",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      showBuyCoinsSheet(
                        context,
                        reason: 'Buy Church Coins to lease the Quiz Engine.',
                      );
                    },
                    child: Text(
                      "Need CC? Buy Church Coins",
                      style: TextStyle(
                        color: Theme.of(context).primaryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAiSeedingModal() {
    final promptCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(
          color: const Color(0xFF151A2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(LucideIcons.brainCircuit, color: Colors.white),
                SizedBox(width: 10),
                Text(
                  "AI Question Seeding",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const Text(
              "Only Superadmins and COA Employees",
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const Divider(color: Colors.white10, height: 30),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white10,
                  style: BorderStyle.none,
                ),
              ),
              child: const Column(
                children: [
                  Icon(LucideIcons.fileText, size: 40, color: Colors.white54),
                  SizedBox(height: 10),
                  Text(
                    "Upload Theological Documents (PDF/Docx)",
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    "AI will extract and format into interogative, quotation, and multiple answer standards.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white30, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              "OR Generate From Database",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: promptCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "e.g. Generate 50 questions on the Book of Acts...",
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.black26,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () async {
                final prompt = promptCtrl.text.trim();
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      prompt.isEmpty
                          ? "Seeding canonical question bank..."
                          : "AI generating questions for: \"$prompt\"...",
                    ),
                  ),
                );
                try {
                  if (prompt.isEmpty) {
                    await ref.read(bibleQuizServiceProvider).seedQuestions();
                  } else {
                    await _seedViaAi(prompt);
                  }
                } catch (e) {
                  debugPrint("AI seeding error: $e");
                }
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      "Database seeded with 200+ canonical questions! 🚀",
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 60),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              icon: const Icon(LucideIcons.sparkles, color: Colors.black),
              label: const Text(
                "GENERATE & SEED DB",
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Seeds questions via the generate-quiz-batch Edge Function using a
  /// free-text topic prompt (Gemini on the server).
  Future<void> _seedViaAi(String topic) async {
    try {
      final existingRes = await Supabase.instance.client
          .from('quiz_questions')
          .select('question')
          .limit(200);
      final exclude = (existingRes as List)
          .map((q) => q['question'] as String)
          .toList();
      final res = await Supabase.instance.client.functions.invoke(
        'generate-quiz-batch',
        body: {
          'count': 50,
          'topic': topic,
          'excludeQuestions': exclude,
        },
      );
      final data = res.data as Map<String, dynamic>?;
      final inserted = (data?['inserted'] as int?) ?? 0;
      debugPrint('[BibleQuiz] AI seeded $inserted questions for "$topic"');
    } catch (e) {
      debugPrint('[BibleQuiz] AI seeding failed: $e');
    }
  }

  void _startSoloPlay() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const BibleQuizArenaScreen(mode: "Solo"),
      ),
    );
  }

  void _startLearningMode() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const BibleQuizArenaScreen(
          mode: "Solo",
          timePerQuestionSec: 999,
          questionCount: 15,
        ),
      ),
    );
  }

  void _startDailyChallenge() async {
    final dcService = DailyChallengeService();
    final challenge = await dcService.getTodaysChallenge();
    if (!mounted) return;

    if (challenge != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => BibleQuizArenaScreen(
            mode: "Solo",
            questionCount: challenge.questionCount,
            categoryFilter: challenge.category,
            difficultyFilter: challenge.difficulty,
          ),
        ),
      );
    } else {
      // Fallback: no challenge configured in DB
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const BibleQuizArenaScreen(
            mode: "Solo",
            questionCount: 5,
            categoryFilter: 'Daily',
          ),
        ),
      );
    }
  }

  void _startStyle(QuizStyle style) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BibleQuizArenaScreen(
          mode: 'Solo',
          style: style,
          questionCount: style.defaultCount,
          timePerQuestionSec: style.defaultSeconds,
        ),
      ),
    );
  }

  Widget _buildImportTile(ThemeData theme) {
    return GestureDetector(
      onTap: _openQuestionImport,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.primaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: theme.primaryColor.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.upload, color: theme.primaryColor, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "IMPORT QUESTIONS",
                    style: TextStyle(
                      color: theme.primaryColor,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.1,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    "Admins & Quiz Engine churches: paste text or upload TXT/PDF/DOC",
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, color: theme.primaryColor, size: 20),
          ],
        ),
      ),
    );
  }

  void _openQuestionImport() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QuizQuestionUploadScreen()),
    );
  }

  void _openStore() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const QuizCcStoreScreen()),
    );
  }

  Widget _storeCard() {
    final coins = ref.read(profileProvider).value?.coins ?? 0;
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: _openStore,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF3A2E00), Color(0xFF1A1400)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: theme.primaryColor.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.primaryColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(LucideIcons.store,
                  color: theme.primaryColor, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "QUIZ CC STORE",
                    style: TextStyle(
                      color: theme.primaryColor,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "$coins CC · buy, lease, wagers, passes, prizes & history",
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight,
                color: theme.primaryColor, size: 20),
          ],
        ),
      ),
    );
  }

  void _showInviteFriend() {
    final profile = ref.read(profileProvider).value;
    final myTenant = profile?.tenantId;
    if (myTenant == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must belong to a church to invite members.'),
        ),
      );
      return;
    }

    ref.read(navBarVisibleProvider.notifier).hide();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      builder: (_) => _FriendPickerSheet(
        tenantId: myTenant,
        onPicked: (memberId, memberName) {
          _chooseWager(memberId, memberName);
        },
      ),
    ).whenComplete(() {
      if (mounted) ref.read(navBarVisibleProvider.notifier).show();
    });
  }

  void _chooseWager(String memberId, String memberName) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF151A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, 24 + MediaQuery.of(ctx).viewPadding.bottom),
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
              "Challenge a Friend",
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "$memberName — choose the wager (staked by both players).",
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [0, 10, 25, 50, 100]
                  .map((w) => ChoiceChip(
                        label: Text(
                          w == 0 ? "Free" : "$w CC",
                          style: TextStyle(
                            color: theme.primaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        selected: false,
                        selectedColor: theme.primaryColor,
                        backgroundColor: const Color(0xFF232845),
                        side: BorderSide(
                            color: theme.primaryColor.withValues(alpha: 0.5)),
                        labelStyle: TextStyle(color: theme.primaryColor),
                        onSelected: (_) {
                          Navigator.pop(ctx);
                          _sendInvite(memberId, memberName, w);
                        },
                      ))
                  .toList(),
            ),
            const SizedBox(height: 8),
            Text(
              "Winner takes 90% of the pot. Draw or no-show = full refund.",
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      if (mounted) ref.read(navBarVisibleProvider.notifier).show();
    });
  }

  Future<void> _sendInvite(
      String memberId, String memberName, int wagerCoins) async {
    final pvpService = ref.read(pvpServiceProvider);
    final match = await pvpService.createInvite(
      opponentId: memberId,
      wagerCoins: wagerCoins,
      questionCount: 10,
      timePerQuestion: 15,
    );
    if (!mounted) return;
    if (match == null) {
      if (wagerCoins > 0) {
        showBuyCoinsSheet(
          context,
          reason: 'Not enough Church Coins to send this challenge.',
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not send the invite right now. Please try again.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          wagerCoins > 0
              ? 'Invite sent to $memberName ($wagerCoins CC staked)!'
              : "Free invite sent to $memberName!",
        ),
        backgroundColor: Colors.green,
      ),
    );
    try {
      await Supabase.instance.client.functions.invoke(
        'push-notifications',
        body: {
          'userId': memberId,
          'title': 'Quiz Challenge!',
          'body': wagerCoins > 0
              ? '${ref.read(profileProvider).value?.name ?? 'A friend'} '
                  'challenged you for $wagerCoins CC. Accept or decline!'
              : '${ref.read(profileProvider).value?.name ?? 'A friend'} '
                  'challenged you to a free quiz match!',
          'data': {
            'type': 'pvp_invite',
            'reference_id': match.id,
            'channel_id': 'coa_events',
          },
        },
      );
    } catch (e) {
      debugPrint('Invite push notification failed: $e');
    }
  }

  void _showLeaderboard() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Consumer(
        builder: (context, ref, child) {
          final leaderboardAsync = ref.watch(quizLeaderboardProvider);
          final top3 = ['$_prize1 CC', '$_prize2 CC', '$_prize3 CC'];
          final theme = Theme.of(context);
          return Container(
            height: MediaQuery.of(context).size.height * 0.75,
            padding: const EdgeInsets.all(25),
            decoration: BoxDecoration(
              color: const Color(0xFF151A2E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            child: Column(
              children: [
                Icon(LucideIcons.trophy, color: theme.primaryColor, size: 36),
                const SizedBox(height: 6),
                Text(
                  "$_trophyTitle — Week $_weekNumber",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  "Weekly rewards: $_prize1 CC | $_prize2 CC | $_prize3 CC",
                  style: TextStyle(
                    color: theme.primaryColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    "Lasts $_seasonWeeks weeks — New winners every Monday!",
                    style: TextStyle(color: theme.primaryColor, fontSize: 11),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: leaderboardAsync.when(
                    data: (users) => users.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(LucideIcons.trophy,
                                    color: Colors.white24, size: 48),
                                SizedBox(height: 12),
                                Text(
                                  "No scores yet this week",
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  "Play a match or the daily challenge to claim the top spot!",
                                  style: TextStyle(
                                    color: Colors.white38,
                                    fontSize: 13,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                      itemCount: users.length,
                      itemBuilder: (context, index) {
                        final user = users[index];
                        final rank = index + 1;
                        final isTop3 = rank <= 3;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: isTop3
                                ? theme.primaryColor.withValues(alpha: 0.1)
                                : Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: isTop3
                                ? Border.all(
                                    color: theme.primaryColor.withValues(
                                      alpha: 0.3,
                                    ),
                                  )
                                : null,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isTop3
                                      ? theme.primaryColor
                                      : Colors.white10,
                                ),
                                child: Center(
                                  child: isTop3
                                      ? Text(
                                          ['🥇', '🥈', '🥉'][index],
                                          style: const TextStyle(fontSize: 18),
                                        )
                                      : Text(
                                          "$rank",
                                          style: const TextStyle(
                                            color: Colors.grey,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      user['full_name'] ?? 'Anonymous',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    if (isTop3)
                                      Text(
                                        "Reward: ${top3[index]}",
                                        style: TextStyle(
                                          color: theme.primaryColor,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.greenAccent.withValues(
                                    alpha: 0.15,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  "${user['correct_answers'] ?? 0} correct",
                                  style: const TextStyle(
                                    color: Colors.greenAccent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
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
                    error: (_, __) => const Center(
                      child: Text(
                        "Error loading leaderboard",
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildOrganizationQuizSection(WidgetRef ref) {
    final profile = ref.watch(profileProvider).value;
    if (profile?.organizationId == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "NETWORK-WIDE COMPETITIONS",
          style: TextStyle(
            color: Theme.of(context).primaryColor,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 15),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: Supabase.instance.client
              .from('church_competitions')
              .select()
              .eq('organization_id', profile!.organizationId!),
          builder: (context, snapshot) {
            final comps = snapshot.data ?? [];
            if (comps.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Center(
                  child: Text(
                    "No national competitions scheduled",
                    style: TextStyle(color: Colors.white24, fontSize: 12),
                  ),
                ),
              );
            }
            return Column(
              children: comps.map((c) {
                final comp = ChurchQuizCompetition.fromMap(c);
                return _buildActionTile(
                  comp.title,
                  "National Final • Join with PIN",
                  LucideIcons.crown,
                  Theme.of(context).primaryColor,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ChurchCompetitionLobbyScreen(competitionId: comp.id),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Future<void> _payQuizLease() async {
    final svc = ref.read(quizEventServiceProvider);
    final ok = await svc.leaseQuizEngineCc();
    if (!mounted) return;
    if (ok) {
      ref.invalidate(profileProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Quiz Engine leased! Create events from the Events tab.',
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
}

/// Church member picker for direct 1v1 invites.
class _FriendPickerSheet extends ConsumerStatefulWidget {
  final String tenantId;
  final void Function(String memberId, String memberName) onPicked;

  const _FriendPickerSheet({
    required this.tenantId,
    required this.onPicked,
  });

  @override
  ConsumerState<_FriendPickerSheet> createState() => _FriendPickerSheetState();
}

class _FriendPickerSheetState extends ConsumerState<_FriendPickerSheet> {
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      final res = await Supabase.instance.client
          .from('profiles')
          .select('id, full_name, avatar_url')
          .eq('tenant_id', widget.tenantId)
          .neq('id', uid ?? '')
          .order('full_name')
          .limit(200);
      if (mounted) {
        setState(() {
          _members = (res as List).cast<Map<String, dynamic>>();
          _filtered = List.from(_members);
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Friend picker load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _filter(String q) {
    final query = q.trim().toLowerCase();
    setState(() {
      _filtered = query.isEmpty
          ? List.from(_members)
          : _members
              .where((m) =>
                  (m['full_name']?.toString() ?? '').toLowerCase().contains(query))
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.75;
    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: Color(0xFF151A2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            "Invite a Church Member",
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _filter,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search members…',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(LucideIcons.search,
                    color: Colors.white38, size: 20),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white))
                : _filtered.isEmpty
                    ? const Center(
                        child: Text('No members found',
                            style: TextStyle(color: Colors.white54)),
                      )
                    : ListView.builder(
                        itemCount: _filtered.length,
                        itemBuilder: (context, i) {
                          final m = _filtered[i];
                          final name =
                              m['full_name']?.toString() ?? 'Member';
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.white.withValues(
                                  alpha: 0.15),
                              foregroundImage: m['avatar_url'] != null &&
                                      m['avatar_url'].toString().isNotEmpty
                                  ? NetworkImage(m['avatar_url'].toString())
                                  : null,
                              child: m['avatar_url'] == null ||
                                      m['avatar_url'].toString().isEmpty
                                  ? Text(name.isNotEmpty ? name[0] : '?',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold))
                                  : null,
                            ),
                            title: Text(name,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600)),
                            trailing: const Icon(LucideIcons.chevronRight,
                                color: Colors.white38, size: 18),
                            onTap: () {
                              Navigator.pop(context);
                              widget.onPicked(
                                m['id'].toString(),
                                name,
                              );
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

/// Live list of invites sent TO the current user, with accept/decline.
class _IncomingInvitesSection extends ConsumerStatefulWidget {
  const _IncomingInvitesSection();

  @override
  ConsumerState<_IncomingInvitesSection> createState() =>
      _IncomingInvitesSectionState();
}

class _IncomingInvitesSectionState
    extends ConsumerState<_IncomingInvitesSection> {
  final Map<String, String> _inviterNames = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(pvpServiceProvider).expireStaleInvites();
    });
  }

  Future<String> _nameFor(String userId) async {
    if (_inviterNames.containsKey(userId)) return _inviterNames[userId]!;
    try {
      final res = await Supabase.instance.client
          .from('profiles')
          .select('full_name')
          .eq('id', userId)
          .maybeSingle();
      final name = res?['full_name']?.toString() ?? 'A friend';
      if (mounted) setState(() => _inviterNames[userId] = name);
      return name;
    } catch (_) {
      return 'A friend';
    }
  }

  Future<void> _respond(PvPMatch match, bool accept) async {
    if (_busy) return;
    setState(() => _busy = true);
    final pvpService = ref.read(pvpServiceProvider);
    if (accept) {
      final updated = await pvpService.acceptInvite(match.id);
      if (!mounted) return;
      setState(() => _busy = false);
      if (updated != null) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BibleQuizArenaScreen(
              mode: 'PvP',
              questionCount: updated.questionCount,
              timePerQuestionSec: updated.timePerQuestion,
              initialPvPMatch: updated,
            ),
          ),
        );
      } else {
        showBuyCoinsSheet(
          context,
          reason: 'Not enough Church Coins to accept this wager.',
        );
      }
    } else {
      final ok = await pvpService.declineInvite(match.id);
      if (!mounted) return;
      setState(() => _busy = false);
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invite declined.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PvPMatch>>(
      stream: ref.read(pvpServiceProvider).incomingInvitesStream(),
      builder: (context, snapshot) {
        final invites = snapshot.data ?? const <PvPMatch>[];
        if (invites.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .primaryColor
                        .withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${invites.length} PENDING INVITE${invites.length > 1 ? 'S' : ''}',
                    style: TextStyle(
                      color: Theme.of(context).primaryColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...invites.map((match) {
              final inviterName = _inviterNames[match.player1Id];
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: Theme.of(context)
                          .primaryColor
                          .withValues(alpha: 0.3)),
                ),
                child: FutureBuilder<String>(
                  future: _nameFor(match.player1Id),
                  builder: (context, snap) => Row(
                    children: [
                      Icon(LucideIcons.swords,
                          color: Theme.of(context).primaryColor, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${snap.data ?? inviterName ?? 'A friend'} challenged you',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              match.wagerAmount > 0
                                  ? '${match.wagerAmount} CC wager · ${match.questionCount} questions'
                                  : 'Free match · ${match.questionCount} questions',
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Accept',
                        onPressed:
                            _busy ? null : () => _respond(match, true),
                        icon: const Icon(LucideIcons.check,
                            color: Colors.greenAccent),
                      ),
                      IconButton(
                        tooltip: 'Decline',
                        onPressed:
                            _busy ? null : () => _respond(match, false),
                        icon: const Icon(LucideIcons.x,
                            color: Colors.redAccent),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}
