#!/usr/bin/env node

import { execFileSync } from 'node:child_process';

const apiBase = trimTrailingSlash(
  process.env.GENERIC_IM_SERVER_URL || 'http://localhost:8080',
);
const webUrl = process.env.GENERIC_IM_WEB_URL || 'http://localhost:5175/';
const username = process.env.GENERIC_IM_SMOKE_USERNAME || 'h5test';
const password = process.env.GENERIC_IM_SMOKE_PASSWORD || '123456';
const chatIdFromEnv = process.env.GENERIC_IM_SMOKE_CHAT_ID || '';
const latitude = Number(process.env.GENERIC_IM_SMOKE_LATITUDE || 31.230416);
const longitude = Number(process.env.GENERIC_IM_SMOKE_LONGITUDE || 121.473701);
const accuracy = Number(process.env.GENERIC_IM_SMOKE_LOCATION_ACCURACY || 18);

async function main() {
  const login = await postJson('/api/v1/auth/login', {
    username,
    password,
    device_id: `web-location-smoke-${Date.now()}`,
    device_type: 'web',
    device_name: 'Flutter Web Location Smoke',
  });
  const token = login?.data?.token;
  if (!token) {
    throw new Error('Login failed: missing token');
  }

  const chatId = chatIdFromEnv || (await firstChatId(token));
  if (!chatId) {
    throw new Error('No chat found. Set GENERIC_IM_SMOKE_CHAT_ID.');
  }

  const browser = await checkBrowserGeolocation({ latitude, longitude, accuracy });
  const sent = await sendLocationMessage(token, chatId, browser);
  const listed = await findSentLocation(token, chatId, sent.msgId);

  console.log(
    JSON.stringify(
      {
        ok: true,
        apiBase,
        webUrl,
        chatId,
        browser,
        sent,
        listed,
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

async function checkBrowserGeolocation(location) {
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
    const origin = new URL(webUrl).origin;
    await client.send('Page.enable');
    await client.send('Runtime.enable');
    await client.send('Browser.grantPermissions', {
      origin,
      permissions: ['geolocation'],
    });
    await client.send('Emulation.setGeolocationOverride', {
      latitude: location.latitude,
      longitude: location.longitude,
      accuracy: location.accuracy,
    });
    await client.send('Page.navigate', { url: webUrl });
    await waitForPageReady(client, origin);
    const result = await client.send('Runtime.evaluate', {
      expression: buildGeolocationExpression(),
      awaitPromise: true,
      returnByValue: true,
      timeout: 12000,
    });
    const value = result?.result?.value;
    if (!value || value.status !== 'ok') {
      throw new Error(`Browser geolocation failed: ${JSON.stringify(value)}`);
    }
    return {
      pageUrl: value.pageUrl || webUrl,
      latitude: value.latitude,
      longitude: value.longitude,
      accuracy: value.accuracy,
      isSecureContext: value.isSecureContext,
      hasGeolocation: value.hasGeolocation,
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

async function sendLocationMessage(token, chatId, location) {
  const msgId = `web-location-smoke-${Date.now()}`;
  const title = 'Web location smoke';
  const address =
    `${Number(location.latitude).toFixed(6)}, ${Number(location.longitude).toFixed(6)}`;
  const json = await postJson(
    '/api/v1/message/send',
    {
      chat_id: chatId,
      type: 6,
      msg_id: msgId,
      content: {
        location: {
          latitude: location.latitude,
          longitude: location.longitude,
          title,
          address,
        },
      },
    },
    token,
  );
  if (json?.code !== 0) {
    throw new Error(`Location message send failed: ${JSON.stringify(json)}`);
  }
  return {
    msgId: json.data?.msg_id || msgId,
    type: json.data?.type,
    seq: json.data?.seq,
    title,
    address,
  };
}

async function findSentLocation(token, chatId, msgId) {
  const json = await getJson(
    `/api/v1/message/list?chat_id=${encodeURIComponent(chatId)}&page=1&page_size=20`,
    token,
  );
  const list = Array.isArray(json?.data) ? json.data : json?.data?.list || [];
  const item = list.find((message) => message?.msg_id === msgId);
  if (!item) {
    throw new Error(`Location message ${msgId} was not found in message list`);
  }
  const location = item?.content?.location;
  if (!location) {
    throw new Error(`Location message has no location content: ${JSON.stringify(item)}`);
  }
  return {
    msgId: item.msg_id,
    type: item.type,
    latitude: location.latitude,
    longitude: location.longitude,
    title: location.title,
    address: location.address,
  };
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

function buildGeolocationExpression() {
  return `(() => new Promise((resolve) => {
    const finish = (status, extra = {}) => resolve({
      status,
      pageUrl: location.href,
      isSecureContext,
      hasGeolocation: !!navigator.geolocation,
      ...extra,
    });
    if (!navigator.geolocation) {
      finish('unsupported', { error: 'navigator.geolocation unavailable' });
      return;
    }
    const timer = setTimeout(() => {
      finish('timeout', { error: 'Timed out while reading geolocation' });
    }, 8000);
    navigator.geolocation.getCurrentPosition(
      (position) => {
        clearTimeout(timer);
        finish('ok', {
          latitude: position.coords.latitude,
          longitude: position.coords.longitude,
          accuracy: position.coords.accuracy,
        });
      },
      (error) => {
        clearTimeout(timer);
        finish('error', {
          code: error.code,
          error: error.message,
        });
      },
      { enableHighAccuracy: true, timeout: 7000, maximumAge: 0 },
    );
  }))()`;
}

main().catch((error) => {
  console.error(error?.stack || error?.message || String(error));
  process.exit(1);
});
