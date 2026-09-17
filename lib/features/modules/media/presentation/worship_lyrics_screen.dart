import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:church_on_app/features/modules/media/data/lyrics_service.dart';
import 'package:church_on_app/core/widgets/premium_toast.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
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
  int _tabIndex = 0;

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

  bool _canManage(UserProfile? profile) {
    if (profile == null) return false;
    return profile.isEmployee ||
        profile.isLeadershipTeam ||
        profile.isWorshipLeader ||
        profile.isPraiseTeam;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = ref.watch(profileProvider).value;
    final canManage = _canManage(profile);

    final libraryAsync = _selectedCategory == 'all'
        ? ref.watch(lyricsStreamProvider)
        : ref.watch(lyricsByCategoryProvider(_selectedCategory));
    final manageAsync = ref.watch(myTenantLyricsStreamProvider);

    final showManageTab = canManage && _tabIndex == 1;

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
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => _showAddLyricDialog(context),
              icon: const Icon(LucideIcons.plus),
              label: const Text('Add Song'),
              backgroundColor: theme.primaryColor,
              foregroundColor: Colors.white,
            )
          : null,
      body: Column(
        children: [
          if (canManage)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('Library'), icon: Icon(LucideIcons.library, size: 16)),
                  ButtonSegment(value: 1, label: Text('Manage'), icon: Icon(LucideIcons.settings2, size: 16)),
                ],
                selected: {_tabIndex},
                onSelectionChanged: (s) => setState(() => _tabIndex = s.first),
              ),
            ),

          if (!showManageTab) ...[
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
          ] else
            const SizedBox(height: 8),

          Expanded(
            child: showManageTab
                ? _buildAsyncList(
                    context,
                    manageAsync,
                    management: true,
                  )
                : _buildAsyncList(context, libraryAsync),
          ),
        ],
      ),
    );
  }

  Widget _buildAsyncList(
    BuildContext context,
    AsyncValue<List<WorshipLyric>> async, {
    bool management = false,
  }) {
    final theme = Theme.of(context);
    return async.when(
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
                  management
                      ? 'Your church has no songs yet. Tap ADD SONG to create one.'
                      : (_searchQuery.isNotEmpty
                          ? 'No songs match "$_searchQuery"'
                          : 'No lyrics available'),
                  textAlign: TextAlign.center,
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
                    Flexible(
                      child: Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    if (song.key != null) ...[
                      const SizedBox(width: 8),
                      _chip('Key: ${song.key}', Colors.amber),
                    ],
                    if (management && !song.isPublished) ...[
                      const SizedBox(width: 6),
                      _chip('DRAFT', Colors.orange),
                    ],
                    if (song.isGlobal) ...[
                      const SizedBox(width: 6),
                      _chip('GLOBAL', Colors.teal),
                    ],
                  ],
                ),
                trailing: management
                    ? PopupMenuButton<String>(
                        icon: const Icon(LucideIcons.moreVertical, size: 18),
                        onSelected: (v) => _onManageAction(v, song),
                        itemBuilder: (context) => [
                          const PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(
                            value: 'publish',
                            child: Text(song.isPublished ? 'Unpublish' : 'Publish'),
                          ),
                          PopupMenuItem(
                            value: 'global',
                            child: Text(song.isGlobal ? 'Remove from global' : 'Air globally'),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete', style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.eye, size: 14, color: theme.disabledColor),
                          const SizedBox(width: 3),
                          Text('${song.views}', style: TextStyle(fontSize: 12, color: theme.disabledColor)),
                          const SizedBox(width: 10),
                          Icon(LucideIcons.heart, size: 14, color: theme.disabledColor),
                          const SizedBox(width: 3),
                          Text('${song.likes}', style: TextStyle(fontSize: 12, color: theme.disabledColor)),
                        ],
                      ),
                onTap: () => _openLyricDetail(context, song),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error loading lyrics: $err')),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Future<void> _onManageAction(String action, WorshipLyric song) async {
    final service = ref.read(lyricsServiceProvider);
    try {
      switch (action) {
        case 'edit':
          _showAddLyricDialog(context, existing: song);
          break;
        case 'publish':
          await service.publishLyric(song.id, !song.isPublished);
          if (mounted) {
            PremiumToast.showSuccess(
              context,
              song.isPublished ? 'Song unpublished' : 'Song published',
            );
          }
          break;
        case 'global':
          await service.setGlobalAirPermission(song.id, !song.isGlobal);
          if (mounted) {
            PremiumToast.showSuccess(
              context,
              song.isGlobal ? 'Removed from global library' : 'Now airing globally',
            );
          }
          break;
        case 'delete':
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Delete song?'),
              content: Text('"${song.title}" will be permanently removed.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Delete', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          );
          if (confirmed == true) {
            await service.deleteLyric(song.id);
            if (mounted) PremiumToast.showSuccess(context, 'Song deleted');
          }
          break;
      }
    } catch (e) {
      if (mounted) PremiumToast.showError(context, 'Action failed: $e');
    }
  }

  void _openLyricDetail(BuildContext context, WorshipLyric lyric) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SongDetailScreen(lyric: lyric, initialShowChords: _showChords),
      ),
    );
  }

  void _showAddLyricDialog(BuildContext context, {WorshipLyric? existing}) {
    final titleCtrl = TextEditingController(text: existing?.title);
    final artistCtrl = TextEditingController(text: existing?.artist);
    final lyricsCtrl = TextEditingController(text: existing?.lyrics);
    final chordsCtrl = TextEditingController(text: existing?.chords);
    final keyCtrl = TextEditingController(text: existing?.key);
    final bpmCtrl = TextEditingController(text: existing?.bpm?.toString());
    final mediaCtrl = TextEditingController(text: existing?.mediaUrl);
    String category = existing?.category ?? 'worship';
    if (!_categories.any((c) => c['id'] == category)) category = 'worship';

    final categories = _categories.where((c) => c['id'] != 'all').toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.9,
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
                  Text(
                    existing == null ? 'Add New Worship Song' : 'Edit Worship Song',
                    style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
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
                        child: TextField(
                          controller: bpmCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'BPM', border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
                    items: categories.map((c) {
                      return DropdownMenuItem(value: c['id'], child: Text(c['name']!));
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) setModalState(() => category = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: mediaCtrl,
                    decoration: const InputDecoration(
                      labelText: 'YouTube / Media link (optional)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(LucideIcons.link, size: 18),
                    ),
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
                      final service = ref.read(lyricsServiceProvider);
                      final payload = {
                        'title': titleCtrl.text.trim(),
                        'artist': artistCtrl.text.trim().isEmpty ? 'Unknown' : artistCtrl.text.trim(),
                        'lyrics': lyricsCtrl.text.trim(),
                        'chords': chordsCtrl.text.trim().isEmpty ? null : chordsCtrl.text.trim(),
                        'category': category,
                        'musical_key': keyCtrl.text.trim().isEmpty ? null : keyCtrl.text.trim(),
                        'bpm': int.tryParse(bpmCtrl.text.trim()),
                        'media_url': mediaCtrl.text.trim().isEmpty ? null : mediaCtrl.text.trim(),
                      };
                      try {
                        if (existing == null) {
                          await service.createLyric(WorshipLyric(
                            id: '',
                            title: payload['title']! as String,
                            artist: payload['artist']! as String,
                            lyrics: payload['lyrics']! as String,
                            chords: payload['chords'] as String?,
                            category: category,
                            key: payload['musical_key'] as String?,
                            bpm: payload['bpm'] as int?,
                            mediaUrl: payload['media_url'] as String?,
                            createdAt: DateTime.now(),
                          ));
                        } else {
                          await service.updateLyric(existing.id, payload);
                        }
                        if (context.mounted) {
                          Navigator.pop(context);
                          PremiumToast.showSuccess(
                            context,
                            existing == null ? 'Song added successfully!' : 'Song updated!',
                          );
                        }
                      } catch (e) {
                        if (context.mounted) PremiumToast.showError(context, 'Failed to save song: $e');
                      }
                    },
                    child: Text(
                      existing == null ? 'SAVE SONG' : 'UPDATE SONG',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
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

class SongDetailScreen extends ConsumerStatefulWidget {
  final WorshipLyric lyric;
  final bool initialShowChords;

  const SongDetailScreen({
    super.key,
    required this.lyric,
    this.initialShowChords = true,
  });

  @override
  ConsumerState<SongDetailScreen> createState() => _SongDetailScreenState();
}

class _SongDetailScreenState extends ConsumerState<SongDetailScreen> {
  final _scrollCtrl = ScrollController();
  late bool _showChords;
  bool _presentationMode = false;
  double _fontSize = 18.0;
  bool _autoScroll = false;
  Timer? _autoScrollTimer;
  late WorshipLyric _lyric;
  final Set<String> _liked = {};

  @override
  void initState() {
    super.initState();
    _lyric = widget.lyric;
    _showChords = widget.initialShowChords && widget.lyric.chords != null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _recordView());
  }

  Future<void> _recordView() async {
    if (_lyric.id.isEmpty) return;
    try {
      final views = await ref.read(lyricsServiceProvider).incrementView(_lyric.id);
      if (mounted) setState(() => _lyric = _copyWith(views: views));
    } catch (e) {
      debugPrint('Failed to record lyric view: $e');
    }
  }

  WorshipLyric _copyWith({int? views, int? likes}) {
    return WorshipLyric(
      id: _lyric.id,
      title: _lyric.title,
      artist: _lyric.artist,
      lyrics: _lyric.lyrics,
      chords: _lyric.chords,
      category: _lyric.category,
      key: _lyric.key,
      bpm: _lyric.bpm,
      mediaUrl: _lyric.mediaUrl,
      tenantId: _lyric.tenantId,
      createdBy: _lyric.createdBy,
      createdAt: _lyric.createdAt,
      isGlobal: _lyric.isGlobal,
      isPublished: _lyric.isPublished,
      views: views ?? _lyric.views,
      likes: likes ?? _lyric.likes,
    );
  }

  bool get _isLiked => _liked.contains(_lyric.id);

  Future<void> _toggleLike() async {
    if (_lyric.id.isEmpty) return;
    try {
      final liked = await ref.read(lyricsServiceProvider).toggleLike(_lyric.id);
      if (!mounted) return;
      setState(() {
        if (liked) {
          _liked.add(_lyric.id);
          _lyric = _copyWith(likes: _lyric.likes + 1);
        } else {
          _liked.remove(_lyric.id);
          _lyric = _copyWith(likes: (_lyric.likes - 1).clamp(0, 1 << 31));
        }
      });
    } catch (e) {
      if (mounted) PremiumToast.showError(context, 'Could not update like');
    }
  }

  void _toggleAutoScroll() {
    setState(() => _autoScroll = !_autoScroll);
    _autoScrollTimer?.cancel();
    if (_autoScroll) {
      _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
        if (!mounted || !_scrollCtrl.hasClients) return;
        final max = _scrollCtrl.position.maxScrollExtent;
        final next = _scrollCtrl.offset + 1.2;
        if (next >= max) {
          _scrollCtrl.jumpTo(max);
          _autoScrollTimer?.cancel();
          if (mounted) setState(() => _autoScroll = false);
        } else {
          _scrollCtrl.jumpTo(next);
        }
      });
    }
  }

  Future<void> _copyLyrics() async {
    final text = '${_lyric.title}\n${_lyric.artist}\n\n${_lyric.lyrics}';
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) PremiumToast.showSuccess(context, 'Lyrics copied');
  }

  Future<void> _shareLyrics() async {
    await SharePlus.instance.share(ShareParams(
      text: '${_lyric.title} — ${_lyric.artist}\n\n${_lyric.lyrics}',
    ));
  }

  Future<void> _openMedia() async {
    final url = _lyric.mediaUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) {
      if (mounted) PremiumToast.showError(context, 'Invalid media link');
      return;
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) PremiumToast.showError(context, 'Could not open link');
    }
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
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
          title: Text(_lyric.title, style: const TextStyle(color: Colors.white)),
          actions: [
            IconButton(
              icon: Icon(_autoScroll ? LucideIcons.pause : LucideIcons.play, color: Colors.white),
              tooltip: 'Auto-scroll',
              onPressed: _toggleAutoScroll,
            ),
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
        body: SingleChildScrollView(
          controller: _scrollCtrl,
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              _lyric.lyrics,
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
        title: Text(_lyric.title, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
        actions: [
          if (_lyric.mediaUrl != null && _lyric.mediaUrl!.isNotEmpty)
            IconButton(
              icon: const Icon(LucideIcons.playCircle),
              tooltip: 'Play media',
              onPressed: _openMedia,
            ),
          IconButton(
            icon: const Icon(LucideIcons.copy),
            tooltip: 'Copy lyrics',
            onPressed: _copyLyrics,
          ),
          IconButton(
            icon: const Icon(LucideIcons.share2),
            tooltip: 'Share',
            onPressed: _shareLyrics,
          ),
          if (_lyric.chords != null)
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
        controller: _scrollCtrl,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _lyric.artist,
                        style: GoogleFonts.plusJakartaSans(fontSize: 16, color: theme.disabledColor, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _lyric.category.toUpperCase(),
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: theme.primaryColor),
                      ),
                    ],
                  ),
                ),
                if (_lyric.key != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber),
                    ),
                    child: Text(
                      'KEY: ${_lyric.key}${_lyric.bpm != null ? ' · ${_lyric.bpm} BPM' : ''}',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.amber, fontSize: 12),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(LucideIcons.eye, size: 16, color: theme.disabledColor),
                const SizedBox(width: 4),
                Text('${_lyric.views} views', style: TextStyle(fontSize: 13, color: theme.disabledColor)),
                const SizedBox(width: 16),
                InkWell(
                  onTap: _toggleLike,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          _isLiked ? Icons.favorite : LucideIcons.heart,
                          size: 16,
                          color: _isLiked ? Colors.red : theme.disabledColor,
                        ),
                        const SizedBox(width: 4),
                        Text('${_lyric.likes}', style: TextStyle(fontSize: 13, color: theme.disabledColor)),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _toggleAutoScroll,
                  icon: Icon(_autoScroll ? LucideIcons.pause : LucideIcons.arrowDown, size: 16),
                  label: Text(_autoScroll ? 'Pause' : 'Auto-scroll'),
                ),
              ],
            ),
            const Divider(height: 32),

            if (_showChords && _lyric.chords != null) ...[
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
                  _lyric.chords!,
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
              _lyric.lyrics,
              style: GoogleFonts.plusJakartaSans(fontSize: _fontSize, height: 1.7),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
