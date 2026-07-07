import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

class WorshipSong {
  final String title;
  final String artist;
  final String lyrics;

  WorshipSong({required this.title, required this.artist, required this.lyrics});
}

class WorshipLyricsScreen extends StatefulWidget {
  const WorshipLyricsScreen({super.key});

  @override
  State<WorshipLyricsScreen> createState() => _WorshipLyricsScreenState();
}

class _WorshipLyricsScreenState extends State<WorshipLyricsScreen> {
  final List<WorshipSong> _songs = [
    WorshipSong(
      title: "How Great Is Our God",
      artist: "Chris Tomlin",
      lyrics: """[Verse 1]
The splendor of the King
Clothed in majesty
Let all the earth rejoice
All the earth rejoice

He wraps Himself in light
And darkness tries to hide
And trembles at His voice
And trembles at His voice

[Chorus]
How great is our God
Sing with me
How great is our God
And all will see how great
How great is our God

[Verse 2]
And age to age He stands
And time is in His hands
Beginning and the End
Beginning and the End

The Godhead, three in one
Father, Spirit, Son
The Lion and the Lamb
The Lion and the Lamb""",
    ),
    WorshipSong(
      title: "Mutsinde (Zambian Worship)",
      artist: "Zambian Hymnal",
      lyrics: """[Verse 1]
Mutsinde, mutsinde
Mwa Mulimu wa luna
Yena u na ni maata
U lu fa tulo kamita

[Chorus]
Mutsinde kapili
Haleluyah kaufela
Yena ya lu file bupilo
Lu to mu lumbeka kamita

[Verse 2]
Mwa lifasi kaufela
Lu lumbeke Libizo la Yena
Kakuli u na ni lilato
Le lituna hahulu""",
    ),
    WorshipSong(
      title: "Amazing Grace",
      artist: "John Newton",
      lyrics: """[Verse 1]
Amazing grace! How sweet the sound
That saved a wretch like me!
I once was lost, but now am found;
Was blind, but now I see.

[Verse 2]
'Twas grace that taught my heart to fear,
And grace my fears relieved;
How precious did that grace appear
The hour I first believed!

[Verse 3]
Through many dangers, toils and snares,
I have already come;
'Tis grace hath brought me safe thus far,
And grace will lead me home.""",
    ),
  ];

  List<WorshipSong> _filteredSongs = [];
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filteredSongs = _songs;
  }

  void _searchSong(String val) {
    setState(() {
      _filteredSongs = _songs
          .where((s) => s.title.toLowerCase().contains(val.toLowerCase()) || s.artist.toLowerCase().contains(val.toLowerCase()))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text("Worship Lyrics", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _searchSong,
              decoration: InputDecoration(
                hintText: "Search song or artist...",
                prefixIcon: const Icon(LucideIcons.search, color: Colors.teal),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _filteredSongs.length,
              itemBuilder: (context, index) => _buildSongTile(_filteredSongs[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSongTile(WorshipSong song) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.teal.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.teal.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: const Icon(LucideIcons.music, color: Colors.teal),
        ),
        title: Text(song.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(song.artist, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        trailing: const Icon(LucideIcons.chevronRight, color: Colors.grey),
        onTap: () => _openLyrics(song),
      ),
    );
  }

  void _openLyrics(WorshipSong song) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0F172A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          padding: const EdgeInsets.all(25),
          child: ListView(
            controller: scrollController,
            children: [
              Center(child: Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(5)))),
              const SizedBox(height: 25),
              Text(song.title, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              Text(song.artist, style: const TextStyle(color: Colors.tealAccent, fontSize: 14)),
              const SizedBox(height: 30),
              Text(
                song.lyrics,
                style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.8, letterSpacing: 0.5),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
