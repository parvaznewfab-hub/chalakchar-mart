// Run: node --test tools/web/web_build.test.js
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const os = require("os");
const path = require("path");
const vm = require("vm");

const { finalizeWebBuild } = require("./finalize_web_build");

function fakeBuild(bootstrap) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "webbuild-"));
  fs.writeFileSync(path.join(dir, "flutter_bootstrap.js"), bootstrap);
  fs.writeFileSync(path.join(dir, "main.dart.js"), "// app");
  fs.writeFileSync(path.join(dir, "flutter_service_worker.js"), "const RESOURCES = {}; // generated");
  return dir;
}

test("installs the self-removing worker over the generated one", () => {
  const dir = fakeBuild("_flutter.loader.load();");
  finalizeWebBuild(dir);
  assert.equal(
    fs.readFileSync(path.join(dir, "flutter_service_worker.js"), "utf8"),
    fs.readFileSync(path.join(__dirname, "flutter_service_worker.js"), "utf8")
  );
});

test("refuses a build whose bootstrap registers a service worker", () => {
  const dir = fakeBuild('_flutter.loader.load({serviceWorkerSettings:{serviceWorkerVersion:"1"}});');
  assert.throws(() => finalizeWebBuild(dir), /registers a service worker/);
});

test("accepts a real build: the inlined loader library names serviceWorkerSettings", () => {
  // Shape of a real flutter_bootstrap.js: loader library, then our load call.
  const dir = fakeBuild(
    'load({serviceWorkerSettings:e,onEntrypointLoaded:r,nonce:t,config:n}={}){...}\n' +
      '_flutter.buildConfig = {"engineRevision":"x"};\n' +
      "_flutter.loader.load();\n"
  );
  assert.doesNotThrow(() => finalizeWebBuild(dir));
});

test("refuses a missing build", () => {
  assert.throws(() => finalizeWebBuild(path.join(os.tmpdir(), "no-such-build")), /not found/);
});

test("the web bootstrap template loads without a service worker", () => {
  const t = fs.readFileSync(path.join(__dirname, "..", "..", "web", "flutter_bootstrap.js"), "utf8");
  assert.ok(t.includes("_flutter.loader.load("));
  assert.ok(!t.includes("serviceWorkerSettings"));
});

test("worker: skips waiting, deletes only Flutter's caches, unregisters, never navigates tabs", async () => {
  const listeners = {};
  const deleted = [];
  let skipped = false;
  let unregistered = false;
  let navigated = 0;
  const self = {
    addEventListener: (type, fn) => { listeners[type] = fn; },
    skipWaiting: () => { skipped = true; },
    registration: { unregister: async () => { unregistered = true; return true; } },
    clients: {
      matchAll: async () => [{ url: "https://x/cart", navigate: () => { navigated++; } }],
      claim: async () => {},
    },
  };
  const caches = {
    keys: async () => ["flutter-app-cache", "flutter-temp-cache", "flutter-app-manifest", "other-cache"],
    delete: async (k) => { deleted.push(k); return true; },
  };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, "flutter_service_worker.js"), "utf8"), { self, caches });

  listeners.install({});
  assert.equal(skipped, true);

  let done;
  listeners.activate({ waitUntil: (p) => { done = p; } });
  await done;
  assert.deepEqual(deleted.sort(), ["flutter-app-cache", "flutter-app-manifest", "flutter-temp-cache"]);
  assert.equal(unregistered, true);
  assert.equal(navigated, 0, "open tabs (cart, checkout, forms) are never reloaded");
  assert.equal(listeners.fetch, undefined, "no fetch handler: requests go to the network");
});
