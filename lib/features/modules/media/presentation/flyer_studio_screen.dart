import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/media_service.dart';

class FlyerStudioScreen extends ConsumerStatefulWidget {
  const FlyerStudioScreen({super.key});

  @override
  ConsumerState<FlyerStudioScreen> createState() => _FlyerStudioScreenState();
}

class _FlyerStudioScreenState extends ConsumerState<FlyerStudioScreen> {
  String _selectedTemplate = "Sunday Celebration";
  final List<String> _templates = [
    "Sunday Celebration",
    "Midweek Service",
    "Youth Conference",
    "Women's Meeting"
  ];
  
  final TextEditingController _sermonTitleController = TextEditingController(text: "The Power of Grace");
  final TextEditingController _preacherController = TextEditingController(text: "Bishop Mwansa");

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text("Flyer Studio V2"),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.download, color: Colors.blue),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Rendering ultra-high quality flyer to Gallery..."), backgroundColor: Colors.green),
              );
            },
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Preview Window
            Container(
              height: 400,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: BorderRadius.circular(20),
                image: const DecorationImage(
                  image: NetworkImage("https://images.unsplash.com/photo-1517457373958-b7bdd4587205?w=800&q=80"),
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(Colors.black54, BlendMode.darken),
                ),
                boxShadow: const [BoxShadow(color: Colors.black26, offset: Offset(0, 10), blurRadius: 20)],
              ),
              child: Padding(
                padding: const EdgeInsets.all(25),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text("SUNDAY MORNING", style: TextStyle(color: Color(0xFFFFD700), fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 2)),
                    const SizedBox(height: 10),
                    Text(
                      _sermonTitleController.text.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, height: 1.1),
                    ),
                    const Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircleAvatar(radius: 12, backgroundImage: NetworkImage("https://i.pravatar.cc/100")),
                        const SizedBox(width: 8),
                        Text(_preacherController.text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text("Starts at 09:00 AM • Main Auditorium", style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),
            
            const Text("Select Template", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 15),
            SizedBox(
              height: 45,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _templates.length,
                itemBuilder: (context, index) {
                  final t = _templates[index];
                  final isSelected = t == _selectedTemplate;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedTemplate = t),
                    child: Container(
                      margin: const EdgeInsets.only(right: 15),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? Theme.of(context).primaryColor : Colors.white,
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(color: isSelected ? Colors.transparent : Colors.grey[300]!)
                      ),
                      child: Text(t, style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? Theme.of(context).colorScheme.secondary : Colors.grey)),
                    ),
                  );
                },
              ),
            ),
            
            const SizedBox(height: 30),
            const Text("Flyer Details", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 15),
            TextField(
              controller: _sermonTitleController,
              onChanged: (v) => setState((){}),
              decoration: InputDecoration(
                labelText: "Sermon Title",
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                prefixIcon: const Icon(LucideIcons.type),
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _preacherController,
              onChanged: (v) => setState((){}),
              decoration: InputDecoration(
                labelText: "Preacher Name",
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                prefixIcon: const Icon(LucideIcons.user),
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () async {
                await ref.read(mediaServiceProvider).seedMedia();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Template data synchronized with Cloud. Sharing..."), backgroundColor: Colors.blue),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 60),
                backgroundColor: Theme.of(context).colorScheme.secondary,
                foregroundColor: Colors.white,
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.share2, size: 20),
                  SizedBox(width: 10),
                  Text("Share to Social Media", style: TextStyle(fontSize: 16)),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}

