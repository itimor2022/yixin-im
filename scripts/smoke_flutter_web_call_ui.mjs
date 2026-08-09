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
const uiMode = normalizeUiMode(process.env.GENERIC_IM_SMOKE_CALL_UI_MODE || 'incoming');
const chatIdFromEnv = process.env.GENERIC_IM_SMOKE_CHAT_ID || '';
const webRouteMode = normalizeWebRouteMode(
  process.env.GENERIC_IM_WEB_ROUTE_MODE || 'hash',
);
const disableWebSecurity =
  process.env.GENERIC_IM_SMOKE_DISABLE_WEB_SECURITY === '1';
const forcedRequestOrigin =
  process.env.GENERIC_IM_SMOKE_FORCE_ORIGIN || '';
const ringbackOnly = process.env.GENERIC_IM_SMOKE_RINGBACK_ONLY === '1';
const viewport = {
  width: Number(process.env.GENERIC_IM_SMOKE_VIEWPORT_WIDTH || 390),
  height: Number(process.env.GENERIC_IM_SMOKE_VIEWPORT_HEIGHT || 844),
  deviceScaleFactor: Number(process.env.GENERIC_IM_SMOKE_DEVICE_SCALE || 2),
};

async function main() {
  if (!callType) {
    throw new Error('GENERIC_IM_SMOKE_CALL_TYPE must be voice or video');
  }
  if (!uiMode) {
    throw new Error('GENERIC_IM_SMOKE_CALL_UI_MODE must be incoming or outgoing');
  }
  if (!webRouteMode) {
    throw new Error('GENERIC_IM_WEB_ROUTE_MODE must be hash or path');
  }

  const caller = await login(callerUsername, callerPassword, 'ui-caller');
  const callee = await login(calleeUsername, calleePassword, 'ui-callee');
  const config = requireApiSuccess(
    await getApi('/api/v1/call/config', caller.token),
    'Call config',
  );
  if (config.data?.enabled !== true) {
    console.log(
      JSON.stringify(
        {
          ok: true,
          skipped: true,
          reason: 'rtc_disabled_or_not_configured',
          apiBase,
          webUrl,
          callType,
        },
        null,
        2,
      ),
    );
    return;
  }

  const cleanupBefore = await cleanupActiveCalls([caller, callee]);
  if (uiMode === 'outgoing') {
    await smokeOutgoingCallUi(caller, callee, cleanupBefore);
    return;
  }

  const callerWs = await AppWebSocket.connect(caller.token, 'caller');
  const chrome = await launchAuthedCalleeChrome(callee);
  let callId = 0;
  let endedByUi = false;

  try {
    await callerWs.ping();
    await waitForFlutterReady(chrome.client);
    await enableFlutterSemantics(chrome.client);
    await waitForAppSettled(chrome.client);

    const createBody = requireApiSuccess(
      await postApi(
        '/api/v1/call/create',
        {
          target_user_id: callee.user.uuid,
          call_type: callType,
        },
        caller.token,
      ),
      'Create call',
    );
    callId = Number(createBody?.data?.call_id || 0);
    if (!callId) {
      throw new Error(`Create call response missing call_id: ${JSON.stringify(createBody)}`);
    }

    const incomingUi = await waitForAccessibilityText(chrome.client, [
      '接听',
      'Answer',
      '来电',
      'Incoming call',
    ]);

    await clickCalleeAnswer(chrome.client);
    const accepted = await callerWs.waitFor(
      (message) =>
        message?.type === 'call_accepted' &&
        Number(message?.data?.call_id) === callId,
      `call_accepted ${callId}`,
    );

    const callPageUi = await waitForAccessibilityText(chrome.client, [
      '挂断',
      'End',
      '静音',
      'Mute',
    ]);

    await clickCalleeEnd(chrome.client);
    const ended = await callerWs.waitFor(
      (message) =>
        message?.type === 'call_ended' &&
        Number(message?.data?.call_id) === callId,
      `call_ended ${callId}`,
    );
    endedByUi = true;

    const history = {
      caller: await findCallInHistory(caller.token, callId),
      callee: await findCallInHistory(callee.token, callId),
    };

    console.log(
      JSON.stringify(
        {
          ok: true,
          mode: uiMode,
          apiBase,
          webUrl,
          wsBase: redactWsUrl(wsBase),
          callType,
          viewport,
          caller: publicUser(caller),
          callee: publicUser(callee),
          cleanupBefore,
          callId,
          ui: {
            incomingMatched: incomingUi.matched,
            callPageMatched: callPageUi.matched,
          },
          events: {
            accepted: pickCallEvent(accepted),
            ended: pickCallEvent(ended),
          },
          history,
        },
        null,
        2,
      ),
    );
  } finally {
    if (callId && !endedByUi) {
      await cleanupCallById(caller.token, callId);
      await cleanupCallById(callee.token, callId);
    }
    callerWs.close();
    await chrome.cleanup();
  }
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

function normalizeUiMode(value) {
  const normalized = String(value || '').trim().toLowerCase();
  if (normalized === 'incoming' || normalized === 'outgoing') {
    return normalized;
  }
  return '';
}

function normalizeWebRouteMode(value) {
  const normalized = String(value || '').trim().toLowerCase();
  if (normalized === 'hash' || normalized === 'path') {
    return normalized;
  }
  return '';
}

function publicUser(session) {
  return {
    username: session.username,
    uuid: session.user.uuid,
    nickname: session.user.nickname || '',
  };
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

async function smokeOutgoingCallUi(caller, callee, cleanupBefore) {
  const chat = await ensurePrivateChat(caller, callee);
  const callerChrome = await launchAuthedChrome(
    caller,
    'caller',
    buildFlutterRouteUrl(chat.path),
  );
  const calleeChrome = await launchAuthedChrome(callee, 'callee');
  let callId = 0;
  let endedByUi = false;

  try {
    await Promise.all([
      prepareFlutterApp(callerChrome.client),
      prepareFlutterApp(calleeChrome.client),
    ]);

    const outgoingButton = await waitForAccessibilityButton(
      callerChrome.client,
      callType === 'video'
        ? ['视频通话', 'Video call']
        : ['语音通话', 'Voice call'],
    );

    await clickSemanticButton(
      callerChrome.client,
      callType === 'video'
        ? ['视频通话', 'Video call']
          : ['语音通话', 'Voice call'],
    );

    const ringbackResource = await waitForRingbackResource(callerChrome);
    // Leave the outgoing page ringing briefly so Chromium emits playback
    // events before the callee answers and the app stops the local tone.
    await sleep(800);
    const ringbackPlayback = await summarizeRingbackPlayback(callerChrome);

    if (ringbackOnly) {
      const cleanupAfter = await cleanupActiveCalls([caller, callee]);
      console.log(JSON.stringify({
        ok: true,
        mode: 'ringback-only',
        apiBase,
        webUrl,
        callType,
        ringback: {
          resource: ringbackResource,
          playback: ringbackPlayback,
        },
        cleanupBefore,
        cleanupAfter,
      }, null, 2));
      return;
    }

    const activeCallPromise = waitForHistoryCall(
      caller.token,
      (item) =>
        item.isOutgoing === true &&
        item.callType === callType &&
        ['calling', 'connected'].includes(item.status),
      `active outgoing ${callType} call`,
    );

    const incomingUi = await waitForAccessibilityText(calleeChrome.client, [
      '接听',
      'Answer',
      '来电',
      'Incoming call',
    ]);
    await clickCalleeAnswer(calleeChrome.client);

    const activeCall = await activeCallPromise;
    callId = activeCall.id;
    const connectedCall = await waitForHistoryCall(
      caller.token,
      (item) => item.id === callId && item.status === 'connected',
      `caller history connected ${callId}`,
      35000,
    );

    const callerCallPageUi = await waitForAccessibilityText(callerChrome.client, [
      '挂断',
      'End',
      '静音',
      'Mute',
    ]);

    await clickCalleeEnd(callerChrome.client);
    const endedHistory = {
      caller: await waitForHistoryCall(
        caller.token,
        (item) => item.id === callId && item.status === 'ended',
        `caller history ended ${callId}`,
      ),
      callee: await waitForHistoryCall(
        callee.token,
        (item) => item.id === callId && item.status === 'ended',
        `callee history ended ${callId}`,
      ),
    };
    endedByUi = true;

    const history = {
      caller: await findCallInHistory(caller.token, callId),
      callee: await findCallInHistory(callee.token, callId),
    };

    console.log(
      JSON.stringify(
        {
          ok: true,
          mode: uiMode,
          apiBase,
          webUrl,
          wsBase: redactWsUrl(wsBase),
          callType,
          webRouteMode,
          viewport,
          chat,
          caller: publicUser(caller),
          callee: publicUser(callee),
          cleanupBefore,
          callId,
          ui: {
            outgoingButtonMatched: outgoingButton.matched,
            incomingMatched: incomingUi.matched,
            callerCallPageMatched: callerCallPageUi.matched,
          },
          ringback: {
            resource: ringbackResource,
            playback: ringbackPlayback,
          },
          stateChecks: {
            activeCall,
            connectedCall,
            endedHistory,
          },
          history,
        },
        null,
        2,
      ),
    );
  } catch (error) {
    console.error(
      JSON.stringify(
        {
          ok: false,
          mode: uiMode,
          callType,
          chat,
          callId,
          callerLogs: callerChrome.logs.slice(-80),
          calleeLogs: calleeChrome.logs.slice(-80),
          callerRingbackResponses: callerChrome.networkResponses,
          callerMediaEvents: callerChrome.mediaEvents.slice(-80),
        },
        null,
        2,
      ),
    );
    throw error;
  } finally {
    if (callId && !endedByUi) {
      await cleanupCallById(caller.token, callId);
      await cleanupCallById(callee.token, callId);
    }
    await callerChrome.cleanup();
    await calleeChrome.cleanup();
  }
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
      device_id: `web-call-ui-smoke-${label}-${Date.now()}`,
      device_type: 'web',
      device_name: `Flutter Web Call UI Smoke ${label}`,
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
  return summarizeHistoryCall(found);
}

async function waitForHistoryCall(token, predicate, description, timeoutMs = 20000) {
  const deadline = Date.now() + timeoutMs;
  let lastCalls = [];
  while (Date.now() < deadline) {
    const body = requireApiSuccess(
      await getApi('/api/v1/call/history', token),
      `Call history for ${description}`,
    );
    const list = Array.isArray(body?.data?.list) ? body.data.list : [];
    const calls = list.map(summarizeHistoryCall);
    const found = calls.find(predicate);
    if (found) return found;
    lastCalls = calls.slice(0, 8);
    await sleep(500);
  }
  throw new Error(
    `Timed out waiting for ${description} in call history. Last calls: ${JSON.stringify(lastCalls)}`,
  );
}

function summarizeHistoryCall(found) {
  return {
    id: Number(found.id),
    status: found.status,
    callType: found.call_type,
    isOutgoing: found.is_outgoing === true,
    duration: found.duration,
  };
}

function pickCallEvent(message) {
  return {
    type: message?.type || '',
    callId: Number(message?.data?.call_id || 0),
    callType: message?.data?.call_type || '',
    callerId: message?.data?.caller_id || '',
    calleeId: message?.data?.callee_id || '',
    provider: message?.data?.rtc_provider || message?.data?.provider || '',
    channelName: message?.data?.channel_name || message?.data?.room_name || '',
    reason: message?.data?.reason || '',
    duration: message?.data?.duration,
  };
}

class AppWebSocket {
  static async connect(token, label) {
    const url = buildWsUrl(token);
    const socket = new WebSocket(url);
    const client = new AppWebSocket(socket, label);
    await client.opened;
    return client;
  }

  constructor(socket, label) {
    this.socket = socket;
    this.label = label;
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
      if (waiter.predicate(message)) {
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

  waitFor(predicate, description, timeoutMs = 20000) {
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

async function launchAuthedCalleeChrome(callee) {
  return launchAuthedChrome(callee, 'callee');
}

async function launchAuthedChrome(session, label, initialUrl = webUrl) {
  const chromePath =
    process.env.CHROME_PATH ||
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
  const port = String(await freePort());
  const safeLabel = label.replace(/[^a-z0-9_-]/gi, '-').toLowerCase();
  const userDataDir = mkdtempSync(
    join(tmpdir(), `genericim-call-ui-smoke-${safeLabel}-chrome-`),
  );
  const origin = new URL(webUrl).origin;
  const navigateUrl = new URL(initialUrl, webUrl).toString();
  const child = spawn(
    chromePath,
    [
      '--headless=new',
      `--remote-debugging-port=${port}`,
      `--user-data-dir=${userDataDir}`,
      `--window-size=${viewport.width},${viewport.height}`,
      `--unsafely-treat-insecure-origin-as-secure=${origin}`,
      '--enable-media-stream',
      '--use-fake-device-for-media-stream',
      '--use-fake-ui-for-media-stream',
      '--autoplay-policy=no-user-gesture-required',
      ...(disableWebSecurity ? ['--disable-web-security'] : []),
      '--disable-background-timer-throttling',
      '--disable-extensions',
      '--disable-popup-blocking',
      '--no-first-run',
      '--no-default-browser-check',
      'about:blank',
    ],
    { stdio: 'ignore' },
  );

  await waitForChromeDebugPort(port);
  const version = await fetch(`http://127.0.0.1:${port}/json/version`).then(
    (response) => response.json(),
  );
  const browser = await connectCDP(version.webSocketDebuggerUrl);
  let targetId = '';
  let client;
  const logs = [];
  const networkResponses = [];
  const mediaEvents = [];
  try {
    const target = await browser.send('Target.createTarget', {
      url: 'about:blank',
    });
    targetId = target?.targetId || '';
    const page = await waitForPageTarget(port, targetId);
    client = await connectCDP(page.webSocketDebuggerUrl);
    attachPageLogCollectors(client, logs);
    attachMediaCollectors(client, mediaEvents);
    client.on('Network.responseReceived', (params) => {
      const response = params?.response || {};
      const url = String(response.url || '');
      if (!url.includes('ringtone.mp3')) return;
      networkResponses.push({
        url,
        status: Number(response.status || 0),
        mimeType: String(response.mimeType || ''),
        fromDiskCache: response.fromDiskCache === true,
        fromServiceWorker: response.fromServiceWorker === true,
      });
    });
    await client.send('Page.enable');
    await client.send('Runtime.enable');
    await client.send('DOM.enable');
    await client.send('Accessibility.enable');
    await client.send('Log.enable').catch(() => {});
    await client.send('Network.enable');
    if (forcedRequestOrigin) {
      await client.send('Network.setExtraHTTPHeaders', {
        headers: { Origin: forcedRequestOrigin },
      });
    }
    await client.send('Media.enable').catch(() => {});
    await client.send('Emulation.setDeviceMetricsOverride', {
      width: viewport.width,
      height: viewport.height,
      deviceScaleFactor: viewport.deviceScaleFactor,
      mobile: true,
    });
    await browser.send('Browser.grantPermissions', {
      origin,
      permissions: ['audioCapture', 'videoCapture'],
    });
    await client.send('Page.addScriptToEvaluateOnNewDocument', {
      source: buildAuthStorageScript(session),
    });
    await client.send('Page.navigate', {
      url: navigateUrl,
    });
  } catch (error) {
    client?.close();
    browser.close();
    child.kill('SIGTERM');
    throw error;
  }

  return {
    port,
    browser,
    client,
    logs,
    networkResponses,
    mediaEvents,
    cleanup: async () => {
      client?.close();
      if (targetId) {
        try {
          await browser.send('Target.closeTarget', { targetId });
        } catch {}
      }
      browser.close();
      child.kill('SIGTERM');
      await sleep(800);
      await removeDirectoryWithRetry(userDataDir);
    },
  };
}

function attachMediaCollectors(client, mediaEvents) {
  const collect = (type, params) => {
    mediaEvents.push({ type, ...params });
    if (mediaEvents.length > 300) {
      mediaEvents.splice(0, mediaEvents.length - 300);
    }
  };
  client.on('Media.playerCreated', (params) => collect('created', params));
  client.on('Media.playerPropertiesChanged', (params) =>
    collect('properties', params));
  client.on('Media.playerEventsAdded', (params) => collect('events', params));
}

async function waitForRingbackResource(chrome, timeoutMs = 10000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const response = chrome.networkResponses.find((item) =>
      item.url.includes('ringtone.mp3'));
    if (response) {
      if (response.status < 200 || response.status >= 300) {
        throw new Error(`Ringback resource failed: ${JSON.stringify(response)}`);
      }
      return response;
    }
    await sleep(100);
  }
  throw new Error('Timed out waiting for the outgoing ringtone.mp3 resource');
}

async function summarizeRingbackPlayback(chrome) {
  const playerIds = new Set();
  for (const item of chrome.mediaEvents) {
    if (JSON.stringify(item).includes('ringtone.mp3') && item.playerId) {
      playerIds.add(item.playerId);
    }
  }
  const events = chrome.mediaEvents.filter((item) =>
    playerIds.has(item.playerId));
  const auditResult = await chrome.client.send('Runtime.evaluate', {
    expression: 'window.__genericimMediaAudit || []',
    returnByValue: true,
  });
  const htmlMediaAudit = Array.isArray(auditResult?.result?.value)
    ? auditResult.result.value.filter((item) =>
        String(item?.src || '').includes('ringtone.mp3'))
    : [];
  return {
    playerIds: [...playerIds],
    events: events.slice(-20),
    htmlMediaAudit,
  };
}

function attachPageLogCollectors(client, logs) {
  const push = (entry) => {
    logs.push({
      at: new Date().toISOString(),
      ...entry,
    });
    if (logs.length > 200) logs.splice(0, logs.length - 200);
  };
  client.on('Runtime.consoleAPICalled', (params) => {
    push({
      source: 'console',
      type: params?.type || '',
      text: (params?.args || [])
        .map((arg) => arg?.value ?? arg?.description ?? '')
        .join(' '),
    });
  });
  client.on('Runtime.exceptionThrown', (params) => {
    push({
      source: 'exception',
      type: 'exception',
      text: params?.exceptionDetails?.text ||
        params?.exceptionDetails?.exception?.description ||
        '',
    });
  });
  client.on('Log.entryAdded', (params) => {
    push({
      source: params?.entry?.source || 'log',
      type: params?.entry?.level || '',
      text: params?.entry?.text || '',
    });
  });
}

async function prepareFlutterApp(client) {
  await waitForFlutterReady(client);
  await enableFlutterSemantics(client);
  await waitForAppSettled(client);
}

async function navigateFlutterPath(client, path) {
  const result = await client.send('Runtime.evaluate', {
    expression: `(() => {
      const path = ${JSON.stringify(path)};
      history.pushState({}, '', path);
      window.dispatchEvent(new PopStateEvent('popstate', { state: history.state }));
      return location.pathname + location.search;
    })()`,
    returnByValue: true,
  });
  await sleep(1200);
  const navigatedTo = String(result?.result?.value || '');
  const expectedPath = path.split('?')[0];
  if (!navigatedTo.startsWith(expectedPath)) {
    throw new Error(`Flutter path navigation did not apply: ${navigatedTo}`);
  }
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
    window.__genericimMediaAudit = [];
    const recordMedia = (action, media, error = '') => {
      window.__genericimMediaAudit.push({
        action,
        src: media.currentSrc || media.src || '',
        paused: media.paused,
        currentTime: media.currentTime || 0,
        error: String(error || ''),
        at: Date.now(),
      });
    };
    const originalPlay = HTMLMediaElement.prototype.play;
    HTMLMediaElement.prototype.play = function(...args) {
      recordMedia('play-called', this);
      let result;
      try {
        result = originalPlay.apply(this, args);
      } catch (error) {
        recordMedia('play-threw', this, error);
        throw error;
      }
      Promise.resolve(result).then(
        () => recordMedia('play-fulfilled', this),
        (error) => recordMedia('play-rejected', this, error),
      );
      return result;
    };
    const originalPause = HTMLMediaElement.prototype.pause;
    HTMLMediaElement.prototype.pause = function(...args) {
      recordMedia('pause-called', this);
      return originalPause.apply(this, args);
    };
    const payload = ${JSON.stringify(payload)};
    localStorage.setItem('flutter.auth_token', JSON.stringify(payload.token));
    localStorage.setItem('flutter.user_id', JSON.stringify(payload.userId));
    localStorage.setItem('flutter.auth_user_data', JSON.stringify(payload.userDataJson));
  })();`;
}

async function waitForFlutterReady(client) {
  await waitForRuntimeValue(
    client,
    `document.readyState === 'interactive' || document.readyState === 'complete'`,
    'document ready',
    15000,
  );
  await waitForRuntimeValue(
    client,
    `!!document.querySelector('flt-glass-pane, flutter-view, flt-scene-host')`,
    'Flutter root',
    20000,
  );
}

async function waitForAppSettled(client) {
  await waitForRuntimeValue(
    client,
    `location.pathname !== '/login'`,
    'authenticated route',
    20000,
  );
  await sleep(3500);
}

async function enableFlutterSemantics(client) {
  const result = await client.send('Runtime.evaluate', {
    expression: `(() => {
      const placeholder = document.querySelector('flt-semantics-placeholder');
      if (!placeholder) return { clicked: false, reason: 'missing' };
      placeholder.click();
      placeholder.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
      return { clicked: true };
    })()`,
    returnByValue: true,
  });
  const clicked = result?.result?.value?.clicked === true;
  if (!clicked) return;
  await sleep(800);
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

async function waitForAccessibilityText(client, candidates, timeoutMs = 20000) {
  const deadline = Date.now() + timeoutMs;
  let lastNames = [];
  let lastLocation = '';
  while (Date.now() < deadline) {
    lastLocation = await currentBrowserLocation(client);
    const names = await getAccessibilityNames(client);
    const matched = names.find((name) =>
      candidates.some((candidate) => name.includes(candidate)),
    );
    if (matched) return { matched, names: names.slice(0, 40) };
    lastNames = names;
    await sleep(300);
  }
  throw new Error(
    `Timed out waiting for accessibility text ${JSON.stringify(candidates)} at ${lastLocation}. Last names: ${JSON.stringify(lastNames.slice(0, 40))}`,
  );
}

async function waitForAccessibilityButton(client, candidates, timeoutMs = 20000) {
  const deadline = Date.now() + timeoutMs;
  let lastLocation = '';
  let lastMatches = [];
  while (Date.now() < deadline) {
    lastLocation = await currentBrowserLocation(client);
    const matches = await getAccessibilityMatches(client, candidates);
    const matched =
      matches.find((item) => item.role === 'button' && item.exact) ||
      matches.find((item) => item.role === 'button');
    if (matched) return { matched: matched.label, matches: matches.slice(0, 40) };
    lastMatches = matches;
    await sleep(300);
  }
  throw new Error(
    `Timed out waiting for accessibility button ${JSON.stringify(candidates)} at ${lastLocation}. Last matches: ${JSON.stringify(lastMatches.slice(0, 40))}`,
  );
}

async function currentBrowserLocation(client) {
  try {
    const result = await client.send('Runtime.evaluate', {
      expression: 'location.href',
      returnByValue: true,
    });
    return String(result?.result?.value || '');
  } catch {
    return '';
  }
}

async function getAccessibilityMatches(client, candidates) {
  const tree = await client.send('Accessibility.getFullAXTree');
  return (tree?.nodes || [])
    .filter((node) => {
      const label = String(node?.name?.value || '');
      return candidates.some((candidate) => label.includes(candidate));
    })
    .map((node) => ({
      label: String(node?.name?.value || ''),
      role: String(node?.role?.value || ''),
      exact: candidates.some((candidate) => String(node?.name?.value || '') === candidate),
      hasBackendNode: Boolean(node?.backendDOMNodeId),
    }));
}

async function getAccessibilityNames(client) {
  const tree = await client.send('Accessibility.getFullAXTree');
  const names = [];
  for (const node of tree?.nodes || []) {
    const value = node?.name?.value;
    if (typeof value === 'string' && value.trim()) {
      names.push(value.trim());
    }
  }
  return [...new Set(names)];
}

async function clickCalleeAnswer(client) {
  await clickSemanticButton(client, ['接听', 'Answer']);
}

async function clickCalleeEnd(client) {
  await clickSemanticButton(client, ['挂断', 'End', '取消', 'Cancel']);
}

async function clickSemanticButton(client, candidates) {
  const result = await client.send('Runtime.evaluate', {
    expression: `(() => {
      const candidates = ${JSON.stringify(candidates)};
      const nodes = Array.from(document.querySelectorAll('[aria-label]'));
      const isButtonMatch = (node) => {
        const label = node.getAttribute('aria-label') || '';
        const role = node.getAttribute('role') || '';
        return role === 'button' && candidates.some((candidate) => label.includes(candidate));
      };
      const isExactButtonMatch = (node) => {
        const label = node.getAttribute('aria-label') || '';
        const role = node.getAttribute('role') || '';
        return role === 'button' && candidates.some((candidate) => label === candidate);
      };
      const element = nodes.find(isExactButtonMatch) || nodes.find(isButtonMatch);
      if (!element) {
        return {
          clicked: false,
          labels: nodes.map((node) => ({
            role: node.getAttribute('role') || '',
            label: node.getAttribute('aria-label') || '',
          })).slice(0, 80),
        };
      }
      const rect = element.getBoundingClientRect();
      return {
        clicked: true,
        label: element.getAttribute('aria-label') || '',
        role: element.getAttribute('role') || '',
        rect: { left: rect.left, top: rect.top, width: rect.width, height: rect.height },
      };
    })()`,
    returnByValue: true,
  });
  const value = result?.result?.value;
  if (value?.clicked === true) {
    await clickRectCenter(client, value.rect);
    return { ...value, inputClicked: true };
  }
  const accessibilityClick = await clickAccessibilityButton(client, candidates);
  if (accessibilityClick?.clicked === true) return accessibilityClick;
  throw new Error(
    `Semantic button not found for ${JSON.stringify(candidates)}: ${JSON.stringify(value)}`,
  );
}

async function clickAccessibilityButton(client, candidates) {
  const tree = await client.send('Accessibility.getFullAXTree');
  const nodes = tree?.nodes || [];
  const matches = nodes
    .filter((node) => {
      const label = String(node?.name?.value || '');
      return candidates.some((candidate) => label.includes(candidate));
    })
    .map((node) => ({
      node,
      label: String(node?.name?.value || ''),
      role: String(node?.role?.value || ''),
      exact: candidates.some((candidate) => String(node?.name?.value || '') === candidate),
    }));
  const match =
    matches.find(
      (item) => item.role === 'button' && item.exact && item.node.backendDOMNodeId,
    ) ||
    matches.find((item) => item.role === 'button' && item.node.backendDOMNodeId);
  if (!match) return { clicked: false, axMatches: matches.slice(0, 20) };

  const resolved = await client.send('DOM.resolveNode', {
    backendNodeId: match.node.backendDOMNodeId,
  });
  const objectId = resolved?.object?.objectId;
  if (!objectId) {
    return {
      clicked: false,
      reason: 'resolve_failed',
      label: match.label,
      role: match.role,
    };
  }

  const result = await client.send('Runtime.callFunctionOn', {
    objectId,
    functionDeclaration: `function() {
      const element = this;
      const rect = element.getBoundingClientRect();
      return {
        clicked: true,
        ariaLabel: element.getAttribute('aria-label') || '',
        role: element.getAttribute('role') || '',
        rect: { left: rect.left, top: rect.top, width: rect.width, height: rect.height },
      };
    }`,
    returnByValue: true,
    userGesture: true,
  });
  const value = {
    ...(result?.result?.value || {}),
    label: match.label,
    axRole: match.role,
  };
  if (value.clicked === true) {
    await clickRectCenter(client, value.rect);
    return { ...value, inputClicked: true };
  }
  return value;
}

async function clickRectCenter(client, rect) {
  const left = Number(rect?.left);
  const top = Number(rect?.top);
  const width = Number(rect?.width);
  const height = Number(rect?.height);
  if (![left, top, width, height].every(Number.isFinite) || width <= 0 || height <= 0) {
    return;
  }
  await clickAt(client, left + width / 2, top + height / 2);
}

async function clickAt(client, x, y) {
  await client.send('Input.dispatchMouseEvent', {
    type: 'mouseMoved',
    x,
    y,
  });
  await client.send('Input.dispatchMouseEvent', {
    type: 'mousePressed',
    x,
    y,
    button: 'left',
    clickCount: 1,
  });
  await sleep(80);
  await client.send('Input.dispatchMouseEvent', {
    type: 'mouseReleased',
    x,
    y,
    button: 'left',
    clickCount: 1,
  });
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
