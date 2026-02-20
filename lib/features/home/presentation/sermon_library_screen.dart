import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../data/sermon_service.dart';
import 'sermon_player_screen.dart';

class SermonLibraryScreen extends StatefulWidget {
  const SermonLibraryScreen({super.key});

  @override
  State<SermonLibraryScreen> createState() => _SermonLibraryScreenState();
}

class _SermonLibraryScreenState extends State<SermonLibraryScreen> {
  String _selectedCategory = "All";
  final List<String> _categories = ["All", "Miracles", "Faith", "Prosperity", "Healing", "Worship"];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text("Kingdom Sermon Library", style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(LucideIcons.search), onPressed: () {}),
          IconButton(icon: const Icon(LucideIcons.filter), onPressed: () {}),
        ],
      ),
      body: Column(
        children: [
          _buildCategoryFilter(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: 6, // Mock count
              itemBuilder: (context, index) {
                return _buildSermonCard(index);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilter() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final bool isSelected = _selectedCategory == _categories[index];
          return GestureDetector(
            onTap: () => setState(() => _selectedCategory = _categories[index]),
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: isSelected ? Theme.of(context).colorScheme.secondary : Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: isSelected ? [BoxShadow(color: Theme.of(context).colorScheme.secondary.withOpacity(0.3), blurRadius: 10)] : [],
              ),
              child: Center(
                child: Text(
                  _categories[index],
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSermonCard(int index) {
    return GestureDetector(
      onTap: () {
        final sermon = Sermon(
          id: index.toString(),
          title: "Living by Faith in a Modern World",
          preacher: "Bishop John Mwansa",
          thumbnailUrl: "https://images.unsplash.com/photo-1544427928-c49cdfebf4ad?w=800&q=80&sig=$index",
          videoUrl: "https://assets.mixkit.co/videos/preview/mixkit-pastor-preaching-at-a-church-service-34538-large.mp4",
          createdAt: DateTime.now(),
        );
        Navigator.push(context, MaterialPageRoute(builder: (context) => SermonPlayerScreen(sermon: sermon)));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  height: 180,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                    image: DecorationImage(
                      image: NetworkImage("https://images.unsplash.com/photo-1544427928-c49cdfebf4ad?w=800&q=80&sig=$index"),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 15,
                  right: 15,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                    child: const Icon(LucideIcons.play, color: Colors.white, size: 20),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(8)),
                  child: const Text("NEW", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 8)),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("SUNDAY MORNING", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  const SizedBox(height: 5),
                  const Text("Living by Faith in a Modern World", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      CircleAvatar(radius: 10, backgroundImage: NetworkImage("https://i.pravatar.cc/100")),
                      const SizedBox(width: 10),
                      Text("Bishop John Mwansa", style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                      const Spacer(),
                      const Icon(LucideIcons.clock, size: 14, color: Colors.grey),
                      const SizedBox(width: 5),
                      const Text("45:00", style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
