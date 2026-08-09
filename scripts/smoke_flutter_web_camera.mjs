#!/usr/bin/env node

import { spawn } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createServer } from 'node:net';

const webUrl = process.env.GENERIC_IM_WEB_URL || 'http://localhost:5175/';
const scanUrl = new URL('/scan', webUrl).toString();

async function main() {
  const chrome = await ensureChromeForCameraSmoke();
  try {
    const result = await checkCameraStream(chrome.port);
    console.log(
      JSON.stringify(
        {
          ok: true,
          webUrl,
          scanUrl,
          camera: result,
        },
        null,
        2,
      ),
    );
  } finally {
    await chrome.cleanup();
  }
}

async function ensureChromeForCameraSmoke() {
  const chromePath =
    process.env.CHROME_PATH ||
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
  const port = String(await freePort());
  const userDataDir = mkdtempSync(join(tmpdir(), 'genericim-camera-smoke-chrome-'));
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

async function checkCameraStream(port) {
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
    await browser.send('Browser.grantPermissions', {
      origin,
      permissions: ['videoCapture'],
    });
    await client.send('Page.navigate', { url: scanUrl });
    await waitForPageReady(client, origin);
    const result = await client.send('Runtime.evaluate', {
      expression: buildCameraExpression(),
      awaitPromise: true,
      returnByValue: true,
      timeout: 15000,
    });
    const value = result?.result?.value;
    if (!value || value.status !== 'ok') {
      throw new Error(`Browser camera failed: ${JSON.stringify(value)}`);
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

function buildCameraExpression() {
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
      finish('timeout', { error: 'Timed out while reading camera stream' });
    }, 10000);
    try {
      if (!navigator.mediaDevices?.getUserMedia) {
        finish('unsupported', { error: 'mediaDevices.getUserMedia unavailable' });
        return;
      }
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { width: { ideal: 640 }, height: { ideal: 480 }, facingMode: 'environment' },
      });
      const [track] = stream.getVideoTracks();
      const video = document.createElement('video');
      video.id = 'codex-camera-smoke';
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
      const settings = track?.getSettings ? track.getSettings() : {};
      const result = {
        videoWidth: video.videoWidth,
        videoHeight: video.videoHeight,
        trackState: track?.readyState || '',
        trackLabel: track?.label || '',
        settings,
      };
      stream.getTracks().forEach((item) => item.stop());
      video.remove();
      if (result.videoWidth <= 0 || result.videoHeight <= 0 || result.trackState !== 'live') {
        finish('error', { error: 'Camera stream did not produce a live video frame', ...result });
        return;
      }
      finish('ok', result);
    } catch (error) {
      finish('error', { error: String(error?.message || error) });
    }
  }))()`;
}

main().catch((error) => {
  console.error(error?.stack || error?.message || String(error));
  process.exit(1);
});
