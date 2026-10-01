import 'package:share_plus/share_plus.dart';

/// One place that owns every shareable/deep link in the app.
///
/// WHY THIS EXISTS
/// Share links were being hand-built at each call site, and several pointed at
/// routes that either did not exist or did not resolve to the exact item. A
/// link that opens the wrong screen is worse than plain text, so every link is
/// now produced here and each one has a matching GoRoute.
class DeepLinks {
  const DeepLinks._();

  static const String host = 'churchonapp.com';
  static String get _base => 'https://$host';

  // ── Content ──────────────────────────────────────────────────────────────

  /// A specific verse, e.g. `/bible/John/3/16`. Opens the reader at that verse.
  static String verse(String book, int chapter, int verse) =>
      '$_base/bible/${Uri.encodeComponent(book)}/$chapter/$verse';

  /// The Verse of the Day for a date, so a shared card still shows the same
  /// verse tomorrow: `/bible/verse-of-the-day/2026-10-01`.
  static String verseOfTheDay(DateTime date) {
    final d = DateTime.utc(date.year, date.month, date.day);
    final iso = '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    return '$_base/bible/verse-of-the-day/$iso';
  }

  /// A search term for the Bible.
  static String bibleSearch(String query) =>
      '$_base/bible/search?q=${Uri.encodeComponent(query)}';

  /// A song's lyrics.
  static String songLyrics(String title) =>
      '$_base/song-lyrics?q=${Uri.encodeComponent(title)}';

  // ── Streaming ────────────────────────────────────────────────────────────

  /// The live service FOR ONE TENANT — resolves the church's current broadcast
  /// server-side, so the link is stable and always points at that church's live
  /// stream rather than a generic list page.
  static String tenantLiveStream(String tenantId, {String? churchSlug}) {
    if (churchSlug != null && churchSlug.isNotEmpty) {
      return '$_base/church/$churchSlug/live';
    }
    return '$_base/live-streaming?tenant=$tenantId';
  }

  /// A specific broadcast, for sharing a link to one exact stream.
  static String streamById(String streamId) =>
      '$_base/live-player?id=$streamId';

  // ── Church / community ───────────────────────────────────────────────────

  static String church(String slug) => '$_base/church/$slug';
  static String churchSite(String tenantId) => '$_base/site/$tenantId';
  static String joinByCode(String code) => '$_base/join?code=$code';
  static String sermons() => '$_base/sermons';
  static String sermon(String id) => '$_base/sermon/$id';
  static String events() => '$_base/events';
  static String event(String id) => '$_base/event/$id';
  static String eventTicket(String id) => '$_base/ticket/$id';
  static String job(String id) => '$_base/jobs/$id';
  static String post(String id) => '$_base/posts/$id';
  static String klips() => '$_base/klips';
  static String giving() => '$_base/giving';
  static String fundraising(String id) => '$_base/fundraising/$id';
  static String prayers() => '$_base/prayer-wall';

  // ── Quiz ─────────────────────────────────────────────────────────────────

  /// The quiz hub (works from outside the app; requires sign-in to play).
  static String quizHub() => '$_base/quiz';

  /// A PvP invite for one match — this is the deep link that must land the
  /// recipient on the specific challenge, not on a generic hub.
  static String quizInvite(String matchId) => '$_base/quiz/invite/$matchId';

  /// A hosted tournament bracket, so a church can share its fixture.
  static String quizTournament(String tournamentId) =>
      '$_base/quiz/tournament/$tournamentId';

  // ── Maps / getting here ──────────────────────────────────────────────────

  static String navigate(double lat, double lng, {String? label}) {
    final params = <String, String>{
      'lat': lat.toString(),
      'lng': lng.toString(),
      if (label != null && label.isNotEmpty) 'name': label,
    };
    final query = params.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return '$_base/navigate?$query';
  }

  static String branchLocator() => '$_base/branch-locator';

  // ── Sharing helper ───────────────────────────────────────────────────────

  /// Share [message] + [link] through the platform sheet.
  static Future<void> shareText(
    String message,
    String link, {
    String? subject,
  }) async {
    final body = link.isEmpty ? message : '$message\n$link'.trim();
    await SharePlus.instance.share(ShareParams(
      text: body,
      subject: subject,
    ));
  }

  /// Share a bare link with no message.
  static Future<void> shareLink(String link, {String? message}) =>
      shareText(message ?? '', link);
}
