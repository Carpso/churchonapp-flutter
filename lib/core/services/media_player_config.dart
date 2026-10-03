import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

/// Builds a [VideoPlayerController] configured for reliable, high-quality
/// playback of Church On App media.
///
/// WHY THIS HELPER EXISTS (and what it fixes)
///
/// 1. **Explicit `formatHint` for HLS/DASH — the real anti-stall fix.** Every
///    call site previously did a bare `VideoPlayerController.networkUrl(...)`.
///    With no hint the platform player has to sniff the container off the first
///    bytes of a network stream. Sniffing an HLS **manifest** is the classic
///    cause of a player that sits and spins, picks the wrong track, or reports
///    a bogus error on a slow connection. Saying "this is HLS" removes the
///    guesswork. MP4 is deliberately left unhinted: it is unambiguous and
///    sniffing a progressive file works correctly, so hinting it could only
///    ever commit the demuxer to the wrong thing.
///
/// 2. **`mixWithOthers: false`.** The app also owns a shared `audio_service`
///    player (radio, sermon audio, kids stories). If a video starts while that
///    player still owns the audio session, the two fight and the symptom is
///    audio that keeps cutting out mid-sermon. Video now takes exclusive
///    control of the session.
///
/// 3. **`allowBackgroundPlayback: true`.** Without it, Android suspends the
///    player the moment the screen goes off or the app is backgrounded, so a
///    long sermon silently freezes partway through while the user is listening
///    with the phone in their pocket. Letting it continue is what people
///    actually expect from an audio-first feature.
///
/// The HLS quality selector in the player still defaults to AUTO, so adaptive
/// bitrate is preserved and the app never pins a low rendition.
VideoPlayerController buildMediaController(
  String url, {
  Map<String, String>? httpHeaders,
  bool allowBackgroundPlayback = true,
}) {
  return VideoPlayerController.networkUrl(
    Uri.parse(url),
    formatHint: mediaFormatHint(url),
    // An empty map is not the same as "no headers" on every platform, so only
    // pass one when the caller actually supplied it.
    httpHeaders: (httpHeaders != null && httpHeaders.isNotEmpty)
        ? httpHeaders
        : const <String, String>{},
    videoPlayerOptions: VideoPlayerOptions(
      mixWithOthers: false,
      allowBackgroundPlayback: allowBackgroundPlayback,
    ),
  );
}

/// Container hint for [url].
///
/// Returns null when the container is obvious (`.mp4`, `.webm`, …) so the
/// platform keeps its own reliable detection; a wrong hint is worse than none
/// because it commits the demuxer to the wrong parser.
VideoFormat? mediaFormatHint(String url) {
  final u = url.toLowerCase();
  if (u.contains('.m3u8') || u.contains('/hls/')) return VideoFormat.hls;
  if (u.contains('.mpd')) return VideoFormat.dash;
  if (u.contains('.ism') || u.contains('/manifest(')) return VideoFormat.ss;
  return null;
}

/// True when [url] is audio-only, so the UI shows an audio surface rather than
/// a black video rectangle.
bool isAudioOnlyUrl(String? url) {
  if (url == null || url.trim().isEmpty) return false;
  final u = url.toLowerCase();
  // An adaptive manifest may carry video, so never call those audio-only.
  if (u.contains('.m3u8') || u.contains('.mpd')) return false;
  for (final e in ['.mp3', '.m4a', '.aac', '.wav', '.flac', '.opus']) {
    if (u.contains(e)) return true;
  }
  return false;
}

/// True when HLS on this platform needs the extra web plugin, because
/// `video_player` cannot decode `.m3u8` in Chrome/Firefox on its own.
bool get needsWebHlsPlugin => kIsWeb;

/// True while the platform is rebuffering.
///
/// Surfaced in the UI so a stall reads as "loading" rather than a frozen
/// player — the difference between a perceived bug and an understood wait.
bool isMediaBuffering(VideoPlayerController? c) {
  if (c == null || !c.value.isInitialized) return false;
  return c.value.isBuffering;
}
