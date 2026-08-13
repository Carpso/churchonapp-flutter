import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../data/bible_audio_r2.dart';

/// Plays the self-hosted KJV audio for a scripture reference
/// (e.g. "John 3:16" streams the R2 range file containing John 3).
/// Shows a speaker icon that toggles play/pause. If no audio is
/// mapped for the reference, the button is hidden entirely.
class ScriptureAudioButton extends StatefulWidget {
  final String reference;
  final Color? iconColor;
  final double iconSize;

  const ScriptureAudioButton({
    super.key,
    required this.reference,
    this.iconColor,
    this.iconSize = 18,
  });

  @override
  State<ScriptureAudioButton> createState() => _ScriptureAudioButtonState();
}

class _ScriptureAudioButtonState extends State<ScriptureAudioButton> {
  final _player = AudioPlayer();
  bool _loading = false;
  bool _playing = false;
  bool _mapped = false;

  @override
  void initState() {
    super.initState();
    final url = kjvR2AudioUrlForReference(widget.reference);
    _mapped = url != null;
    if (!_mapped) return;
    _player.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() => _playing = state.playing);
    });
  }

  Future<void> _toggle() async {
    if (!_mapped) return;
    if (_playing) {
      await _player.pause();
      return;
    }
    try {
      setState(() => _loading = true);
      final url = kjvR2AudioUrlForReference(widget.reference);
      if (url == null) return;
      if (_player.audioSource == null) {
        await _player.setUrl(url);
      }
      await _player.play();
    } catch (e) {
      debugPrint('ScriptureAudioButton: playback error for ${widget.reference}: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _player.dispose();
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
      tooltip: _playing ? 'Stop audio' : 'Play this passage',
      onPressed: _toggle,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: EdgeInsets.zero,
    );
  }
}
