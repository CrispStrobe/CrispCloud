#!/usr/bin/env node
// Copyright 2026 CrispCloud contributors
// SPDX-License-Identifier: MIT
// Run a compiled Dart JavaScript probe with browser-style async scheduling.
// A quiet exit is not evidence: require its exact successful completion line.

'use strict';

const path = require('node:path');
const { spawnSync } = require('node:child_process');

if (process.argv[2] === '--execute') {
  // dart2js uses self to select its asynchronous event-loop implementation.
  // Node alone can otherwise exit before an async Dart main reaches its work.
  globalThis.self = globalThis;
  require(path.resolve(process.argv[3]));
} else {
  const [file, completion, ...extra] = process.argv.slice(2);
  const timeout = Number(process.env.CRISP_WEB_PROBE_TIMEOUT_MS || '60000');
  if (!file || !completion?.startsWith('PASS: ') || extra.length !== 0 ||
      !Number.isSafeInteger(timeout) || timeout < 1 || timeout > 300000) {
    console.error('Usage: node tool/run_dart_web_probe.cjs <compiled.js> "PASS: exact completion line"');
    process.exit(2);
  }

  const result = spawnSync(
    process.execPath,
    ['--unhandled-rejections=strict', __filename, '--execute', path.resolve(file)],
    {
      encoding: 'utf8',
      timeout,
      maxBuffer: 1024 * 1024,
      stdio: ['ignore', 'pipe', 'pipe'],
    },
  );
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  if (result.error || result.signal || result.status !== 0) {
    const reason = result.error?.code || result.signal || `exit ${result.status}`;
    console.error(`FAIL: Dart JavaScript probe failed (${reason}).`);
    process.exit(1);
  }
  if (!(result.stdout || '').split(/\r?\n/).includes(completion)) {
    console.error('FAIL: Dart JavaScript probe exited without its completion receipt.');
    process.exit(1);
  }
}
