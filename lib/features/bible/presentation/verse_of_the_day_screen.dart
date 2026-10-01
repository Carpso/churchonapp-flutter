import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/services/deep_links.dart';
import '../data/bible_verse_service.dart';

/// Verse of the Day, for a SPECIFIC date — the target of a shared card.
///
/// Without this, `churchonapp.com/bible/verse-of-the-day/2026-10-01` had no
/// route, so a shared verse opened the generic Bible screen (or 404) and the
/// recipient never saw the verse that was shared. Resolving by date also means
/// the link keeps working tomorrow and shows the same verse.
class VerseOfTheDayScreen extends ConsumerStatefulWidget {
  const VerseOfTheDayScreen({super.key, this.dateIso});

  /// `yyyy-MM-dd`. Defaults to today.
  final String? dateIso;

  @override
  ConsumerState<VerseOfTheDayScreen> createState() =>
      _VerseOfTheDayScreenState();
}

class _VerseOfTheDayScreenState extends ConsumerState<VerseOfTheDayScreen> {
  late DateTime _date;
  bool _loading = true;
  String? _error;
  DailyBibleVerse? _verse;

  @override
  void initState() {
    super.initState();
    _date = DateTime.tryParse(widget.dateIso ?? '') ?? DateTime.now();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final v = await ref.read(bibleVerseServiceProvider).fetchLatestVerse(forDate: _date);
      if (!mounted) return;
      setState(() {
        _verse = v;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _shiftDay(int days) {
    setState(() {
      _date = _date.add(Duration(days: days));
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final day = DateFormat('EEEE d MMMM yyyy').format(_date);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Verse of the Day',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: theme.scaffoldBackgroundColor,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        actions: [
          if (_verse != null)
            IconButton(
              tooltip: 'Share this verse',
              icon: const Icon(LucideIcons.share2),
              onPressed: () => DeepLinks.shareText(
                '"${_verse!.text}" — ${_verse!.reference}',
                DeepLinks.verseOfTheDay(_date),
                subject: 'Verse of the Day — $day',
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.bookX,
                            size: 48, color: Colors.grey.withValues(alpha: 0.4)),
                        const SizedBox(height: 12),
                        const Text('Could not load the verse'),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _load,
                          icon: const Icon(LucideIcons.refreshCw, size: 16),
                          label: const Text('TRY AGAIN'),
                        ),
                      ],
                    ),
                  ),
                )
              : Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color:
                                theme.primaryColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(day.toUpperCase(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.1,
                                color: theme.primaryColor,
                              )),
                        ),
                        const SizedBox(height: 22),
                        Icon(LucideIcons.bookOpen,
                            size: 40, color: theme.primaryColor),
                        const SizedBox(height: 18),
                        Text(
                          '"${_verse?.text ?? ''}"',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 17,
                            height: 1.6,
                            fontStyle: FontStyle.italic,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          '— ${_verse?.reference ?? ''}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: theme.primaryColor,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _shiftDay(-1),
                              icon: const Icon(LucideIcons.chevronLeft, size: 16),
                              label: const Text('Previous',
                                  style: TextStyle(fontSize: 12)),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton.icon(
                              onPressed: () => _shiftDay(1),
                              icon: const Icon(LucideIcons.chevronRight, size: 16),
                              label: const Text('Next',
                                  style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        TextButton.icon(
                          onPressed: () => context.push('/bible'),
                          icon: const Icon(LucideIcons.bookOpen, size: 15),
                          label: const Text('Open the Bible',
                              style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}
