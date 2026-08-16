import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WorshipSong {
  final String title;
  final String artist;
  final String lyrics;
  final String category;

  WorshipSong({required this.title, required this.artist, required this.lyrics, this.category = 'Contemporary'});
}

class WorshipLyricsScreen extends StatefulWidget {
  const WorshipLyricsScreen({super.key});

  @override
  State<WorshipLyricsScreen> createState() => _WorshipLyricsScreenState();
}

class _WorshipLyricsScreenState extends State<WorshipLyricsScreen> {
  List<WorshipSong> _allSongs = [];
  List<WorshipSong> _filteredSongs = [];
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  String _selectedCategory = 'All';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSongs();
  }

  Future<void> _loadSongs() async {
    try {
      final data = await Supabase.instance.client
          .from('lyrics')
          .select('title, artist, lyrics, category')
          .order('title', ascending: true);
      final songs = (data as List).map((e) => WorshipSong(
        title: e['title'] as String? ?? '',
        artist: e['artist'] as String? ?? 'Unknown',
        lyrics: e['lyrics'] as String? ?? '',
        category: e['category'] as String? ?? 'Contemporary',
      )).toList();
      if (mounted) {
        setState(() {
          _allSongs = songs;
          _filteredSongs = songs;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Failed to load worship songs: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String val) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _filterSongs();
    });
  }

  void _filterSongs() {
    final query = _searchCtrl.text.toLowerCase();
    setState(() {
      _filteredSongs = _allSongs.where((s) {
        final matchesCategory = _selectedCategory == 'All' || s.category == _selectedCategory;
        final matchesSearch = query.isEmpty ||
            s.title.toLowerCase().contains(query) ||
            s.artist.toLowerCase().contains(query);
        return matchesCategory && matchesSearch;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Worship Lyrics", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.black,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await _showAddLyricsSheet(context);
          _loadSongs();
        },
        backgroundColor: Theme.of(context).primaryColor,
        child: const Icon(LucideIcons.plus, color: Colors.black),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            color: Theme.of(context).primaryColor,
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: "Search song or artist...",
                hintStyle: const TextStyle(color: Colors.black45),
                prefixIcon: const Icon(LucideIcons.search, color: Colors.black54),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.35),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
              style: const TextStyle(color: Colors.black87),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            color: Theme.of(context).primaryColor,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ['All', 'Hymns', 'Contemporary', 'Traditional'].map((cat) {
                  final isSelected = _selectedCategory == cat;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(cat, style: TextStyle(
                        color: isSelected ? Theme.of(context).primaryColor : const Color(0xFF7A5C00),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      )),
                      selected: isSelected,
                      onSelected: (_) {
                        setState(() => _selectedCategory = cat);
                        _filterSongs();
                      },
                      backgroundColor: Colors.white.withValues(alpha: 0.3),
                      selectedColor: Colors.white,
                      checkmarkColor: Theme.of(context).primaryColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredSongs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.music, size: 48, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text(
                          "No songs found",
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "Try a different search or category",
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
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
        boxShadow: [BoxShadow(color: Theme.of(context).primaryColor.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Theme.of(context).primaryColor.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: Icon(LucideIcons.music, color: Theme.of(context).primaryColor),
        ),
        title: Text(song.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text("${song.artist}  •  ${song.category}", style: const TextStyle(color: Colors.grey, fontSize: 13)),
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
              Text(song.artist, style: TextStyle(color: Theme.of(context).primaryColor, fontSize: 14)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(song.category, style: TextStyle(color: Theme.of(context).primaryColor, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 24),
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

  Future<void> _showAddLyricsSheet(BuildContext context) async {
    final titleCtrl = TextEditingController();
    final artistCtrl = TextEditingController();
    final lyricsCtrl = TextEditingController();
    String category = 'Contemporary';
    bool isSaving = false;
    String? titleError;
    String? artistError;
    String? lyricsError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
          ),
          padding: EdgeInsets.fromLTRB(25, 20, 25, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)))),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Theme.of(context).primaryColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                    child: Icon(LucideIcons.music, color: Theme.of(context).primaryColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Add Worship Song", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      Text("Add a new song to the worship lyrics catalog", style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      TextField(
                        controller: titleCtrl,
                        decoration: InputDecoration(
                          labelText: "Song Title",
                          hintText: "e.g. How Great Is Our God",
                          prefixIcon: const Icon(LucideIcons.heading, size: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                          errorText: titleError,
                        ),
                        textCapitalization: TextCapitalization.words,
                        onChanged: (_) { if (titleError != null) setSheetState(() => titleError = null); },
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: artistCtrl,
                        decoration: InputDecoration(
                          labelText: "Artist / Writer",
                          hintText: "e.g. Chris Tomlin",
                          prefixIcon: const Icon(LucideIcons.user, size: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                          errorText: artistError,
                        ),
                        textCapitalization: TextCapitalization.words,
                        onChanged: (_) { if (artistError != null) setSheetState(() => artistError = null); },
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        initialValue: category,
                        items: ['Contemporary', 'Traditional', 'Hymns', 'Gospel', 'Praise'].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                        onChanged: (v) => setSheetState(() => category = v ?? category),
                        decoration: InputDecoration(
                          labelText: "Category",
                          prefixIcon: const Icon(LucideIcons.tag, size: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: lyricsCtrl,
                        maxLines: 8,
                        decoration: InputDecoration(
                          labelText: "Lyrics",
                          hintText: "Paste or type the lyrics here...",
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                          errorText: lyricsError,
                        ),
                        textCapitalization: TextCapitalization.sentences,
                        onChanged: (_) { if (lyricsError != null) setSheetState(() => lyricsError = null); },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton.icon(
                  onPressed: isSaving ? null : () async {
                    String? err;
                    if (titleCtrl.text.trim().isEmpty) { err = "Song title is required"; setSheetState(() => titleError = err); }
                    if (artistCtrl.text.trim().isEmpty) { err ??= "Artist is required"; setSheetState(() => artistError = "Artist is required"); }
                    if (lyricsCtrl.text.trim().isEmpty) { err ??= "Lyrics are required"; setSheetState(() => lyricsError = "Lyrics are required"); }
                    if (err != null) return;
                    setSheetState(() => isSaving = true);
                    try {
                      await Supabase.instance.client.from('lyrics').insert({
                        'title': titleCtrl.text.trim(),
                        'artist': artistCtrl.text.trim(),
                        'lyrics': lyricsCtrl.text.trim(),
                        'category': category,
                        'created_at': DateTime.now().toIso8601String(),
                      });
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("Song added successfully!"), backgroundColor: Colors.green));
                        Navigator.pop(ctx);
                      }
                    } catch (e) {
                      setSheetState(() => isSaving = false);
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
                      }
                    }
                  },
                  icon: isSaving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Icon(LucideIcons.checkCircle, size: 20),
                  label: Text(isSaving ? "Saving..." : "Save Song", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
