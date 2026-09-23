import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Web-safe wrappers around `path_provider`.
///
/// `path_provider` has **no web implementation**, so calling
/// `getTemporaryDirectory()` / `getApplicationDocumentsDirectory()` in the
/// browser throws:
///
///   MissingPluginException(No implementation found for method
///   getTemporaryDirectory on channel plugins.flutter.io/path_provider)
///
/// These helpers return `null` on web (and on any plugin failure) so callers
/// can fall back to in-memory bytes (`XFile.fromData`) or a graceful message.
/// It is therefore impossible for web to reach `path_provider`.
Future<String?> safeTemporaryDirectoryPath() async {
  if (kIsWeb) return null;
  try {
    return (await getTemporaryDirectory()).path;
  } catch (e) {
    debugPrint('safeTemporaryDirectoryPath failed: $e');
    return null;
  }
}

Future<String?> safeDocumentsDirectoryPath() async {
  if (kIsWeb) return null;
  try {
    return (await getApplicationDocumentsDirectory()).path;
  } catch (e) {
    debugPrint('safeDocumentsDirectoryPath failed: $e');
    return null;
  }
}
