import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:church_on_app/features/modules/media/data/lyrics_service.dart';
import 'package:church_on_app/core/widgets/premium_toast.dart';
import 'setlist_builder_screen.dart';

class WorshipLyricsScreen extends ConsumerStatefulWidget {
  const WorshipLyricsScreen({super.key});

  @override
  ConsumerState<WorshipLyricsScreen> createState() => _WorshipLyricsScreenState();
}

class _WorshipLyricsScreenState extends ConsumerState<WorshipLyricsScreen> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String _selectedCategory = 'all';
  bool _showChords = true;

  final List<Map<String, String>> _categories = [
    {'id': 'all', 'name': 'All Songs'},
    {'id': 'worship', 'name': 'Worship'},
    {'id': 'praise', 'name': 'Praise'},
    {'id': 'hymn', 'name': 'Hymns'},
    {'id': 'gospel', 'name': 'Gospel'},
    {'id': 'contemporary', 'name': 'Contemporary'},
  ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lyricsAsync = _selectedCategory == 'all'
        ? ref.watch(lyricsStreamProvider)
        : ref.watch(lyricsByCategoryProvider(_selectedCategory));

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Worship & Lyrics',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: Icon(_showChords ? LucideIcons.music : LucideIcons.fileText),
            tooltip: _showChords ? 'Hide Chords' : 'Show Chords',
            onPressed: () => setState(() => _showChords = !_showChords),
          ),
          IconButton(
            icon: const Icon(LucideIcons.listMusic),
            tooltip: 'Setlists',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SetlistBuilderScreen()),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddLyricDialog(context),
        icon: const Icon(LucideIcons.plus),
        label: const Text('Add Song'),
        backgroundColor: theme.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Search & Filter
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search songs by title or artist...',
                prefixIcon: const Icon(LucideIcons.search, size: 18),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(LucideIcons.x, size: 16),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: theme.colorScheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
            ),
          ),

          // Categories
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final cat = _categories[index];
                final isSelected = _selectedCategory == cat['id'];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(cat['name']!),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() => _selectedCategory = cat['id']!);
                    },
                    selectedColor: theme.primaryColor.withValues(alpha: 0.2),
                    checkmarkColor: theme.primaryColor,
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 8),

          // Songs List
          Expanded(
            child: lyricsAsync.when(
              data: (lyrics) {
                final filtered = lyrics.where((l) {
                  if (_searchQuery.isEmpty) return true;
                  return l.title.toLowerCase().contains(_searchQuery) ||
                      l.artist.toLowerCase().contains(_searchQuery);
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.music2, size: 48, color: theme.disabledColor),
                        const SizedBox(height: 12),
                        Text(
                          _searchQuery.isNotEmpty ? 'No songs match "$_searchQuery"' : 'No lyrics available',
                          style: TextStyle(color: theme.disabledColor),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final song = filtered[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: CircleAvatar(
                          backgroundColor: theme.primaryColor.withValues(alpha: 0.1),
                          child: Icon(LucideIcons.music, color: theme.primaryColor, size: 20),
                        ),
                        title: Text(
                          song.title,
                          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        subtitle: Row(
                          children: [
                            Text(song.artist, style: const TextStyle(fontSize: 13)),
                            if (song.key != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Key: ${song.key}',
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber),
                                ),
                              ),
                            ],
                          ],
                        ),
                        trailing: const Icon(LucideIcons.chevronRight, size: 18),
                        onTap: () => _openLyricDetail(context, song),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(child: Text('Error loading lyrics: $err')),
            ),
          ),
        ],
      ),
    );
  }

  void _openLyricDetail(BuildContext context, WorshipLyric lyric) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SongDetailScreen(lyric: lyric, initialShowChords: _showChords),
      ),
    );
  }

  void _showAddLyricDialog(BuildContext context) {
    final titleCtrl = TextEditingController();
    final artistCtrl = TextEditingController();
    final lyricsCtrl = TextEditingController();
    final chordsCtrl = TextEditingController();
    final keyCtrl = TextEditingController();
    String category = 'worship';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: StatefulBuilder(
            builder: (context, setModalState) {
              return ListView(
                children: [
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Add New Worship Song', style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(labelText: 'Song Title *', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: artistCtrl,
                    decoration: const InputDecoration(labelText: 'Artist / Author', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: keyCtrl,
                          decoration: const InputDecoration(labelText: 'Key (e.g. G, C#m)', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: category,
                          decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
                          items: _categories.where((c) => c['id'] != 'all').map((c) {
                            return DropdownMenuItem(value: c['id'], child: Text(c['name']!));
                          }).toList(),
                          onChanged: (v) {
                            if (v != null) setModalState(() => category = v);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: lyricsCtrl,
                    maxLines: 6,
                    decoration: const InputDecoration(labelText: 'Lyrics *', border: OutlineInputBorder(), alignLabelWithHint: true),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: chordsCtrl,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Chords (Optional)', border: OutlineInputBorder(), alignLabelWithHint: true),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      if (titleCtrl.text.trim().isEmpty || lyricsCtrl.text.trim().isEmpty) {
                        PremiumToast.showError(context, 'Title and lyrics are required');
                        return;
                      }
                      try {
                        final lyric = WorshipLyric(
                          id: '',
                          title: titleCtrl.text.trim(),
                          artist: artistCtrl.text.trim().isEmpty ? 'Unknown' : artistCtrl.text.trim(),
                          lyrics: lyricsCtrl.text.trim(),
                          chords: chordsCtrl.text.trim().isEmpty ? null : chordsCtrl.text.trim(),
                          category: category,
                          key: keyCtrl.text.trim().isEmpty ? null : keyCtrl.text.trim(),
                          createdAt: DateTime.now(),
                        );
                        await ref.read(lyricsServiceProvider).createLyric(lyric);
                        if (context.mounted) {
                          Navigator.pop(context);
                          PremiumToast.showSuccess(context, 'Song added successfully!');
                        }
                      } catch (e) {
                        if (context.mounted) PremiumToast.showError(context, 'Failed to add song: $e');
                      }
                    },
                    child: const Text('SAVE SONG', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class SongDetailScreen extends StatefulWidget {
  final WorshipLyric lyric;
  final bool initialShowChords;

  const SongDetailScreen({
    super.key,
    required this.lyric,
    this.initialShowChords = true,
  });

  @override
  State<SongDetailScreen> createState() => _SongDetailScreenState();
}

class _SongDetailScreenState extends State<SongDetailScreen> {
  late bool _showChords;
  bool _presentationMode = false;
  double _fontSize = 18.0;

  @override
  void initState() {
    super.initState();
    _showChords = widget.initialShowChords && widget.lyric.chords != null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_presentationMode) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
          title: Text(widget.lyric.title, style: const TextStyle(color: Colors.white)),
          actions: [
            IconButton(
              icon: const Icon(LucideIcons.minus, color: Colors.white),
              onPressed: () => setState(() => _fontSize = (_fontSize - 2).clamp(12, 36)),
            ),
            IconButton(
              icon: const Icon(LucideIcons.plus, color: Colors.white),
              onPressed: () => setState(() => _fontSize = (_fontSize + 2).clamp(12, 36)),
            ),
            IconButton(
              icon: const Icon(LucideIcons.minimize2, color: Colors.white),
              onPressed: () => setState(() => _presentationMode = false),
            ),
          ],
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Text(
              widget.lyric.lyrics,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontSize: _fontSize + 4,
                height: 1.8,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(widget.lyric.title, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
        actions: [
          if (widget.lyric.chords != null)
            IconButton(
              icon: Icon(_showChords ? LucideIcons.music : LucideIcons.fileText),
              tooltip: _showChords ? 'Hide Chords' : 'Show Chords',
              onPressed: () => setState(() => _showChords = !_showChords),
            ),
          IconButton(
            icon: const Icon(LucideIcons.maximize2),
            tooltip: 'Presentation Mode',
            onPressed: () => setState(() => _presentationMode = true),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.lyric.artist,
                      style: GoogleFonts.plusJakartaSans(fontSize: 16, color: theme.disabledColor, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.lyric.category.toUpperCase(),
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: theme.primaryColor),
                    ),
                  ],
                ),
                if (widget.lyric.key != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber),
                    ),
                    child: Text(
                      'KEY: ${widget.lyric.key}',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.amber, fontSize: 13),
                    ),
                  ),
              ],
            ),
            const Divider(height: 32),

            if (_showChords && widget.lyric.chords != null) ...[
              Text(
                'CHORDS',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2, color: theme.primaryColor),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.primaryColor.withValues(alpha: 0.2)),
                ),
                child: SelectableText(
                  widget.lyric.chords!,
                  style: GoogleFonts.robotoMono(fontSize: 14, fontWeight: FontWeight.bold, color: theme.primaryColor),
                ),
              ),
              const SizedBox(height: 24),
            ],

            Text(
              'LYRICS',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2, color: theme.disabledColor),
            ),
            const SizedBox(height: 12),
            SelectableText(
              widget.lyric.lyrics,
              style: GoogleFonts.plusJakartaSans(fontSize: _fontSize, height: 1.7),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
