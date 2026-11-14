// Self-removing service worker ("kill switch").
//
// Until 2026-11 the web app registered Flutter's offline-first service
// worker, which kept serving the cached (old) build after every deploy —
// even across a hard reload — until the worker was unregistered by hand.
// The app no longer registers any worker (web/flutter_bootstrap.js). This
// file replaces the generated build/web/flutter_service_worker.js at Hosting
// predeploy (tools/web/finalize_web_build.js), so browsers that still have
// the old worker fetch this one on their next update check. It:
//   - activates immediately,
//   - deletes Flutter's caches,
//   - unregisters itself.
// It never reloads or navigates open tabs: a worker can't tell whether a
// tab is on the cart, checkout or a half-filled form (the old build can't
// report its state, and in-app navigation doesn't change the URL), so
// every open tab keeps running and picks up the new build on its next full
// page load. Keep this file deployed for several months so rare visitors
// are cleaned up too.

const FLUTTER_CACHES = ["flutter-app-cache", "flutter-temp-cache", "flutter-app-manifest"];

self.addEventListener("install", () => {
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    (async () => {
      const keys = await caches.keys();
      await Promise.all(keys.filter((k) => FLUTTER_CACHES.includes(k)).map((k) => caches.delete(k)));
      await self.registration.unregister();
    })()
  );
});

// No fetch handler: requests go straight to the network.
