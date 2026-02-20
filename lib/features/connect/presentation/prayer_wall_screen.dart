import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:animations/animations.dart';
import '../../../core/widgets/kingdom_logo.dart';
import '../data/prayer_service.dart';

class PrayerWallScreen extends ConsumerStatefulWidget {
  const PrayerWallScreen({super.key});

  @override
  ConsumerState<PrayerWallScreen> createState() => _PrayerWallScreenState();
}

class _PrayerWallScreenState extends ConsumerState<PrayerWallScreen> {
  String _selectedCategory = 'all';
  final _contentController = TextEditingController();
  bool _isAnonymous = false;
  String _visibility = 'public';
  String _newCategory = 'other';

  final List<Map<String, dynamic>> _categories = [
    {'id': 'healing', 'label': 'Healing', 'emoji': '🏥', 'color': Colors.red},
    {'id': 'guidance', 'label': 'Guidance', 'emoji': '🧭', 'color': Colors.blue},
    {'id': 'thanksgiving', 'label': 'Thanksgiving', 'emoji': '🙏', 'color': Colors.green},
    {'id': 'provision', 'label': 'Provision', 'emoji': '💰', 'color': Colors.orange},
    {'id': 'family', 'label': 'Family', 'emoji': '👨‍👩‍👧‍👦', 'color': Colors.purple},
    {'id': 'other', 'label': 'Other', 'emoji': '✨', 'color': Colors.grey},
  ];

  @override
  Widget build(BuildContext context) {
    final prayersAsync = ref.watch(prayerStreamProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF1B0B3B), // Deep Purple from React version
      body: Column(
        children: [
          _buildHeader(),
          _buildCategoryFilter(),
          Expanded(
            child: prayersAsync.when(
              data: (prayers) {
                final filtered = _selectedCategory == 'all'
                    ? prayers
                    : prayers.where((p) => p.category == _selectedCategory).toList();
                
                if (filtered.isEmpty) {
                  return _buildEmptyState();
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) => _buildPrayerCard(filtered[index]),
                );
              },
              loading: () => Center(child: CircularProgressIndicator(color: Theme.of(context).primaryColor)),
              error: (err, stack) => _buildMockList(), // Fallback for prototype
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreatePrayerSheet(),
        backgroundColor: Colors.purple,
        child: const Icon(LucideIcons.plus, color: Colors.white),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 10, bottom: 20, left: 20, right: 20),
      color: Colors.black.withOpacity(0.2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          const KingdomLogo(size: 32, white: true),
          const Column(
            children: [
              Text("PRAYER WALL", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 2)),
              Text("Faithful Community", style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildCategoryFilter() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          _buildFilterChip('all', 'All', '🙌'),
          ..._categories.map((cat) => _buildFilterChip(cat['id'], cat['label'], cat['emoji'])),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String id, String label, String emoji) {
    final isSelected = _selectedCategory == id;
    return GestureDetector(
      onTap: () => setState(() => _selectedCategory = id),
      child: Container(
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Center(
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: isSelected ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPrayerCard(PrayerRequest prayer) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.purple.withOpacity(0.2),
                backgroundImage: prayer.userPhoto != null ? NetworkImage(prayer.userPhoto!) : null,
                child: prayer.userPhoto == null ? Text(prayer.userName[0], style: const TextStyle(color: Colors.white)) : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(prayer.userName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    Text("${prayer.createdAt.day}m ago", style: const TextStyle(color: Colors.grey, fontSize: 10)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (_categories.firstWhere((c) => c['id'] == prayer.category)['color'] as Color).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  prayer.category.toUpperCase(),
                  style: TextStyle(
                    color: _categories.firstWhere((c) => c['id'] == prayer.category)['color'],
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Text(prayer.content, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.5)),
          if (prayer.aiEncouragement != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.purple.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(LucideIcons.sparkles, color: Colors.purpleAccent, size: 12),
                      SizedBox(width: 6),
                      Text("WORD OF ENCOURAGEMENT", style: TextStyle(color: Colors.purpleAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text("\"${prayer.aiEncouragement}\"", style: const TextStyle(color: Colors.white70, fontSize: 13, fontStyle: FontStyle.italic)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () => ref.read(prayerServiceProvider).prayForRequest(prayer.id, prayer.prayedBy),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.heart, color: Colors.pinkAccent, size: 16),
                      const SizedBox(width: 8),
                      Text("${prayer.prayerCount} PRAYING", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              const Icon(LucideIcons.messageCircle, color: Colors.grey, size: 18),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text("🙏", style: TextStyle(fontSize: 60)),
          const SizedBox(height: 20),
          const Text("No prayers yet", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          Text("Be the first to share what's on your heart", style: TextStyle(color: Colors.white.withOpacity(0.6))),
        ],
      ),
    );
  }

  Widget _buildMockList() {
    // Add some mock data to make it look alive during prototype
    final mockPrayers = [
      PrayerRequest(
        id: '1',
        userId: 'u1',
        userName: 'Believer John',
        content: 'Please pray for my mother who is undergoing surgery tomorrow. We trust in the Great Physician.',
        category: 'healing',
        visibility: 'public',
        prayerCount: 12,
        prayedBy: [],
        isAnonymous: false,
        aiEncouragement: 'God is your refuge and strength, an ever-present help in trouble.',
        createdAt: DateTime.now().subtract(const Duration(minutes: 15)),
      ),
      PrayerRequest(
        id: '2',
        userId: 'u2',
        userName: 'Sister Mary',
        content: 'Thanking God for His provision! I just secured a new job after months of searching. To God be the glory!',
        category: 'thanksgiving',
        visibility: 'public',
        prayerCount: 45,
        prayedBy: [],
        isAnonymous: false,
        aiEncouragement: 'Rejoice in the Lord always; again I will say, rejoice.',
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      ),
    ];

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: mockPrayers.length,
      itemBuilder: (context, index) => _buildPrayerCard(mockPrayers[index]),
    );
  }

  void _showCreatePrayerSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
          decoration: const BoxDecoration(
            color: Color(0xFF2D145D),
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Share a Prayer", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(LucideIcons.x, color: Colors.white), onPressed: () => Navigator.pop(context)),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _contentController,
                  maxLines: 4,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "What's on your heart?",
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 20),
                const Text("Category", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  children: _categories.map((cat) {
                    final isSelected = _newCategory == cat['id'];
                    return GestureDetector(
                      onTap: () => setModalState(() => _newCategory = cat['id']),
                      child: Chip(
                        backgroundColor: isSelected ? cat['color'] : Colors.white.withOpacity(0.05),
                        label: Text("${cat['emoji']} ${cat['label']}", style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 10)),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Post Anonymously", style: TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: Text("Your name won't be visible", style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12)),
                  trailing: Switch(
                    value: _isAnonymous,
                    onChanged: (val) => setModalState(() => _isAnonymous = val),
                    activeColor: Theme.of(context).primaryColor,
                  ),
                ),
                const SizedBox(height: 30),
                ElevatedButton(
                  onPressed: () {
                    ref.read(prayerServiceProvider).submitPrayer(_contentController.text, _newCategory, _visibility, _isAnonymous);
                    Navigator.pop(context);
                    _contentController.clear();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    minimumSize: const Size(double.infinity, 60),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  child: const Text("SUBMIT PRAYER", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
