import 'package:flutter_riverpod/legacy.dart';

/// Bumped every time a Klip is posted.
///
/// The Klips feed lives inside the Connect `TabBarView` and is kept alive, so it
/// never rebuilds on its own after the composer pops. The composer increments
/// this counter and the feed listens to it and refetches — a just-posted Klip
/// therefore appears immediately instead of after an app restart.
final klipsFeedRefreshProvider = StateProvider<int>((ref) => 0);
