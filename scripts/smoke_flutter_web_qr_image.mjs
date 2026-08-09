#!/usr/bin/env node

import { execFileSync, spawn } from 'node:child_process';
import { existsSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createServer } from 'node:net';

const webUrl = process.env.GENERIC_IM_WEB_URL || 'http://localhost:5175/';
const scanUrl = new URL('/#/scan', webUrl).toString();
const dartPath =
  process.env.DART_PATH ||
  (process.platform === 'win32' &&
  existsSync('D:\\flutter\\bin\\cache\\dart-sdk\\bin\\dart.exe')
    ? 'D:\\flutter\\bin\\cache\\dart-sdk\\bin\\dart.exe'
    : 'dart');
const payload =
  process.env.GENERIC_IM_SMOKE_QR_PAYLOAD ||
  'genericim://user/592a0893-4c3b-42e1-bcef-55b0ab393486';

async function main() {
  const svg = execFileSync(
    dartPath,
    ['run', 'scripts/generate_qr_svg.dart', payload],
    { encoding: 'utf8' },
  );
  const chrome = await ensureChrome();
  try {
    const decoded = await decodeQrImage(chrome.port, svg);
    console.log(
      JSON.stringify(
        {
          ok: true,
          webUrl,
          scanUrl,
          payload,
          svgBytes: Buffer.byteLength(svg),
          decoded,
        },
        null,
        2,
      ),
    );
  } finally {
    await chrome.cleanup();
  }
}

async function ensureChrome() {
  const chromePath =
    process.env.CHROME_PATH ||
    (process.platform === 'win32'
      ? [
          join(
            process.env.LOCALAPPDATA || '',
            'Google',
            'Chrome',
            'Application',
            'chrome.exe',
          ),
          'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
          'C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe',
        ].find(existsSync)
      : '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome');
  if (!chromePath || !existsSync(chromePath)) {
    throw new Error('Chrome executable was not found');
  }
  const port = String(await freePort());
  const userDataDir = mkdtempSync(join(tmpdir(), 'genericim-qr-image-chrome-'));
  const child = spawn(
    chromePath,
    [
      '--headless=new',
      `--remote-debugging-port=${port}`,
      `--user-data-dir=${userDataDir}`,
      `--unsafely-treat-insecure-origin-as-secure=${new URL(webUrl).origin}`,
      '--disable-background-timer-throttling',
      '--disable-extensions',
      '--disable-popup-blocking',
      '--no-first-run',
      '--no-default-browser-check',
      scanUrl,
    ],
    { stdio: 'ignore' },
  );

  await waitForChromeDebugPort(port);

  return {
    port,
    cleanup: async () => {
      child.kill('SIGTERM');
      await new Promise((resolve) => setTimeout(resolve, 800));
      await removeDirectoryWithRetry(userDataDir);
    },
  };
}

async function decodeQrImage(port, svg) {
  const version = await fetch(`http://127.0.0.1:${port}/json/version`).then(
    (r) => r.json(),
  );
  const browser = await connectCDP(version.webSocketDebuggerUrl);
  let targetId = '';
  let client;
  try {
    const target = await browser.send('Target.createTarget', { url: scanUrl });
    targetId = target?.targetId || '';
    const page = await waitForPageTarget(port, targetId);
    client = await connectCDP(page.webSocketDebuggerUrl);
    const origin = new URL(webUrl).origin;
    await client.send('Page.enable');
    await client.send('Runtime.enable');
    await client.send('Page.navigate', { url: scanUrl });
    await waitForPageReady(client, origin);
    const result = await client.send('Runtime.evaluate', {
      expression: buildDecodeExpression(svg),
      awaitPromise: true,
      returnByValue: true,
      timeout: 15000,
    });
    const value = result?.result?.value;
    if (!value || value.status !== 'ok') {
      throw new Error(`QR image decode failed: ${JSON.stringify(value)}`);
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

function buildDecodeExpression(svg) {
  return `(() => new Promise((resolve) => {
    const finish = (status, extra = {}) => resolve({
      status,
      pageUrl: location.href,
      isSecureContext,
      hasBarcodeDetector: 'BarcodeDetector' in window,
      hasZxing: Boolean(window.ZXing?.BrowserQRCodeReader),
      ...extra,
    });
    if (!('BarcodeDetector' in window) && !window.ZXing?.BrowserQRCodeReader) {
      finish('unsupported', { error: 'No QR image decoder available' });
      return;
    }
    const image = new Image();
    const url = URL.createObjectURL(new Blob([${JSON.stringify(svg)}], { type: 'image/svg+xml' }));
    const cleanup = () => URL.revokeObjectURL(url);
    const timer = setTimeout(() => {
      cleanup();
      finish('timeout', { error: 'Timed out while decoding QR image' });
    }, 10000);
    image.onload = async () => {
      try {
        let values = [];
        let decoder = '';
        if ('BarcodeDetector' in window) {
          const detector = new BarcodeDetector({ formats: ['qr_code'] });
          const codes = await detector.detect(image);
          values = Array.from(codes || []).map((item) => item.rawValue || '').filter(Boolean);
          decoder = 'BarcodeDetector';
        } else {
          const reader = new window.ZXing.BrowserQRCodeReader();
          const result = await reader.decodeFromImageElement(image);
          const value = String(result?.text || result?.getText?.() || '').trim();
          values = value ? [value] : [];
          decoder = 'ZXing';
        }
        clearTimeout(timer);
        cleanup();
        if (!values.length) {
          finish('not_found', { values });
          return;
        }
        finish('ok', {
          decoder,
          values,
          firstValue: values[0],
          imageWidth: image.naturalWidth,
          imageHeight: image.naturalHeight,
        });
      } catch (error) {
        clearTimeout(timer);
        cleanup();
        finish('error', { error: String(error?.message || error) });
      }
    };
    image.onerror = () => {
      clearTimeout(timer);
      cleanup();
      finish('load_error', { error: 'Failed to load generated QR image' });
    };
    image.src = url;
  }))()`;
}

main().catch((error) => {
  console.error(error?.stack || error?.message || String(error));
  process.exit(1);
});
