{{flutter_js}}
{{flutter_build_config}}

// Loads the app WITHOUT a service worker (no worker settings passed).
// Flutter's offline-first worker served cached, stale builds after deploys;
// browsers that still have it receive tools/web/flutter_service_worker.js,
// which removes it. Fresh builds are ensured by no-cache headers on the app
// shell in firebase.json instead.
_flutter.loader.load();
