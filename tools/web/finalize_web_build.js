#!/usr/bin/env node
// Hosting predeploy step (firebase.json "hosting.predeploy").
//
// 1. Refuses to deploy a web build whose flutter_bootstrap.js would register
//    a service worker (that brings back stale builds after deploys). The
//    template web/flutter_bootstrap.js loads without one.
// 2. Replaces the generated build/web/flutter_service_worker.js with the
//    self-removing worker (tools/web/flutter_service_worker.js), so browsers
//    that still have the old offline-first worker get rid of it.
//
// Build with:  flutter build web --release --pwa-strategy=none
// Usage:       node tools/web/finalize_web_build.js <buildDir>

const fs = require("fs");
const path = require("path");

function finalizeWebBuild(buildDir) {
  const bootstrap = path.join(buildDir, "flutter_bootstrap.js");
  const mainJs = path.join(buildDir, "main.dart.js");
  for (const f of [bootstrap, mainJs]) {
    if (!fs.existsSync(f)) throw new Error(`${f} not found — run "flutter build web --release --pwa-strategy=none" first.`);
  }
  // Only the app's own load call matters: Flutter's inlined loader library
  // mentions serviceWorkerSettings as a parameter name in every build.
  const text = fs.readFileSync(bootstrap, "utf8");
  const loadCall = text.slice(text.lastIndexOf("_flutter.loader.load("));
  if (loadCall.includes("serviceWorkerSettings")) {
    throw new Error(
      `${bootstrap} registers a service worker (serviceWorkerSettings). ` +
        "Build from a tree that has web/flutter_bootstrap.js (loads without a worker)."
    );
  }
  const killSwitch = path.join(__dirname, "flutter_service_worker.js");
  fs.copyFileSync(killSwitch, path.join(buildDir, "flutter_service_worker.js"));
  return { replaced: "flutter_service_worker.js" };
}

module.exports = { finalizeWebBuild };

if (require.main === module) {
  const buildDir = process.argv[2] || path.join(__dirname, "..", "..", "build", "web");
  try {
    finalizeWebBuild(buildDir);
    console.log(`finalize_web_build: OK (no service worker registered; self-removing worker installed in ${buildDir})`);
  } catch (e) {
    console.error(`finalize_web_build: ${e.message}`);
    process.exit(1);
  }
}
