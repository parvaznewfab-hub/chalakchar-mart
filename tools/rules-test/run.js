#!/usr/bin/env node
// Runs the rules tests inside a throwaway Firestore emulator.
//   node tools/rules-test/run.js                 -> new firestore.rules
//   node tools/rules-test/run.js <rules file>    -> e.g. the old live copy
'use strict';

const { spawnSync } = require('node:child_process');
const path = require('node:path');

const repo = path.resolve(__dirname, '..', '..');
const rulesFile = process.argv[2] || 'firestore.rules';
const testDir = path.join('tools', 'rules-test');
const inner = `node --test --test-concurrency=1 ${testDir}/holes.test.js ${testDir}/rules.test.js ${testDir}/step_b.test.js ${testDir}/rollback_b.test.js ${testDir}/step_d.test.js`;

const r = spawnSync(
  'firebase',
  ['emulators:exec', '--only', 'firestore', '--project', 'demo-chalakchar-rules', `"${inner}"`],
  { cwd: repo, stdio: 'inherit', shell: true, env: { ...process.env, RULES_FILE: rulesFile } }
);
process.exit(r.status ?? 1);
