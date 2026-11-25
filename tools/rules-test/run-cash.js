#!/usr/bin/env node
// 14b step G: the Cash / order total triggers (functions/cash) on a throwaway
// Firestore EMULATOR (demo project; never the live database).
//   node tools/rules-test/run-cash.js
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
const inner = `node --test --test-concurrency=1 ${path.join('functions', 'test-emulator', 'cashCheck.emulator.js')}`;

const r = spawnSync(
  'firebase',
  ['emulators:exec', '--only', 'firestore', '--project', 'demo-chalakchar-cash', `"${inner}"`],
  { cwd: repo, stdio: 'inherit', shell: true, env: { ...process.env, NODE_PATH: nodeModules, GCLOUD_PROJECT: 'demo-chalakchar-cash' } }
);
process.exit(r.status ?? 1);
