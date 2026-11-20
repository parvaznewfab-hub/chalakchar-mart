#!/usr/bin/env node
// End-to-end test of functions/scripts/movePrivateProfiles.js, restorePrivateProfiles.js
// and clearPublicOwnerName.js on a throwaway
// Firestore EMULATOR (demo project; never the live database).
//   node tools/rules-test/run-move-script.js
// firebase-admin is taken from functions/node_modules, or from the folder in
// MOVE_TEST_NODE_MODULES (e.g. another checkout's functions/node_modules).
'use strict';

const { spawnSync } = require('node:child_process');
const path = require('node:path');
const fs = require('node:fs');

const repo = path.resolve(__dirname, '..', '..');
const own = path.join(repo, 'functions', 'node_modules');
const nodeModules = process.env.MOVE_TEST_NODE_MODULES || own;
if (!fs.existsSync(path.join(nodeModules, 'firebase-admin'))) {
  console.error(`firebase-admin not found in ${nodeModules}; run npm ci in functions/ or set MOVE_TEST_NODE_MODULES`);
  process.exit(1);
}
const inner = `node --test --test-concurrency=1 ${['movePrivateProfiles', 'clearPublicOwnerName'].map((n) => path.join('functions', 'test-emulator', `${n}.emulator.js`)).join(' ')}`;

const r = spawnSync(
  'firebase',
  ['emulators:exec', '--only', 'firestore', '--project', 'demo-chalakchar-move', `"${inner}"`],
  { cwd: repo, stdio: 'inherit', shell: true, env: { ...process.env, NODE_PATH: nodeModules, GCLOUD_PROJECT: 'demo-chalakchar-move' } }
);
process.exit(r.status ?? 1);
