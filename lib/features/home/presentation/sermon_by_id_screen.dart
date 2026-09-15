import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:church_on_app/features/home/data/sermon_service.dart';
import 'package:church_on_app/features/home/presentation/sermon_player_screen.dart';

/// Loads a sermon by id and opens the player.
///
/// Sermon push notifications and share links point at `/sermon/<id>` but no
/// such route existed (the player needed a full `Sermon` object), so those
/// deep links showed "page not found". This resolves the id first.
class SermonByIdScreen extends ConsumerStatefulWidget {
  final String sermonId;
  const SermonByIdScreen({super.key, required this.sermonId});

  @override
  ConsumerState<SermonByIdScreen> createState() => _SermonByIdScreenState();
}

class _SermonByIdScreenState extends ConsumerState<SermonByIdScreen> {
  late Future<Sermon?> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(sermonServiceProvider).fetchSermonById(widget.sermonId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Sermon?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final sermon = snap.data;
        if (sermon == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Sermon')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.videoOff,
                        size: 48, color: Colors.grey.shade400),
                    const SizedBox(height: 14),
                    const Text(
                      'This sermon is no longer available.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 18),
                    OutlinedButton(
                      onPressed: () => setState(() {
                        _future = ref
                            .read(sermonServiceProvider)
                            .fetchSermonById(widget.sermonId);
                      }),
                      child: const Text('RETRY'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return SermonPlayerScreen(sermon: sermon);
      },
    );
  }
}
