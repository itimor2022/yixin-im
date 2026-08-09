#!/usr/bin/env node

import { spawn } from 'node:child_process';
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { createServer as createNetServer } from 'node:net';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const webUrl = String(
  process.env.GENERIC_IM_AUTH_WEB_URL || 'http://127.0.0.1:5185/',
).replace(/\/+$/, '/');
const action = String(process.env.GENERIC_IM_AUTH_ACTION || 'inspect').trim();
const loginUsername = String(process.env.GENERIC_IM_AUTH_USERNAME || '').trim();
const loginPassword = String(process.env.GENERIC_IM_AUTH_PASSWORD || '');
const expectQuickRegister =
  String(process.env.GENERIC_IM_EXPECT_QUICK_REGISTER || '1') !== '0';
const browserPath =
  process.env.CHROME_PATH ||
  'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';
const artifactDir = resolve(
  process.env.GENERIC_IM_AUTH_ARTIFACT_DIR ||
    `artifacts/flutter-web-auth-${new Date().toISOString().replace(/[:.]/g, '-')}`,
);

async function main() {
  assert(existsSync(browserPath), `Missing Chromium browser: ${browserPath}`);
  assert(
    ['inspect', 'quick-register', 'login'].includes(action),
    `Unsupported GENERIC_IM_AUTH_ACTION: ${action}`,
  );
  if (action === 'quick-register' || action === 'login') {
    const target = new URL(webUrl);
    assert(
      ['127.0.0.1', 'localhost'].includes(target.hostname),
      `${action} smoke is restricted to a local H5 URL`,
    );
  }
  if (action === 'login') {
    assert(loginUsername, 'GENERIC_IM_AUTH_USERNAME is required for login smoke');
    assert(loginPassword, 'GENERIC_IM_AUTH_PASSWORD is required for login smoke');
  }

  mkdirSync(artifactDir, { recursive: true });
  let browser;
  try {
    browser = await launchBrowser(`${webUrl}?auth-smoke=${Date.now()}`);
    await waitForRuntime(
      browser.client,
      `!!document.querySelector('flt-glass-pane, flutter-view, flt-scene-host')`,
      45000,
      'Flutter root',
    );
    await enableSemantics(browser.client);
    const loginNames = await waitForNames(
      browser.client,
      (names) =>
        names.some((name) => name === '登录' || name === 'Login') &&
        names.some(
          (name) =>
            name.includes('用户名') ||
            name.toLowerCase().includes('username'),
        ),
      45000,
      'login semantics',
    );

    const quickRegisterVisible = loginNames.some(
      (name) =>
        name.includes('一键注册登录') ||
        name.includes('一鍵註冊登入') ||
        name.includes('One-Tap Registration'),
    );
    if (expectQuickRegister) {
      assert(
        quickRegisterVisible,
        `One-tap registration is missing; accessibility names: ${JSON.stringify(loginNames)}`,
      );
    }

    const beforeScreenshot = await captureScreenshot(
      browser.client,
      'login-before',
    );
    let quickRegisterResult = null;
    let loginResult = null;
    let afterScreenshot = '';

    if (action === 'quick-register') {
      await clickAxNode(browser.client, (node) => {
        const name = axName(node);
        return (
          axRole(node) === 'checkbox' ||
          name.includes('我已阅读并同意') ||
          name.includes('我已閱讀並同意') ||
          name.includes('I have read and agree')
        );
      }, 'agreement checkbox');

      await clickAxNode(browser.client, (node) => {
        const name = axName(node);
        return (
          name.includes('一键注册登录') ||
          name.includes('一鍵註冊登入') ||
          name.includes('One-Tap Registration')
        );
      }, 'one-tap registration button');

      const request = await waitForNetwork(
        browser,
        (entry) =>
          entry.method === 'POST' &&
          entry.url.includes('/api/v1/auth/quick-register') &&
          Number(entry.status) > 0,
        45000,
        'quick-register API response',
      );
      const session = await waitForRuntimeValue(
        browser.client,
        `(() => ({
          token: localStorage.getItem('flutter.auth_token') || '',
          route: location.href
        }))()`,
        (value) => Boolean(value?.token),
        45000,
        'quick-register session',
      );
      quickRegisterResult = {
        method: request.method,
        url: request.url,
        status: request.status,
        responseBody: request.responseBody,
        route: session.route,
        tokenStored: Boolean(session.token),
      };
      assert(
        request.status === 200,
        `Quick registration failed: ${JSON.stringify(quickRegisterResult)}`,
      );
      afterScreenshot = await captureScreenshot(
        browser.client,
        'quick-register-after',
      );
    }
    if (action === 'login') {
      await fillAxTextField(
        browser.client,
        0,
        loginUsername,
        'username field',
      );
      await fillAxTextField(
        browser.client,
        1,
        loginPassword,
        'password field',
      );
      await clickAxNode(browser.client, (node) => {
        const name = axName(node);
        return (
          axRole(node) === 'checkbox' ||
          name.includes('我已阅读并同意') ||
          name.includes('我已閱讀並同意') ||
          name.includes('I have read and agree')
        );
      }, 'agreement checkbox');
      await clickAxNode(browser.client, (node) => {
        const name = axName(node);
        return (
          axRole(node) === 'button' &&
          (name === '登录' || name === '登入' || name === 'Login')
        );
      }, 'login button');

      const request = await waitForNetwork(
        browser,
        (entry) =>
          entry.method === 'POST' &&
          entry.url.includes('/api/v1/auth/login') &&
          Number(entry.status) > 0,
        45000,
        'login API response',
      );
      const session = await waitForRuntimeValue(
        browser.client,
        `(() => ({
          token: localStorage.getItem('flutter.auth_token') || '',
          route: location.href
        }))()`,
        (value) => Boolean(value?.token),
        45000,
        'login session',
      );
      loginResult = {
        method: request.method,
        url: request.url,
        status: request.status,
        responseBody: request.responseBody,
        route: session.route,
        tokenStored: Boolean(session.token),
      };
      assert(
        request.status === 200,
        `Login failed: ${JSON.stringify(loginResult)}`,
      );
      afterScreenshot = await captureScreenshot(browser.client, 'login-after');
    }

    const appSettingsRequests = browser.network.filter((entry) =>
      entry.url.includes('/api/v1/app/settings'),
    );
    const runtime = await evaluateRuntime(
      browser.client,
      `(() => ({
        href: location.href,
        title: document.title,
        serviceWorkers: 'serviceWorker' in navigator,
        userAgent: navigator.userAgent
      }))()`,
    );

    const output = {
      ok:
        browser.runtimeExceptions.length === 0 &&
        browser.consoleErrors.length === 0 &&
        (!expectQuickRegister || quickRegisterVisible),
      action,
      webUrl,
      quickRegisterVisible,
      appSettingsRequests,
      runtime,
      runtimeExceptions: browser.runtimeExceptions,
      consoleErrors: browser.consoleErrors,
      consoleMessages: browser.consoleMessages,
      quickRegisterResult,
      loginResult,
      accessibilityNames: loginNames,
      screenshots: {
        before: beforeScreenshot,
        after: afterScreenshot,
      },
    };
    console.log(JSON.stringify(output, null, 2));

    assert(
      browser.runtimeExceptions.length === 0,
      `Browser runtime exceptions: ${JSON.stringify(browser.runtimeExceptions)}`,
    );
    assert(
      browser.consoleErrors.length === 0,
      `Browser console errors: ${JSON.stringify(browser.consoleErrors)}`,
    );
  } finally {
    await browser?.cleanup();
  }
}

async function launchBrowser(url) {
  const port = await freePort();
  const userDataDir = mkdtempSync(join(tmpdir(), 'genericim-web-auth-smoke-'));
  const child = spawn(
    browserPath,
    [
      '--headless=new',
      `--remote-debugging-port=${port}`,
      `--user-data-dir=${userDataDir}`,
      '--window-size=430,932',
      '--force-device-scale-factor=1',
      '--disable-extensions',
      '--disable-background-networking',
      '--no-first-run',
      '--no-default-browser-check',
      'about:blank',
    ],
    { stdio: 'ignore', windowsHide: true },
  );
  await waitForDebugPort(port);
  const version = await fetch(`http://127.0.0.1:${port}/json/version`).then(
    (response) => response.json(),
  );
  const browser = await connectCDP(version.webSocketDebuggerUrl);
  const target = await browser.send('Target.createTarget', {
    url: 'about:blank',
  });
  const page = await waitForPageTarget(port, target.targetId);
  const client = await connectCDP(page.webSocketDebuggerUrl);
  const network = [];
  const runtimeExceptions = [];
  const consoleErrors = [];
  const consoleMessages = [];

  client.on('Network.requestWillBeSent', (event) => {
    if (!event?.request?.url) return;
    network.push({
      requestId: event.requestId,
      method: event.request.method,
      url: event.request.url,
      status: 0,
      responseBody: '',
    });
  });
  client.on('Network.responseReceived', async (event) => {
    const item = [...network]
      .reverse()
      .find((entry) => entry.requestId === event.requestId);
    if (!item) return;
    item.status = Number(event.response.status || 0);
    if (
      item.url.includes('/api/v1/auth/') ||
      item.url.includes('/api/v1/app/settings')
    ) {
      try {
        const body = await client.send('Network.getResponseBody', {
          requestId: event.requestId,
        });
        item.responseBody = String(body?.body || '').slice(0, 2000);
      } catch {}
    }
  });
  client.on('Network.loadingFailed', (event) => {
    const item = [...network]
      .reverse()
      .find((entry) => entry.requestId === event.requestId);
    if (!item) return;
    item.failed = true;
    item.errorText = event.errorText || '';
    item.blockedReason = event.blockedReason || '';
    item.corsErrorStatus = event.corsErrorStatus || null;
  });
  client.on('Runtime.exceptionThrown', (event) => {
    const details = event?.exceptionDetails || {};
    runtimeExceptions.push({
      text: details.text || '',
      description: details.exception?.description || '',
      url: details.url || '',
      lineNumber: details.lineNumber,
      columnNumber: details.columnNumber,
      stackTrace: details.stackTrace || null,
    });
  });
  client.on('Runtime.consoleAPICalled', (event) => {
    const message = (event.args || [])
      .map((arg) => String(arg.value || arg.description || ''))
      .join(' ')
      .slice(0, 2000);
    consoleMessages.push({ type: event.type, message });
    if (event.type === 'error') consoleErrors.push(message);
  });

  await client.send('Page.enable');
  await client.send('Runtime.enable');
  await client.send('DOM.enable');
  await client.send('Accessibility.enable');
  await client.send('Network.enable');
  await client.send('Page.navigate', { url });

  return {
    client,
    network,
    runtimeExceptions,
    consoleErrors,
    consoleMessages,
    cleanup: async () => {
      client.close();
      try {
        await browser.send('Target.closeTarget', {
          targetId: target.targetId,
        });
      } catch {}
      browser.close();
      child.kill();
      await sleep(400);
      try {
        rmSync(userDataDir, { recursive: true, force: true });
      } catch {}
    },
  };
}

async function enableSemantics(client) {
  for (let attempt = 0; attempt < 20; attempt += 1) {
    await client.send('Runtime.evaluate', {
      expression: `(() => {
        const node = document.querySelector('flt-semantics-placeholder');
        if (node) node.click();
        return true;
      })()`,
      returnByValue: true,
    });
    const names = await getAxNames(client);
    if (names.length > 3) return;
    await sleep(250);
  }
}

async function getAxNodes(client) {
  const tree = await client.send('Accessibility.getFullAXTree');
  return tree?.nodes || [];
}

async function getAxNames(client) {
  return [
    ...new Set(
      (await getAxNodes(client)).map(axName).filter(Boolean),
    ),
  ];
}

function axName(node) {
  return String(node?.name?.value || '').trim();
}

function axRole(node) {
  return String(node?.role?.value || '').trim();
}

async function waitForNames(client, predicate, timeoutMs, label) {
  const deadline = Date.now() + timeoutMs;
  let names = [];
  while (Date.now() < deadline) {
    names = await getAxNames(client);
    if (predicate(names)) return names;
    await sleep(300);
  }
  throw new Error(
    `Timed out waiting for ${label}; accessibility names: ${JSON.stringify(names)}`,
  );
}

async function clickAxNode(client, predicate, label) {
  const nodes = await getAxNodes(client);
  const matches = nodes.filter(
    (node) => node?.backendDOMNodeId && predicate(node),
  );
  const node =
    matches.find((item) =>
      ['button', 'checkbox', 'link'].includes(axRole(item)),
    ) || matches[0];
  assert(
    node,
    `${label} not found; accessibility names: ${JSON.stringify(nodes.map(axName).filter(Boolean))}`,
  );
  const resolved = await client.send('DOM.resolveNode', {
    backendNodeId: node.backendDOMNodeId,
  });
  const objectId = resolved?.object?.objectId;
  assert(objectId, `Could not resolve ${label}`);
  const result = await client.send('Runtime.callFunctionOn', {
    objectId,
    functionDeclaration:
      'function() { const r = this.getBoundingClientRect(); return { left: r.left, top: r.top, width: r.width, height: r.height }; }',
    returnByValue: true,
  });
  const rect = result?.result?.value;
  assert(
    rect && rect.width > 0 && rect.height > 0,
    `${label} has no clickable bounds`,
  );
  const x = rect.left + rect.width / 2;
  const y = rect.top + rect.height / 2;
  await client.send('Input.dispatchMouseEvent', {
    type: 'mousePressed',
    x,
    y,
    button: 'left',
    clickCount: 1,
  });
  await client.send('Input.dispatchMouseEvent', {
    type: 'mouseReleased',
    x,
    y,
    button: 'left',
    clickCount: 1,
  });
}

async function fillAxTextField(client, index, value, label) {
  const nodes = await getAxNodes(client);
  const fields = nodes.filter(
    (node) => node?.backendDOMNodeId && axRole(node) === 'textbox',
  );
  const node = fields[index];
  assert(
    node,
    `${label} not found; textboxes: ${JSON.stringify(fields.map(axName))}`,
  );
  const resolved = await client.send('DOM.resolveNode', {
    backendNodeId: node.backendDOMNodeId,
  });
  const objectId = resolved?.object?.objectId;
  assert(objectId, `Could not resolve ${label}`);
  const result = await client.send('Runtime.callFunctionOn', {
    objectId,
    functionDeclaration:
      'function() { const r = this.getBoundingClientRect(); return { left: r.left, top: r.top, width: r.width, height: r.height }; }',
    returnByValue: true,
  });
  const rect = result?.result?.value;
  assert(
    rect && rect.width > 0 && rect.height > 0,
    `${label} has no editable bounds`,
  );
  const x = rect.left + rect.width / 2;
  const y = rect.top + rect.height / 2;
  await client.send('Input.dispatchMouseEvent', {
    type: 'mousePressed',
    x,
    y,
    button: 'left',
    clickCount: 1,
  });
  await client.send('Input.dispatchMouseEvent', {
    type: 'mouseReleased',
    x,
    y,
    button: 'left',
    clickCount: 1,
  });
  await client.send('Input.dispatchKeyEvent', {
    type: 'keyDown',
    key: 'a',
    code: 'KeyA',
    modifiers: 2,
  });
  await client.send('Input.dispatchKeyEvent', {
    type: 'keyUp',
    key: 'a',
    code: 'KeyA',
    modifiers: 2,
  });
  await client.send('Input.dispatchKeyEvent', {
    type: 'keyDown',
    key: 'Backspace',
    code: 'Backspace',
  });
  await client.send('Input.dispatchKeyEvent', {
    type: 'keyUp',
    key: 'Backspace',
    code: 'Backspace',
  });
  await client.send('Input.insertText', { text: value });
}

async function waitForNetwork(browser, predicate, timeoutMs, label) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const entry = [...browser.network].reverse().find(predicate);
    if (entry) return entry;
    await sleep(250);
  }
  throw new Error(
    `Timed out waiting for ${label}; network: ${JSON.stringify(browser.network.slice(-30))}`,
  );
}

async function waitForRuntimeValue(
  client,
  expression,
  predicate,
  timeoutMs,
  label,
) {
  const deadline = Date.now() + timeoutMs;
  let value;
  while (Date.now() < deadline) {
    value = await evaluateRuntime(client, expression);
    if (predicate(value)) return value;
    await sleep(250);
  }
  throw new Error(
    `Timed out waiting for ${label}; last value: ${JSON.stringify(value)}`,
  );
}

async function evaluateRuntime(client, expression) {
  const result = await client.send('Runtime.evaluate', {
    expression,
    returnByValue: true,
  });
  if (result?.exceptionDetails) {
    throw new Error(
      result.exceptionDetails.exception?.description ||
        result.exceptionDetails.text ||
        'Runtime evaluation failed',
    );
  }
  return result?.result?.value;
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
    const pages = await fetch(`http://127.0.0.1:${port}/json/list`).then(
      (response) => response.json(),
    );
    const page = pages.find((item) => item.id === targetId);
    if (page?.webSocketDebuggerUrl) return page;
    await sleep(150);
  }
  throw new Error(`Browser target ${targetId} was not ready`);
}

async function waitForRuntime(client, expression, timeoutMs, label) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const result = await client.send('Runtime.evaluate', {
      expression,
      returnByValue: true,
    });
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
      message.error
        ? item.reject(new Error(JSON.stringify(message.error)))
        : item.resolve(message.result);
      return;
    }
    if (message.method) {
      for (const callback of listeners.get(message.method) || []) {
        callback(message.params || {});
      }
    }
  });
  return {
    send(method, params = {}) {
      return new Promise((resolvePromise, reject) => {
        const requestId = id++;
        pending.set(requestId, { resolve: resolvePromise, reject });
        socket.send(JSON.stringify({ id: requestId, method, params }));
      });
    },
    on(method, callback) {
      const callbacks = listeners.get(method) || [];
      callbacks.push(callback);
      listeners.set(method, callbacks);
    },
    close() {
      socket.close();
    },
  };
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function sleep(ms) {
  return new Promise((resolvePromise) => setTimeout(resolvePromise, ms));
}

main().catch((error) => {
  console.error(error?.stack || error);
  process.exit(1);
});
