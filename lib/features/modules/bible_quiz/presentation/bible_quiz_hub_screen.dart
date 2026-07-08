import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/providers/profile_provider.dart';
import '../data/bible_quiz_service.dart';
import 'bible_quiz_arena_screen.dart';
import 'quiz_event_lobby_screen.dart';

class BibleQuizHubScreen extends ConsumerStatefulWidget {
  const BibleQuizHubScreen({super.key});

  @override
  ConsumerState<BibleQuizHubScreen> createState() => _BibleQuizHubScreenState();
}

class _BibleQuizHubScreenState extends ConsumerState<BibleQuizHubScreen> {
  // No longer hardcoded

  void _startP2P(String mode) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => BibleQuizArenaScreen(mode: mode)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2C), // Deep premium dark theme
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text("Global Bible Quiz", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
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
    );
  }

  Widget _buildTournamentBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF6A11CB), Color(0xFF2575FC)]),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Colors.blue.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Icon(LucideIcons.trophy, color: Colors.amber, size: 40),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)),
                child: const Text("SEASON 1: GOSPELS", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text("THE BISHOP'S TROPHY", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1)),
          const Text("Live Inter-Church Bible Contest. Win glory and activity tokens for your branch.", style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 25),
          ElevatedButton(
            onPressed: () => _showTournamentAccess(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.blue,
              minimumSize: const Size(double.infinity, 55),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
            child: const Text("ACCESS TOURNAMENT ARENA", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showTournamentAccess(BuildContext context) {
    // TODO: Check if the church has paid for the season (query subscriptions table via edge function)
    const bool hasPaid = false;

    if (!hasPaid) {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (context) => Container(
          padding: const EdgeInsets.all(30),
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.lock, color: Colors.amber, size: 50),
              const SizedBox(height: 20),
              const Text("Arena Locked", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const Text("Your church branch needs a Season Pass to enter the Bishop's Trophy contest.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _showLeaseModal();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6A11CB),
                  minimumSize: const Size(double.infinity, 60),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: const Text("GET SEASON PASS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      );
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Welcome to the Tournament! Arena Opening...")));
  }

  Widget _buildP2PCard(String title, String subtitle, IconData icon, Color iconColor, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: iconColor.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 10)),
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
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: iconColor)),
            const SizedBox(height: 15),
            Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 11)),
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
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 11)),
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
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
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
        decoration: const BoxDecoration(color: Color(0xFF2D2D3F), borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
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
        decoration: const BoxDecoration(color: Color(0xFF1E1E2C), borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
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
  
  void _showLeaderboard() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Consumer(
        builder: (context, ref, child) {
          final leaderboardAsync = ref.watch(quizLeaderboardProvider);
          return Container(
            padding: const EdgeInsets.all(25),
            decoration: const BoxDecoration(
              color: Color(0xFF1E1E2C),
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Global Leaderboard", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                leaderboardAsync.when(
                  data: (users) => Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: users.length,
                      itemBuilder: (context, index) {
                        final user = users[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.white10,
                            child: Text("${index + 1}", style: const TextStyle(color: Colors.amber)),
                          ),
                          title: Text(user['full_name'] ?? 'Anonymous', style: const TextStyle(color: Colors.white)),
                          trailing: Text("${user['coins']} CC", style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                        );
                      },
                    ),
                  ),
                  loading: () => const Center(child: CircularProgressIndicator(color: Colors.amber)),
                  error: (e, s) => const Center(child: Text("Error loading leaderboard", style: TextStyle(color: Colors.red))),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

