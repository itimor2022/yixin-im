#!/usr/bin/env node

import { spawn } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { createServer } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const apiBase = trimTrailingSlash(
  process.env.GENERIC_IM_SERVER_URL || 'http://localhost:8080',
);
const webUrl = process.env.GENERIC_IM_WEB_URL || 'http://localhost:5175/';
const wsBase =
  process.env.GENERIC_IM_WS_URL ||
  httpToWs(new URL('/api/v1/ws', apiBase).toString());
const callerUsername = process.env.GENERIC_IM_SMOKE_USERNAME || 'h5test';
const callerPassword = process.env.GENERIC_IM_SMOKE_PASSWORD || '123456';
const calleeUsername = process.env.GENERIC_IM_SMOKE_PEER_USERNAME || 'h5peer';
const calleePassword = process.env.GENERIC_IM_SMOKE_PEER_PASSWORD || '123456';
const callType = normalizeCallType(process.env.GENERIC_IM_SMOKE_CALL_TYPE || 'voice');
const eventTimeoutMs = Number(
  process.env.GENERIC_IM_SMOKE_CALL_EVENT_TIMEOUT_MS || 12000,
);

async function main() {
  if (!callType) {
    throw new Error('GENERIC_IM_SMOKE_CALL_TYPE must be voice or video');
  }

  const caller = await login(callerUsername, callerPassword, 'caller');
  const callee = await login(calleeUsername, calleePassword, 'callee');
  const configBody = requireApiSuccess(
    await getApi('/api/v1/call/config', caller.token),
    'Call config',
  );
  const config = summarizeRtcConfig(configBody.data);
  const media = await checkBrowserCallMedia();

  let call;
  if (!config.enabled) {
    call = {
      skipped: true,
      reason: 'rtc_disabled_or_not_configured',
      note: '/call/config reports RTC is disabled, so API create/accept/end was not attempted.',
    };
  } else {
    call = await smokeCallApiAndWsChain(caller, callee, config);
  }

  console.log(
    JSON.stringify(
      {
        ok: true,
        apiBase,
        webUrl,
        wsBase: redactWsUrl(wsBase),
        callType,
        caller: publicUser(caller),
        callee: publicUser(callee),
        config,
        media,
        call,
      },
      null,
      2,
    ),
  );
}

function trimTrailingSlash(value) {
  return value.replace(/\/+$/, '');
}

function httpToWs(value) {
  const url = new URL(value);
  url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
  return url.toString();
}

function normalizeCallType(value) {
  const normalized = String(value || '').trim().toLowerCase();
  if (normalized === 'audio') return 'voice';
  if (normalized === 'voice' || normalized === 'video') return normalized;
  return '';
}

function publicUser(session) {
  return {
    username: session.username,
    uuid: session.user.uuid,
    nickname: session.user.nickname || '',
  };
}

function summarizeRtcConfig(data) {
  const provider = String(data?.rtc_provider || data?.provider || '').trim();
  return {
    enabled: data?.enabled === true,
    provider,
    agoraEnabled: data?.agora_enabled === true,
    liveKitEnabled: data?.livekit_enabled === true,
    hasAgoraAppId: !!data?.app_id,
    hasLiveKitServerUrl: !!data?.livekit_server_url,
  };
}

function redactWsUrl(value) {
  try {
    const url = new URL(value);
    if (url.searchParams.has('token')) {
      url.searchParams.set('token', '***');
    }
    return url.toString();
  } catch {
    return value;
  }
}

async function login(username, password, label) {
  const loginBody = requireApiSuccess(
    await postApi('/api/v1/auth/login', {
      username,
      password,
      device_id: `web-call-smoke-${label}-${Date.now()}`,
      device_type: 'web',
      device_name: `Flutter Web Call Smoke ${label}`,
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

async function smokeCallApiAndWsChain(caller, callee, config) {
  const cleanupBefore = await cleanupActiveCalls([caller, callee]);
  const callerWs = await AppWebSocket.connect(caller.token, 'caller');
  const calleeWs = await AppWebSocket.connect(callee.token, 'callee');
  let callId = 0;
  let ended = false;

  try {
    await Promise.all([callerWs.ping(), calleeWs.ping()]);
    await sleep(300);

    const createResult = await postApi(
      '/api/v1/call/create',
      {
        target_user_id: callee.user.uuid,
        call_type: callType,
      },
      caller.token,
    );
    if (!isApiSuccess(createResult)) {
      if (isRtcNotConfigured(createResult.body)) {
        return {
          skipped: true,
          reason: 'rtc_not_configured_on_create',
          note: '/call/config looked enabled, but /call/create still reported RTC service is not configured.',
          cleanupBefore,
          create: compactApiResult(createResult),
        };
      }
      throw new Error(
        `Create call failed: ${JSON.stringify(compactApiResult(createResult))}`,
      );
    }

    const createBody = createResult.body;
    callId = Number(createBody?.data?.call_id || 0);
    if (!callId) {
      throw new Error(`Create call response missing call_id: ${JSON.stringify(createBody)}`);
    }

    const incoming = await calleeWs.waitFor(
      (message) =>
        message?.type === 'incoming_call' &&
        Number(message?.data?.call_id) === callId &&
        message?.data?.caller_id === caller.user.uuid,
      `incoming_call ${callId}`,
    );

    const acceptResult = await postApi(
      '/api/v1/call/accept',
      { call_id: callId },
      callee.token,
    );
    const acceptBody = requireApiSuccess(acceptResult, 'Accept call');

    const accepted = await callerWs.waitFor(
      (message) =>
        message?.type === 'call_accepted' &&
        Number(message?.data?.call_id) === callId,
      `call_accepted ${callId}`,
    );

    const callerHeartbeat = requireApiSuccess(
      await postApi('/api/v1/call/heartbeat', { call_id: callId }, caller.token),
      'Caller heartbeat',
    );
    const calleeHeartbeat = requireApiSuccess(
      await postApi('/api/v1/call/heartbeat', { call_id: callId }, callee.token),
      'Callee heartbeat',
    );
    assertHeartbeatConnected(callerHeartbeat, 'caller');
    assertHeartbeatConnected(calleeHeartbeat, 'callee');

    const endResult = await postApi(
      '/api/v1/call/end',
      { call_id: callId, reason: 'hangup' },
      caller.token,
    );
    const endBody = requireApiSuccess(endResult, 'End call');
    ended = true;

    const endedEvent = await calleeWs.waitFor(
      (message) =>
        message?.type === 'call_ended' &&
        Number(message?.data?.call_id) === callId,
      `call_ended ${callId}`,
    );

    const history = {
      caller: await findCallInHistory(caller.token, callId),
      callee: await findCallInHistory(callee.token, callId),
    };
    if (!history.caller || !history.callee) {
      throw new Error(`Call history missing call ${callId}: ${JSON.stringify(history)}`);
    }

    return {
      ok: true,
      provider: config.provider,
      cleanupBefore,
      callId,
      create: pickRtcFields(createBody.data),
      incoming: pickCallEvent(incoming),
      accept: pickRtcFields(acceptBody.data),
      accepted: pickCallEvent(accepted),
      heartbeat: {
        caller: callerHeartbeat.data,
        callee: calleeHeartbeat.data,
      },
      end: endBody.data,
      ended: pickCallEvent(endedEvent),
      history,
    };
  } finally {
    if (callId && !ended) {
      await cleanupCallById(caller.token, callId);
      await cleanupCallById(callee.token, callId);
    }
    callerWs.close();
    calleeWs.close();
  }
}

function isApiSuccess(result) {
  return result.ok && result.body?.code === 0;
}

function requireApiSuccess(result, label) {
  if (!isApiSuccess(result)) {
    throw new Error(`${label} failed: ${JSON.stringify(compactApiResult(result))}`);
  }
  return result.body;
}

function isRtcNotConfigured(body) {
  return String(body?.message || '')
    .toLowerCase()
    .includes('audio/video service is not configured');
}

function compactApiResult(result) {
  return {
    httpStatus: result.status,
    httpOk: result.ok,
    code: result.body?.code,
    message: result.body?.message,
    data: compactApiData(result.body?.data),
  };
}

function compactApiData(data) {
  if (!data || typeof data !== 'object') return data;
  const out = { ...data };
  if ('token' in out) out.token = '***';
  if ('app_id' in out) out.app_id = out.app_id ? 'configured' : '';
  return out;
}

function pickRtcFields(data) {
  return {
    callId: Number(data?.call_id || 0),
    provider: data?.rtc_provider || data?.provider || '',
    channelName: data?.channel_name || data?.room_name || '',
    hasToken: !!data?.token,
    hasAppId: !!data?.app_id,
    hasServerUrl: !!data?.server_url,
    identity: data?.identity || '',
  };
}

function pickCallEvent(message) {
  return {
    type: message?.type || '',
    callId: Number(message?.data?.call_id || 0),
    callType: message?.data?.call_type || '',
    callerId: message?.data?.caller_id || '',
    provider: message?.data?.rtc_provider || message?.data?.provider || '',
    channelName: message?.data?.channel_name || message?.data?.room_name || '',
    reason: message?.data?.reason || '',
    duration: message?.data?.duration,
  };
}

function assertHeartbeatConnected(body, label) {
  if (body?.data?.active !== true || body?.data?.status !== 'connected') {
    throw new Error(
      `${label} heartbeat expected connected: ${JSON.stringify(body?.data)}`,
    );
  }
}

async function cleanupActiveCalls(participants) {
  const cleaned = [];
  const seen = new Set();
  for (const participant of participants) {
    const historyResult = await getApi('/api/v1/call/history', participant.token);
    if (!isApiSuccess(historyResult)) {
      cleaned.push({
        by: participant.username,
        error: compactApiResult(historyResult),
      });
      continue;
    }
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
        { call_id: id, reason: 'smoke_cleanup' },
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

async function cleanupCallById(token, callId) {
  try {
    await postApi('/api/v1/call/end', { call_id: callId, reason: 'smoke_cleanup' }, token);
  } catch {}
}

async function findCallInHistory(token, callId) {
  const body = requireApiSuccess(
    await getApi('/api/v1/call/history', token),
    'Call history',
  );
  const list = Array.isArray(body?.data?.list) ? body.data.list : [];
  const found = list.find((item) => Number(item?.id || 0) === callId);
  if (!found) return null;
  return {
    id: Number(found.id),
    status: found.status,
    callType: found.call_type,
    isOutgoing: found.is_outgoing === true,
    duration: found.duration,
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

class AppWebSocket {
  static async connect(token, label) {
    const url = buildWsUrl(token);
    const socket = new WebSocket(url);
    const client = new AppWebSocket(socket, label, url);
    await client.opened;
    return client;
  }

  constructor(socket, label, url) {
    this.socket = socket;
    this.label = label;
    this.url = url;
    this.messages = [];
    this.waiters = [];
    this.seq = 1;
    this.opened = new Promise((resolve, reject) => {
      socket.addEventListener('open', resolve, { once: true });
      socket.addEventListener(
        'error',
        () => reject(new Error(`WebSocket ${label} failed to open`)),
        { once: true },
      );
    });
    socket.addEventListener('message', (event) => this.handleMessage(event));
    socket.addEventListener('close', () => this.rejectWaiters('closed'));
    socket.addEventListener('error', () => this.rejectWaiters('error'));
  }

  handleMessage(event) {
    const raw = typeof event.data === 'string'
      ? event.data
      : Buffer.from(event.data).toString('utf8');
    let message;
    try {
      message = JSON.parse(raw);
    } catch {
      message = { type: '__invalid__', raw };
    }
    this.messages.push(message);

    for (let index = 0; index < this.waiters.length; index += 1) {
      const waiter = this.waiters[index];
      let matched = false;
      try {
        matched = waiter.predicate(message);
      } catch (error) {
        waiter.reject(error);
        this.waiters.splice(index, 1);
        index -= 1;
        continue;
      }
      if (matched) {
        clearTimeout(waiter.timer);
        waiter.resolve(message);
        this.waiters.splice(index, 1);
        index -= 1;
      }
    }
  }

  ping() {
    const seq = this.seq++;
    const waiter = this.waitFor(
      (message) => message?.type === 'pong' && Number(message?.seq) === seq,
      `pong ${seq}`,
    );
    this.socket.send(JSON.stringify({ type: 'ping', seq }));
    return waiter;
  }

  waitFor(predicate, description, timeoutMs = eventTimeoutMs) {
    const existing = this.messages.find((message) => {
      try {
        return predicate(message);
      } catch {
        return false;
      }
    });
    if (existing) return Promise.resolve(existing);

    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.waiters = this.waiters.filter((waiter) => waiter.timer !== timer);
        reject(
          new Error(
            `Timed out waiting for ${description} on ${this.label}. Recent messages: ${JSON.stringify(this.messages.slice(-6))}`,
          ),
        );
      }, timeoutMs);
      this.waiters.push({ predicate, resolve, reject, timer });
    });
  }

  rejectWaiters(reason) {
    const waiters = this.waiters.splice(0);
    for (const waiter of waiters) {
      clearTimeout(waiter.timer);
      waiter.reject(new Error(`WebSocket ${this.label} ${reason}`));
    }
  }

  close() {
    try {
      this.socket.close();
    } catch {}
  }
}

function buildWsUrl(token) {
  const url = new URL(wsBase);
  url.searchParams.set('device_type', 'web');
  url.searchParams.set('token', token);
  return url.toString();
}

async function checkBrowserCallMedia() {
  const chrome = await ensureChromeForCallMediaSmoke();
  try {
    return await checkCallMediaStream(chrome.port);
  } finally {
    await chrome.cleanup();
  }
}

async function ensureChromeForCallMediaSmoke() {
  const chromePath =
    process.env.CHROME_PATH ||
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
  const port = String(await freePort());
  const userDataDir = mkdtempSync(join(tmpdir(), 'genericim-call-smoke-chrome-'));
  const child = spawn(
    chromePath,
    [
      '--headless=new',
      `--remote-debugging-port=${port}`,
      `--user-data-dir=${userDataDir}`,
      `--unsafely-treat-insecure-origin-as-secure=${new URL(webUrl).origin}`,
      '--enable-media-stream',
      '--use-fake-device-for-media-stream',
      '--use-fake-ui-for-media-stream',
      '--autoplay-policy=no-user-gesture-required',
      '--disable-background-timer-throttling',
      '--disable-extensions',
      '--disable-popup-blocking',
      '--no-first-run',
      '--no-default-browser-check',
      webUrl,
    ],
    { stdio: 'ignore' },
  );

  await waitForChromeDebugPort(port);

  return {
    port,
    cleanup: async () => {
      child.kill('SIGTERM');
      await sleep(800);
      await removeDirectoryWithRetry(userDataDir);
    },
  };
}

async function checkCallMediaStream(port) {
  const version = await fetch(`http://127.0.0.1:${port}/json/version`).then(
    (response) => response.json(),
  );
  const browser = await connectCDP(version.webSocketDebuggerUrl);
  let targetId = '';
  let client;
  try {
    const target = await browser.send('Target.createTarget', { url: webUrl });
    targetId = target?.targetId || '';
    const page = await waitForPageTarget(port, targetId);
    client = await connectCDP(page.webSocketDebuggerUrl);
    const origin = new URL(webUrl).origin;
    await client.send('Page.enable');
    await client.send('Runtime.enable');
    await browser.send('Browser.grantPermissions', {
      origin,
      permissions: ['audioCapture', 'videoCapture'],
    });
    await client.send('Page.navigate', { url: webUrl });
    await waitForPageReady(client, origin);
    const result = await client.send('Runtime.evaluate', {
      expression: buildCallMediaExpression(),
      awaitPromise: true,
      returnByValue: true,
      timeout: 15000,
    });
    const value = result?.result?.value;
    if (!value || value.status !== 'ok') {
      throw new Error(`Browser call media failed: ${JSON.stringify(value)}`);
    }
    return value;
  } finally {
    client?.close();
    if (targetId) {
      try {
        await browser.send('Target.closeTarget', { targetId });
      } catch {}
    }
    browser.close();
  }
}

function buildCallMediaExpression() {
  return `(() => new Promise(async (resolve) => {
    let settled = false;
    const finish = (status, extra = {}) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve({
        status,
        pageUrl: location.href,
        isSecureContext,
        hasMediaDevices: !!navigator.mediaDevices,
        hasGetUserMedia: !!navigator.mediaDevices?.getUserMedia,
        ...extra,
      });
    };
    const timer = setTimeout(() => {
      finish('timeout', { error: 'Timed out while reading audio/video stream' });
    }, 10000);
    try {
      if (!navigator.mediaDevices?.getUserMedia) {
        finish('unsupported', { error: 'mediaDevices.getUserMedia unavailable' });
        return;
      }
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: { echoCancellation: true, noiseSuppression: true },
        video: { width: { ideal: 640 }, height: { ideal: 480 }, facingMode: 'user' },
      });
      const audioTrack = stream.getAudioTracks()[0] || null;
      const videoTrack = stream.getVideoTracks()[0] || null;
      const video = document.createElement('video');
      video.id = 'codex-call-media-smoke';
      video.muted = true;
      video.playsInline = true;
      video.srcObject = stream;
      video.style.cssText = 'position:fixed;left:-9999px;top:0;width:160px;height:120px;';
      document.body.appendChild(video);
      await video.play();
      await new Promise((resolveFrame) => {
        if (video.videoWidth > 0 && video.videoHeight > 0) {
          resolveFrame();
          return;
        }
        video.addEventListener('loadedmetadata', resolveFrame, { once: true });
        setTimeout(resolveFrame, 2500);
      });
      const result = {
        audioTracks: stream.getAudioTracks().length,
        videoTracks: stream.getVideoTracks().length,
        audioTrackState: audioTrack?.readyState || '',
        videoTrackState: videoTrack?.readyState || '',
        audioTrackLabel: audioTrack?.label || '',
        videoTrackLabel: videoTrack?.label || '',
        audioSettings: audioTrack?.getSettings ? audioTrack.getSettings() : {},
        videoSettings: videoTrack?.getSettings ? videoTrack.getSettings() : {},
        videoWidth: video.videoWidth,
        videoHeight: video.videoHeight,
      };
      stream.getTracks().forEach((track) => track.stop());
      video.remove();
      if (
        result.audioTracks <= 0 ||
        result.videoTracks <= 0 ||
        result.audioTrackState !== 'live' ||
        result.videoTrackState !== 'live' ||
        result.videoWidth <= 0 ||
        result.videoHeight <= 0
      ) {
        finish('error', { error: 'Call media stream did not produce live audio and video tracks', ...result });
        return;
      }
      finish('ok', result);
    } catch (error) {
      finish('error', { error: String(error?.message || error) });
    }
  }))()`;
}

async function connectCDP(webSocketDebuggerUrl) {
  const ws = new WebSocket(webSocketDebuggerUrl);
  const pending = new Map();
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
  };
}

async function waitForPageTarget(port, targetId) {
  const deadline = Date.now() + 12000;
  while (Date.now() < deadline) {
    const pages = await fetch(`http://127.0.0.1:${port}/json/list`).then(
      (response) => response.json(),
    );
    const page = pages.find((item) => item.id === targetId);
    if (page?.webSocketDebuggerUrl) return page;
    await sleep(250);
  }
  throw new Error(`Chrome target ${targetId} was not ready`);
}

async function waitForPageReady(client, expectedOrigin) {
  const deadline = Date.now() + 12000;
  while (Date.now() < deadline) {
    const result = await client.send('Runtime.evaluate', {
      expression:
        '({ readyState: document.readyState, href: location.href, origin: location.origin })',
      returnByValue: true,
    });
    const value = result?.result?.value;
    if (
      value?.origin === expectedOrigin &&
      (value.readyState === 'interactive' || value.readyState === 'complete')
    ) {
      return;
    }
    await sleep(250);
  }
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

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

main().catch((error) => {
  console.error(error?.stack || error?.message || String(error));
  process.exit(1);
});
