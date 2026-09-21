@JS()
library hls.js;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

@JS('Hls.isSupported')
external bool isSupported();

@JS()
@staticInterop
class Hls {
  external factory Hls(HlsConfig config);
}

extension HlsExtension on Hls {
  external void stopLoad();

  external void loadSource(String videoSrc);

  external void attachMedia(web.HTMLVideoElement video);

  external void on(String event, JSFunction callback);

  external HlsConfig config;
}

@JS()
@anonymous
@staticInterop
class HlsConfig {
  external factory HlsConfig({JSFunction xhrSetup});
}

extension HlsConfigExtension on HlsConfig {
  external JSFunction get xhrSetup;
}

/// Defensive reader for the hls.js `hlsError` event payload.
///
/// hls.js passes a plain JS object (`{ type, details, fatal, ... }`). The
/// upstream implementation read it via Dart dynamic dispatch
/// (`errorData.type`), which throws `NoSuchMethodError: method not found:
/// 'type'` because a JS object exposes no Dart getters. That throw happened
/// *inside* the `hlsError` handler, so the real playback failure was swallowed
/// and the player never left its loading state.
///
/// Every field is now read through `getProperty` behind its own guard, so a
/// missing/unexpected shape can never throw. `ErrorData(null)` is a valid
/// "unknown error" value that callers can still surface as a normal player
/// error.
class ErrorData {
  late final String type;
  late final String details;
  late final bool fatal;

  ErrorData(dynamic errorData) {
    type = _readString(errorData, 'type');
    details = _readString(errorData, 'details');
    fatal = _readBool(errorData, 'fatal');
  }

  static Object? _read(dynamic errorData, String key) {
    if (errorData == null) return null;
    try {
      final JSAny? value = (errorData as JSObject).getProperty(key.toJS);
      if (value == null) return null;
      return value.dartify();
    } catch (_) {
      return null;
    }
  }

  static String _readString(dynamic errorData, String key) {
    final value = _read(errorData, key);
    if (value == null) return '';
    return value.toString();
  }

  static bool _readBool(dynamic errorData, String key) {
    final value = _read(errorData, key);
    if (value is bool) return value;
    if (value is num) return value != 0;
    return false;
  }
}
