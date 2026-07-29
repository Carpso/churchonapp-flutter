import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:church_on_app/features/modules/media/data/lyrics_service.dart';
import 'package:church_on_app/core/widgets/premium_toast.dart';
import 'package:intl/intl.dart';

class SetlistBuilderScreen extends ConsumerStatefulWidget {
  const SetlistBuilderScreen({super.key});

  @override
  ConsumerState<SetlistBuilderScreen> createState() => _SetlistBuilderScreenState();
}

class _SetlistBuilderScreenState extends ConsumerState<SetlistBuilderScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final setlistsAsync = ref.watch(setlistsStreamProvider);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Worship Setlists',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateSetlistModal(context),
        icon: const Icon(LucideIcons.plus),
        label: const Text('New Setlist'),
        backgroundColor: theme.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: setlistsAsync.when(
        data: (setlists) {
          if (setlists.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.listMusic, size: 48, color: theme.disabledColor),
                  const SizedBox(height: 12),
                  Text('No setlists created yet', style: TextStyle(color: theme.disabledColor)),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => _showCreateSetlistModal(context),
                    icon: const Icon(LucideIcons.plus, size: 16),
                    label: const Text('Create your first setlist'),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: setlists.length,
            itemBuilder: (context, index) {
              final setlist = setlists[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: CircleAvatar(
                    backgroundColor: theme.primaryColor.withValues(alpha: 0.1),
                    child: Icon(LucideIcons.music, color: theme.primaryColor),
                  ),
                  title: Text(
                    setlist.title,
                    style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        '${setlist.songIds.length} song${setlist.songIds.length == 1 ? '' : 's'}',
                        style: const TextStyle(fontSize: 13),
                      ),
                      if (setlist.serviceDate != null)
                        Text(
                          'Service Date: ${setlist.serviceDate}',
                          style: TextStyle(fontSize: 11, color: theme.disabledColor),
                        ),
                    ],
                  ),
                  trailing: IconButton(
                    icon: const Icon(LucideIcons.trash2, size: 18, color: Colors.red),
                    onPressed: () async {
                      try {
                        await ref.read(lyricsServiceProvider).deleteSetlist(setlist.id);
                        if (context.mounted) PremiumToast.showSuccess(context, 'Setlist deleted');
                      } catch (e) {
                        if (context.mounted) PremiumToast.showError(context, 'Failed to delete setlist');
                      }
                    },
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error loading setlists: $err')),
      ),
    );
  }

  void _showCreateSetlistModal(BuildContext context) {
    final titleCtrl = TextEditingController();
    DateTime serviceDate = DateTime.now();
    final List<WorshipLyric> selectedSongs = [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Create Worship Setlist', style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(labelText: 'Setlist Title *', hintText: 'e.g., Sunday Service - Morning Worship', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    leading: const Icon(LucideIcons.calendar),
                    title: const Text('Service Date'),
                    subtitle: Text(DateFormat('EEEE, MMM d, yyyy').format(serviceDate)),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: serviceDate,
                        firstDate: DateTime.now().subtract(const Duration(days: 7)),
                        lastDate: DateTime.now().add(const Duration(days: 90)),
                      );
                      if (picked != null) {
                        setModalState(() => serviceDate = picked);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Selected Songs (${selectedSongs.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
                      TextButton.icon(
                        icon: const Icon(LucideIcons.plus, size: 16),
                        label: const Text('Add Songs'),
                        onPressed: () async {
                          final song = await _showSongPicker(context);
                          if (song != null && !selectedSongs.any((s) => s.id == song.id)) {
                            setModalState(() => selectedSongs.add(song));
                          }
                        },
                      ),
                    ],
                  ),
                  Expanded(
                    child: selectedSongs.isEmpty
                        ? const Center(child: Text('No songs added yet', style: TextStyle(color: Colors.grey)))
                        : ReorderableListView.builder(
                            itemCount: selectedSongs.length,
                            onReorder: (oldIndex, newIndex) {
                              setModalState(() {
                                if (newIndex > oldIndex) newIndex--;
                                final item = selectedSongs.removeAt(oldIndex);
                                selectedSongs.insert(newIndex, item);
                              });
                            },
                            itemBuilder: (context, index) {
                              final song = selectedSongs[index];
                              return ListTile(
                                key: ValueKey(song.id),
                                leading: CircleAvatar(child: Text('${index + 1}')),
                                title: Text(song.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text(song.artist),
                                trailing: IconButton(
                                  icon: const Icon(LucideIcons.x, size: 16),
                                  onPressed: () => setModalState(() => selectedSongs.removeAt(index)),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      if (titleCtrl.text.trim().isEmpty) {
                        PremiumToast.showError(context, 'Please enter a setlist title');
                        return;
                      }
                      if (selectedSongs.isEmpty) {
                        PremiumToast.showError(context, 'Please add at least one song');
                        return;
                      }
                      try {
                        await ref.read(lyricsServiceProvider).createSetlist(
                          title: titleCtrl.text.trim(),
                          songIds: selectedSongs.map((s) => s.id).toList(),
                          serviceDate: DateFormat('yyyy-MM-dd').format(serviceDate),
                        );
                        if (context.mounted) {
                          Navigator.pop(context);
                          PremiumToast.showSuccess(context, 'Setlist created!');
                        }
                      } catch (e) {
                        if (context.mounted) PremiumToast.showError(context, 'Failed to create setlist: $e');
                      }
                    },
                    child: const Text('CREATE SETLIST', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<WorshipLyric?> _showSongPicker(BuildContext context) async {
    final songs = await ref.read(lyricsServiceProvider).getLyricsStream().first;
    if (!context.mounted) return null;

    return showModalBottomSheet<WorshipLyric>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        String query = '';
        return StatefulBuilder(
          builder: (context, setPickerState) {
            final filtered = songs.where((s) {
              return query.isEmpty ||
                  s.title.toLowerCase().contains(query.toLowerCase()) ||
                  s.artist.toLowerCase().contains(query.toLowerCase());
            }).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.65,
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Search songs...',
                      prefixIcon: const Icon(LucideIcons.search, size: 18),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onChanged: (v) => setPickerState(() => query = v),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final song = filtered[index];
                        return ListTile(
                          leading: const Icon(LucideIcons.music),
                          title: Text(song.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(song.artist),
                          onTap: () => Navigator.pop(context, song),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
