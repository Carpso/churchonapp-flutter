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
//   `{{flutter_service_worker_version}}` is substituted by `flutter build web`
//   with the real version hash. Do NOT hardcode it, or the app would serve a
//   stale cached shell after every release.

{{flutter_service_worker_version}}

_flutter.loader.load({
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}},
    // Was 4000 (Flutter's default). 20s is comfortably longer than any real
    // SW activation while still failing fast if registration is genuinely dead.
    timeoutMillis: 20000,
  },
});
