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

const buildDir = resolve(process.env.GENERIC_IM_ADMIN_BUILD_DIR || 'admin/dist');
const apiOrigin = (process.env.GENERIC_IM_ADMIN_API_ORIGIN || 'https://api.example.com').replace(/\/+$/, '');
const username = process.env.GENERIC_IM_ADMIN_USERNAME || 'admin';
const password = process.env.GENERIC_IM_ADMIN_PASSWORD || '123456';
const expectRuntimeFingerprint = process.env.GENERIC_IM_EXPECT_RUNTIME_FINGERPRINT === '1';
const webOriginOverride = (process.env.GENERIC_IM_ADMIN_WEB_ORIGIN || '').replace(/\/+$/, '');
const browserPath = process.env.CHROME_PATH ||
  'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';
const artifactDir = resolve(process.env.GENERIC_IM_ADMIN_SMOKE_ARTIFACT_DIR || 'artifacts/admin-same-origin-smoke');

async function main() {
  assert(existsSync(join(buildDir, 'index.html')), `Missing admin build: ${buildDir}`);
  assert(existsSync(browserPath), `Missing Chromium browser: ${browserPath}`);
  mkdirSync(artifactDir, { recursive: true });

  const server = webOriginOverride ? null : await startServer();
  let browser;
  try {
    const webOrigin = webOriginOverride || `http://127.0.0.1:${server.port}`;
    browser = await launchBrowser(`${webOrigin}/#/auth/login`);
    await waitForRuntime(browser.client,
      `document.querySelectorAll('input').length >= 2 && !!document.querySelector('.drag_verify')`,
      30000,
      'admin login form',
    );

    const startup = await evaluateRuntime(browser.client, `(() => {
      const verify = window[Symbol.for('v:4e8d')];
      const output = typeof verify === 'function' ? verify() : null;
      return {
        readyState: document.readyState,
        appHtmlLength: document.querySelector('#app')?.innerHTML?.length || 0,
        fingerprintInstalled: typeof verify === 'function',
        fingerprintStatus: output?.['核验状态'] || '',
        fingerprintOwner: output?.['版权所有者'] || '',
        fingerprintProject: output?.['项目名称'] || '',
        fingerprintCarriers: output?.['载体状态'] || '',
      };
    })()`);
    assert(startup.readyState === 'complete', `Document did not complete: ${JSON.stringify(startup)}`);
    assert(startup.appHtmlLength > 1000, `Vue app did not render: ${JSON.stringify(startup)}`);
    if (expectRuntimeFingerprint) {
      const expectedOwner = String.fromCharCode(0x6d4e, 0x5357, 0x58f9, 0x8f6f);
      const expectedProject = String.fromCharCode(0x58f9, 0x4fe1, 0x49, 0x4d);
      assert(startup.fingerprintInstalled, `Runtime fingerprint was not installed: ${JSON.stringify(startup)}`);
      assert(startup.fingerprintOwner === expectedOwner, `Unexpected fingerprint owner: ${JSON.stringify(startup)}`);
      assert(startup.fingerprintProject === expectedProject, `Unexpected fingerprint project: ${JSON.stringify(startup)}`);
      assert(startup.fingerprintCarriers === '2/2 完整', `Fingerprint carriers incomplete: ${JSON.stringify(startup)}`);
    }

    await setInput(browser.client, 0, username);
    await setInput(browser.client, 1, password);
    await dragVerify(browser.client);
    await clickLogin(browser.client);
    await waitForRuntime(browser.client,
      `!location.hash.includes('/auth/login')`,
      30000,
      'admin login navigation',
    );
    await sleep(1500);

    const apiRequests = browser.network.filter((entry) => entry.url.includes('/api/v1/'));
    const loginRequest = apiRequests.find((entry) => entry.url.includes('/api/v1/admin/login'));
    const meRequest = apiRequests.find((entry) => entry.url.includes('/api/v1/admin/me'));
    const directCrossOrigin = browser.network.filter((entry) => entry.url.startsWith(apiOrigin));
    assert(loginRequest?.status === 200,
      `Admin login request did not succeed: ${JSON.stringify(loginRequest)}`);
    assert(meRequest?.status === 200,
      `Admin user-info request did not succeed: ${JSON.stringify(meRequest)}`);
    assert(directCrossOrigin.length === 0,
      `Browser still called the API cross-origin: ${JSON.stringify(directCrossOrigin)}`);
    assert(browser.runtimeExceptions.length === 0,
      `Browser runtime exceptions: ${JSON.stringify(browser.runtimeExceptions)}`);

    const screenshot = await browser.client.send('Page.captureScreenshot', {
      format: 'png', captureBeyondViewport: false,
    });
    const screenshotPath = join(artifactDir, `admin-login-success-${Date.now()}.png`);
    writeFileSync(screenshotPath, Buffer.from(screenshot.data, 'base64'));

    console.log(JSON.stringify({
      ok: true,
      route: browser.currentUrl(),
      loginStatus: loginRequest.status,
      adminMeStatus: meRequest.status,
      browserApiMode: 'same-origin /api/v1',
      crossOriginApiRequests: directCrossOrigin.length,
      startup,
      runtimeExceptions: browser.runtimeExceptions,
      apiRequests: apiRequests.map(({ method, url, status }) => ({
        method, url: url.replace(webOrigin, ''), status,
      })),
      screenshotPath,
    }, null, 2));
  } finally {
    await browser?.cleanup();
    await server?.close();
  }
}

async function startServer() {
  const port = await freePort();
  const mime = {
    '.html': 'text/html; charset=utf-8', '.js': 'text/javascript',
    '.css': 'text/css', '.json': 'application/json', '.svg': 'image/svg+xml',
    '.png': 'image/png', '.webp': 'image/webp', '.ico': 'image/x-icon',
  };
  const server = createServer(async (req, res) => {
    try {
      const url = new URL(req.url, `http://${req.headers.host}`);
      if (url.pathname.startsWith('/api/')) {
        const chunks = [];
        for await (const chunk of req) chunks.push(chunk);
        const body = chunks.length > 0 ? Buffer.concat(chunks) : undefined;
        const upstream = await fetch(`${apiOrigin}${url.pathname}${url.search}`, {
          method: req.method,
          headers: {
            ...(req.headers['content-type'] ? { 'content-type': req.headers['content-type'] } : {}),
            ...(req.headers.authorization ? { authorization: req.headers.authorization } : {}),
          },
          body: ['GET', 'HEAD'].includes(req.method || 'GET') ? undefined : body,
        });
        res.statusCode = upstream.status;
        res.setHeader('content-type', upstream.headers.get('content-type') || 'application/json');
        res.end(Buffer.from(await upstream.arrayBuffer()));
        return;
      }

      const requested = normalize(join(buildDir, decodeURIComponent(url.pathname)));
      const file = requested.startsWith(buildDir) && existsSync(requested) && statSync(requested).isFile()
        ? requested : join(buildDir, 'index.html');
      res.setHeader('content-type', mime[extname(file).toLowerCase()] || 'application/octet-stream');
      res.setHeader('cache-control', 'no-store');
      createReadStream(file).pipe(res);
    } catch (error) {
      res.statusCode = 502;
      res.end(String(error));
    }
  });
  await new Promise((resolvePromise, reject) =>
    server.listen(port, '127.0.0.1', resolvePromise).once('error', reject));
  return { port, close: () => new Promise((resolvePromise) => server.close(resolvePromise)) };
}

async function launchBrowser(url) {
  const port = await freePort();
  const userDataDir = mkdtempSync(join(tmpdir(), 'genericim-admin-smoke-'));
  const child = spawn(browserPath, [
    '--headless=new', `--remote-debugging-port=${port}`, `--user-data-dir=${userDataDir}`,
    '--window-size=1440,900', '--disable-extensions', '--no-first-run',
    '--no-default-browser-check', 'about:blank',
  ], { stdio: 'ignore', windowsHide: true });
  await waitForDebugPort(port);
  const version = await fetch(`http://127.0.0.1:${port}/json/version`).then((response) => response.json());
  const browser = await connectCDP(version.webSocketDebuggerUrl);
  const target = await browser.send('Target.createTarget', { url: 'about:blank' });
  const page = await waitForPageTarget(port, target.targetId);
  const client = await connectCDP(page.webSocketDebuggerUrl);
  const network = [];
  const runtimeExceptions = [];
  let currentUrl = url;
  client.on('Network.requestWillBeSent', (event) => {
    if (!event?.request?.url) return;
    network.push({ requestId: event.requestId, method: event.request.method, url: event.request.url, status: 0 });
  });
  client.on('Network.responseReceived', (event) => {
    const item = [...network].reverse().find((entry) => entry.requestId === event.requestId);
    if (item) item.status = event.response.status;
  });
  client.on('Page.frameNavigated', (event) => {
    if (event?.frame?.parentId == null && event?.frame?.url) currentUrl = event.frame.url;
  });
  client.on('Runtime.exceptionThrown', (event) => {
    runtimeExceptions.push(event?.exceptionDetails?.text || 'Runtime exception');
  });
  await client.send('Page.enable');
  await client.send('Runtime.enable');
  await client.send('Network.enable');
  await client.send('Page.navigate', { url });
  return {
    client, network, runtimeExceptions, currentUrl: () => currentUrl,
    cleanup: async () => {
      client.close();
      try { await browser.send('Target.closeTarget', { targetId: target.targetId }); } catch {}
      browser.close(); child.kill(); await sleep(400);
      try { rmSync(userDataDir, { recursive: true, force: true }); } catch {}
    },
  };
}

async function evaluateRuntime(client, expression) {
  const result = await client.send('Runtime.evaluate', { expression, returnByValue: true });
  if (result?.exceptionDetails) {
    throw new Error(result.exceptionDetails.text || 'Runtime evaluation failed');
  }
  return result?.result?.value;
}

async function setInput(client, index, value) {
  const result = await client.send('Runtime.evaluate', {
    expression: `(() => {
      const input = document.querySelectorAll('input')[${index}];
      if (!input) return false;
      const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
      setter.call(input, ${JSON.stringify(value)});
      input.dispatchEvent(new Event('input', { bubbles: true }));
      input.dispatchEvent(new Event('change', { bubbles: true }));
      return true;
    })()`, returnByValue: true,
  });
  assert(result?.result?.value === true, `Could not set input ${index}`);
}

async function dragVerify(client) {
  const result = await client.send('Runtime.evaluate', {
    expression: `(() => {
      const handler = document.querySelector('.dv_handler');
      const track = document.querySelector('.drag_verify');
      if (!handler || !track) return null;
      const h = handler.getBoundingClientRect();
      const t = track.getBoundingClientRect();
      return { startX: h.left + h.width / 2, y: h.top + h.height / 2, endX: t.right + 5 };
    })()`, returnByValue: true,
  });
  const point = result?.result?.value;
  assert(point, 'Drag verify control was not found');
  await client.send('Input.dispatchMouseEvent', {
    type: 'mousePressed', x: point.startX, y: point.y, button: 'left', clickCount: 1,
  });
  for (let step = 1; step <= 12; step += 1) {
    const x = point.startX + ((point.endX - point.startX) * step / 12);
    await client.send('Input.dispatchMouseEvent', {
      type: 'mouseMoved', x, y: point.y, button: 'left', buttons: 1,
    });
  }
  await client.send('Input.dispatchMouseEvent', {
    type: 'mouseReleased', x: point.endX, y: point.y, button: 'left', clickCount: 1,
  });
}

async function clickLogin(client) {
  const result = await client.send('Runtime.evaluate', {
    expression: `(() => {
      const button = [...document.querySelectorAll('button')].find((node) => node.textContent.trim() === '登录');
      if (!button) return false;
      button.click();
      return true;
    })()`, returnByValue: true,
  });
  assert(result?.result?.value === true, 'Login button was not found');
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
      return new Promise((resolvePromise, reject) => pending.set(current, { resolve: resolvePromise, reject }));
    },
    on(method, callback) {
      const list = listeners.get(method) || [];
      list.push(callback); listeners.set(method, list);
    },
    close() { socket.close(); },
  };
}

function sleep(ms) { return new Promise((resolvePromise) => setTimeout(resolvePromise, ms)); }
function assert(condition, message) { if (!condition) throw new Error(message); }

main().catch((error) => {
  console.error(error?.stack || String(error));
  process.exitCode = 1;
});
