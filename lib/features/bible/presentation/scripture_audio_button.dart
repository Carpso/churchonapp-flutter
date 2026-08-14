import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:church_on_app/features/bible/data/audio_bible_service.dart';
import 'package:church_on_app/features/bible/data/bible_service.dart';

/// Plays audio for a scripture reference (e.g. "John 3:16").
///
/// On-device Flutter TTS — speaks [text] if provided, otherwise fetches
/// the passage live in the user's preferred translation. Works for EVERY
/// translation, so the button is always available when text can be resolved.
/// If no passage text is obtainable the button is hidden entirely.
class ScriptureAudioButton extends ConsumerStatefulWidget {
  final String reference;
  final String? text;
  final Color? iconColor;
  final double iconSize;

  const ScriptureAudioButton({
    super.key,
    required this.reference,
    this.text,
    this.iconColor,
    this.iconSize = 18,
  });

  @override
  ConsumerState<ScriptureAudioButton> createState() =>
      _ScriptureAudioButtonState();
}

class _ScriptureAudioButtonState extends ConsumerState<ScriptureAudioButton> {
  bool _loading = false;
  bool _playing = false;
  bool _mapped = false;
  String? _ttsText;
  StreamSubscription<bool>? _ttsSub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(ScriptureAudioButton old) {
    super.didUpdateWidget(old);
    if (old.reference != widget.reference || old.text != widget.text) {
      _init();
    }
  }

  Future<void> _init() async {
    _ttsSub?.cancel();
    _ttsSub = null;
    _mapped = false;
    _playing = false;

    final direct = widget.text?.trim();
    String? text = (direct == null || direct.isEmpty) ? null : direct;
    if (text == null) {
      try {
        final live = await ref
            .read(bibleReferenceTextProvider(widget.reference).future);
        if (live.trim().isNotEmpty) text = live;
      } catch (_) {
        return;
      }
    }

    if (text == null || text.trim().isEmpty) return;

    final tts = ref.read(audioBibleServiceProvider);
    await tts.initialize();
    _ttsText = text;
    _mapped = true;
    _ttsSub = tts.speechStateStream.listen((p) {
      if (mounted) setState(() => _playing = p);
    });
    if (mounted) setState(() {});
  }

  Future<void> _toggle() async {
    if (!_mapped) return;
    final tts = ref.read(audioBibleServiceProvider);
    if (_playing) {
      await tts.stopSpeech();
      return;
    }
    try {
      setState(() => _loading = true);
      await tts.speakText(_ttsText!);
    } catch (e) {
      debugPrint('ScriptureAudioButton: TTS error for ${widget.reference}: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _ttsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_mapped) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final color = widget.iconColor ?? theme.primaryColor;
    return IconButton(
      icon: Icon(
        _loading
            ? LucideIcons.loader
            : _playing
                ? LucideIcons.square
                : LucideIcons.volume2,
        color: color,
        size: widget.iconSize,
      ),
      tooltip: _playing ? 'Stop audio' : 'Listen to this passage',
      onPressed: _toggle,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: EdgeInsets.zero,
    );
  }
}