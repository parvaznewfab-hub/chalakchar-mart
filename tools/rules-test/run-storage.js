#!/usr/bin/env node
// Runs the storage.rules tests inside throwaway Firestore + Storage emulators.
// The Firestore emulator gets firestore.rules (for seeding via fixtures);
// the Storage emulator loads storage.rules from firebase.json.
//   node tools/rules-test/run-storage.js
'use strict';

const { spawnSync } = require('node:child_process');
const path = require('node:path');

const repo = path.resolve(__dirname, '..', '..');
const inner = `node --test --test-concurrency=1 ${path.join('tools', 'rules-test', 'storage.test.js')}`;

const r = spawnSync(
  'firebase',
  ['emulators:exec', '--only', 'firestore,storage', '--project', 'demo-chalakchar-rules', `"${inner}"`],
  { cwd: repo, stdio: 'inherit', shell: true, env: { ...process.env, RULES_FILE: process.env.RULES_FILE || 'firestore.rules' } }
);
process.exit(r.status ?? 1);
