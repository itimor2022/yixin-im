#!/usr/bin/env node

import { execFileSync, spawn } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createServer } from 'node:net';

const apiBase = trimTrailingSlash(
  process.env.GENERIC_IM_SERVER_URL || 'http://localhost:8080',
);
const webUrl = process.env.GENERIC_IM_WEB_URL || 'http://localhost:5175/';
const username = process.env.GENERIC_IM_SMOKE_USERNAME || 'h5test';
const password = process.env.GENERIC_IM_SMOKE_PASSWORD || '123456';
const chatIdFromEnv = process.env.GENERIC_IM_SMOKE_CHAT_ID || '';
const durationMs = Number(process.env.GENERIC_IM_SMOKE_VOICE_DURATION_MS || 1800);

async function main() {
  const login = await postJson('/api/v1/auth/login', {
    username,
    password,
    device_id: `web-voice-smoke-${Date.now()}`,
    device_type: 'web',
    device_name: 'Flutter Web Voice Smoke',
  });
  const token = login?.data?.token;
  if (!token) {
    throw new Error('Login failed: missing token');
  }

  const chatId = chatIdFromEnv || (await firstChatId(token));
  if (!chatId) {
    throw new Error('No chat found. Set GENERIC_IM_SMOKE_CHAT_ID.');
  }

  const recording = await recordInChrome(durationMs);
  const upload = await uploadVoice(token, recording);
  const sent = await sendVoiceMessage(token, chatId, upload, recording);
  const headers = await checkVoiceHeaders(upload.url);
  const playback = await checkChromeAudioPlayback(upload.url);

  console.log(
    JSON.stringify(
      {
        ok: true,
        apiBase,
        webUrl,
        chatId,
        recording: {
          mimeType: recording.mimeType,
          size: recording.bytes.length,
          durationMs: recording.durationMs,
          events: recording.events,
        },
        upload,
        sent,
        headers,
        playback,
      },
      null,
      2,
    ),
  );
}

function trimTrailingSlash(value) {
  return value.replace(/\/+$/, '');
}

async function postJson(path, data, token = '') {
  const response = await fetch(`${apiBase}${path}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify(data),
  });
  return response.json();
}

async function getJson(path, token) {
  const response = await fetch(`${apiBase}${path}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  return response.json();
}

async function firstChatId(token) {
  const json = await getJson('/api/v1/chat/list', token);
  const list = Array.isArray(json?.data?.list) ? json.data.list : [];
  return list[0]?.chat_id || '';
}

async function uploadVoice(token, recording) {
  const ext = recording.mimeType.includes('ogg') ? 'ogg' : 'webm';
  const fileName = `voice_smoke_${Date.now()}.${ext}`;
  const form = new FormData();
  form.append('duration', String(recording.durationMs));
  form.append(
    'file',
    new Blob([recording.bytes], { type: recording.mimeType }),
    fileName,
  );

  const response = await fetch(`${apiBase}/api/v1/upload/voice`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}` },
    body: form,
  });
  const json = await response.json();
  if (!response.ok || json?.code !== 0 || !json?.data?.url) {
    throw new Error(`Voice upload failed: ${JSON.stringify(json)}`);
  }
  return {
    url: json.data.url,
    filename: json.data.filename,
    size: json.data.size,
    type: json.data.type,
    duration: json.data.duration,
  };
}

async function sendVoiceMessage(token, chatId, upload, recording) {
  const msgId = `web-voice-smoke-${Date.now()}`;
  const json = await postJson(
    '/api/v1/message/send',
    {
      chat_id: chatId,
      type: 4,
      msg_id: msgId,
      content: {
        voice: {
          url: upload.url,
          duration: recording.durationMs,
          size: upload.size || recording.bytes.length,
          mime_type: recording.mimeType,
        },
      },
    },
    token,
  );
  if (json?.code !== 0) {
    throw new Error(`Voice message send failed: ${JSON.stringify(json)}`);
  }
  return {
    msgId: json.data?.msg_id || msgId,
    type: json.data?.type,
    seq: json.data?.seq,
  };
}

async function checkVoiceHeaders(voiceUrl) {
  const origin = new URL(webUrl).origin;
  const response = await fetch(voiceUrl, {
    method: 'HEAD',
    headers: { Origin: origin },
  });
  const contentType = response.headers.get('content-type') || '';
  const allowOrigin = response.headers.get('access-control-allow-origin') || '';
  const acceptRanges = response.headers.get('accept-ranges') || '';

  if (!response.ok) {
    throw new Error(`Voice HEAD failed with ${response.status}`);
  }
  if (!contentType.startsWith('audio/')) {
    throw new Error(`Unexpected voice Content-Type: ${contentType}`);
  }
  if (!allowOrigin) {
    throw new Error('Missing voice Access-Control-Allow-Origin');
  }

  return {
    headStatus: response.status,
    contentType,
    allowOrigin,
    acceptRanges,
  };
}

async function recordInChrome(recordMs) {
  const chrome = await ensureChromeForVoiceSmoke();

  try {
    const version = await fetch(
      `http://127.0.0.1:${chrome.port}/json/version`,
    ).then((r) => r.json());
    const browser = await connectCDP(version.webSocketDebuggerUrl);
    let targetId = '';
    let client;
    try {
      const target = await browser.send('Target.createTarget', { url: webUrl });
      targetId = target?.targetId || '';
      const page = await waitForPageTarget(chrome.port, targetId);
      client = await connectCDP(page.webSocketDebuggerUrl);
      await client.send('Page.enable');
      await client.send('Runtime.enable');
      const targetOrigin = new URL(webUrl).origin;
      await client.send('Page.navigate', { url: webUrl });
      await waitForPageReady(client, targetOrigin);
      try {
        await browser.send('Browser.grantPermissions', {
          origin: targetOrigin,
          permissions: ['audioCapture'],
        });
      } catch (error) {
        if (!chrome.fakeMedia) throw error;
      }
      const result = await client.send('Runtime.evaluate', {
        expression: buildRecordExpression(recordMs),
        awaitPromise: true,
        returnByValue: true,
        timeout: recordMs + 15000,
      });
      const value = result?.result?.value;
      if (!value || value.status !== 'ok') {
        throw new Error(
          `Chrome voice recording failed: ${JSON.stringify(value)}`,
        );
      }
      const bytes = Buffer.from(value.base64, 'base64');
      if (bytes.length <= 0) {
        throw new Error('Chrome voice recording returned empty bytes');
      }
      return {
        pageUrl: value.diagnostics?.href || webUrl,
        mimeType: value.mimeType || 'audio/webm',
        durationMs: value.durationMs || recordMs,
        events: value.events || [],
        bytes,
      };
    } finally {
      client?.close();
      if (targetId) {
        try {
          await browser.send('Target.closeTarget', { targetId });
        } catch {}
      }
      browser.close();
    }
  } finally {
    await chrome.cleanup();
  }
}

async function checkChromeAudioPlayback(audioUrl) {
  const chrome = await ensureChromeForVoiceSmoke();

  try {
    const version = await fetch(
      `http://127.0.0.1:${chrome.port}/json/version`,
    ).then((r) => r.json());
    const browser = await connectCDP(version.webSocketDebuggerUrl);
    let targetId = '';
    let client;
    try {
      const target = await browser.send('Target.createTarget', { url: webUrl });
      targetId = target?.targetId || '';
      const page = await waitForPageTarget(chrome.port, targetId);
      client = await connectCDP(page.webSocketDebuggerUrl);
      await client.send('Page.enable');
      await client.send('Runtime.enable');
      await client.send('Page.navigate', { url: webUrl });
      await waitForPageReady(client, new URL(webUrl).origin);
      const result = await client.send('Runtime.evaluate', {
        expression: buildAudioPlaybackExpression(audioUrl),
        awaitPromise: true,
        returnByValue: true,
        timeout: 15000,
      });
      const value = result?.result?.value;
      if (!value || value.status !== 'ok') {
        throw new Error(`Chrome audio playback failed: ${JSON.stringify(value)}`);
      }
      return {
        pageUrl: value.pageUrl || webUrl,
        status: value.status,
        duration: value.duration,
        currentTime: value.currentTime,
        events: value.events || [],
      };
    } finally {
      client?.close();
      if (targetId) {
        try {
          await browser.send('Target.closeTarget', { targetId });
        } catch {}
      }
      browser.close();
    }
  } finally {
    await chrome.cleanup();
  }
}

async function ensureChromeForVoiceSmoke() {
  const explicitPort = process.env.GENERIC_IM_CHROME_DEBUG_PORT;
  if (explicitPort) {
    return { port: explicitPort, fakeMedia: false, cleanup: async () => {} };
  }

  const useFakeMedia = process.env.GENERIC_IM_SMOKE_FAKE_MEDIA !== '0';
  if (!useFakeMedia) {
    const port = discoverChromeDebugPort();
    if (!port) {
      throw new Error(
        'Chrome remote debugging port not found. Start Flutter Web with flutter run -d chrome first, or set GENERIC_IM_CHROME_DEBUG_PORT.',
      );
    }
    return { port, fakeMedia: false, cleanup: async () => {} };
  }

  const chromePath =
    process.env.CHROME_PATH ||
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
  const port = String(await freePort());
  const userDataDir = mkdtempSync(join(tmpdir(), 'genericim-voice-smoke-chrome-'));
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
    fakeMedia: true,
    cleanup: async () => {
      child.kill('SIGTERM');
      await new Promise((resolve) => setTimeout(resolve, 800));
      await removeDirectoryWithRetry(userDataDir);
    },
  };
}

async function removeDirectoryWithRetry(path) {
  let lastError;
  for (let attempt = 0; attempt < 5; attempt += 1) {
    try {
      rmSync(path, { recursive: true, force: true });
      return;
    } catch (error) {
      lastError = error;
      await new Promise((resolve) => setTimeout(resolve, 250));
    }
  }
  throw lastError;
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
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error(`Chrome debug port ${port} was not ready: ${lastError}`);
}

async function waitForPageTarget(port, targetId) {
  const deadline = Date.now() + 12000;
  while (Date.now() < deadline) {
    const pages = await fetch(`http://127.0.0.1:${port}/json/list`).then((r) =>
      r.json(),
    );
    const page = pages.find((item) => item.id === targetId);
    if (page?.webSocketDebuggerUrl) return page;
    await new Promise((resolve) => setTimeout(resolve, 250));
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
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
}

function discoverChromeDebugPort() {
  let output = '';
  try {
    output = execFileSync('ps', ['aux'], { encoding: 'utf8' });
  } catch {
    return '';
  }
  const expectedPort = new URL(webUrl).port || '80';
  const lines = output.split('\n');
  const preferred = lines.find(
    (line) =>
      line.includes('--remote-debugging-port=') &&
      line.includes(`:${expectedPort}`),
  );
  const fallback = lines.find((line) => line.includes('--remote-debugging-port='));
  const match = (preferred || fallback || '').match(/--remote-debugging-port=(\d+)/);
  return match?.[1] || '';
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

function buildRecordExpression(recordMs) {
  return `(() => new Promise(async (resolve) => {
    let settled = false;
    const events = [];
    const preferred = [
      'audio/webm;codecs=opus',
      'audio/webm',
      'audio/ogg;codecs=opus',
      'audio/ogg'
    ];
    const diagnostics = () => ({
      href: location.href,
      origin: location.origin,
      protocol: location.protocol,
      isSecureContext,
      hasNavigator: typeof navigator !== 'undefined',
      hasMediaDevices: !!navigator.mediaDevices,
      hasGetUserMedia: !!navigator.mediaDevices?.getUserMedia,
      hasLegacyGetUserMedia: !!(
        navigator.getUserMedia ||
        navigator.webkitGetUserMedia ||
        navigator.mozGetUserMedia
      ),
      hasMediaRecorder: !!window.MediaRecorder,
      supportedTypes: window.MediaRecorder
        ? preferred.filter((type) => MediaRecorder.isTypeSupported(type))
        : [],
      userAgent: navigator.userAgent,
    });
    const finish = (status, extra = {}) => {
      if (settled) return;
      settled = true;
      clearTimeout(hardTimer);
      resolve({ status, events, diagnostics: diagnostics(), ...extra });
    };
    const hardTimer = setTimeout(() => {
      finish('timeout', { error: 'Timed out while recording audio' });
    }, ${Math.max(9000, recordMs + 7000)});
    try {
      if (!navigator.mediaDevices?.getUserMedia) {
        finish('unsupported', { error: 'mediaDevices.getUserMedia unavailable' });
        return;
      }
      if (!window.MediaRecorder) {
        finish('unsupported', { error: 'MediaRecorder unavailable' });
        return;
      }
      const mimeType = preferred.find((type) => MediaRecorder.isTypeSupported(type)) || '';
      const stream = await Promise.race([
        navigator.mediaDevices.getUserMedia({ audio: true }),
        new Promise((_, reject) => setTimeout(() => reject(new Error('getUserMedia timeout')), 5000)),
      ]);
      const chunks = [];
      const startedAt = Date.now();
      const recorder = new MediaRecorder(stream, mimeType ? { mimeType } : undefined);
      ['start', 'dataavailable', 'stop', 'error', 'pause', 'resume'].forEach((name) => {
        recorder.addEventListener(name, () => events.push(name));
      });
      recorder.addEventListener('dataavailable', (event) => {
        if (event.data && event.data.size > 0) chunks.push(event.data);
      });
      await new Promise((resolveRecord, rejectRecord) => {
        recorder.addEventListener('stop', resolveRecord, { once: true });
        recorder.addEventListener('error', () => rejectRecord(recorder.error), { once: true });
        recorder.start(200);
        setTimeout(() => {
          if (recorder.state !== 'inactive') recorder.stop();
        }, ${Math.max(1000, recordMs)});
      });
      stream.getTracks().forEach((track) => track.stop());
      const blob = new Blob(chunks, { type: recorder.mimeType || mimeType || 'audio/webm' });
      const buffer = await blob.arrayBuffer();
      const bytes = new Uint8Array(buffer);
      let binary = '';
      const chunkSize = 0x8000;
      for (let i = 0; i < bytes.length; i += chunkSize) {
        binary += String.fromCharCode(...bytes.subarray(i, i + chunkSize));
      }
      finish('ok', {
        mimeType: blob.type || recorder.mimeType || mimeType || 'audio/webm',
        size: blob.size,
        durationMs: Date.now() - startedAt,
        base64: btoa(binary),
      });
    } catch (error) {
      finish('error', { error: String(error?.message || error) });
    }
  }))()`;
}

function buildAudioPlaybackExpression(audioUrl) {
  return `(() => new Promise((resolve) => {
    const existing = document.getElementById('codex-audio-smoke');
    if (existing) existing.remove();
    const audio = document.createElement('audio');
    audio.id = 'codex-audio-smoke';
    audio.muted = true;
    audio.crossOrigin = 'anonymous';
    audio.preload = 'auto';
    audio.style.cssText = 'position:fixed;left:-9999px;top:0;width:1px;height:1px;';
    document.body.appendChild(audio);
    const events = [];
    const finish = (status, extra = {}) => {
      clearTimeout(timer);
      const error = audio.error ? { code: audio.error.code, message: audio.error.message } : null;
      const result = {
        status,
        pageUrl: location.href,
        events,
        readyState: audio.readyState,
        networkState: audio.networkState,
        currentTime: audio.currentTime,
        duration: Number.isFinite(audio.duration) ? audio.duration : null,
        error,
        ...extra,
      };
      audio.pause();
      audio.remove();
      resolve(result);
    };
    const timer = setTimeout(() => finish('timeout'), 12000);
    ['loadstart','durationchange','loadedmetadata','loadeddata','canplay','playing','timeupdate','error','stalled','suspend'].forEach((name) => {
      audio.addEventListener(name, () => events.push(name));
    });
    audio.addEventListener('error', () => finish('error'), { once: true });
    audio.addEventListener('loadedmetadata', async () => {
      try {
        await audio.play();
        setTimeout(() => finish('ok'), 900);
      } catch (e) {
        finish('play_failed', { exception: String(e) });
      }
    }, { once: true });
    audio.src = ${JSON.stringify(audioUrl)};
    audio.load();
  }))()`;
}

main().catch((error) => {
  console.error(error?.stack || error?.message || String(error));
  process.exit(1);
});
