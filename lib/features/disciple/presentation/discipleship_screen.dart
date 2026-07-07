import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/utils/connectivity_util.dart';

class DiscipleshipScreen extends ConsumerStatefulWidget {
  const DiscipleshipScreen({super.key});

  @override
  ConsumerState<DiscipleshipScreen> createState() => _DiscipleshipScreenState();
}

class _DiscipleshipScreenState extends ConsumerState<DiscipleshipScreen> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = ref.watch(profileProvider).value;
    final isMentor = profile?.role == 'pastor' || profile?.isSuperadmin == true || profile?.isEmployee == true;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Discipleship"),
        actions: [
          IconButton(icon: const Icon(LucideIcons.userPlus), onPressed: () => _showFindMentor(context)),
        ],
      ),
      body: OfflineAwareWrapper(
        child: Column(
          children: [
            Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _tab("My Journey", 0),
                  if (isMentor) _tab("My Disciples", 1),
                  _tab("Milestones", 2),
                ],
              ),
            ),
            Expanded(child: _buildTabContent(isMentor)),
          ],
        ),
      ),
    );
  }

  Widget _tab(String label, int index) {
    final selected = _tabIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _tabIndex = index),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? Theme.of(context).primaryColor : Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label, style: TextStyle(
          color: selected ? Colors.white : Colors.grey,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        )),
      ),
    );
  }

  Widget _buildTabContent(bool isMentor) {
    switch (_tabIndex) {
      case 0: return _buildJourney();
      case 1: return isMentor ? _buildDisciples() : _buildJourney();
      case 2: return _buildMilestones();
      default: return _buildJourney();
    }
  }

  Widget _buildJourney() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildProgressCard(),
        const SizedBox(height: 20),
        const Text("Recommended Next Steps", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
        _buildStepCard("Water Baptism", "Take the first step of obedience", LucideIcons.droplets, false),
        _buildStepCard("Bible Reading Plan", "30-day Gospel of John", LucideIcons.bookOpen, false),
        _buildStepCard("Join a Small Group", "Connect with fellow believers", LucideIcons.users, false),
        _buildStepCard("Serve in Ministry", "Find your place to serve", LucideIcons.heart, true),
      ],
    );
  }

  Widget _buildProgressCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Theme.of(context).primaryColor, Theme.of(context).primaryColor.withValues(alpha: 0.7)]),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("My Discipleship Journey", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text("2 of 8 milestones completed", style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(value: 0.25, backgroundColor: Colors.white.withValues(alpha: 0.2), valueColor: const AlwaysStoppedAnimation(Colors.white), minHeight: 8),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Container(
            width: 60, height: 60,
            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.2)),
            child: const Icon(LucideIcons.trendingUp, color: Colors.white, size: 30),
          ),
        ],
      ),
    );
  }

  Widget _buildStepCard(String title, String subtitle, IconData icon, bool done) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: done ? Colors.green.withValues(alpha: 0.3) : Colors.grey.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: done ? Colors.green.withValues(alpha: 0.1) : Theme.of(context).primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: done ? Colors.green : Theme.of(context).primaryColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          Icon(done ? LucideIcons.checkCircle : LucideIcons.chevronRight, color: done ? Colors.green : Colors.grey, size: 20),
        ],
      ),
    );
  }

  Widget _buildDisciples() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            const Text("My Disciples", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Spacer(),
            Text("3 active", style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 16),
        _discipleCard("Sarah Banda", "Baptism", 3),
        _discipleCard("John Phiri", "Bible Study", 5),
        _discipleCard("Mary Zulu", "Small Group", 2),
      ],
    );
  }

  Widget _discipleCard(String name, String currentStep, int meetings) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.2),
            child: Text(name[0], style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text("Current: $currentStep • $meetings meetings", style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          Icon(LucideIcons.messageCircle, color: Theme.of(context).primaryColor, size: 20),
        ],
      ),
    );
  }

  Widget _buildMilestones() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            const Text("Completed Milestones", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Spacer(),
            IconButton(
              icon: const Icon(LucideIcons.plus, size: 20),
              onPressed: () { /* Add milestone dialog */ },
              style: IconButton.styleFrom(backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _milestoneCard("Water Baptism", DateTime.now().subtract(const Duration(days: 30)), true),
        _milestoneCard("Salvation Prayer", DateTime.now().subtract(const Duration(days: 45)), true),
        _milestoneCard("Bible Reading: Genesis", null, false),
        _milestoneCard("Church Membership Class", null, false),
      ],
    );
  }

  Widget _milestoneCard(String title, DateTime? date, bool done) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: done ? Colors.green.withValues(alpha: 0.3) : Colors.grey.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? Colors.green : Colors.grey.withValues(alpha: 0.2),
            ),
            child: Icon(done ? LucideIcons.check : LucideIcons.clock, color: done ? Colors.white : Colors.grey, size: 16),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: done ? Colors.black : Colors.grey))),
          if (date != null)
            Text("${date.day}/${date.month}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  void _showFindMentor(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: const BoxDecoration(
          color: Color(0xFF0F172A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 24),
            const Text("Find a Mentor", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text("Connect with spiritual leaders for guidance", style: TextStyle(color: Colors.white.withValues(alpha: 0.5))),
            const SizedBox(height: 24),
            const TextField(
              decoration: InputDecoration(
                hintText: "Search mentors...",
                prefixIcon: Icon(LucideIcons.search, color: Colors.white38),
                filled: true,
                fillColor: Color(0xFF1E293B),
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14)), borderSide: BorderSide.none),
                hintStyle: TextStyle(color: Colors.white38),
              ),
              style: TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView(
                children: [
                  _mentorTile("Pastor John Banda", "Senior Pastor • 15 yrs", "I help believers grow in their faith journey."),
                  _mentorTile("Apostle Sarah Zulu", "Apostolic Leader • 20 yrs", "Called to raise and equip the next generation."),
                  _mentorTile("Pastor David Phiri", "Youth Pastor • 8 yrs", "Passionate about mentoring young adults."),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mentorTile(String name, String role, String bio) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          CircleAvatar(backgroundColor: Theme.of(context).primaryColor, child: Text(name[0], style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold))),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                Text(role, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                Text(bio, style: const TextStyle(color: Colors.white54, fontSize: 11), maxLines: 1),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).primaryColor, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), minimumSize: Size.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text("Connect", style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
