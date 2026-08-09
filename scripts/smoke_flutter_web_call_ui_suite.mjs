#!/usr/bin/env node

import { spawn } from 'node:child_process';

const webUrl = process.env.GENERIC_IM_WEB_URL || 'http://localhost:5185/';
const settleMs = Number(process.env.GENERIC_IM_SMOKE_CALL_SUITE_SETTLE_MS || 6000);
const retries = Number(process.env.GENERIC_IM_SMOKE_CALL_SUITE_RETRIES || 1);
const caseTimeoutMs = Number(process.env.GENERIC_IM_SMOKE_CALL_SUITE_TIMEOUT_MS || 180000);

const cases = [
  { mode: 'incoming', callType: 'voice' },
  { mode: 'incoming', callType: 'video' },
  { mode: 'outgoing', callType: 'voice' },
  { mode: 'outgoing', callType: 'video' },
];

async function main() {
  const startedAt = new Date().toISOString();
  const results = [];

  for (let index = 0; index < cases.length; index += 1) {
    if (index > 0 && settleMs > 0) {
      await sleep(settleMs);
    }
    results.push(await runCaseWithRetry(cases[index]));
  }

  const ok = results.every((result) => result.ok);
  console.log(
    JSON.stringify(
      {
        ok,
        startedAt,
        finishedAt: new Date().toISOString(),
        webUrl,
        settleMs,
        retries,
        results,
      },
      null,
      2,
    ),
  );

  if (!ok) process.exit(1);
}

async function runCaseWithRetry(testCase) {
  const attempts = [];
  for (let attempt = 0; attempt <= retries; attempt += 1) {
    if (attempt > 0 && settleMs > 0) {
      await sleep(settleMs);
    }
    const result = await runCase(testCase, attempt + 1);
    attempts.push(result);
    if (result.ok) {
      return {
        ok: true,
        mode: testCase.mode,
        callType: testCase.callType,
        attempts,
        summary: summarizeSmokeResult(result.output),
      };
    }
  }

  return {
    ok: false,
    mode: testCase.mode,
    callType: testCase.callType,
    attempts,
  };
}

async function runCase(testCase, attempt) {
  const env = {
    ...process.env,
    GENERIC_IM_WEB_URL: webUrl,
    GENERIC_IM_SMOKE_CALL_UI_MODE: testCase.mode,
    GENERIC_IM_SMOKE_CALL_TYPE: testCase.callType,
  };
  const child = spawn(
    process.execPath,
    ['scripts/smoke_flutter_web_call_ui.mjs'],
    {
      env,
      stdio: ['ignore', 'pipe', 'pipe'],
    },
  );

  let stdout = '';
  let stderr = '';
  child.stdout.on('data', (chunk) => {
    stdout += chunk.toString('utf8');
  });
  child.stderr.on('data', (chunk) => {
    stderr += chunk.toString('utf8');
  });

  const exitCode = await waitForExit(child, caseTimeoutMs);
  const output = parseJson(stdout) || parseJson(stderr);
  return {
    ok: exitCode === 0 && output?.ok === true,
    attempt,
    exitCode,
    output,
    stdoutTail: tail(stdout),
    stderrTail: tail(stderr),
  };
}

function waitForExit(child, timeoutMs) {
  return new Promise((resolve) => {
    const timer = setTimeout(() => {
      child.kill('SIGTERM');
      resolve(124);
    }, timeoutMs);
    child.on('exit', (code) => {
      clearTimeout(timer);
      resolve(code ?? 0);
    });
  });
}

function parseJson(text) {
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start < 0 || end <= start) return null;
  try {
    return JSON.parse(text.slice(start, end + 1));
  } catch {
    return null;
  }
}

function summarizeSmokeResult(output) {
  if (!output) return null;
  return {
    callId: output.callId,
    mode: output.mode,
    callType: output.callType,
    ui: output.ui,
    history: output.history,
    stateChecks: output.stateChecks,
    events: output.events,
  };
}

function tail(text, maxLength = 2000) {
  if (text.length <= maxLength) return text;
  return text.slice(text.length - maxLength);
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

main().catch((error) => {
  console.error(error?.stack || error?.message || String(error));
  process.exit(1);
});
