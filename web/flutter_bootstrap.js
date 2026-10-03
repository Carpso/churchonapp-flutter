// Custom Flutter web bootstrap.
//
// WHY THIS FILE EXISTS
//   The generated bootstrap registers the service worker with Flutter's default
//   `timeoutMillis` of 4000ms. On a cold cache, a slow mobile network, or
//   behind the Cloudflare Pages edge, `prepareServiceWorker` legitimately takes
//   longer than that, and the loader throws:
//
//     Exception: prepareServiceWorker took more than 4000ms to resolve.
//                Moving on.
//
//   It is a WARNING, not a crash — the app boots regardless ("Moving on") — but
//   it surfaces as a console exception on nearly every first load and makes
//   real errors hard to spot.
//
// THE FIX
//   Raise the registration/activation budget to 20s. The service worker still
//   installs and precaches exactly as before, so PWA/offline behaviour and the
//   "Add to Home Screen" install prompt are unchanged; the app simply stops
//   treating a slow-but-successful registration as a failure.
//
// NOTE
//   The service-worker-version placeholder is substituted by `flutter build web`
//   with the real version hash. Do NOT hardcode it, or the app would serve a
//   stale cached shell after every release.
//
// CRITICAL - DO NOT DROP THE TWO PLACEHOLDERS BELOW
//   The flutter-js and flutter-build-config placeholders are what inject
//   <script src="flutter.js"> and the build config. A custom bootstrap REPLACES
//   the generated one entirely, so if they are missing `_flutter` is never
//   defined and the loader throws on the first line:
//       Uncaught ReferenceError: _flutter is not defined
//   Nothing Flutter-rendered then paints at all - which looks like "every image
//   on the website is broken" rather than the total boot failure it actually is.
//   Compare against Flutter's own template:
//       packages/flutter_tools/lib/src/web/bootstrap.dart
//
//   DO NOT write these placeholder names anywhere else in this file - not even
//   in a comment. `flutter build web` substitutes EVERY textual occurrence, so
//   mentioning one inside a `//` comment injects the whole 30KB loader into
//   that comment and corrupts the file with a syntax error.

{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}},
    // Was 4000 (Flutter's default). 20s is comfortably longer than any real
    // SW activation while still failing fast if registration is genuinely dead.
    timeoutMillis: 20000,
  },
});
