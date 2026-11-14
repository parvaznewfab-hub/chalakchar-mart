#!/usr/bin/env node
// Hosting predeploy step (firebase.json "hosting.predeploy").
//
// 1. Refuses to deploy a web build whose flutter_bootstrap.js would register
//    a service worker (that brings back stale builds after deploys). The
//    template web/flutter_bootstrap.js loads without one.
// 2. Replaces the generated build/web/flutter_service_worker.js with the
//    self-removing worker (tools/web/flutter_service_worker.js), so browsers
//    that still have the old offline-first worker get rid of it.
// 3. Refuses a build missing the files Flutter needs at startup
//    (assets/AssetManifest.bin.json, assets/FontManifest.json, ...): the
//    hosting "**" rewrite would answer them with index.html and the app
//    dies on a JSON parse error (white screen). Seen 2026-11-14 when
//    Flutter's build cache skipped the asset step; fix: flutter clean, rebuild.
// 4. Copies every file under web/ that the build left out (manifest.json,
//    favicon.png, robots.txt, icons/...). Flutter's build cache skips that
//    copy step when it thinks it is up to date, even after build/web was
//    cleared, so some builds silently ship without them. Files the build did
//    produce (index.html, flutter_bootstrap.js, ...) are never overwritten.
//
// Build with:  flutter build web --release --pwa-strategy=none
// Usage:       node tools/web/finalize_web_build.js <buildDir>

const fs = require("fs");
const path = require("path");

/** Copies files from [srcDir] missing in [destDir] (recursive); returns their relative paths. */
function copyMissing(srcDir, destDir, rel = "") {
  const copied = [];
  if (!fs.existsSync(srcDir)) return copied;
  for (const entry of fs.readdirSync(srcDir, { withFileTypes: true })) {
    const src = path.join(srcDir, entry.name);
    const dest = path.join(destDir, entry.name);
    const relPath = rel ? `${rel}/${entry.name}` : entry.name;
    if (entry.isDirectory()) {
      fs.mkdirSync(dest, { recursive: true });
      copied.push(...copyMissing(src, dest, relPath));
    } else if (!fs.existsSync(dest)) {
      fs.copyFileSync(src, dest);
      copied.push(relPath);
    }
  }
  return copied;
}

// Loaded by the Flutter engine at startup; a build without them never renders.
const REQUIRED_BUILD_FILES = [
  "assets/AssetManifest.bin",
  "assets/AssetManifest.bin.json",
  "assets/FontManifest.json",
];

function finalizeWebBuild(buildDir, webDir = path.join(__dirname, "..", "..", "web")) {
  const bootstrap = path.join(buildDir, "flutter_bootstrap.js");
  const mainJs = path.join(buildDir, "main.dart.js");
  for (const f of [bootstrap, mainJs]) {
    if (!fs.existsSync(f)) throw new Error(`${f} not found — run "flutter build web --release --pwa-strategy=none" first.`);
  }
  const missing = REQUIRED_BUILD_FILES.filter((f) => !fs.existsSync(path.join(buildDir, f)));
  if (missing.length) {
    throw new Error(
      `incomplete build, missing ${missing.join(", ")} (the app would show a white screen). ` +
        'Run "flutter clean" and "flutter build web --release --pwa-strategy=none" again.'
    );
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
  const restored = copyMissing(webDir, buildDir);
  return { replaced: "flutter_service_worker.js", restored };
}

module.exports = { finalizeWebBuild };

if (require.main === module) {
  const buildDir = process.argv[2] || path.join(__dirname, "..", "..", "build", "web");
  try {
    const { restored } = finalizeWebBuild(buildDir);
    if (restored.length) console.log(`finalize_web_build: restored files the build left out: ${restored.join(", ")}`);
    console.log(`finalize_web_build: OK (no service worker registered; self-removing worker installed in ${buildDir})`);
  } catch (e) {
    console.error(`finalize_web_build: ${e.message}`);
    process.exit(1);
  }
}
