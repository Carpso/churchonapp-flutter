import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

class ActivityDetailsPage extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;

  const ActivityDetailsPage({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
  });

  static const _memoryVerses = [
    {"ref": "John 3:16", "text": "For God so loved the world that he gave his one and only Son..."},
    {"ref": "Psalm 23:1", "text": "The Lord is my shepherd; I shall not want."},
    {"ref": "Philippians 4:13", "text": "I can do all things through Christ who strengthens me."},
    {"ref": "Proverbs 3:5", "text": "Trust in the Lord with all your heart and lean not on your own understanding."},
    {"ref": "Jeremiah 29:11", "text": "For I know the plans I have for you, declares the Lord..."},
  ];

  static const _triviaQuestions = [
    {"q": "How many books are in the Bible?", "a": "66"},
    {"q": "Who built the ark?", "a": "Noah"},
    {"q": "How many days did God create the world?", "a": "6"},
    {"q": "Who was the first man?", "a": "Adam"},
    {"q": "What did God send to save Noah's family?", "a": "An ark"},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: color,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: _buildContent(context),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    switch (title) {
      case "Memory Verses":
        return _buildMemoryVerses();
      case "Bible Trivia":
        return _buildBibleTrivia();
      case "Coloring Book":
        return _buildColoring();
      case "Sunday School":
        return _buildSundaySchool();
      default:
        return _buildPlaceholder();
    }
  }

  Widget _buildMemoryVerses() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Colors.blue.shade400, Colors.blue.shade700]),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Column(
            children: [
              Icon(LucideIcons.book, color: Colors.white, size: 40),
              SizedBox(height: 10),
              Text("Learn 5 Bible Verses", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              Text("Memorize and recite!", style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        ..._memoryVerses.map((v) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.blue.withValues(alpha: 0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(v["ref"]!, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 14)),
              const SizedBox(height: 5),
              Text(v["text"]!, style: const TextStyle(fontSize: 13, color: Colors.black87, fontStyle: FontStyle.italic)),
            ],
          ),
        )),
      ],
    );
  }

  Widget _buildBibleTrivia() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Colors.purple.shade400, Colors.purple.shade700]),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Column(
            children: [
              Icon(LucideIcons.helpCircle, color: Colors.white, size: 40),
              SizedBox(height: 10),
              Text("Bible Trivia Quiz", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              Text("Test your Bible knowledge!", style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        ..._triviaQuestions.map((q) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.purple.withValues(alpha: 0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(q["q"]!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text("Answer: ${q["a"]!}", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
        )),
      ],
    );
  }

  Widget _buildColoring() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Colors.pink.shade400, Colors.pink.shade600]),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Column(
            children: [
              Icon(LucideIcons.penTool, color: Colors.white, size: 40),
              SizedBox(height: 10),
              Text("Bible Coloring Pages", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              Text("Color and learn!", style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        ...[
          {"title": "Noah's Ark", "desc": "Color the animals on Noah's ark!"},
          {"title": "David & Goliath", "desc": "Color the story of David's victory!"},
          {"title": "Jonah & the Whale", "desc": "Color Jonah's underwater adventure!"},
          {"title": "Jesus Loves Children", "desc": "Color Jesus blessing the children!"},
        ].map((page) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.pink.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              Container(
                width: 60, height: 60,
                decoration: BoxDecoration(
                  color: Colors.pink.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(LucideIcons.image, color: Colors.pink, size: 30),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(page["title"]!, style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(page["desc"]!, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        )),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Row(
            children: [
              Icon(LucideIcons.info, color: Colors.amber, size: 20),
              SizedBox(width: 10),
              Expanded(child: Text("Coloring pages coming soon! Download printable versions.", style: TextStyle(fontSize: 12))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSundaySchool() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Colors.green.shade400, Colors.green.shade700]),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Column(
            children: [
              Icon(LucideIcons.video, color: Colors.white, size: 40),
              SizedBox(height: 10),
              Text("Sunday School", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              Text("Fun Bible lessons for kids!", style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        ...[
          _LessonData("The Creation Story", "Learn how God made the world in 7 days", LucideIcons.sun),
          _LessonData("Moses & the Red Sea", "Watch how God parted the sea for His people", LucideIcons.waves),
          _LessonData("Daniel in the Lion's Den", "Learn about Daniel's faith and courage", LucideIcons.shield),
          _LessonData("The Good Samaritan", "Jesus' story about loving your neighbor", LucideIcons.heart),
        ].map((lesson) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.green.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              Container(
                width: 50, height: 50,
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(lesson.icon, color: Colors.green, size: 28),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(lesson.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(lesson.desc, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        )),
      ],
    );
  }

  Widget _buildPlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 100),
          const SizedBox(height: 30),
          Text("Welcome to $title!", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          const SizedBox(height: 20),
          const Text(
            "Prepare for an exciting spiritual journey! This feature is being tuned for maximum fun and learning.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _LessonData {
  final String title;
  final String desc;
  final IconData icon;
  const _LessonData(this.title, this.desc, this.icon);
}
