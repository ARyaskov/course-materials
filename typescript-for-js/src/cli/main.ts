#!/usr/bin/env node
import process from 'node:process';

import { run } from './run.ts';

const exitCode = await run({
  argv: process.argv.slice(2),
  env: process.env,
  io: {
    out: (text) => process.stdout.write(text),
    error: (text) => process.stderr.write(text),
  },
});

process.exitCode = exitCode;
