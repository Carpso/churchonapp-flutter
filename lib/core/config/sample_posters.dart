/// Tasteful, FREE sample poster art for streams and sermons (URLs only — no
/// bundled binaries). Used as the default thumbnail when a stream/sermon has
/// none. These are remote Unsplash URLs, so `AppImage`/`CachedNetworkImage`
/// handle them exactly like any other network image.
library;

const List<String> kSampleStreamPosters = [
  'https://images.unsplash.com/photo-1438232992991-995b7058bbb3?w=1200&q=80&auto=format&fit=crop',
  'https://images.unsplash.com/photo-1510133755869-79a639739569?w=1200&q=80&auto=format&fit=crop',
  'https://images.unsplash.com/photo-1507699622108-4be3abd695ad?w=1200&q=80&auto=format&fit=crop',
  'https://images.unsplash.com/photo-1516280440614-37939bbacd81?w=1200&q=80&auto=format&fit=crop',
  'https://images.unsplash.com/photo-1544427928-c49cdfebf4ad?w=1200&q=80&auto=format&fit=crop',
  'https://images.unsplash.com/photo-1504052434569-70ad5836ab65?w=1200&q=80&auto=format&fit=crop',
  'https://images.unsplash.com/photo-1544427920-c49ccfb85579?w=1200&q=80&auto=format&fit=crop',
];

/// Stable poster for a given seed (stream/sermon id) — the same id always maps
/// to the same poster so lists do not reshuffle on rebuild.
String samplePosterFor(Object seed) {
  final s = seed.toString();
  if (s.isEmpty) return kSampleStreamPosters.first;
  var hash = 0;
  for (final unit in s.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return kSampleStreamPosters[hash % kSampleStreamPosters.length];
}

/// Returns [url] when it has a real value, otherwise a deterministic sample
/// poster derived from [seed].
///
/// NOTE: new UI should prefer `SmartStreamPoster` (see
/// `lib/core/widgets/branded_stream_poster.dart`), which renders a fully
/// on-brand Flutter-drawn poster instead of these legacy stock photos. This
/// function is kept for backwards compatibility with existing call sites.
String posterOrDefault(String? url, {Object seed = ''}) {
  final trimmed = url?.trim() ?? '';
  if (trimmed.isNotEmpty) return trimmed;
  return samplePosterFor(seed);
}

/// True when [url] is one of the legacy generated sample posters (or empty) —
/// i.e. the row has NO real custom art. Used by `SmartStreamPoster` to decide
/// whether to render the branded default.
bool isGeneratedSamplePoster(String? url) {
  final trimmed = url?.trim() ?? '';
  if (trimmed.isEmpty) return true;
  return kSampleStreamPosters.contains(trimmed);
}
