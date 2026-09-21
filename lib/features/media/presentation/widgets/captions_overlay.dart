import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/transcript_service.dart';

/// Renders the active caption cue for the current playback position.
///
/// Place it as the LAST child of the player `Stack` so it floats over video.
/// Rendering is driven by the player's own position listener (the parent
/// rebuilds on every tick), so the overlay stays in sync without polling.
class CaptionsOverlay extends StatelessWidget {
  final MediaTranscript? transcript;
  final Duration position;
  final bool enabled;
  final double bottomInset;

  const CaptionsOverlay({
    super.key,
    required this.transcript,
    required this.position,
    required this.enabled,
    this.bottomInset = 64,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.shrink();
    final segment = transcript?.segmentAt(position);
    final text = segment?.text.trim() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();

    return Positioned(
      left: 16,
      right: 16,
      bottom: bottomInset,
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                height: 1.35,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(color: Colors.black, blurRadius: 4)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small CC on/off chip. The preference is persisted in SharedPreferences by
/// `captionsEnabledProvider`.
class CcToggleButton extends ConsumerWidget {
  final bool onDarkBackground;

  const CcToggleButton({super.key, this.onDarkBackground = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(captionsEnabledProvider);
    final bg = enabled
        ? Theme.of(context).primaryColor
        : (onDarkBackground ? Colors.black45 : Colors.white70);
    final fg = enabled
        ? Colors.black
        : (onDarkBackground ? Colors.white : Colors.black87);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => ref.read(captionsEnabledProvider.notifier).toggle(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(
            'CC',
            style: TextStyle(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}
