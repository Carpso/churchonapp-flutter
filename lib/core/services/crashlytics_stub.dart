import 'package:flutter/foundation.dart';

class FirebaseCrashlytics {
  static final FirebaseCrashlytics instance = FirebaseCrashlytics._();
  FirebaseCrashlytics._();

  void recordFlutterFatalError(FlutterErrorDetails details) {}
  void recordFlutterError(FlutterErrorDetails details) {}
  void recordError(Object exception, StackTrace? stack, {bool fatal = false}) {}
  void log(String message) {}
  void setCustomKey(String key, Object value) {}
  void setUserIdentifier(String identifier) {}
}
