#!/usr/bin/env node

import { spawn } from 'node:child_process';

const profile = normalizeProfile(process.env.GENERIC_IM_H5_SUITE_PROFILE || 'quick');
const dryRun = parseBool(process.env.GENERIC_IM_H5_SUITE_DRY_RUN);
const retries = Number(process.env.GENERIC_IM_H5_SUITE_RETRIES || 0);
const settleMs = Number(process.env.GENERIC_IM_H5_SUITE_SETTLE_MS || 1500);
const defaultTimeoutMs = Number(process.env.GENERIC_IM_H5_SUITE_TIMEOUT_MS || 240000);
const chatId =
  process.env.GENERIC_IM_H5_SUITE_CHAT_ID ||
  process.env.GENERIC_IM_SMOKE_CHAT_ID ||
  '710a5471-ab43-4728-9acf-7db3a65e2bea';
const baseWebUrl =
  process.env.GENERIC_IM_H5_SUITE_WEB_URL ||
  process.env.GENERIC_IM_WEB_URL ||
  'http://localhost:5175/';
const debugWebUrl =
  process.env.GENERIC_IM_H5_SUITE_DEBUG_WEB_URL ||
  baseWebUrl;
const callUiWebUrl =
  process.env.GENERIC_IM_H5_SUITE_CALL_UI_WEB_URL ||
  'http://localhost:5185/';

const caseDefinitions = [
  {
    name: 'manual-native',
    description: 'Native manual QA launcher dry-run',
    args: ['scripts/launch_flutter_web_native_manual_qa.mjs'],
    env: { GENERIC_IM_MANUAL_NATIVE_DRY_RUN: '1', GENERIC_IM_WEB_URL: baseWebUrl },
    timeoutMs: 30000,
    profiles: ['quick', 'full'],
  },
  {
    name: 'manual-call',
    description: 'Call manual QA launcher dry-run',
    args: ['scripts/launch_flutter_web_call_manual_qa.mjs'],
    env: { GENERIC_IM_MANUAL_CALL_DRY_RUN: '1', GENERIC_IM_WEB_URL: baseWebUrl },
    timeoutMs: 30000,
    profiles: ['quick', 'full'],
  },
  {
    name: 'qr-flow',
    description: 'QR user/group/login API flow',
    args: ['scripts/smoke_flutter_web_qr_flow.mjs'],
    env: { GENERIC_IM_WEB_URL: baseWebUrl },
    profiles: ['quick', 'full'],
  },
  {
    name: 'qr-image',
    description: 'QR image decode in Flutter Web scan page',
    args: ['scripts/smoke_flutter_web_qr_image.mjs'],
    env: { GENERIC_IM_WEB_URL: baseWebUrl },
    profiles: ['quick', 'full'],
  },
  {
    name: 'camera',
    description: 'Browser camera stream on scan page with fake media',
    args: ['scripts/smoke_flutter_web_camera.mjs'],
    env: { GENERIC_IM_WEB_URL: baseWebUrl },
    profiles: ['quick', 'full'],
  },
  {
    name: 'voice',
    description: 'Browser voice recording, upload, send, playback',
    args: ['scripts/smoke_flutter_web_voice.mjs'],
    env: { GENERIC_IM_WEB_URL: baseWebUrl },
    profiles: ['quick', 'full'],
  },
  {
    name: 'call-api-voice',
    description: 'Voice call API/WS chain with fake media',
    args: ['scripts/smoke_flutter_web_call.mjs'],
    env: { GENERIC_IM_SMOKE_CALL_TYPE: 'voice', GENERIC_IM_WEB_URL: baseWebUrl },
    profiles: ['quick', 'full'],
  },
  {
    name: 'call-api-video',
    description: 'Video call API/WS chain with fake media',
    args: ['scripts/smoke_flutter_web_call.mjs'],
    env: { GENERIC_IM_SMOKE_CALL_TYPE: 'video', GENERIC_IM_WEB_URL: baseWebUrl },
    profiles: ['quick', 'full'],
  },
  {
    name: 'location',
    description: 'Browser geolocation override and location message',
    args: ['scripts/smoke_flutter_web_location.mjs'],
    env: { GENERIC_IM_WEB_URL: debugWebUrl },
    profiles: ['debug', 'full'],
    optionalFlag: 'GENERIC_IM_H5_SUITE_INCLUDE_DEBUG',
  },
  {
    name: 'video',
    description: 'Existing video message CORS/range/browser playback',
    args: ['scripts/smoke_flutter_web_video.mjs'],
    env: { GENERIC_IM_WEB_URL: debugWebUrl },
    profiles: ['debug', 'full'],
    optionalFlag: 'GENERIC_IM_H5_SUITE_INCLUDE_DEBUG',
  },
  {
    name: 'call-ui',
    description: 'Four-way call UI regression suite on static Flutter Web build',
    args: ['scripts/smoke_flutter_web_call_ui_suite.mjs'],
    env: { GENERIC_IM_WEB_URL: callUiWebUrl },
    timeoutMs: 720000,
    profiles: ['ui', 'full'],
    optionalFlag: 'GENERIC_IM_H5_SUITE_INCLUDE_CALL_UI',
  },
];

async function main() {
  if (!profile) {
    throw new Error('GENERIC_IM_H5_SUITE_PROFILE must be quick, debug, ui, or full');
  }
  const selected = selectCases();
  const startedAt = new Date().toISOString();
  if (dryRun) {
    console.log(
      JSON.stringify(
        {
          ok: true,
          dryRun: true,
          profile,
          chatId,
          webUrls: suiteWebUrls(),
          retries,
          settleMs,
          cases: selected.map(publicCase),
        },
        null,
        2,
      ),
    );
    return;
  }

  const results = [];
  for (let index = 0; index < selected.length; index += 1) {
    if (index > 0 && settleMs > 0) {
      await sleep(settleMs);
    }
    results.push(await runCaseWithRetry(selected[index]));
  }

  const ok = results.every((result) => result.ok);
  console.log(
    JSON.stringify(
      {
        ok,
        startedAt,
        finishedAt: new Date().toISOString(),
        profile,
        chatId,
        webUrls: suiteWebUrls(),
        retries,
        settleMs,
        results,
      },
      null,
      2,
    ),
  );
  if (!ok) process.exit(1);
}

function selectCases() {
  const explicit = splitList(process.env.GENERIC_IM_H5_SUITE_CASES);
  if (explicit.length > 0) {
    return explicit.map((name) => {
      const found = caseDefinitions.find((item) => item.name === name);
      if (!found) {
        throw new Error(`Unknown H5 suite case: ${name}`);
      }
      return found;
    });
  }

  return caseDefinitions.filter((item) => {
    if (!item.profiles.includes(profile)) return false;
    if (!item.optionalFlag) return true;
    if (profile !== 'full') return true;
    return parseBool(process.env[item.optionalFlag]);
  });
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
        ...publicCase(testCase),
        attempts,
        summary: summarizeOutput(result.output),
      };
    }
  }
  return {
    ok: false,
    ...publicCase(testCase),
    attempts,
  };
}

async function runCase(testCase, attempt) {
  const env = {
    ...process.env,
    GENERIC_IM_SMOKE_CHAT_ID: chatId,
    ...(testCase.env || {}),
  };
  const child = spawn(process.execPath, testCase.args, {
    env,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let stdout = '';
  let stderr = '';
  child.stdout.on('data', (chunk) => {
    stdout += chunk.toString('utf8');
  });
  child.stderr.on('data', (chunk) => {
    stderr += chunk.toString('utf8');
  });

  const exitCode = await waitForExit(child, testCase.timeoutMs || defaultTimeoutMs);
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
    let settled = false;
    const finish = (code) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve(code ?? 0);
    };
    const timer = setTimeout(() => {
      child.kill('SIGTERM');
      setTimeout(() => {
        if (!settled) child.kill('SIGKILL');
      }, 2000);
      finish(124);
    }, timeoutMs);
    child.on('exit', finish);
  });
}

function publicCase(testCase) {
  return {
    name: testCase.name,
    description: testCase.description,
    command: [process.execPath, ...testCase.args].join(' '),
    webUrl: testCase.env?.GENERIC_IM_WEB_URL,
    timeoutMs: testCase.timeoutMs || defaultTimeoutMs,
  };
}

function suiteWebUrls() {
  return {
    base: baseWebUrl,
    debug: debugWebUrl,
    callUi: callUiWebUrl,
  };
}

function summarizeOutput(output) {
  if (!output) return null;
  return {
    ok: output.ok,
    skipped: output.skipped,
    mode: output.mode,
    callType: output.callType,
    chatId: output.chatId || output.chat?.chatId,
    callId: output.callId || output.call?.callId,
    webUrl: output.webUrl,
    apiBase: output.apiBase,
    rtc: output.rtc || output.config,
    urls: output.urls,
    camera: output.camera
      ? {
          status: output.camera.status,
          width: output.camera.width,
          height: output.camera.height,
        }
      : undefined,
    recording: output.recording
      ? {
          mimeType: output.recording.mimeType,
          size: output.recording.size,
          durationMs: output.recording.durationMs,
        }
      : undefined,
    decoded: output.decoded
      ? {
          status: output.decoded.status,
          decodedText: output.decoded.decodedText,
        }
      : undefined,
    userQr: output.userQr ? { raw: output.userQr.raw } : undefined,
    groupQr: output.groupQr ? { raw: output.groupQr.raw } : undefined,
    loginQr: output.loginQr ? { ticket: output.loginQr.ticket } : undefined,
    seededVideo: output.seededVideo
      ? {
          mimeType: output.seededVideo.generated?.mimeType,
          size: output.seededVideo.generated?.size,
          seq: output.seededVideo.sent?.seq,
        }
      : undefined,
  };
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

function splitList(value) {
  return String(value || '')
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean);
}

function normalizeProfile(value) {
  const normalized = String(value || '').trim().toLowerCase();
  if (['quick', 'debug', 'ui', 'full'].includes(normalized)) {
    return normalized;
  }
  return '';
}

function parseBool(value) {
  return ['1', 'true', 'yes', 'on'].includes(String(value || '').trim().toLowerCase());
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
