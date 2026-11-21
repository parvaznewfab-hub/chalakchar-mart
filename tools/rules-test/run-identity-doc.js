#!/usr/bin/env node
// 14b step C: functions/identity/identityDocumentUrl.js against throwaway
// Firestore + Storage EMULATORS (demo project; never the live data).
//   node tools/rules-test/run-identity-doc.js
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
const inner = `node --test ${path.join('functions', 'test-emulator', 'identityDocumentUrl.emulator.js')}`;

const r = spawnSync(
  'firebase',
  ['emulators:exec', '--only', 'firestore,storage', '--project', 'demo-chalakchar-idoc', `"${inner}"`],
  { cwd: repo, stdio: 'inherit', shell: true, env: { ...process.env, NODE_PATH: nodeModules, GCLOUD_PROJECT: 'demo-chalakchar-idoc' } }
);
process.exit(r.status ?? 1);
