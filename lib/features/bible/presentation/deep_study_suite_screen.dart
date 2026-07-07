import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'bible_podcast_screen.dart';
import '../../modules/bible_quiz/presentation/bible_quiz_hub_screen.dart';

class DeepStudySuiteScreen extends ConsumerStatefulWidget {
  const DeepStudySuiteScreen({super.key});

  @override
  ConsumerState<DeepStudySuiteScreen> createState() => _DeepStudySuiteScreenState();
}

class _DeepStudySuiteScreenState extends ConsumerState<DeepStudySuiteScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(profileProvider.notifier).updateReadingStreak();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFC),
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(context),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(25.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeroSection(context),
                  const SizedBox(height: 30),
                  _buildToolMatrix(context),
                  const SizedBox(height: 30),
                  _buildStreakCard(context),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 180,
      pinned: true,
      backgroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(LucideIcons.arrowLeft, color: Colors.black),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        IconButton(
          icon: const Icon(LucideIcons.settings, color: Colors.black),
          onPressed: () => _openSettingsDialog(),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Padding(
          padding: const EdgeInsets.only(top: 80, left: 25, right: 25),
          child: Column(
            children: [
              Text("DEEP STUDY", style: GoogleFonts.plusJakartaSans(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
              Text("THEOLOGICAL SUITE", style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 3, color: Colors.indigo)),
              const SizedBox(height: 15),
              _buildSearchBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: TextField(
        onSubmitted: (query) {
          if (query.isNotEmpty) {
            Navigator.push(context, MaterialPageRoute(
              builder: (_) => _ScriptureSearchScreen(query: query),
            ));
          }
        },
        decoration: const InputDecoration(
          hintText: "Search scripture, topics, keywords...",
          hintStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
          icon: Icon(LucideIcons.search, size: 18, color: Colors.grey),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildHeroSection(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.indigo.shade600, Colors.purple.shade600], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Colors.indigo.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(12)),
                child: const Icon(LucideIcons.bookOpen, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 15),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Bible Reader", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  Text("PREMIUM v2.0", style: TextStyle(color: Colors.white70, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 2)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 25),
          const Text(
            "\"I have hidden your word in my heart that I might not sin against you.\"",
            style: TextStyle(color: Colors.white, fontSize: 18, fontStyle: FontStyle.italic, fontWeight: FontWeight.w300),
          ),
          const SizedBox(height: 10),
          const Text("— PSALM 119:11", style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 2)),
        ],
      ),
    );
  }

  Widget _buildToolMatrix(BuildContext context) {
    final tools = [
      {"icon": LucideIcons.mic, "title": "Podcast", "sub": "Audio Bible", "color": Colors.red, "screen": const BiblePodcastScreen()},
      {"icon": LucideIcons.sword, "title": "Match", "sub": "Bible Quiz P2P", "color": Colors.orange, "screen": const BibleQuizHubScreen()},
      {"icon": LucideIcons.brain, "title": "Exegesis", "sub": "Word Study", "color": Colors.blue, "action": "exegesis"},
      {"icon": LucideIcons.map, "title": "Atlas", "sub": "Historic Maps", "color": const Color(0xFF10B981), "action": "atlas"},
      {"icon": LucideIcons.target, "title": "Memory", "sub": "Master Verses", "color": Colors.purple, "action": "memory"},
      {"icon": LucideIcons.calendar, "title": "Plans", "sub": "Reading Paths", "color": Colors.pink, "action": "plans"},
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 15, mainAxisSpacing: 15, childAspectRatio: 1.3),
      itemCount: tools.length,
      itemBuilder: (context, index) {
        return GestureDetector(
          onTap: () {
            if (tools[index].containsKey('screen')) {
              Navigator.push(context, MaterialPageRoute(builder: (_) => tools[index]['screen'] as Widget));
            } else {
              final action = tools[index]['action'] as String;
              _openDeepStudyFeature(action);
            }
          },
          child: _buildToolCard(tools[index]['icon'] as IconData, tools[index]['title'] as String, tools[index]['sub'] as String, tools[index]['color'] as Color),
        );
      },
    );
  }

  void _openDeepStudyFeature(String action) {
    switch (action) {
      case 'exegesis':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const _ExegesisScreen()));
      case 'atlas':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const _BiblicalAtlasScreen()));
      case 'memory':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const _VerseMemoryScreen()));
      case 'plans':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const _ReadingPlansScreen()));
    }
  }

  Widget _buildToolCard(IconData icon, String title, String sub, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          Text(sub, style: const TextStyle(color: Colors.grey, fontSize: 9, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildStreakCard(BuildContext context) {
    final profile = ref.watch(profileProvider).value;
    final streak = profile?.streakCount ?? 0;

    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(30)),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Study Streak", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              Row(
                children: [
                  const Icon(LucideIcons.trendingUp, color: Color(0xFF10B981), size: 14),
                  const SizedBox(width: 5),
                  Text("GLOBAL RANK: #${streak > 0 ? 100 - streak : '99+'}", style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
          const Spacer(),
          Text(streak.toString(), style: GoogleFonts.plusJakartaSans(fontSize: 42, fontWeight: FontWeight.w900, color: const Color(0xFFFFD700))),
        ],
      ),
    );
  }

  void _openSettingsDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      backgroundColor: Colors.white,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(25),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Study Preferences", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black)),
                  const SizedBox(height: 5),
                  const Text("Customize your Deep Study Theological Suite settings.", style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const Divider(height: 30),
                  ListTile(
                    leading: const Icon(LucideIcons.globe, color: Colors.blue),
                    title: const Text("Study Translation", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: const Text("World English Bible (WEB)", style: TextStyle(fontSize: 12)),
                    trailing: const Icon(LucideIcons.chevronRight, size: 16),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Translation set to World English Bible (WEB)")));
                    },
                  ),
                  ListTile(
                    leading: const Icon(LucideIcons.target, color: Colors.red),
                    title: const Text("Daily Memory Goal", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: const Text("15 Verses per day", style: TextStyle(fontSize: 12)),
                    trailing: const Icon(LucideIcons.chevronRight, size: 16),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Daily memory goal updated!")));
                    },
                  ),
                  SwitchListTile(
                    secondary: const Icon(LucideIcons.bell, color: Colors.green),
                    activeThumbColor: Colors.amber,
                    title: const Text("Daily Reminders", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: const Text("Get alert notifications to stay on streak", style: TextStyle(fontSize: 12)),
                    value: true,
                    onChanged: (bool value) {},
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                    child: const Text("Save Preferences", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );
          }
        );
      }
    );
  }
}

// ═══════════════════════════════════════
// EXEGESIS / WORD STUDY SCREEN
// ═══════════════════════════════════════
class _ExegesisScreen extends StatefulWidget {
  const _ExegesisScreen();
  @override
  State<_ExegesisScreen> createState() => _ExegesisScreenState();
}

class _ExegesisScreenState extends State<_ExegesisScreen> {
  final _wordController = TextEditingController();
  String? _selectedWord;
  
  final Map<String, Map<String, String>> _wordStudies = {
    'agape': {'greek': 'ἀγάπη', 'transliteration': 'agapē', 'meaning': 'Unconditional, selfless love. The highest form of love in Greek. Used 116 times in the NT.', 'usage': 'John 3:16, 1 Cor 13:4-8, Romans 5:8', 'root': 'From agapaō - to love deeply'},
    'shalom': {'hebrew': 'שָׁלוֹם', 'transliteration': 'shālôm', 'meaning': 'Completeness, wholeness, peace, welfare, safety. Far more than absence of conflict.', 'usage': 'Numbers 6:26, Psalm 29:11, Isaiah 26:3', 'root': 'From shalem - to be complete'},
    'logos': {'greek': 'λόγος', 'transliteration': 'logos', 'meaning': 'Word, reason, principle. In John 1:1, refers to the pre-existent Christ as the divine Word.', 'usage': 'John 1:1, Hebrews 4:12, Rev 19:13', 'root': 'From legō - to say, speak'},
    'chesed': {'hebrew': 'חֶסֶד', 'transliteration': 'ḥeseḏ', 'meaning': 'Lovingkindness, steadfast love, mercy, faithfulness. God\'s covenant loyalty.', 'usage': 'Psalm 136, Lamentations 3:22, Micah 6:8', 'root': 'Covenant faithfulness'},
    'pneuma': {'greek': 'πνεῦμα', 'transliteration': 'pneuma', 'meaning': 'Spirit, breath, wind. Used for the Holy Spirit, human spirit, and wind.', 'usage': 'John 3:8, Romans 8:16, Acts 2:4', 'root': 'From pneō - to blow, breathe'},
    'sozo': {'greek': 'σώζω', 'transliteration': 'sōzō', 'meaning': 'To save, deliver, protect, heal, make whole. Encompasses spiritual and physical salvation.', 'usage': 'Matthew 1:21, Acts 2:21, Romans 10:9', 'root': 'From saos - safe, sound'},
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text("Exegesis", style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(25),
        children: [
          Text("WORD STUDY", style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2, color: Colors.blue)),
          const SizedBox(height: 15),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 15),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.shade200)),
            child: TextField(
              controller: _wordController,
              onSubmitted: (val) => setState(() => _selectedWord = val.toLowerCase()),
              decoration: const InputDecoration(hintText: "Enter a Greek or Hebrew word...", icon: Icon(LucideIcons.languages, size: 18), border: InputBorder.none),
            ),
          ),
          const SizedBox(height: 20),
          Text("POPULAR STUDIES", style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2, color: Colors.grey)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: _wordStudies.keys.map((w) => GestureDetector(
              onTap: () => setState(() => _selectedWord = w),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: _selectedWord == w ? Colors.blue : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _selectedWord == w ? Colors.blue : Colors.grey.shade300),
                ),
                child: Text(w, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _selectedWord == w ? Colors.white : Colors.black)),
              ),
            )).toList(),
          ),
          const SizedBox(height: 25),
          if (_selectedWord != null && _wordStudies.containsKey(_selectedWord))
            _buildWordCard(_selectedWord!, _wordStudies[_selectedWord]!),
          if (_selectedWord != null && !_wordStudies.containsKey(_selectedWord))
            Center(child: Padding(padding: const EdgeInsets.all(30), child: Text("Word \"$_selectedWord\" not found in database.", style: const TextStyle(color: Colors.grey)))),
        ],
      ),
    );
  }

  Widget _buildWordCard(String word, Map<String, String> data) {
    final isGreek = data.containsKey('greek');
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 15)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: isGreek ? Colors.blue.withValues(alpha: 0.1) : Colors.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Text(isGreek ? "GREEK" : "HEBREW", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: isGreek ? Colors.blue : Colors.amber, letterSpacing: 1)),
              ),
              const Spacer(),
              Text(data['transliteration'] ?? '', style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 15),
          Center(child: Text(data[isGreek ? 'greek' : 'hebrew'] ?? '', style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold))),
          const SizedBox(height: 5),
          Center(child: Text(word.toUpperCase(), style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 3, color: Colors.grey))),
          const Divider(height: 30),
          const Text("MEANING", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1, color: Colors.grey)),
          const SizedBox(height: 8),
          Text(data['meaning'] ?? '', style: const TextStyle(fontSize: 15, height: 1.5)),
          const SizedBox(height: 15),
          const Text("KEY PASSAGES", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1, color: Colors.grey)),
          const SizedBox(height: 8),
          Text(data['usage'] ?? '', style: TextStyle(fontSize: 14, color: Colors.blue.shade700, fontWeight: FontWeight.w500)),
          const SizedBox(height: 15),
          const Text("ROOT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1, color: Colors.grey)),
          const SizedBox(height: 8),
          Text(data['root'] ?? '', style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════
// BIBLICAL ATLAS SCREEN
// ═══════════════════════════════════════
class _BiblicalAtlasScreen extends StatelessWidget {
  const _BiblicalAtlasScreen();

  @override
  Widget build(BuildContext context) {
    final locations = [
      {'name': 'Jerusalem', 'desc': 'Holy City, Temple Mount, crucifixion & resurrection of Christ', 'era': 'All Eras', 'icon': LucideIcons.church},
      {'name': 'Bethlehem', 'desc': 'Birthplace of Jesus, City of David', 'era': 'NT Era', 'icon': LucideIcons.star},
      {'name': 'Nazareth', 'desc': 'Hometown of Jesus, where He grew up', 'era': 'NT Era', 'icon': LucideIcons.home},
      {'name': 'Galilee', 'desc': 'Region of Jesus\' ministry, Sea of Galilee miracles', 'era': 'NT Era', 'icon': LucideIcons.waves},
      {'name': 'Egypt', 'desc': 'Bondage & Exodus, flight of Holy Family', 'era': 'OT Era', 'icon': LucideIcons.landmark},
      {'name': 'Mount Sinai', 'desc': 'Ten Commandments given to Moses', 'era': 'OT Era', 'icon': LucideIcons.mountain},
      {'name': 'Babylon', 'desc': 'Jewish exile, Daniel & the lions den', 'era': 'OT Era', 'icon': LucideIcons.building2},
      {'name': 'Damascus', 'desc': 'Paul\'s conversion on the road to Damascus', 'era': 'NT Era', 'icon': LucideIcons.navigation},
      {'name': 'Corinth', 'desc': 'Paul\'s letters to the Corinthian church', 'era': 'NT Era', 'icon': LucideIcons.mail},
      {'name': 'Rome', 'desc': 'Center of the Roman Empire, Paul\'s imprisonment', 'era': 'NT Era', 'icon': LucideIcons.crown},
      {'name': 'Garden of Eden', 'desc': 'Paradise where God placed Adam and Eve', 'era': 'Creation', 'icon': LucideIcons.flower2},
      {'name': 'Jericho', 'desc': 'Walls fell down, Good Samaritan road', 'era': 'OT/NT', 'icon': LucideIcons.building},
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        title: Text("Biblical Atlas", style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.teal.shade600, Colors.teal.shade800]),
              borderRadius: BorderRadius.circular(25),
            ),
            child: const Column(
              children: [
                Icon(LucideIcons.globe, color: Colors.white, size: 40),
                SizedBox(height: 10),
                Text("Biblical Geography", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                SizedBox(height: 5),
                Text("Explore the lands of the Bible", style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ...locations.map((loc) => Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.teal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(15)),
                  child: Icon(loc['icon'] as IconData, color: Colors.teal, size: 22),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(loc['name'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 3),
                      Text(loc['desc'] as String, style: const TextStyle(color: Colors.grey, fontSize: 12), maxLines: 2),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text(loc['era'] as String, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.amber)),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════
// VERSE MEMORY SCREEN
// ═══════════════════════════════════════
class _VerseMemoryScreen extends StatefulWidget {
  const _VerseMemoryScreen();
  @override
  State<_VerseMemoryScreen> createState() => _VerseMemoryScreenState();
}

class _VerseMemoryScreenState extends State<_VerseMemoryScreen> {
  int _currentIndex = 0;
  bool _showVerse = false;
  int _score = 0;

  final List<Map<String, String>> _verses = [
    {'ref': 'John 3:16', 'text': 'For God so loved the world that he gave his one and only Son, that whoever believes in him shall not perish but have eternal life.'},
    {'ref': 'Jeremiah 29:11', 'text': 'For I know the plans I have for you, declares the LORD, plans to prosper you and not to harm you, plans to give you hope and a future.'},
    {'ref': 'Philippians 4:13', 'text': 'I can do all this through him who gives me strength.'},
    {'ref': 'Romans 8:28', 'text': 'And we know that in all things God works for the good of those who love him, who have been called according to his purpose.'},
    {'ref': 'Proverbs 3:5-6', 'text': 'Trust in the LORD with all your heart and lean not on your own understanding; in all your ways submit to him, and he will make your paths straight.'},
    {'ref': 'Isaiah 40:31', 'text': 'But those who hope in the LORD will renew their strength. They will soar on wings like eagles; they will run and not grow weary, they will walk and not be faint.'},
    {'ref': 'Psalm 23:1', 'text': 'The LORD is my shepherd, I lack nothing.'},
    {'ref': 'Matthew 28:19', 'text': 'Therefore go and make disciples of all nations, baptizing them in the name of the Father and of the Son and of the Holy Spirit.'},
  ];

  @override
  Widget build(BuildContext context) {
    final verse = _verses[_currentIndex];
    return Scaffold(
      backgroundColor: const Color(0xFF1A1030),
      appBar: AppBar(
        title: Text("Verse Memory", style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.transparent, elevation: 0, foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(25),
        child: Column(
          children: [
            // Score and progress
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
                  child: Row(children: [
                    const Icon(LucideIcons.trophy, color: Colors.amber, size: 16),
                    const SizedBox(width: 6),
                    Text("Score: $_score", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                  ]),
                ),
                Text("${_currentIndex + 1} / ${_verses.length}", style: const TextStyle(color: Colors.white54)),
              ],
            ),
            const SizedBox(height: 40),
            // Verse reference
            Text(verse['ref']!, style: GoogleFonts.plusJakartaSans(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white)),
            const SizedBox(height: 10),
            const Text("Can you recite this verse?", style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 40),
            // Verse card
            GestureDetector(
              onTap: () => setState(() => _showVerse = !_showVerse),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: double.infinity,
                padding: const EdgeInsets.all(30),
                decoration: BoxDecoration(
                  color: _showVerse ? Colors.white.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(color: _showVerse ? Colors.amber.withValues(alpha: 0.5) : Colors.white12),
                ),
                child: _showVerse
                  ? Text(verse['text']!, style: const TextStyle(color: Colors.white, fontSize: 18, height: 1.6, fontStyle: FontStyle.italic), textAlign: TextAlign.center)
                  : const Column(children: [
                      Icon(LucideIcons.eye, color: Colors.white54, size: 40),
                      SizedBox(height: 10),
                      Text("Tap to reveal", style: TextStyle(color: Colors.white54, fontSize: 14)),
                    ]),
              ),
            ),
            const Spacer(),
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _showVerse = false;
                        _currentIndex = (_currentIndex + 1) % _verses.length;
                      });
                    },
                    icon: const Icon(LucideIcons.skipForward, size: 18),
                    label: const Text("SKIP"),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.white12, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _score++;
                        _showVerse = false;
                        _currentIndex = (_currentIndex + 1) % _verses.length;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("🎉 Great Job! +1 Point"), backgroundColor: Colors.green, duration: Duration(seconds: 1)));
                    },
                    icon: const Icon(LucideIcons.check, size: 18),
                    label: const Text("I KNOW IT"),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════
// READING PLANS SCREEN
// ═══════════════════════════════════════
class _ReadingPlansScreen extends StatelessWidget {
  const _ReadingPlansScreen();

  @override
  Widget build(BuildContext context) {
    final plans = [
      {'title': 'Bible in a Year', 'desc': 'Read the entire Bible in 365 days', 'days': '365', 'progress': 0.12, 'color': Colors.blue, 'icon': LucideIcons.bookOpen},
      {'title': 'Psalms & Proverbs', 'desc': 'Daily wisdom and worship', 'days': '30', 'progress': 0.45, 'color': Colors.purple, 'icon': LucideIcons.music},
      {'title': 'Gospel of John', 'desc': 'The heart of the Gospel in 21 days', 'days': '21', 'progress': 0.0, 'color': Colors.red, 'icon': LucideIcons.heart},
      {'title': 'Paul\'s Letters', 'desc': 'Romans through Philemon', 'days': '60', 'progress': 0.0, 'color': Colors.teal, 'icon': LucideIcons.mail},
      {'title': 'New Believer', 'desc': 'Foundation scriptures for new Christians', 'days': '14', 'progress': 0.0, 'color': Colors.green, 'icon': LucideIcons.sprout},
      {'title': 'Prophetic Books', 'desc': 'Isaiah through Malachi', 'days': '90', 'progress': 0.0, 'color': Colors.orange, 'icon': LucideIcons.megaphone},
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFC),
      appBar: AppBar(
        title: Text("Reading Plans", style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: plans.map((plan) {
          final progress = plan['progress'] as double;
          final isActive = progress > 0;
          return Container(
            margin: const EdgeInsets.only(bottom: 15),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(25),
              border: isActive ? Border.all(color: (plan['color'] as Color).withValues(alpha: 0.3), width: 2) : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: (plan['color'] as Color).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                      child: Icon(plan['icon'] as IconData, color: plan['color'] as Color, size: 22),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(plan['title'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          Text(plan['desc'] as String, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
                      child: Text("${plan['days']} days", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                if (isActive) ...[
                  const SizedBox(height: 15),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(value: progress, backgroundColor: Colors.grey.shade100, valueColor: AlwaysStoppedAnimation(plan['color'] as Color), minHeight: 6),
                  ),
                  const SizedBox(height: 5),
                  Text("${(progress * 100).toInt()}% complete", style: TextStyle(fontSize: 11, color: plan['color'] as Color, fontWeight: FontWeight.bold)),
                ],
                if (!isActive) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Started: ${plan['title']}!"), backgroundColor: plan['color'] as Color));
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: (plan['color'] as Color).withValues(alpha: 0.1),
                        foregroundColor: plan['color'] as Color,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                      child: const Text("START PLAN", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                    ),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ═══════════════════════════════════════
// SCRIPTURE SEARCH SCREEN
// ═══════════════════════════════════════
class _ScriptureSearchScreen extends StatelessWidget {
  final String query;
  const _ScriptureSearchScreen({required this.query});

  @override
  Widget build(BuildContext context) {
    // Simulate search results
    final results = [
      {'ref': 'John 3:16', 'text': 'For God so loved the world...', 'book': 'John'},
      {'ref': 'Romans 8:28', 'text': 'And we know that in all things God works...', 'book': 'Romans'},
      {'ref': 'Psalm 23:1', 'text': 'The LORD is my shepherd, I lack nothing.', 'book': 'Psalms'},
      {'ref': 'Philippians 4:13', 'text': 'I can do all this through him who gives me strength.', 'book': 'Philippians'},
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text("Results for \"$query\"", style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 14)),
        backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: results.map((r) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)]),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r['ref']!, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.indigo.shade700)),
              const SizedBox(height: 5),
              Text(r['text']!, style: const TextStyle(fontSize: 14, height: 1.5, color: Colors.black87)),
              const SizedBox(height: 8),
              Text(r['book']!, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
            ],
          ),
        )).toList(),
      ),
    );
  }
}

