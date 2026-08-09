#!/usr/bin/env node

import { spawn } from 'node:child_process';
import {
  createReadStream,
  existsSync,
  mkdirSync,
  mkdtempSync,
  rmSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import { createServer } from 'node:http';
import { createServer as createNetServer } from 'node:net';
import { tmpdir } from 'node:os';
import { extname, join, normalize, resolve } from 'node:path';

const apiBase = trim(process.env.GENERIC_IM_SERVER_URL || 'https://api.example.com');
const username = process.env.GENERIC_IM_SMOKE_USERNAME || 'h5test';
const password = process.env.GENERIC_IM_SMOKE_PASSWORD || '123456';
const buildDir = resolve(process.env.GENERIC_IM_WEB_BUILD_DIR || 'build/web');
const artifactDir = resolve(
  process.env.GENERIC_IM_SMOKE_ARTIFACT_DIR || 'artifacts/web-portal-smoke',
);
const browserPath = process.env.CHROME_PATH ||
  'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';

async function main() {
  assert(existsSync(join(buildDir, 'index.html')), `Missing Flutter Web build: ${buildDir}`);
  assert(existsSync(browserPath), `Missing Chromium browser: ${browserPath}`);
  mkdirSync(artifactDir, { recursive: true });

  const session = await loginOrCreate(username, password);
  const server = await startStaticServer();
  let browser;
  try {
    const webUrl = `http://127.0.0.1:${server.port}/`;
    browser = await launchBrowser(webUrl, session);
    const portalNames = await waitForNames(
      browser.client,
      (names) => names.includes('关闭') || names.includes('Close') || names.includes('關閉'),
      30000,
      'portal close button',
    );
    const forbiddenNavLabels = ['消息', '联系人', '聯絡人', '发现', '發現', '设置', '設定'];
    const visibleBottomNav = portalNames.filter((name) => forbiddenNavLabels.includes(name));
    assert(visibleBottomNav.length === 0,
      `Bottom navigation is still exposed on the portal: ${JSON.stringify(visibleBottomNav)}`);
    const portalScreenshot = await captureScreenshot(browser.client, 'portal');

    await clickAxLabel(browser.client, ['关闭', 'Close', '關閉']);
    await waitForRuntime(
      browser.client,
      `location.hash.includes('/home')`,
      15000,
      'close button to navigate home',
    );
    const homeNames = await waitForNames(
      browser.client,
      (names) => names.includes('消息') || names.includes('Messages'),
      20000,
      'home navigation restoration',
    );
    const homeScreenshot = await captureScreenshot(browser.client, 'home');

    console.log(JSON.stringify({
      ok: true,
      webUrl,
      portalRoute: '/portal',
      closeRoute: '/home',
      closeButtonVisible: true,
      bottomNavigationHiddenOnPortal: true,
      bottomNavigationRestoredOnHome:
        homeNames.includes('消息') || homeNames.includes('Messages'),
      screenshots: { portal: portalScreenshot, home: homeScreenshot },
    }, null, 2));
  } finally {
    await browser?.cleanup();
    await server.close();
  }
}

async function captureScreenshot(client, label) {
  const screenshot = await client.send('Page.captureScreenshot', {
    format: 'png',
    captureBeyondViewport: false,
  });
  const path = join(artifactDir, `${label}-${Date.now()}.png`);
  writeFileSync(path, Buffer.from(screenshot.data, 'base64'));
  return path;
}

async function login(loginUsername, loginPassword) {
  const body = await jsonRequest('/api/v1/auth/login', {
    method: 'POST',
    data: {
      username: loginUsername,
      password: loginPassword,
      device_id: `web-portal-smoke-${Date.now()}`,
      device_type: 'web',
      device_name: 'Flutter Web Portal Smoke',
    },
  });
  assert(body?.code === 0 && body?.data?.token,
    `Login failed for ${loginUsername}: ${JSON.stringify(body)}`);
  const me = await jsonRequest('/api/v1/user/me', { token: body.data.token });
  assert(me?.code === 0 && (me?.data?.uuid || me?.data?.id),
    `/user/me failed for ${loginUsername}`);
  return {
    username: loginUsername,
    token: body.data.token,
    user: { uuid: String(me.data.uuid || me.data.id), raw: me.data },
  };
}

async function loginOrCreate(preferredUsername, loginPassword) {
  try {
    return await login(preferredUsername, loginPassword);
  } catch (error) {
    if (process.env.GENERIC_IM_SMOKE_USERNAME) throw error;
    const suffix = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
    const createdUsername = `portalqa${suffix}`.slice(0, 20);
    const body = await jsonRequest('/api/v1/auth/register', {
      method: 'POST',
      data: {
        username: createdUsername,
        password: loginPassword,
        nickname: 'Portal QA',
        gender: 'male',
        device_id: `web-portal-smoke-register-${Date.now()}`,
        device_type: 'web',
        device_name: 'Flutter Web Portal Smoke',
      },
    });
    assert(body?.code === 0,
      `Register fallback failed: ${JSON.stringify(body)}; original login: ${String(error)}`);
    return login(createdUsername, loginPassword);
  }
}

async function startStaticServer() {
  const port = await freePort();
  const mime = {
    '.html': 'text/html; charset=utf-8',
    '.js': 'text/javascript',
    '.json': 'application/json',
    '.wasm': 'application/wasm',
    '.png': 'image/png',
    '.svg': 'image/svg+xml',
    '.css': 'text/css',
  };
  const server = createServer((req, res) => {
    const pathname = decodeURIComponent(new URL(req.url, `http://${req.headers.host}`).pathname);
    const requested = normalize(join(buildDir, pathname));
    const file = requested.startsWith(buildDir) && existsSync(requested) && statSync(requested).isFile()
      ? requested : join(buildDir, 'index.html');
    res.setHeader('Content-Type', mime[extname(file).toLowerCase()] || 'application/octet-stream');
    res.setHeader('Cache-Control', 'no-store');
    createReadStream(file).pipe(res);
  });
  await new Promise((resolvePromise, reject) =>
    server.listen(port, '127.0.0.1', resolvePromise).once('error', reject));
  return {
    port,
    close: () => new Promise((resolvePromise) => server.close(resolvePromise)),
  };
}

async function launchBrowser(webUrl, session) {
  const port = await freePort();
  const userDataDir = mkdtempSync(join(tmpdir(), 'genericim-web-portal-smoke-'));
  const child = spawn(browserPath, [
    '--headless=new',
    `--remote-debugging-port=${port}`,
    `--user-data-dir=${userDataDir}`,
    '--window-size=430,932',
    '--force-device-scale-factor=1',
    '--disable-extensions',
    '--no-first-run',
    '--no-default-browser-check',
    'about:blank',
  ], { stdio: 'ignore', windowsHide: true });
  await waitForDebugPort(port);
  const version = await fetch(`http://127.0.0.1:${port}/json/version`).then((response) => response.json());
  const browser = await connectCDP(version.webSocketDebuggerUrl);
  const target = await browser.send('Target.createTarget', { url: 'about:blank' });
  const page = await waitForPageTarget(port, target.targetId);
  const client = await connectCDP(page.webSocketDebuggerUrl);
  await client.send('Page.enable');
  await client.send('Runtime.enable');
  await client.send('DOM.enable');
  await client.send('Accessibility.enable');
  await client.send('Page.addScriptToEvaluateOnNewDocument', { source: authScript(session) });
  await client.send('Page.navigate', { url: `${webUrl}#/portal` });
  await waitForRuntime(client,
    `!!document.querySelector('flt-glass-pane, flutter-view, flt-scene-host')`,
    30000,
    'Flutter root',
  );
  await client.send('Runtime.evaluate', {
    expression: `(() => { const node = document.querySelector('flt-semantics-placeholder'); if (node) node.click(); return true; })()`,
    returnByValue: true,
  });
  return {
    client,
    cleanup: async () => {
      client.close();
      try { await browser.send('Target.closeTarget', { targetId: target.targetId }); } catch {}
      browser.close();
      child.kill();
      await sleep(400);
      try { rmSync(userDataDir, { recursive: true, force: true }); } catch {}
    },
  };
}

function authScript(session) {
  const raw = {
    ...session.user.raw,
    uuid: session.user.uuid,
    id: String(session.user.raw.id || session.user.uuid),
    username: session.username,
  };
  return `(() => {
    localStorage.setItem('flutter.auth_token', JSON.stringify(${JSON.stringify(session.token)}));
    localStorage.setItem('flutter.user_id', JSON.stringify(${JSON.stringify(session.user.uuid)}));
    localStorage.setItem('flutter.auth_user_data', JSON.stringify(${JSON.stringify(JSON.stringify(raw))}));
  })();`;
}

async function getAxNames(client) {
  const tree = await client.send('Accessibility.getFullAXTree');
  return [...new Set((tree?.nodes || [])
    .map((node) => String(node?.name?.value || '').trim())
    .filter(Boolean))];
}

async function waitForNames(client, predicate, timeoutMs, label) {
  const deadline = Date.now() + timeoutMs;
  let names = [];
  while (Date.now() < deadline) {
    names = await getAxNames(client);
    if (predicate(names)) return names;
    await sleep(300);
  }
  throw new Error(`Timed out waiting for ${label}; accessibility names: ${JSON.stringify(names)}`);
}

async function clickAxLabel(client, candidates) {
  const tree = await client.send('Accessibility.getFullAXTree');
  const matches = (tree?.nodes || []).filter((node) => {
    const name = String(node?.name?.value || '');
    return node?.backendDOMNodeId && candidates.some((candidate) => name === candidate);
  });
  const node = matches.find((item) => String(item?.role?.value || '') === 'button') || matches[0];
  assert(node, `Accessibility control not found: ${JSON.stringify(candidates)}`);
  const resolved = await client.send('DOM.resolveNode', { backendNodeId: node.backendDOMNodeId });
  const objectId = resolved?.object?.objectId;
  assert(objectId, `Could not resolve accessibility control: ${JSON.stringify(candidates)}`);
  const result = await client.send('Runtime.callFunctionOn', {
    objectId,
    functionDeclaration: 'function() { const r = this.getBoundingClientRect(); return { left: r.left, top: r.top, width: r.width, height: r.height }; }',
    returnByValue: true,
  });
  const rect = result?.result?.value;
  assert(rect && rect.width > 0 && rect.height > 0,
    `Accessibility control has no clickable bounds: ${JSON.stringify(candidates)}`);
  await client.send('Input.dispatchMouseEvent', {
    type: 'mousePressed', x: rect.left + rect.width / 2, y: rect.top + rect.height / 2,
    button: 'left', clickCount: 1,
  });
  await client.send('Input.dispatchMouseEvent', {
    type: 'mouseReleased', x: rect.left + rect.width / 2, y: rect.top + rect.height / 2,
    button: 'left', clickCount: 1,
  });
}

async function jsonRequest(path, { method = 'GET', token = '', data } = {}) {
  const response = await fetch(`${apiBase}${path}`, {
    method,
    headers: {
      ...(data ? { 'Content-Type': 'application/json' } : {}),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: data ? JSON.stringify(data) : undefined,
  });
  const text = await response.text();
  let body;
  try { body = JSON.parse(text); } catch {
    throw new Error(`${method} ${path} returned non-JSON HTTP ${response.status}: ${text.slice(0, 300)}`);
  }
  if (!response.ok) {
    throw new Error(`${method} ${path} failed HTTP ${response.status}: ${text.slice(0, 500)}`);
  }
  return body;
}

async function freePort() {
  return new Promise((resolvePromise, reject) => {
    const server = createNetServer();
    server.listen(0, '127.0.0.1', () => {
      const port = server.address().port;
      server.close(() => resolvePromise(port));
    });
    server.once('error', reject);
  });
}

async function waitForDebugPort(port) {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    try {
      const response = await fetch(`http://127.0.0.1:${port}/json/version`);
      if (response.ok) return;
    } catch {}
    await sleep(150);
  }
  throw new Error(`Browser debugging port ${port} did not open`);
}

async function waitForPageTarget(port, targetId) {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    const pages = await fetch(`http://127.0.0.1:${port}/json/list`).then((response) => response.json());
    const page = pages.find((item) => item.id === targetId);
    if (page?.webSocketDebuggerUrl) return page;
    await sleep(150);
  }
  throw new Error(`Browser target ${targetId} was not ready`);
}

async function waitForRuntime(client, expression, timeoutMs, label) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const result = await client.send('Runtime.evaluate', { expression, returnByValue: true });
    if (result?.result?.value === true) return;
    await sleep(250);
  }
  throw new Error(`Timed out waiting for ${label}`);
}

async function connectCDP(url) {
  const socket = new WebSocket(url);
  const pending = new Map();
  const listeners = new Map();
  let id = 1;
  await new Promise((resolvePromise, reject) => {
    socket.addEventListener('open', resolvePromise, { once: true });
    socket.addEventListener('error', reject, { once: true });
  });
  socket.addEventListener('message', (event) => {
    const message = JSON.parse(event.data);
    if (message.id && pending.has(message.id)) {
      const item = pending.get(message.id);
      pending.delete(message.id);
      message.error ? item.reject(new Error(JSON.stringify(message.error))) : item.resolve(message.result);
    } else if (message.method) {
      for (const callback of listeners.get(message.method) || []) callback(message.params || {});
    }
  });
  return {
    send(method, params = {}) {
      const current = id++;
      socket.send(JSON.stringify({ id: current, method, params }));
      return new Promise((resolvePromise, reject) =>
        pending.set(current, { resolve: resolvePromise, reject }));
    },
    on(method, callback) {
      const list = listeners.get(method) || [];
      list.push(callback);
      listeners.set(method, list);
    },
    close() { socket.close(); },
  };
}

function trim(value) { return value.replace(/\/+$/, ''); }
function sleep(ms) { return new Promise((resolvePromise) => setTimeout(resolvePromise, ms)); }
function assert(condition, message) { if (!condition) throw new Error(message); }

main().catch((error) => {
  console.error(error?.stack || String(error));
  process.exitCode = 1;
});
