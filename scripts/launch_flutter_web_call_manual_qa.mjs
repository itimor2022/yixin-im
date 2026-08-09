#!/usr/bin/env node

import { spawn } from 'node:child_process';
import { existsSync, mkdtempSync, rmSync } from 'node:fs';
import { createServer } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const apiBase = trimTrailingSlash(
  process.env.GENERIC_IM_SERVER_URL || 'http://localhost:8080',
);
const webUrl = process.env.GENERIC_IM_WEB_URL || 'http://localhost:5175/';
const callerUsername = process.env.GENERIC_IM_MANUAL_CALL_USERNAME ||
  process.env.GENERIC_IM_SMOKE_USERNAME ||
  'h5test';
const callerPassword = process.env.GENERIC_IM_MANUAL_CALL_PASSWORD ||
  process.env.GENERIC_IM_SMOKE_PASSWORD ||
  '123456';
const calleeUsername = process.env.GENERIC_IM_MANUAL_CALL_PEER_USERNAME ||
  process.env.GENERIC_IM_SMOKE_PEER_USERNAME ||
  'h5peer';
const calleePassword = process.env.GENERIC_IM_MANUAL_CALL_PEER_PASSWORD ||
  process.env.GENERIC_IM_SMOKE_PEER_PASSWORD ||
  '123456';
const chatIdFromEnv = process.env.GENERIC_IM_MANUAL_CALL_CHAT_ID ||
  process.env.GENERIC_IM_SMOKE_CHAT_ID ||
  '';
const webRouteMode = normalizeWebRouteMode(
  process.env.GENERIC_IM_WEB_ROUTE_MODE || 'hash',
);
const viewport = {
  width: Number(process.env.GENERIC_IM_MANUAL_CALL_VIEWPORT_WIDTH || 430),
  height: Number(process.env.GENERIC_IM_MANUAL_CALL_VIEWPORT_HEIGHT || 932),
  deviceScaleFactor: Number(process.env.GENERIC_IM_MANUAL_CALL_DEVICE_SCALE || 2),
};
const dryRun = parseBool(process.env.GENERIC_IM_MANUAL_CALL_DRY_RUN);
const keepProfiles = parseBool(process.env.GENERIC_IM_MANUAL_CALL_KEEP_PROFILES);
const cleanupCalls = process.env.GENERIC_IM_MANUAL_CALL_CLEANUP === undefined ||
  parseBool(process.env.GENERIC_IM_MANUAL_CALL_CLEANUP);

async function main() {
  if (!webRouteMode) {
    throw new Error('GENERIC_IM_WEB_ROUTE_MODE must be hash or path');
  }

  const caller = await login(callerUsername, callerPassword, 'manual-caller');
  const callee = await login(calleeUsername, calleePassword, 'manual-callee');
  const callConfig = requireApiSuccess(
    await getApi('/api/v1/call/config', caller.token),
    'Call config',
  );
  if (callConfig.data?.enabled !== true) {
    throw new Error(
      `RTC is disabled or not configured: ${JSON.stringify(callConfig.data || {})}`,
    );
  }

  const cleanupBefore = cleanupCalls ? await cleanupActiveCalls([caller, callee]) : [];
  const chat = await ensurePrivateChat(caller, callee);
  const callerUrl = buildFlutterRouteUrl(chat.path);
  const calleeUrl = new URL(webUrl).toString();
  const summary = {
    ok: true,
    dryRun,
    apiBase,
    webUrl,
    webRouteMode,
    rtc: {
      enabled: callConfig.data?.enabled === true,
      provider: callConfig.data?.provider || callConfig.data?.rtc_provider || '',
    },
    viewport,
    caller: publicUser(caller),
    callee: publicUser(callee),
    chat,
    urls: {
      caller: callerUrl,
      callee: calleeUrl,
    },
    cleanupBefore,
    notes: [
      'This launcher does not use fake media devices.',
      'This launcher does not auto-grant microphone or camera permission.',
      'Keep this process running during manual QA; press Ctrl+C to close launched Chrome windows.',
    ],
  };

  if (dryRun) {
    console.log(JSON.stringify(summary, null, 2));
    return;
  }

  const launched = [];
  try {
    launched.push(await launchManualChrome(caller, 'caller', callerUrl, 40));
    launched.push(await launchManualChrome(callee, 'callee', calleeUrl, 520));
    console.log(JSON.stringify({
      ...summary,
      dryRun: false,
      chrome: launched.map((item) => ({
        label: item.label,
        port: item.port,
        userDataDir: item.userDataDir,
        url: item.url,
      })),
    }, null, 2));
    printManualSteps();
    await waitForShutdown();
  } finally {
    await cleanupChrome(launched);
  }
}

function printManualSteps() {
  console.log('');
  console.log('Manual RTC QA steps:');
  console.log('1. In the caller window, click the voice or video call button.');
  console.log('2. Allow microphone/camera permission in both browser prompts.');
  console.log('3. In the callee window, answer the incoming call.');
  console.log('4. Verify local preview, remote video, microphone input, speaker output, mute/video toggles, camera switch, and hangup.');
  console.log('5. Repeat once for voice and once for video. Press Ctrl+C here when finished.');
}

async function launchManualChrome(session, label, url, x) {
  const chromePath = resolveChromePath();
  const port = String(await freePort());
  const safeLabel = label.replace(/[^a-z0-9_-]/gi, '-').toLowerCase();
  const userDataDir = mkdtempSync(
    join(tmpdir(), `genericim-call-manual-${safeLabel}-chrome-`),
  );
  const origin = new URL(webUrl).origin;
  const child = spawn(
    chromePath,
    [
      `--remote-debugging-port=${port}`,
      `--user-data-dir=${userDataDir}`,
      `--window-size=${viewport.width},${viewport.height}`,
      `--window-position=${x},40`,
      `--unsafely-treat-insecure-origin-as-secure=${origin}`,
      '--enable-media-stream',
      '--autoplay-policy=no-user-gesture-required',
      '--disable-background-timer-throttling',
      '--disable-extensions',
      '--disable-popup-blocking',
      '--no-first-run',
      '--no-default-browser-check',
      '--new-window',
      'about:blank',
    ],
    { stdio: 'ignore' },
  );

  let client;
  try {
    await waitForChromeDebugPort(port);
    const page = await waitForFirstPageTarget(port);
    client = await connectCDP(page.webSocketDebuggerUrl);
    await client.send('Page.enable');
    await client.send('Runtime.enable');
    await client.send('Emulation.setDeviceMetricsOverride', {
      width: viewport.width,
      height: viewport.height,
      deviceScaleFactor: viewport.deviceScaleFactor,
      mobile: true,
    });
    await client.send('Page.addScriptToEvaluateOnNewDocument', {
      source: buildAuthStorageScript(session),
    });
    await client.send('Page.navigate', { url });
    await waitForRuntimeValue(
      client,
      `document.readyState === 'interactive' || document.readyState === 'complete'`,
      'document ready',
      20000,
    );
    return {
      label,
      port,
      userDataDir,
      child,
      client,
      url,
    };
  } catch (error) {
    client?.close();
    child.kill('SIGTERM');
    await sleep(500);
    rmSync(userDataDir, { recursive: true, force: true });
    throw error;
  }
}

async function cleanupChrome(launched) {
  for (const item of launched.reverse()) {
    item.client?.close();
    item.child?.kill('SIGTERM');
  }
  await sleep(800);
  if (keepProfiles) return;
  for (const item of launched) {
    await removeDirectoryWithRetry(item.userDataDir);
  }
}

function resolveChromePath() {
  if (process.env.CHROME_PATH) return process.env.CHROME_PATH;
  const macPath = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
  if (existsSync(macPath)) return macPath;
  return 'google-chrome';
}

async function ensurePrivateChat(caller, callee) {
  const peerName = callee.user.nickname || callee.username;
  const chatId = chatIdFromEnv || await createPrivateChat(caller, callee);
  const path =
    `/chat/${encodeURIComponent(chatId)}` +
    `?name=${encodeURIComponent(peerName)}&type=private`;
  return {
    chatId,
    path,
    source: chatIdFromEnv ? 'env' : 'created_or_reused',
  };
}

async function createPrivateChat(caller, callee) {
  const body = requireApiSuccess(
    await postApi(
      '/api/v1/chat/create',
      {
        type: 1,
        member_ids: [callee.user.uuid],
      },
      caller.token,
    ),
    'Create private chat',
  );
  const chatId = body?.data?.uuid || body?.data?.id || body?.data?.chat_id;
  if (!chatId) {
    throw new Error(`Create private chat response missing uuid: ${JSON.stringify(body)}`);
  }
  return String(chatId);
}

function buildFlutterRouteUrl(path) {
  if (webRouteMode === 'path') {
    return new URL(path, webUrl).toString();
  }
  const url = new URL(webUrl);
  url.hash = path;
  return url.toString();
}

function buildAuthStorageScript(session) {
  const userData = {
    ...session.user.raw,
    uuid: session.user.uuid,
    id: session.user.raw?.id?.toString?.() || session.user.uuid,
    username: session.user.raw?.username || session.username,
    nickname: session.user.nickname || session.user.raw?.nickname || session.username,
    status: session.user.raw?.status ?? 1,
    created_at: session.user.raw?.created_at || new Date().toISOString(),
  };
  const payload = {
    token: session.token,
    userId: session.user.uuid,
    userDataJson: JSON.stringify(userData),
  };
  return `(() => {
    const payload = ${JSON.stringify(payload)};
    localStorage.setItem('flutter.auth_token', JSON.stringify(payload.token));
    localStorage.setItem('flutter.user_id', JSON.stringify(payload.userId));
    localStorage.setItem('flutter.auth_user_data', JSON.stringify(payload.userDataJson));
  })();`;
}

async function login(username, password, label) {
  const loginBody = requireApiSuccess(
    await postApi('/api/v1/auth/login', {
      username,
      password,
      device_id: `web-call-manual-${label}-${Date.now()}`,
      device_type: 'web',
      device_name: `Flutter Web Call Manual QA ${label}`,
    }),
    `Login ${username}`,
  );
  const token = loginBody?.data?.token;
  if (!token) {
    throw new Error(`Login ${username} failed: missing token`);
  }

  const meBody = requireApiSuccess(
    await getApi('/api/v1/user/me', token),
    `/user/me ${username}`,
  );
  const uuid = meBody?.data?.uuid || meBody?.data?.id;
  if (!uuid) {
    throw new Error(`/user/me ${username} failed: missing uuid`);
  }
  return {
    username,
    token,
    user: {
      uuid,
      nickname: meBody.data.nickname || '',
      raw: meBody.data,
    },
  };
}

async function cleanupActiveCalls(participants) {
  const cleaned = [];
  const seen = new Set();
  for (const participant of participants) {
    const historyResult = await getApi('/api/v1/call/history', participant.token);
    if (!historyResult.ok || historyResult.body?.code !== 0) continue;
    const list = Array.isArray(historyResult.body?.data?.list)
      ? historyResult.body.data.list
      : [];
    for (const item of list) {
      const id = Number(item?.id || 0);
      const status = String(item?.status || '');
      if (!id || seen.has(id) || !['calling', 'connected'].includes(status)) {
        continue;
      }
      seen.add(id);
      const endResult = await postApi(
        '/api/v1/call/end',
        { call_id: id, reason: 'manual_qa_cleanup' },
        participant.token,
      );
      cleaned.push({
        by: participant.username,
        callId: id,
        previousStatus: status,
        result: compactApiResult(endResult),
      });
    }
  }
  return cleaned;
}

function requireApiSuccess(result, label) {
  if (!result.ok || result.body?.code !== 0) {
    throw new Error(`${label} failed: ${JSON.stringify(compactApiResult(result))}`);
  }
  return result.body;
}

function compactApiResult(result) {
  return {
    httpStatus: result.status,
    httpOk: result.ok,
    code: result.body?.code,
    message: result.body?.message,
  };
}

async function postApi(path, data, token = '') {
  return requestApi('POST', path, token, data);
}

async function getApi(path, token = '') {
  return requestApi('GET', path, token);
}

async function requestApi(method, path, token = '', data) {
  const response = await fetch(`${apiBase}${path}`, {
    method,
    headers: {
      ...(data !== undefined ? { 'Content-Type': 'application/json' } : {}),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    ...(data !== undefined ? { body: JSON.stringify(data) } : {}),
  });
  let body;
  try {
    body = await response.json();
  } catch {
    body = { message: await response.text() };
  }
  return {
    status: response.status,
    ok: response.ok,
    body,
  };
}

function publicUser(session) {
  return {
    username: session.username,
    uuid: session.user.uuid,
    nickname: session.user.nickname || '',
  };
}

async function connectCDP(webSocketDebuggerUrl) {
  const ws = new WebSocket(webSocketDebuggerUrl);
  const pending = new Map();
  const listeners = new Map();
  let nextId = 1;

  await new Promise((resolve, reject) => {
    ws.addEventListener('open', resolve, { once: true });
    ws.addEventListener('error', reject, { once: true });
  });

  ws.addEventListener('message', (event) => {
    const message = JSON.parse(event.data);
    if (message.id && pending.has(message.id)) {
      const { resolve, reject } = pending.get(message.id);
      pending.delete(message.id);
      if (message.error) {
        reject(new Error(JSON.stringify(message.error)));
      } else {
        resolve(message.result);
      }
    } else if (message.method && listeners.has(message.method)) {
      for (const listener of listeners.get(message.method)) {
        listener(message.params || {});
      }
    }
  });

  return {
    send(method, params = {}) {
      const id = nextId++;
      ws.send(JSON.stringify({ id, method, params }));
      return new Promise((resolve, reject) => {
        pending.set(id, { resolve, reject });
      });
    },
    close() {
      ws.close();
    },
    on(method, listener) {
      const methodListeners = listeners.get(method) || [];
      methodListeners.push(listener);
      listeners.set(method, methodListeners);
    },
  };
}

async function waitForFirstPageTarget(port) {
  const deadline = Date.now() + 12000;
  while (Date.now() < deadline) {
    const pages = await fetch(`http://127.0.0.1:${port}/json/list`).then(
      (response) => response.json(),
    );
    const page = pages.find((item) => item.type === 'page' && item.webSocketDebuggerUrl);
    if (page) return page;
    await sleep(250);
  }
  throw new Error(`Chrome page target on ${port} was not ready`);
}

async function waitForChromeDebugPort(port) {
  const deadline = Date.now() + 15000;
  let lastError;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(`http://127.0.0.1:${port}/json/version`);
      if (response.ok) return;
    } catch (error) {
      lastError = error;
    }
    await sleep(250);
  }
  throw new Error(`Chrome debug port ${port} was not ready: ${lastError}`);
}

async function waitForRuntimeValue(client, expression, description, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  let lastValue;
  while (Date.now() < deadline) {
    const result = await client.send('Runtime.evaluate', {
      expression,
      returnByValue: true,
    });
    lastValue = result?.result?.value;
    if (lastValue === true) return true;
    await sleep(250);
  }
  throw new Error(`Timed out waiting for ${description}: last=${lastValue}`);
}

async function freePort() {
  return new Promise((resolve, reject) => {
    const server = createServer();
    server.listen(0, '127.0.0.1', () => {
      const address = server.address();
      const port = typeof address === 'object' && address ? address.port : 0;
      server.close(() => resolve(port));
    });
    server.on('error', reject);
  });
}

async function waitForShutdown() {
  return new Promise((resolve) => {
    const done = () => resolve();
    process.once('SIGINT', done);
    process.once('SIGTERM', done);
    process.stdin.resume();
  });
}

async function removeDirectoryWithRetry(path) {
  let lastError;
  for (let attempt = 0; attempt < 5; attempt += 1) {
    try {
      rmSync(path, { recursive: true, force: true });
      return;
    } catch (error) {
      lastError = error;
      await sleep(250);
    }
  }
  throw lastError;
}

function normalizeWebRouteMode(value) {
  const normalized = String(value || '').trim().toLowerCase();
  if (normalized === 'hash' || normalized === 'path') {
    return normalized;
  }
  return '';
}

function trimTrailingSlash(value) {
  return value.replace(/\/+$/, '');
}

function parseBool(value) {
  return ['1', 'true', 'yes', 'on'].includes(String(value || '').trim().toLowerCase());
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

main().catch((error) => {
  console.error(error?.stack || error?.message || String(error));
  process.exit(1);
});
