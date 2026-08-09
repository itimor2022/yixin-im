#!/usr/bin/env node

import { createServer } from 'node:http';
import { createReadStream, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { extname, join, normalize, resolve } from 'node:path';
import { spawn } from 'node:child_process';
import { tmpdir } from 'node:os';
import { createServer as createNetServer } from 'node:net';

const apiBase = trim(process.env.GENERIC_IM_SERVER_URL || 'https://api.example.com');
const username = process.env.GENERIC_IM_SMOKE_USERNAME || 'h5test';
const password = process.env.GENERIC_IM_SMOKE_PASSWORD || '123456';
const peerUsername = process.env.GENERIC_IM_SMOKE_PEER_USERNAME || 'h5peer';
const peerPassword = process.env.GENERIC_IM_SMOKE_PEER_PASSWORD || '123456';
const buildDir = resolve(process.env.GENERIC_IM_WEB_BUILD_DIR || 'build/web');
const imagePath = resolve(process.env.GENERIC_IM_SMOKE_IMAGE || 'web/icons/Icon-192.png');
const chromePath = process.env.CHROME_PATH ||
  'C:\\Users\\MSI\\AppData\\Local\\Google\\Chrome\\Application\\chrome.exe';
const artifactDir = resolve(process.env.GENERIC_IM_SMOKE_ARTIFACT_DIR || 'artifacts/web-image-smoke');
const externalWebUrl = process.env.GENERIC_IM_WEB_URL || '';

async function main() {
  assert(existsSync(join(buildDir, 'index.html')), `Missing Flutter Web build: ${buildDir}`);
  assert(existsSync(imagePath), `Missing test image: ${imagePath}`);
  assert(existsSync(chromePath), `Missing Chrome: ${chromePath}`);
  mkdirSync(artifactDir, { recursive: true });

  const sender = await loginOrCreate(username, password, 'sender');
  const peer = await loginOrCreate(peerUsername, peerPassword, 'peer');
  const chatId = await ensurePrivateChat(sender, peer);
  const baselineMessages = await listMessages(sender.token, chatId);
  const baselineIds = new Set(
    baselineMessages.map((item) => String(item?.msg_id)),
  );
  const upload = await uploadImage(sender.token);
  const sent = await sendImage(sender.token, chatId, upload);
  const stored = await waitForStoredMessage(sender.token, chatId, sent.msgId);
  const mediaUrl = absoluteMediaUrl(stored.content.media.url);
  baselineIds.add(String(sent.msgId));

  const server = externalWebUrl ? null : await startStaticServer();
  const webUrl = externalWebUrl || `http://127.0.0.1:${server.port}/`;
  let browser;
  try {
    const media = await checkMedia(mediaUrl, webUrl);
    browser = await launchChrome(webUrl, sender, chatId, peer);
    const uiSend = await sendImageThroughFlutterUi(
      browser.client,
      sender.token,
      chatId,
      baselineIds,
    );
    const uiAccess = await accessURL(uiSend.mediaId, sender.token);
    const uiMedia = await checkMedia(uiAccess.url, webUrl);
    const chrome = await verifyInChrome(
      browser.client,
      uiAccess.url,
      uiSend.msgId,
    );
    const screenshotPath = join(artifactDir, `image-message-${Date.now()}.png`);
    const screenshot = await browser.client.send('Page.captureScreenshot', {
      format: 'png',
      captureBeyondViewport: false,
    });
    writeFileSync(screenshotPath, Buffer.from(screenshot.data, 'base64'));

    const fatalLogs = browser.logs.filter((entry) =>
      entry.source === 'exception' || /upload\/image|message\/send|image.*(fail|error)|null check/i.test(entry.text),
    );
    console.log(JSON.stringify({
      ok: true,
      apiBase,
      webUrl,
      chatId,
      upload,
      sent,
      stored: {
        msgId: stored.msg_id,
        type: stored.type,
        media: stored.content.media,
      },
      media,
      uiMedia,
      chrome,
      uiSend,
      accessibilityNames: browser.accessibilityNames,
      attachmentMenuNames: browser.attachmentMenuNames,
      fatalLogs,
      apiNetwork: browser.network.filter((entry) => /api\.example\.com\/api\/v1\/(message|upload|call|auth)/.test(entry.url)),
      screenshotPath,
    }, null, 2));
    if (!chrome.decoded || chrome.width <= 0 || chrome.height <= 0) {
      throw new Error(`Chrome did not decode the uploaded image: ${JSON.stringify(chrome)}`);
    }
  } finally {
    await browser?.cleanup();
    await server?.close();
  }
}

async function sendImageThroughFlutterUi(client, token, chatId, baselineIds) {
  await client.send('Page.setInterceptFileChooserDialog', { enabled: true });
  const chooserPromise = new Promise((resolvePromise, reject) => {
    const timer = setTimeout(() => reject(new Error('Timed out waiting for the Flutter image file chooser')), 10000);
    client.on('Page.fileChooserOpened', (event) => { clearTimeout(timer); resolvePromise(event); });
  });
  await clickAxLabel(client, ['相册', 'Album', 'Gallery']);
  const chooser = await chooserPromise;
  assert(chooser?.backendNodeId, `File chooser did not expose an input node: ${JSON.stringify(chooser)}`);
  await client.send('DOM.setFileInputFiles', { files: [imagePath], backendNodeId: chooser.backendNodeId });
  await client.send('Page.setInterceptFileChooserDialog', { enabled: false });
  await sleep(1800);

  const names = await getAxNames(client);
  if (names.some((name) => name === '发送' || name === 'Send')) {
    await clickAxLabel(client, ['发送', 'Send']);
  }

  for (let attempt = 0; attempt < 30; attempt += 1) {
    const body = await jsonRequest(`/api/v1/message/list?chat_id=${encodeURIComponent(chatId)}&page=1&page_size=50`, { token });
    const list = Array.isArray(body?.data) ? body.data : (body?.data?.list || []);
    const found = list.find((item) =>
      item?.type === 2 &&
      item?.content?.media?.url &&
      item?.content?.media?.media_id &&
      !baselineIds.has(String(item?.msg_id)),
    );
    if (found) {
      return {
        ok: true,
        msgId: String(found.msg_id),
        mediaId: String(found.content.media.media_id),
        mediaUrl: found.content.media.url,
        previewNames: names,
      };
    }
    await sleep(500);
  }
  throw new Error(`Flutter UI did not send a second image message; preview semantics: ${JSON.stringify(names)}`);
}

async function listMessages(token, chatId) {
  const body = await jsonRequest(
    `/api/v1/message/list?chat_id=${encodeURIComponent(chatId)}&page=1&page_size=100`,
    { token },
  );
  return Array.isArray(body?.data) ? body.data : body?.data?.list || [];
}

async function accessURL(mediaId, token) {
  const body = await jsonRequest(
    `/api/v1/media/${encodeURIComponent(mediaId)}/access-url`,
    { token },
  );
  assert(body?.code === 0 && body?.data?.url, `Access URL failed for ${mediaId}`);
  return body.data;
}

async function getAxNames(client) {
  const tree = await client.send('Accessibility.getFullAXTree');
  return [...new Set((tree?.nodes || []).map((node) => String(node?.name?.value || '').trim()).filter(Boolean))];
}

async function clickAxLabel(client, candidates) {
  const tree = await client.send('Accessibility.getFullAXTree');
  const matches = (tree?.nodes || []).filter((node) => {
    const name = String(node?.name?.value || '');
    return node?.backendDOMNodeId && candidates.some((candidate) => name === candidate || name.includes(candidate));
  });
  const node = matches.find((item) => String(item?.role?.value || '') === 'button') || matches[0];
  assert(node, `Accessibility control not found: ${JSON.stringify(candidates)}`);
  const resolved = await client.send('DOM.resolveNode', { backendNodeId: node.backendDOMNodeId });
  const objectId = resolved?.object?.objectId;
  assert(objectId, `Could not resolve accessibility control: ${JSON.stringify(candidates)}`);
  const result = await client.send('Runtime.callFunctionOn', {
    objectId,
    functionDeclaration: `function() { const r = this.getBoundingClientRect(); return { left: r.left, top: r.top, width: r.width, height: r.height }; }`,
    returnByValue: true,
  });
  const rect = result?.result?.value;
  assert(rect && rect.width > 0 && rect.height > 0, `Accessibility control has no clickable bounds: ${JSON.stringify(candidates)}`);
  await clickAt(client, rect.left + rect.width / 2, rect.top + rect.height / 2);
}

async function login(loginUsername, loginPassword, label) {
  const body = await jsonRequest('/api/v1/auth/login', {
    method: 'POST',
    data: {
      username: loginUsername,
      password: loginPassword,
      device_id: `web-image-smoke-${label}-${Date.now()}`,
      device_type: 'web',
      device_name: `Flutter Web Image Smoke ${label}`,
    },
  });
  assert(body?.code === 0 && body?.data?.token, `Login failed for ${loginUsername}: ${JSON.stringify(body)}`);
  const me = await jsonRequest('/api/v1/user/me', { token: body.data.token });
  assert(me?.code === 0 && (me?.data?.uuid || me?.data?.id), `/user/me failed for ${loginUsername}`);
  return {
    username: loginUsername,
    token: body.data.token,
    user: { uuid: String(me.data.uuid || me.data.id), raw: me.data },
  };
}

async function loginOrCreate(preferredUsername, loginPassword, label) {
  try {
    return await login(preferredUsername, loginPassword, label);
  } catch (error) {
    if (process.env.GENERIC_IM_SMOKE_USERNAME || process.env.GENERIC_IM_SMOKE_PEER_USERNAME) {
      throw error;
    }
    const suffix = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
    const createdUsername = `imgqa${label === 'sender' ? 'a' : 'b'}${suffix}`.slice(0, 20);
    const body = await jsonRequest('/api/v1/auth/register', {
      method: 'POST',
      data: {
        username: createdUsername,
        password: loginPassword,
        nickname: `Image QA ${label}`,
        gender: 'male',
        device_id: `web-image-smoke-register-${label}-${Date.now()}`,
        device_type: 'web',
        device_name: `Flutter Web Image Smoke ${label}`,
      },
    });
    assert(body?.code === 0, `Register fallback failed for ${label}: ${JSON.stringify(body)}`);
    return login(createdUsername, loginPassword, label);
  }
}

async function ensurePrivateChat(sender, peer) {
  const body = await jsonRequest('/api/v1/chat/create', {
    method: 'POST', token: sender.token, data: { type: 1, member_ids: [peer.user.uuid] },
  });
  const chatId = body?.data?.uuid || body?.data?.id || body?.data?.chat_id;
  assert(body?.code === 0 && chatId, `Create private chat failed: ${JSON.stringify(body)}`);
  return String(chatId);
}

async function uploadImage(token) {
  const bytes = readFileSync(imagePath);
  const extension = extname(imagePath).toLowerCase().replace('.', '') || 'png';
  const mimeType = extension === 'jpg' || extension === 'jpeg'
    ? 'image/jpeg'
    : extension === 'webp' ? 'image/webp'
      : extension === 'avif' ? 'image/avif' : 'image/png';
  const form = new FormData();
  form.append('file', new Blob([bytes], { type: mimeType }), `web_image_smoke_${Date.now()}.${extension}`);
  const response = await fetch(`${apiBase}/api/v1/upload/image`, {
    method: 'POST', headers: { Authorization: `Bearer ${token}`, Origin: 'http://127.0.0.1:5185' }, body: form,
  });
  const body = await response.json();
  assert(response.ok && body?.code === 0 && body?.data?.url,
    `Image upload failed HTTP ${response.status}: ${JSON.stringify(body)}`);
  return {
    url: body.data.url,
    filename: body.data.filename,
    size: Number(body.data.size || bytes.length),
    type: body.data.type || 'image/png',
    mimeType,
    sourceBytes: bytes.length,
  };
}

async function sendImage(token, chatId, upload) {
  const msgId = `web-image-smoke-${Date.now()}`;
  const body = await jsonRequest('/api/v1/message/send', {
    method: 'POST', token, data: {
      chat_id: chatId,
      type: 2,
      msg_id: msgId,
      content: { media: { url: upload.url, size: upload.size, mime_type: upload.mimeType, width: 192, height: 192 } },
    },
  });
  assert(body?.code === 0, `Image message send failed: ${JSON.stringify(body)}`);
  return { msgId: String(body?.data?.msg_id || msgId), seq: body?.data?.seq, type: body?.data?.type };
}

async function waitForStoredMessage(token, chatId, msgId) {
  for (let attempt = 0; attempt < 12; attempt += 1) {
    const body = await jsonRequest(`/api/v1/message/list?chat_id=${encodeURIComponent(chatId)}&page=1&page_size=50`, { token });
    const list = Array.isArray(body?.data) ? body.data : (body?.data?.list || []);
    const found = list.find((item) => String(item?.msg_id) === msgId);
    if (found?.type === 2 && found?.content?.media?.url) return found;
    await sleep(500);
  }
  throw new Error(`Sent image message ${msgId} was not returned by message/list`);
}

async function checkMedia(mediaUrl, webUrl) {
  const response = await fetch(mediaUrl, { headers: { Origin: new URL(webUrl).origin } });
  const bytes = Buffer.from(await response.arrayBuffer());
  const contentType = response.headers.get('content-type') || '';
  const allowOrigin = response.headers.get('access-control-allow-origin') || '';
  assert(response.ok, `Uploaded image GET failed: HTTP ${response.status}`);
  assert(contentType.startsWith('image/'), `Uploaded image has bad Content-Type: ${contentType}`);
  assert(bytes.length > 100, `Uploaded image is unexpectedly small: ${bytes.length}`);
  assert(allowOrigin === '*' || allowOrigin === new URL(webUrl).origin,
    `Uploaded image CORS does not allow local H5: ${allowOrigin || '(missing)'}`);
  return { url: mediaUrl, status: response.status, contentType, allowOrigin, bytes: bytes.length };
}

async function startStaticServer() {
  const port = await freePort();
  const mime = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.json': 'application/json', '.wasm': 'application/wasm', '.png': 'image/png', '.svg': 'image/svg+xml', '.css': 'text/css' };
  const server = createServer((req, res) => {
    const pathname = decodeURIComponent(new URL(req.url, `http://${req.headers.host}`).pathname);
    const requested = normalize(join(buildDir, pathname));
    let file = requested.startsWith(buildDir) && existsSync(requested) && statSync(requested).isFile()
      ? requested : join(buildDir, 'index.html');
    res.setHeader('Content-Type', mime[extname(file).toLowerCase()] || 'application/octet-stream');
    res.setHeader('Cache-Control', 'no-store');
    createReadStream(file).pipe(res);
  });
  await new Promise((resolvePromise, reject) => server.listen(port, '127.0.0.1', resolvePromise).once('error', reject));
  return { port, close: () => new Promise((resolvePromise) => server.close(resolvePromise)) };
}

async function launchChrome(webUrl, session, chatId, peer) {
  const port = await freePort();
  const userDataDir = mkdtempSync(join(tmpdir(), 'genericim-web-image-smoke-'));
  const route = `${webUrl}#/chat/${encodeURIComponent(chatId)}?name=${encodeURIComponent(peer.user.raw.nickname || peer.username)}&type=private`;
  const child = spawn(chromePath, [
    '--headless=new', `--remote-debugging-port=${port}`, `--user-data-dir=${userDataDir}`,
    '--window-size=430,932', '--force-device-scale-factor=1', '--disable-extensions',
    '--disable-background-timer-throttling', '--no-first-run', '--no-default-browser-check', 'about:blank',
  ], { stdio: 'ignore', windowsHide: true });
  await waitForDebugPort(port);
  const version = await fetch(`http://127.0.0.1:${port}/json/version`).then((r) => r.json());
  const browser = await connectCDP(version.webSocketDebuggerUrl);
  const target = await browser.send('Target.createTarget', { url: 'about:blank' });
  const page = await waitForPageTarget(port, target.targetId);
  const client = await connectCDP(page.webSocketDebuggerUrl);
  const logs = [];
  const network = [];
  client.on('Runtime.exceptionThrown', (p) => logs.push({ source: 'exception', text: p?.exceptionDetails?.exception?.description || p?.exceptionDetails?.text || '' }));
  client.on('Runtime.consoleAPICalled', (p) => logs.push({ source: 'console', text: (p?.args || []).map((x) => x.value ?? x.description ?? '').join(' ') }));
  client.on('Network.responseReceived', (p) => {
    if (!p?.response?.url?.includes('api.example.com')) return;
    network.push({ requestId: p.requestId, url: p.response.url, status: p.response.status, mimeType: p.response.mimeType });
  });
  client.on('Network.loadingFailed', (p) => network.push({ requestId: p.requestId, url: '', failed: true, errorText: p.errorText }));
  await client.send('Page.enable');
  await client.send('Runtime.enable');
  await client.send('Network.enable');
  await client.send('DOM.enable');
  await client.send('Accessibility.enable');
  await client.send('Page.addScriptToEvaluateOnNewDocument', { source: authScript(session) });
  await client.send('Page.navigate', { url: route });
  await waitForRuntime(client, `!!document.querySelector('flt-glass-pane, flutter-view, flt-scene-host')`, 30000, 'Flutter root');
  await waitForRuntime(client, `location.hash.includes('/chat/${chatId}')`, 15000, 'chat route');
  await client.send('Runtime.evaluate', {
    expression: `(() => { const node = document.querySelector('flt-semantics-placeholder'); if (node) node.click(); return !!node; })()`,
    returnByValue: true,
  });
  await sleep(9000);
  const axTree = await client.send('Accessibility.getFullAXTree');
  const accessibilityNames = [...new Set((axTree?.nodes || []).map((node) => String(node?.name?.value || '').trim()).filter(Boolean))];
  await clickAt(client, 28, 808);
  await sleep(900);
  const attachmentTree = await client.send('Accessibility.getFullAXTree');
  const attachmentMenuNames = [...new Set((attachmentTree?.nodes || []).map((node) => String(node?.name?.value || '').trim()).filter(Boolean))];
  return {
    client, logs, network, accessibilityNames, attachmentMenuNames,
    cleanup: async () => {
      client.close();
      try { await browser.send('Target.closeTarget', { targetId: target.targetId }); } catch {}
      browser.close(); child.kill(); await sleep(400);
      try { rmSync(userDataDir, { recursive: true, force: true }); } catch {}
    },
  };
}

async function verifyInChrome(client, mediaUrl, msgId) {
  const result = await client.send('Runtime.evaluate', {
    expression: `(() => new Promise((resolve) => {
      const img = new Image();
       img.onload = () => resolve({ decoded: true, width: img.naturalWidth, height: img.naturalHeight, href: location.href, msgId: ${JSON.stringify(msgId)} });
      img.onerror = (event) => resolve({ decoded: false, error: String(event?.type || 'error'), href: location.href });
      img.src = ${JSON.stringify(mediaUrl)} + (${JSON.stringify(mediaUrl)}.includes('?') ? '&' : '?') + 'smoke=' + Date.now();
    }))()`, awaitPromise: true, returnByValue: true,
  });
  return result?.result?.value || { decoded: false, error: 'missing Runtime.evaluate result' };
}

function authScript(session) {
  const raw = { ...session.user.raw, uuid: session.user.uuid, id: String(session.user.raw.id || session.user.uuid), username: session.username };
  return `(() => {
    localStorage.setItem('flutter.auth_token', JSON.stringify(${JSON.stringify(session.token)}));
    localStorage.setItem('flutter.user_id', JSON.stringify(${JSON.stringify(session.user.uuid)}));
    localStorage.setItem('flutter.auth_user_data', JSON.stringify(${JSON.stringify(JSON.stringify(raw))}));
  })();`;
}

async function jsonRequest(path, { method = 'GET', token = '', data } = {}) {
  const response = await fetch(`${apiBase}${path}`, {
    method,
    headers: { ...(data ? { 'Content-Type': 'application/json' } : {}), ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: data ? JSON.stringify(data) : undefined,
  });
  const text = await response.text();
  let body;
  try { body = JSON.parse(text); } catch { throw new Error(`${method} ${path} returned non-JSON HTTP ${response.status}: ${text.slice(0, 300)}`); }
  if (!response.ok) throw new Error(`${method} ${path} failed HTTP ${response.status}: ${text.slice(0, 500)}`);
  return body;
}

function absoluteMediaUrl(value) { return new URL(value, `${apiBase}/`).toString(); }
function trim(value) { return value.replace(/\/+$/, ''); }
function assert(condition, message) { if (!condition) throw new Error(message); }
function sleep(ms) { return new Promise((resolvePromise) => setTimeout(resolvePromise, ms)); }

async function clickAt(client, x, y) {
  await client.send('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', clickCount: 1 });
  await client.send('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', clickCount: 1 });
}

async function freePort() {
  return new Promise((resolvePromise, reject) => {
    const server = createNetServer();
    server.listen(0, '127.0.0.1', () => { const port = server.address().port; server.close(() => resolvePromise(port)); });
    server.once('error', reject);
  });
}

async function waitForDebugPort(port) {
  for (let i = 0; i < 80; i += 1) {
    try { const response = await fetch(`http://127.0.0.1:${port}/json/version`); if (response.ok) return; } catch {}
    await sleep(150);
  }
  throw new Error(`Chrome debugging port ${port} did not open`);
}

async function waitForPageTarget(port, targetId) {
  for (let i = 0; i < 80; i += 1) {
    const pages = await fetch(`http://127.0.0.1:${port}/json/list`).then((r) => r.json());
    const page = pages.find((item) => item.id === targetId);
    if (page?.webSocketDebuggerUrl) return page;
    await sleep(150);
  }
  throw new Error(`Chrome target ${targetId} was not ready`);
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
  const ws = new WebSocket(url);
  const pending = new Map();
  const listeners = new Map();
  let id = 1;
  await new Promise((resolvePromise, reject) => { ws.addEventListener('open', resolvePromise, { once: true }); ws.addEventListener('error', reject, { once: true }); });
  ws.addEventListener('message', (event) => {
    const message = JSON.parse(event.data);
    if (message.id && pending.has(message.id)) {
      const item = pending.get(message.id); pending.delete(message.id);
      message.error ? item.reject(new Error(JSON.stringify(message.error))) : item.resolve(message.result);
    } else if (message.method) {
      for (const callback of listeners.get(message.method) || []) callback(message.params || {});
    }
  });
  return {
    send(method, params = {}) { const current = id++; ws.send(JSON.stringify({ id: current, method, params })); return new Promise((resolvePromise, reject) => pending.set(current, { resolve: resolvePromise, reject })); },
    on(method, callback) { const list = listeners.get(method) || []; list.push(callback); listeners.set(method, list); },
    close() { ws.close(); },
  };
}

main().catch((error) => { console.error(error?.stack || String(error)); process.exitCode = 1; });
