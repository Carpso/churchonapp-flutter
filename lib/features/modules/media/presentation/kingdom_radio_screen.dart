import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

class KingdomRadioScreen extends ConsumerStatefulWidget {
  const KingdomRadioScreen({super.key});

  @override
  ConsumerState<KingdomRadioScreen> createState() => _KingdomRadioScreenState();
}

class _KingdomRadioScreenState extends ConsumerState<KingdomRadioScreen> {
  bool _isPlaying = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Kingdom Radio", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey.shade900,
                boxShadow: _isPlaying
                    ? [BoxShadow(color: Theme.of(context).primaryColor.withOpacity(0.5), blurRadius: 50, spreadRadius: 10)]
                    : [],
                image: const DecorationImage(
                  image: NetworkImage("https://images.unsplash.com/photo-1593697972674-8b010c7104b3?w=800&q=80"),
                  fit: BoxFit.cover,
                  opacity: 0.5,
                ),
              ),
              child: _isPlaying
                  ? Center(child: Image.network("https://i.giphy.com/media/xT9IgzoXWc3tM1m812/giphy.webp", width: 100))
                  : const Icon(LucideIcons.radio, color: Colors.white24, size: 80),
            ),
            const SizedBox(height: 50),
            const Text("LIVE: 24/7 Worship & Prophetic Hub", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const Text("Now Playing: So Will I - Hillsong United", style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 50),
            GestureDetector(
              onTap: () => setState(() => _isPlaying = !_isPlaying),
              child: Container(
                padding: const EdgeInsets.all(25),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(_isPlaying ? LucideIcons.pause : LucideIcons.play, color: Colors.black, size: 40),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
