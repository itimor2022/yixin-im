#!/usr/bin/env node

import { execFileSync } from 'node:child_process';

const apiBase = trimTrailingSlash(
  process.env.GENERIC_IM_SERVER_URL || 'http://localhost:8080',
);
const webUrl = process.env.GENERIC_IM_WEB_URL || 'http://localhost:5175/';
const username = process.env.GENERIC_IM_SMOKE_USERNAME || 'h5test';
const password = process.env.GENERIC_IM_SMOKE_PASSWORD || '123456';
const chatIdFromEnv = process.env.GENERIC_IM_SMOKE_CHAT_ID || '';
const videoUrlFromEnv = process.env.GENERIC_IM_SMOKE_VIDEO_URL || '';
const forceVideoUpload = process.env.GENERIC_IM_SMOKE_FORCE_VIDEO_UPLOAD === '1';

async function main() {
  const login = await postJson('/api/v1/auth/login', {
    username,
    password,
    device_id: `web-video-smoke-${Date.now()}`,
    device_type: 'web',
    device_name: 'Flutter Web Video Smoke',
  });
  const token = login?.data?.token;
  if (!token) {
    throw new Error('Login failed: missing token');
  }

  const chatId = chatIdFromEnv || (await firstChatId(token));
  if (!chatId) {
    throw new Error('No chat found. Set GENERIC_IM_SMOKE_CHAT_ID.');
  }

  let seededVideo = null;
  let videoUrl =
    videoUrlFromEnv ||
    (forceVideoUpload ? '' : await latestVideoUrl(token, chatId));
  if (!videoUrl && !videoUrlFromEnv) {
    seededVideo = await createAndSendVideoSample(token, chatId);
    videoUrl = seededVideo.upload.url;
  }
  if (!videoUrl) {
    throw new Error('No video message found. Send one or set GENERIC_IM_SMOKE_VIDEO_URL.');
  }

  const headers = await checkMediaHeaders(videoUrl);
  const chrome = await checkChromePlayback(videoUrl);

  console.log(
    JSON.stringify(
      {
        ok: true,
        apiBase,
        webUrl,
        chatId,
        videoUrl,
        seededVideo,
        headers,
        chrome,
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

async function latestVideoUrl(token, chatId) {
  for (let page = 1; page <= 5; page += 1) {
    const json = await getJson(
      `/api/v1/message/list?chat_id=${encodeURIComponent(chatId)}&page=${page}&page_size=50`,
      token,
    );
    const list = Array.isArray(json?.data) ? json.data : json?.data?.list || [];
    const video = list.find((item) => item?.type === 3 && item?.content?.media?.url);
    if (video?.content?.media?.url) return video.content.media.url;
    if (list.length < 50) break;
  }
  return '';
}

async function createAndSendVideoSample(token, chatId) {
  const sample = await recordVideoSampleInChrome();
  const upload = await uploadVideo(token, sample);
  const sent = await sendVideoMessage(token, chatId, upload, sample);
  return {
    generated: {
      mimeType: sample.mimeType,
      size: sample.bytes.length,
      durationMs: sample.durationMs,
      width: sample.width,
      height: sample.height,
      events: sample.events,
    },
    upload,
    sent,
  };
}

async function uploadVideo(token, sample) {
  const ext = sample.mimeType.includes('webm') ? 'webm' : 'mp4';
  const fileName = `video_smoke_${Date.now()}.${ext}`;
  const form = new FormData();
  form.append(
    'file',
    new Blob([sample.bytes], { type: sample.mimeType }),
    fileName,
  );

  const response = await fetch(`${apiBase}/api/v1/upload/video`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}` },
    body: form,
  });
  const json = await response.json();
  if (!response.ok || json?.code !== 0 || !json?.data?.url) {
    throw new Error(`Video upload failed: ${JSON.stringify(json)}`);
  }
  return {
    url: json.data.url,
    filename: json.data.filename,
    size: json.data.size,
    type: json.data.type,
    mimeType: sample.mimeType,
  };
}

async function sendVideoMessage(token, chatId, upload, sample) {
  const msgId = `web-video-smoke-${Date.now()}`;
  const json = await postJson(
    '/api/v1/message/send',
    {
      chat_id: chatId,
      type: 3,
      msg_id: msgId,
      content: {
        media: {
          url: upload.url,
          duration: sample.durationMs,
          size: upload.size || sample.bytes.length,
          mime_type: sample.mimeType,
          width: sample.width,
          height: sample.height,
        },
      },
    },
    token,
  );
  if (json?.code !== 0) {
    throw new Error(`Video message send failed: ${JSON.stringify(json)}`);
  }
  return {
    msgId: json.data?.msg_id || msgId,
    type: json.data?.type,
    seq: json.data?.seq,
  };
}

async function recordVideoSampleInChrome() {
  const port = process.env.GENERIC_IM_CHROME_DEBUG_PORT || discoverChromeDebugPort();
  if (!port) {
    throw new Error(
      'Chrome remote debugging port not found. Start Flutter Web with flutter run -d chrome first, or set GENERIC_IM_CHROME_DEBUG_PORT.',
    );
  }

  const version = await fetch(`http://127.0.0.1:${port}/json/version`).then(
    (r) => r.json(),
  );
  const browser = await connectCDP(version.webSocketDebuggerUrl);
  let targetId = '';
  let client;
  try {
    const target = await browser.send('Target.createTarget', { url: webUrl });
    targetId = target?.targetId || '';
    const page = await waitForPageTarget(port, targetId);
    client = await connectCDP(page.webSocketDebuggerUrl);
    await client.send('Page.enable');
    await client.send('Runtime.enable');
    await client.send('Page.navigate', { url: webUrl });
    await waitForPageReady(client, new URL(webUrl).origin);
    const result = await client.send('Runtime.evaluate', {
      expression: buildVideoSampleExpression(),
      awaitPromise: true,
      returnByValue: true,
      timeout: 20000,
    });
    const value = result?.result?.value;
    if (!value || value.status !== 'ok') {
      throw new Error(`Chrome video sample recording failed: ${JSON.stringify(value)}`);
    }
    const bytes = Buffer.from(value.base64, 'base64');
    if (bytes.length <= 0) {
      throw new Error('Chrome video sample recording returned empty bytes');
    }
    return {
      mimeType: value.mimeType || 'video/webm',
      durationMs: value.durationMs || 1200,
      width: value.width || 160,
      height: value.height || 90,
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
}

async function checkMediaHeaders(videoUrl) {
  const origin = new URL(webUrl).origin;
  const head = await fetch(videoUrl, {
    method: 'HEAD',
    headers: { Origin: origin },
  });
  const range = await fetch(videoUrl, {
    headers: {
      Origin: origin,
      Range: 'bytes=0-1023',
    },
  });

  const contentType = head.headers.get('content-type') || '';
  const allowOrigin =
    head.headers.get('access-control-allow-origin') ||
    range.headers.get('access-control-allow-origin') ||
    '';
  const acceptRanges =
    head.headers.get('accept-ranges') || range.headers.get('accept-ranges') || '';
  const contentRange = range.headers.get('content-range') || '';

  if (!head.ok) {
    throw new Error(`HEAD failed with ${head.status}`);
  }
  if (!contentType.startsWith('video/')) {
    throw new Error(`Unexpected Content-Type: ${contentType}`);
  }
  if (range.status !== 206) {
    throw new Error(`Range request expected 206, got ${range.status}`);
  }
  if (!allowOrigin) {
    throw new Error('Missing Access-Control-Allow-Origin');
  }
  if (!/bytes/i.test(acceptRanges) || !contentRange) {
    throw new Error('Missing byte range headers');
  }

  return {
    headStatus: head.status,
    rangeStatus: range.status,
    contentType,
    allowOrigin,
    acceptRanges,
    contentRange,
  };
}

async function checkChromePlayback(videoUrl) {
  const port = process.env.GENERIC_IM_CHROME_DEBUG_PORT || discoverChromeDebugPort();
  if (!port) {
    throw new Error(
      'Chrome remote debugging port not found. Start Flutter Web with flutter run -d chrome first, or set GENERIC_IM_CHROME_DEBUG_PORT.',
    );
  }

  const version = await fetch(`http://127.0.0.1:${port}/json/version`).then(
    (r) => r.json(),
  );
  const browser = await connectCDP(version.webSocketDebuggerUrl);
  let targetId = '';
  let client;
  try {
    const target = await browser.send('Target.createTarget', { url: webUrl });
    targetId = target?.targetId || '';
    const page = await waitForPageTarget(port, targetId);
    client = await connectCDP(page.webSocketDebuggerUrl);
    await client.send('Page.enable');
    await client.send('Runtime.enable');
    await client.send('Page.navigate', { url: webUrl });
    await waitForPageReady(client, new URL(webUrl).origin);
    const expression = buildVideoPlaybackExpression(videoUrl);
    const result = await client.send('Runtime.evaluate', {
      expression,
      awaitPromise: true,
      returnByValue: true,
      timeout: 15000,
    });
    const value = result?.result?.value;
    if (!value || value.status !== 'ok') {
      throw new Error(`Chrome video playback failed: ${JSON.stringify(value)}`);
    }
    return {
      pageUrl: value.pageUrl || webUrl,
      status: value.status,
      duration: value.duration,
      currentTime: value.currentTime,
      videoWidth: value.videoWidth,
      videoHeight: value.videoHeight,
      events: value.events,
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

function buildVideoPlaybackExpression(videoUrl) {
  return `(() => new Promise((resolve) => {
    const existing = document.getElementById('codex-video-smoke');
    if (existing) existing.remove();
    const video = document.createElement('video');
    video.id = 'codex-video-smoke';
    video.muted = true;
    video.playsInline = true;
    video.crossOrigin = 'anonymous';
    video.preload = 'auto';
    video.style.cssText = 'position:fixed;left:-9999px;top:0;width:160px;height:90px;z-index:-1;';
    document.body.appendChild(video);
    const events = [];
    const finish = (status, extra = {}) => {
      clearTimeout(timer);
      const error = video.error ? { code: video.error.code, message: video.error.message } : null;
      const result = {
        status,
        events,
        readyState: video.readyState,
        networkState: video.networkState,
        currentTime: video.currentTime,
        duration: Number.isFinite(video.duration) ? video.duration : null,
        videoWidth: video.videoWidth,
        videoHeight: video.videoHeight,
        error,
        ...extra,
      };
      video.pause();
      video.remove();
      resolve(result);
    };
    const timer = setTimeout(() => finish('timeout'), 12000);
    ['loadstart','durationchange','loadedmetadata','loadeddata','canplay','playing','timeupdate','error','stalled','suspend'].forEach((name) => {
      video.addEventListener(name, () => events.push(name));
    });
    video.addEventListener('error', () => finish('error'), { once: true });
    video.addEventListener('loadedmetadata', async () => {
      try {
        await video.play();
        setTimeout(() => finish('ok'), 1200);
      } catch (e) {
        finish('play_failed', { exception: String(e) });
      }
    }, { once: true });
    video.src = ${JSON.stringify(videoUrl)};
    video.load();
  }))()`;
}

function buildVideoSampleExpression() {
  return `(() => new Promise((resolve) => {
    const mimeTypes = ['video/webm;codecs=vp8', 'video/webm'];
    const mimeType = mimeTypes.find((item) => MediaRecorder.isTypeSupported(item));
    if (!mimeType) {
      resolve({ status: 'unsupported', reason: 'MediaRecorder video/webm is not supported' });
      return;
    }
    const canvas = document.createElement('canvas');
    canvas.width = 160;
    canvas.height = 90;
    const ctx = canvas.getContext('2d');
    if (!ctx || !canvas.captureStream) {
      resolve({ status: 'unsupported', reason: 'canvas captureStream is not supported' });
      return;
    }
    const stream = canvas.captureStream(12);
    const recorder = new MediaRecorder(stream, { mimeType });
    const chunks = [];
    const events = [];
    const startedAt = performance.now();
    let frame = 0;
    let interval = 0;

    const draw = () => {
      const hue = (frame * 19) % 360;
      ctx.fillStyle = 'hsl(' + hue + ' 75% 48%)';
      ctx.fillRect(0, 0, canvas.width, canvas.height);
      ctx.fillStyle = '#ffffff';
      ctx.font = 'bold 18px sans-serif';
      ctx.fillText('GENERIC_IM H5', 28, 42);
      ctx.font = '12px sans-serif';
      ctx.fillText('video smoke ' + frame, 34, 62);
      frame += 1;
    };

    recorder.addEventListener('dataavailable', (event) => {
      events.push('dataavailable');
      if (event.data && event.data.size > 0) chunks.push(event.data);
    });
    recorder.addEventListener('start', () => events.push('start'));
    recorder.addEventListener('stop', async () => {
      events.push('stop');
      clearInterval(interval);
      stream.getTracks().forEach((track) => track.stop());
      const blob = new Blob(chunks, { type: recorder.mimeType || mimeType });
      const reader = new FileReader();
      reader.onloadend = () => {
        const dataUrl = String(reader.result || '');
        resolve({
          status: blob.size > 0 ? 'ok' : 'empty',
          mimeType: blob.type || mimeType,
          size: blob.size,
          durationMs: Math.round(performance.now() - startedAt),
          width: canvas.width,
          height: canvas.height,
          events,
          base64: dataUrl.includes(',') ? dataUrl.split(',').pop() : '',
        });
      };
      reader.onerror = () => resolve({ status: 'read_failed', events });
      reader.readAsDataURL(blob);
    });
    draw();
    interval = setInterval(draw, 83);
    recorder.start(100);
    setTimeout(() => recorder.stop(), 1200);
  }))()`;
}

main().catch((error) => {
  console.error(error?.stack || error?.message || String(error));
  process.exit(1);
});
