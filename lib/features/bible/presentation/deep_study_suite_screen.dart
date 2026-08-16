import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/features/bible/data/study_settings_provider.dart';
import 'package:church_on_app/features/bible/data/strongs_lexicon.dart';
import 'package:church_on_app/features/bible/data/bible_translations.dart';
import 'package:church_on_app/features/bible/data/bible_service.dart';
import 'package:church_on_app/core/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'bible_podcast_screen.dart';
import 'daily_devotions_screen.dart';
import 'scripture_memory_screen.dart';
import 'study_plans_screen.dart';
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
    _cacheStudyDataOffline();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(profileProvider.notifier).updateReadingStreak();
    });
  }

  Future<void> _cacheStudyDataOffline() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_deep_study_access', DateTime.now().toIso8601String());
      await prefs.setBool('offline_study_ready', true);
    } catch (e) {
      debugPrint('Error caching deep study offline data: $e');
    }
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
      backgroundColor: Theme.of(context).colorScheme.surface,
      elevation: 0,
      leading: IconButton(
        icon: Icon(LucideIcons.arrowLeft, color: Theme.of(context).colorScheme.onSurface),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        IconButton(
          icon: Icon(LucideIcons.settings, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => _openSettingsDialog(),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.only(top: 80, left: 25, right: 25),
            child: Column(
              children: [
                Text("DEEP STUDY", style: GoogleFonts.plusJakartaSans(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                Text("THEOLOGICAL SUITE", style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 3, color: Theme.of(context).primaryColor)),
                const SizedBox(height: 15),
                _buildSearchBar(),
              ],
            ),
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
    final settings = ref.watch(studySettingsProvider);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFFFDA03), Color(0xFFE8A400)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Theme.of(context).primaryColor.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: const Icon(LucideIcons.bookOpen, color: Colors.black, size: 24),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Bible Reader", style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(_translationLabel(settings.preferredTranslation), style: const TextStyle(color: Colors.black87, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 25),
          const Text(
            "\"I have hidden your word in my heart that I might not sin against you.\"",
            style: TextStyle(color: Colors.black, fontSize: 18, fontStyle: FontStyle.italic, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          const Text("— PSALM 119:11", style: TextStyle(color: Colors.black87, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 2)),
        ],
      ),
    );
  }

  Widget _buildToolMatrix(BuildContext context) {
    final brand = Theme.of(context).primaryColor;
    final tools = [
      {"icon": LucideIcons.mic, "title": "Podcast", "sub": "Audio Bible", "color": Colors.red, "screen": const BiblePodcastScreen()},
      {"icon": LucideIcons.sword, "title": "Match", "sub": "Bible Quiz P2P", "color": Colors.orange, "screen": const BibleQuizHubScreen()},
      {"icon": LucideIcons.brain, "title": "Exegesis", "sub": "Word Study", "color": brand, "action": "exegesis"},
      {"icon": LucideIcons.map, "title": "Atlas", "sub": "Historic Maps", "color": const Color(0xFF10B981), "action": "atlas"},
      {"icon": LucideIcons.target, "title": "Memory", "sub": "Master Verses", "color": brand.withValues(alpha: 0.8), "action": "memory"},
      {"icon": LucideIcons.sunrise, "title": "Devotions", "sub": "Daily Devotionals", "color": Colors.amber, "screen": const DailyDevotionsScreen()},
      {"icon": LucideIcons.brainCircuit, "title": "Scripture", "sub": "Verse Memorizer", "color": brand.withValues(alpha: 0.6), "screen": const ScriptureMemoryScreen()},
      {"icon": LucideIcons.layers, "title": "Study Plans", "sub": "Track Progress", "color": brand.withValues(alpha: 0.45), "screen": const StudyPlansScreen()},
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.95),
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
    }
  }

  Widget _buildToolCard(IconData icon, String title, String sub, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(sub, style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _buildStreakCard(BuildContext context) {
    final profile = ref.watch(profileProvider).value;
    final streak = profile?.streakCount ?? 0;

    String tier;
    Color tierColor;
    IconData tierIcon;
    if (streak >= 365) { tier = "DIAMOND"; tierColor = const Color(0xFF00BFFF); tierIcon = LucideIcons.gem; }
    else if (streak >= 100) { tier = "GOLD"; tierColor = const Color(0xFFFFD700); tierIcon = LucideIcons.trophy; }
    else if (streak >= 30) { tier = "SILVER"; tierColor = const Color(0xFFC0C0C0); tierIcon = LucideIcons.medal; }
    else if (streak >= 7) { tier = "BRONZE"; tierColor = const Color(0xFFCD7F32); tierIcon = LucideIcons.award; }
    else { tier = "BEGINNER"; tierColor = Colors.white54; tierIcon = LucideIcons.sprout; }

    final weekDays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
    final today = DateTime.now().weekday - 1;
    final dayStatuses = List.generate(7, (i) => i <= today && streak > (today - i) ? true : false);

    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: streak >= 30 ? [Colors.amber.shade900, Colors.black] : [Colors.grey.shade900, Colors.black],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Colors.amber.withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(LucideIcons.flame, color: Colors.orange, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Study Streak", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    Row(
                      children: [
                        Icon(tierIcon, color: tierColor, size: 12),
                        const SizedBox(width: 4),
                        Text(tier, style: TextStyle(color: tierColor, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1)),
                        const SizedBox(width: 8),
                        Text("• ${streak}d streak", style: const TextStyle(color: Colors.white54, fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ),
              Text(streak.toString(), style: GoogleFonts.plusJakartaSans(fontSize: 42, fontWeight: FontWeight.w900, color: const Color(0xFFFFD700))),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (i) {
              final isActive = dayStatuses[i];
              final dayName = weekDays[i];
              final isToday = i == today;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isActive ? (isToday ? Colors.amber : Colors.amber.withValues(alpha: 0.4)) : Colors.white12,
                    ),
                    child: isActive
                      ? Icon(LucideIcons.check, size: 16, color: isToday ? Colors.black : Colors.amber)
                      : Icon(LucideIcons.circle, size: 12, color: Colors.white24),
                  ),
                  const SizedBox(height: 4),
                  Text(dayName, style: TextStyle(fontSize: 11, color: isToday ? Colors.amber : Colors.white38, fontWeight: isToday ? FontWeight.bold : FontWeight.normal)),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  void _openSettingsDialog() {
    final settings = ref.read(studySettingsProvider);
    final notifier = ref.read(studySettingsProvider.notifier);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(25, 25, 25, MediaQuery.of(context).padding.bottom + 20),
                child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Study Preferences", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                  const SizedBox(height: 5),
                  const Text("Customize your Deep Study Theological Suite settings.", style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const Divider(height: 30),
                  ListTile(
                    leading: Icon(LucideIcons.globe, color: Theme.of(context).primaryColor),
                    title: const Text("Study Translation", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: Text(_translationLabel(settings.preferredTranslation), style: const TextStyle(fontSize: 12)),
                    trailing: const Icon(LucideIcons.chevronRight, size: 16),
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                        builder: (_) => _translationPicker(settings, notifier, setModalState),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(LucideIcons.target, color: Colors.red),
                    title: const Text("Daily Memory Goal", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: Text("${settings.dailyMemoryVerseGoal} Verses per day", style: const TextStyle(fontSize: 12)),
                    trailing: const Icon(LucideIcons.chevronRight, size: 16),
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                        builder: (_) => _goalPicker(settings, notifier, setModalState),
                      );
                    },
                  ),
                  SwitchListTile(
                    secondary: const Icon(LucideIcons.bell, color: Colors.green),
                    activeThumbColor: Colors.amber,
                    title: const Text("Daily Reminders", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: Text(
                      settings.dailyReminders
                          ? "Reminders at ${settings.reminderTime.formatted}"
                          : "Get alert notifications to stay on streak",
                      style: const TextStyle(fontSize: 12),
                    ),
                    value: settings.dailyReminders,
                    onChanged: (bool value) async {
                      await notifier.setDailyReminders(value);
                      setModalState(() {});
                      try {
                        final notifService = ref.read(notificationServiceProvider);
                        if (value) {
                          final settings = ref.read(studySettingsProvider);
                          await notifService.scheduleDailyReminder(
                            hour: settings.reminderTime.hour,
                            minute: settings.reminderTime.minute,
                          );
                        } else {
                          await notifService.cancelDailyReminder();
                        }
                      } catch (e) {
                        debugPrint('Failed to schedule reminder: $e');
                      }
                      if (!context.mounted) return;
                      if (value) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text("Reminders set for ${settings.reminderTime.formatted}"),
                          backgroundColor: Colors.green,
                        ));
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text("Reminders disabled"),
                          backgroundColor: Colors.grey,
                        ));
                      }
                    },
                  ),
                  if (settings.dailyReminders)
                    ListTile(
                      leading: Icon(LucideIcons.clock, color: Theme.of(context).primaryColor.withValues(alpha: 0.8)),
                      title: const Text("Reminder Time", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: Text(settings.reminderTime.formatted, style: const TextStyle(fontSize: 12)),
                      trailing: const Icon(LucideIcons.chevronRight, size: 16),
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay(hour: settings.reminderTime.hour, minute: settings.reminderTime.minute),
                        );
                        if (picked != null) {
                          final pref = TimeOfDayPreference(hour: picked.hour, minute: picked.minute);
                          await notifier.setReminderTime(pref);
                          setModalState(() {});
                          try {
                            final notifService = ref.read(notificationServiceProvider);
                            await notifService.scheduleDailyReminder(hour: pref.hour, minute: pref.minute);
                          } catch (e) {
                            debugPrint('Failed to schedule reminder: $e');
                          }
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text("Reminders set for ${pref.formatted}"),
                            backgroundColor: Colors.green,
                          ));
                        }
                      },
                    ),
                  const SizedBox(height: 8),
                  ListTile(
                    leading: Icon(LucideIcons.calendarClock, color: Theme.of(context).primaryColor),
                    title: const Text("Set Weekly Reminder", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: const Text("Pick a day & time for weekly study alert", style: TextStyle(fontSize: 12)),
                    trailing: const Icon(LucideIcons.chevronRight, size: 16),
                    onTap: () async {
                      final day = await showDialog<String>(
                        context: context,
                        builder: (ctx) => SimpleDialog(
                          title: const Text("Select Day of the Week"),
                          children: ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'].map((d) => 
                            SimpleDialogOption(
                              onPressed: () => Navigator.pop(ctx, d),
                              child: Text(d, style: const TextStyle(fontWeight: FontWeight.w500)),
                            ),
                          ).toList(),
                        ),
                      );
                      if (day == null || !context.mounted) return;
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay(hour: settings.reminderTime.hour, minute: settings.reminderTime.minute),
                      );
                      if (picked != null) {
                        try {
                          final notifService = ref.read(notificationServiceProvider);
                          await notifService.scheduleWeeklyReminder(day: day, hour: picked.hour, minute: picked.minute);
                        } catch (e) {
                          debugPrint('Failed to schedule weekly reminder: $e');
                        }
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text("Weekly reminder set for $day at ${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}"),
                          backgroundColor: Colors.green,
                        ));
                      }
                    },
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                    child: const Text("Save Preferences", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              ),
            );
          }
        );
      }
    );
  }

  String _translationLabel(String code) {
    return getTranslationFullName(code);
  }

  Widget _translationPicker(StudySettings settings, StudySettingsNotifier notifier, StateSetter setModalState) {
    final translations = kEnglishTranslations
        .where(
          (t) =>
              t.remoteSupported ||
              t.code == 'nkjv' ||
              t.code == 'nlt',
        )
        .toList();
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: translations.map((t) {
          final isSelected = settings.preferredTranslation == t.code;
          return ListTile(
            leading: Icon(isSelected ? LucideIcons.checkCircle : LucideIcons.circle, color: isSelected ? Theme.of(context).primaryColor : Colors.grey),
            title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Text(t.shortName, style: const TextStyle(fontSize: 11)),
            onTap: () async {
              await notifier.setTranslation(t.code);
              setModalState(() {});
              if (!mounted) return;
              Navigator.pop(context);
            },
          );
        }).toList(),
      ),
    );
  }

  Widget _goalPicker(StudySettings settings, StudySettingsNotifier notifier, StateSetter setModalState) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(5, (i) {
          final goal = i + 1;
          final isSelected = settings.dailyMemoryVerseGoal == goal;
          return ListTile(
            leading: Icon(isSelected ? LucideIcons.checkCircle : LucideIcons.circle, color: isSelected ? Theme.of(context).primaryColor : Colors.grey),
            title: Text("$goal verse${goal > 1 ? 's' : ''} per day", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            onTap: () async {
              await notifier.setDailyMemoryVerseGoal(goal);
              setModalState(() {});
              if (!mounted) return;
              Navigator.pop(context);
            },
          );
        }),
      ),
    );
  }

}

String _translationLabelStatic(String code) {
  switch (code) {
    case 'kjv': return 'KJV';
    case 'web': return 'WEB';
    case 'niv': return 'NIV';
    case 'nkjv': return 'NKJV';
    default: return code.toUpperCase();
  }
}

// ═══════════════════════════════════════
// EXEGESIS / WORD STUDY SCREEN
// ═══════════════════════════════════════
class _ExegesisScreen extends ConsumerStatefulWidget {
  const _ExegesisScreen();
  @override
  ConsumerState<_ExegesisScreen> createState() => _ExegesisScreenState();
}

class _ExegesisScreenState extends ConsumerState<_ExegesisScreen> {
  final _wordController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _wordController.dispose();
    super.dispose();
  }

  void _runSearch(String v) => setState(() => _query = v.trim());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text("Exegesis", style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 0,
      ),
      body: Consumer(
        builder: (context, ref, _) {
          final settings = ref.watch(studySettingsProvider);
          final translationLabel = _translationLabelStatic(settings.preferredTranslation);
          final isStrongsNumber = RegExp(r'^[hgH G]?\s*\d+$').hasMatch(_query);
          final resultsAsync = _query.isEmpty
              ? ref.watch(strongsPopularProvider)
              : isStrongsNumber
                  ? ref.watch(strongsNumberProvider(_query))
                  : ref.watch(strongsSearchProvider(_query));
          return ListView(
            padding: const EdgeInsets.all(25),
            children: [
              Row(
                children: [
                  Text("WORD STUDY", style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2, color: Theme.of(context).primaryColor)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: Theme.of(context).primaryColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: Text(translationLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor)),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.shade200)),
                child: TextField(
                  controller: _wordController,
                  onChanged: _runSearch,
                  onSubmitted: _runSearch,
                  decoration: InputDecoration(
                    hintText: "Search 14,298 words… love, agape, shalom, H3068",
                    icon: const Icon(LucideIcons.languages, size: 18),
                    border: InputBorder.none,
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(LucideIcons.x, size: 18),
                            onPressed: () {
                              _wordController.clear();
                              _runSearch('');
                            },
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (_query.isEmpty) ...[
                Text("POPULAR STUDIES", style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2, color: Colors.grey)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: [
                    for (final label in const ['agape', 'shalom', 'logos', 'chesed', 'pneuma', 'grace', 'faith', 'love'])
                      _PopularChip(label: label, onTap: () {
                        _wordController.text = label;
                        _runSearch(label);
                      }),
                  ],
                ),
                const SizedBox(height: 25),
              ],
              resultsAsync.when(
                data: (words) => words.isEmpty
                    ? const Center(child: Padding(padding: EdgeInsets.all(30), child: Text("No entries found. Try \"love\", \"grace\" or a Strong's number.", style: TextStyle(color: Colors.grey))))
                    : Column(
                        children: [
                          for (final w in words) _LexiconCard(entry: w),
                        ],
                      ),
                loading: () => const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator())),
                error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(30), child: Text("Lexicon error: $e", style: const TextStyle(color: Colors.red)))),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PopularChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PopularChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black)),
      ),
    );
  }
}

/// Real Strong's entry card: original script, morphology, definitions,
/// derivation and KJV renderings.
class _LexiconCard extends StatelessWidget {
  final StrongsEntry entry;
  const _LexiconCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isGreek = !entry.isHebrew;
    final script = entry.word.isNotEmpty ? entry.word : entry.lemma;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 15)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: isGreek ? Theme.of(context).primaryColor.withValues(alpha: 0.1) : Colors.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Text(isGreek ? "GREEK" : "HEBREW", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: isGreek ? Theme.of(context).primaryColor : Colors.amber, letterSpacing: 1)),
              ),
              const SizedBox(width: 8),
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Text(entry.id, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1)),
              ),
              const Spacer(),
              if (entry.transliteration.isNotEmpty)
                Text(entry.transliteration, style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 15),
          Center(child: Text(script, style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold))),
          if (entry.lemma.isNotEmpty && entry.lemma != script) ...[
            const SizedBox(height: 5),
            Center(child: Text(entry.lemma, style: const TextStyle(fontSize: 22, color: Colors.grey))),
          ],
          if (entry.morphLabel.isNotEmpty) ...[
            const SizedBox(height: 5),
            Center(child: Text(entry.morphLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade600))),
          ],
          const Divider(height: 30),
          const Text("MEANING", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1, color: Colors.grey)),
          const SizedBox(height: 8),
          Text(entry.definition.isNotEmpty ? entry.definition : '(no definition)', style: const TextStyle(fontSize: 15, height: 1.5)),
          if (entry.explanation.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(entry.explanation, style: const TextStyle(fontSize: 14, height: 1.5, fontStyle: FontStyle.italic, color: Colors.blueGrey)),
          ],
          if (entry.derivation.isNotEmpty) ...[
            const SizedBox(height: 15),
            const Text("DERIVATION", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1, color: Colors.grey)),
            const SizedBox(height: 8),
            Text(entry.derivation, style: const TextStyle(fontSize: 14, height: 1.5)),
          ],
          if (entry.kjvRenderings.isNotEmpty) ...[
            const SizedBox(height: 15),
            const Text("KJV RENDERINGS", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1, color: Colors.grey)),
            const SizedBox(height: 8),
            Text(entry.kjvRenderings, style: TextStyle(fontSize: 14, color: const Color(0xFF7A5C00), fontWeight: FontWeight.w500)),
          ],
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
              gradient: const LinearGradient(colors: [Color(0xFFFFDA03), Color(0xFFE8A400)]),
              borderRadius: BorderRadius.circular(25),
            ),
            child: const Column(
              children: [
                Icon(LucideIcons.globe, color: Colors.black, size: 40),
                SizedBox(height: 10),
                Text("Biblical Geography", style: TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold)),
                SizedBox(height: 5),
                Text("Explore the lands of the Bible", style: TextStyle(color: Colors.black87, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ...locations.map((loc) => GestureDetector(
            onTap: () => _showLocationDetails(context, loc),
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Theme.of(context).primaryColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(15)),
                    child: Icon(loc['icon'] as IconData, color: Theme.of(context).primaryColor, size: 22),
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
                    child: Text(loc['era'] as String, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber)),
                  ),
                  const SizedBox(width: 8),
                  const Icon(LucideIcons.chevronRight, color: Colors.grey, size: 20),
                ],
              ),
            ),
          )),
        ],
      ),
    );
  }

  void _showLocationDetails(BuildContext context, Map<String, dynamic> loc) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: const BoxDecoration(
          color: Color(0xFFF0F4F8),
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Theme.of(context).primaryColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(15)),
                  child: Icon(loc['icon'] as IconData, color: Theme.of(context).primaryColor, size: 28),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(loc['name'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                        child: Text(loc['era'] as String, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text("Biblical Significance", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(loc['desc'] as String, style: const TextStyle(fontSize: 15, color: Colors.grey, height: 1.5)),
            const SizedBox(height: 20),
            const Text("Key Events", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            _buildLocationEvents(context, loc['name'] as String),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  // TODO: Open in maps/external app
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Map integration coming soon!"), backgroundColor: Colors.amber),
                  );
                },
                icon: const Icon(LucideIcons.mapPin, size: 18),
                label: const Text("View on Map"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationEvents(BuildContext context, String locationName) {
    final events = {
      'Jerusalem': ['Temple dedication', 'Crucifixion & Resurrection', 'Pentecost', 'Early church center'],
      'Bethlehem': ['Birth of Jesus', 'David anointed king', 'Ruth & Boaz story'],
      'Nazareth': ['Jesus\' childhood', 'Annunciation to Mary', 'Rejection in synagogue'],
      'Galilee': ['Feeding of 5000', 'Walking on water', 'Sermon on the Mount', 'Transfiguration'],
      'Egypt': ['Israel\'s bondage', 'Moses\' birth', 'Flight of Holy Family', 'Joseph\'s rise'],
      'Mount Sinai': ['Ten Commandments', 'Golden calf', 'Moses\' face shines'],
      'Babylon': ['Daniel in lions\' den', 'Fiery furnace', 'Jewish exile', 'Writing on the wall'],
      'Damascus': ['Paul\'s conversion', 'Ananias heals Paul', 'Early church persecution'],
      'Corinth': ['Paul\'s 18-month stay', '1 & 2 Corinthians written', 'Isthmian games'],
      'Rome': ['Paul\'s imprisonment', 'Peter\'s martyrdom', 'Catacombs', 'Constantine\'s conversion'],
      'Garden of Eden': ['Creation of Adam & Eve', 'The Fall', 'First promise of Messiah'],
      'Jericho': ['Walls fall down', 'Rahab saves spies', 'Good Samaritan road', 'Jesus heals blind man'],
    };
    
    final locationEvents = events[locationName] ?? ['Historical biblical site'];
    
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: locationEvents.map((event) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Theme.of(context).primaryColor.withValues(alpha: 0.3)),
        ),
        child: Text(event, style: TextStyle(fontSize: 12, color: Theme.of(context).primaryColor, fontWeight: FontWeight.w600)),
      )).toList(),
    );
  }
}

// ═══════════════════════════════════════
// VERSE MEMORY SCREEN
// ═══════════════════════════════════════
class _VerseMemoryScreen extends ConsumerStatefulWidget {
  const _VerseMemoryScreen();
  @override
  ConsumerState<_VerseMemoryScreen> createState() => _VerseMemoryScreenState();
}

class _VerseMemoryScreenState extends ConsumerState<_VerseMemoryScreen> {
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
    final settings = ref.watch(studySettingsProvider);
    final maxVerses = settings.dailyMemoryVerseGoal;
    final displayVerses = _verses.take(maxVerses).toList();
    if (displayVerses.isEmpty) return const SizedBox.shrink();
    final verse = displayVerses[_currentIndex % displayVerses.length];
    final liveText = ref
        .watch(bibleReferenceTextProvider(verse['ref']?.toString() ?? ''))
        .value;
    final verseText =
        (liveText != null && liveText.isNotEmpty)
            ? liveText
            : verse['text']?.toString() ?? '';
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
                Text("${_currentIndex + 1} / ${displayVerses.length}", style: const TextStyle(color: Colors.white54)),
              ],
            ),
            const SizedBox(height: 40),
            Text(verse['ref']?.toString() ?? '', style: GoogleFonts.plusJakartaSans(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white)),
            const SizedBox(height: 6),
            Text(getTranslationFullName(settings.preferredTranslation), style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
            const SizedBox(height: 10),
            const Text("Can you recite this verse?", style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 40),
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
                  ? Text(verseText, style: const TextStyle(color: Colors.white, fontSize: 18, height: 1.6, fontStyle: FontStyle.italic), textAlign: TextAlign.center)
                  : const Column(children: [
                      Icon(LucideIcons.eye, color: Colors.white54, size: 40),
                      SizedBox(height: 10),
                      Text("Tap to reveal", style: TextStyle(color: Colors.white54, fontSize: 14)),
                    ]),
              ),
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _showVerse = false;
                        _currentIndex = (_currentIndex + 1) % displayVerses.length;
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
                        _currentIndex = (_currentIndex + 1) % displayVerses.length;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Great Job! +1 Point"), backgroundColor: Colors.green, duration: Duration(seconds: 1)));
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
// READING PLANS — consolidated into StudyPlansScreen (study_plans_screen.dart)
// ═══════════════════════════════════════

// ═══════════════════════════════════════
// SCRIPTURE SEARCH SCREEN
// ═══════════════════════════════════════
class _ScriptureSearchScreen extends ConsumerStatefulWidget {
  final String query;
  const _ScriptureSearchScreen({required this.query});

  @override
  ConsumerState<_ScriptureSearchScreen> createState() => _ScriptureSearchScreenState();
}

class _ScriptureSearchScreenState extends ConsumerState<_ScriptureSearchScreen> {
  @override
  Widget build(BuildContext context) {
    final resultsAsync = ref.watch(scriptureSearchProvider(widget.query));

    return Scaffold(
      appBar: AppBar(
        title: Text("Results for \"${widget.query}\"", style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 14)),
        backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 0,
      ),
      body: resultsAsync.when(
        data: (results) {
          if (results.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Text(
                  "No matches found. Open a book in the Bible reader to add its translation to search.",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 14, height: 1.5),
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: results.length,
            itemBuilder: (context, index) {
              final r = results[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)]),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.reference, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Theme.of(context).primaryColor)),
                    const SizedBox(height: 5),
                    Text(r.text, style: const TextStyle(fontSize: 14, height: 1.5, color: Colors.black87)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (r.book.isNotEmpty) ...[
                          Text(r.book, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                        ],
                        if (r.translation.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(context).primaryColor.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(r.translation.toUpperCase(), style: TextStyle(fontSize: 10, color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text("Search failed: $e")),
      ),
    );
  }
}

