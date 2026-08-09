#!/usr/bin/env node

import { existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { createServer as createNetServer } from 'node:net';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { spawn } from 'node:child_process';

const apiBase = trim(process.env.GENERIC_IM_SERVER_URL || 'http://127.0.0.1:8080');
const webUrl = trim(process.env.GENERIC_IM_H5_URL || 'http://127.0.0.1:5176');
const senderUsername = process.env.GENERIC_IM_SMOKE_USERNAME || 'smoke_alice';
const receiverUsername = process.env.GENERIC_IM_SMOKE_PEER_USERNAME || 'smoke_bob';
const password = process.env.GENERIC_IM_SMOKE_PASSWORD || 'Smoke123';
const imagePath = resolve(
  process.env.GENERIC_IM_SMOKE_IMAGE || 'web/icons/Icon-192.png',
);
const videoPath = resolve(
  process.env.GENERIC_IM_SMOKE_VIDEO ||
    'artifacts/p1-s3-acceptance-20260727/p1-playable-100m.mp4',
);
const artifactDir = resolve(
  process.env.GENERIC_IM_SMOKE_ARTIFACT_DIR ||
    'artifacts/cross-platform-media-acceptance-20260728/h5',
);
const existingImageMessageId =
  process.env.GENERIC_IM_SMOKE_EXISTING_IMAGE_MSG_ID || '';
const existingVideoMessageId =
  process.env.GENERIC_IM_SMOKE_EXISTING_VIDEO_MSG_ID || '';
const configuredChatId = process.env.GENERIC_IM_SMOKE_CHAT_ID || '';
const configuredChatType = process.env.GENERIC_IM_SMOKE_CHAT_TYPE || 'private';
const viewportWidth = Number(process.env.GENERIC_IM_SMOKE_VIEWPORT_WIDTH || 430);
const viewportHeight = Number(process.env.GENERIC_IM_SMOKE_VIEWPORT_HEIGHT || 932);
const expectedStorageProvider = (
  process.env.GENERIC_IM_EXPECT_STORAGE_PROVIDER || 's3'
).trim().toLowerCase();
const chromePath =
  process.env.CHROME_PATH ||
  'C:\\Users\\MSI\\AppData\\Local\\Google\\Chrome\\Application\\chrome.exe';
const existingOnly = process.env.GENERIC_IM_SMOKE_EXISTING_ONLY === '1';
const revokedOnly = process.env.GENERIC_IM_SMOKE_REVOKED_ONLY === '1';
const revokedMessageId = process.env.GENERIC_IM_SMOKE_REVOKED_MSG_ID || '';

async function main() {
  assert(existsSync(imagePath), `Missing image fixture: ${imagePath}`);
  assert(existsSync(videoPath), `Missing video fixture: ${videoPath}`);
  assert(existsSync(chromePath), `Missing Chrome: ${chromePath}`);
  mkdirSync(artifactDir, { recursive: true });

  const sender = await login(senderUsername, 'sender');
  const receiver = await login(receiverUsername, 'receiver');
  const chatId = configuredChatId || (await ensurePrivateChat(sender, receiver));
  const baseline = await listMessages(sender.token, chatId);
  const baselineIds = new Set(baseline.map((item) => String(item.msg_id)));

  if (revokedOnly) {
    await verifyRevokedMessage(sender, receiver, chatId);
    return;
  }

  if (existingOnly) {
    await verifyExistingMedia(sender, receiver, chatId, baseline);
    return;
  }

  const senderBrowser = await launchBrowser(sender, chatId);
  let receiverBrowser;
  let senderBrowserCleaned = false;
  let stage = 'sender image upload';
  try {
    progress(stage);
    await chooseFile(senderBrowser.client, 'input[type=file][multiple]', imagePath);
    const imageMessage = await waitForNewMediaMessage(
      sender.token,
      chatId,
      baselineIds,
      2,
      120_000,
    );
    baselineIds.add(String(imageMessage.msg_id));
    assertMediaIds(imageMessage, false);
    const senderImage = await verifyImageMessage(
      senderBrowser.client,
      imageMessage,
    );

    stage = 'sender video upload';
    progress(stage);
    await chooseFile(
      senderBrowser.client,
      'input[type=file][accept^="video"]',
      videoPath,
    );
    const videoMessage = await waitForNewMediaMessage(
      sender.token,
      chatId,
      baselineIds,
      3,
      12 * 60_000,
    );
    assertMediaIds(videoMessage, true);
    const senderVideo = await verifyVideoMessage(
      senderBrowser.client,
      videoMessage,
    );
    const senderScreenshot = await captureScreenshot(
      senderBrowser.client,
      'sender-media.png',
    );

    stage = 'receiver media rendering';
    progress(stage);
    await senderBrowser.cleanup();
    senderBrowserCleaned = true;
    receiverBrowser = await launchBrowser(receiver, chatId);
    const receiverImage = await verifyImageMessage(
      receiverBrowser.client,
      imageMessage,
    );
    const receiverVideo = await verifyVideoMessage(
      receiverBrowser.client,
      videoMessage,
    );
    const receiverScreenshot = await captureScreenshot(
      receiverBrowser.client,
      'receiver-media.png',
    );
    assertNoBrowserErrors(senderBrowser, 'sender');
    assertNoBrowserErrors(receiverBrowser, 'receiver');

    const uploadRequests = senderBrowser.network.filter(
      (entry) =>
        entry.url.includes('/media/uploads/') ||
        entry.url.includes('/upload/image') ||
        entry.url.includes('/upload/video') ||
        entry.method === 'PUT' ||
        entry.url.includes('/access-url'),
    );
    assertExpectedUploadPath(uploadRequests);

    const result = {
      ok: true,
      apiBase,
      webUrl,
      chatId,
      expectedStorageProvider,
      fixtures: { imagePath, videoPath },
      imageMessage: messageEvidence(imageMessage),
      videoMessage: messageEvidence(videoMessage),
      sender: {
        image: senderImage,
        video: senderVideo,
        screenshot: senderScreenshot,
      },
      receiver: {
        image: receiverImage,
        video: receiverVideo,
        screenshot: receiverScreenshot,
      },
      uploadRequests,
      senderErrors: senderBrowser.errors,
      receiverErrors: receiverBrowser.errors,
    };
    const resultPath = join(artifactDir, 'h5-media-acceptance.json');
    writeFileSync(resultPath, `${JSON.stringify(result, null, 2)}\n`);
    progress('completed');
    console.log(JSON.stringify({ ...result, resultPath }, null, 2));
  } catch (error) {
    const failedScreenshot = await captureScreenshot(
      senderBrowser.client,
      'sender-failure.png',
    ).catch(() => '');
    const failure = {
      ok: false,
      stage,
      error: error?.stack || String(error),
      failedScreenshot,
      network: relevantNetwork(senderBrowser.network),
      senderErrors: senderBrowser.errors,
      senderWebSocketFrames: senderBrowser.webSocketFrames,
      receiverNetwork: relevantNetwork(receiverBrowser?.network || []),
      receiverErrors: receiverBrowser?.errors || [],
      receiverWebSocketFrames: receiverBrowser?.webSocketFrames || [],
    };
    writeFileSync(
      join(artifactDir, 'h5-media-failure.json'),
      `${JSON.stringify(failure, null, 2)}\n`,
    );
    throw error;
  } finally {
    await receiverBrowser?.cleanup();
    if (!senderBrowserCleaned) {
      await senderBrowser.cleanup();
    }
  }
}

async function verifyRevokedMessage(sender, receiver, chatId) {
  assert(revokedMessageId, 'GENERIC_IM_SMOKE_REVOKED_MSG_ID is required');
  const artifactName = 'h5-revoked-message-acceptance.json';
  let senderBrowser;
  let receiverBrowser;
  try {
    const senderState = await readMessageState(
      sender.token,
      chatId,
      revokedMessageId,
    );
    const receiverState = await readMessageState(
      receiver.token,
      chatId,
      revokedMessageId,
    );
    assert(senderState?.is_revoked === true, 'Sender API state is not revoked');
    assert(
      receiverState?.is_revoked === true,
      'Receiver API state is not revoked',
    );

    senderBrowser = await launchBrowser(sender, chatId);
    await sleep(1_500);
    const senderBeforeRefresh = await captureScreenshot(
      senderBrowser.client,
      'sender-revoked-before-refresh.png',
    );
    await senderBrowser.client.send('Page.reload', { ignoreCache: true });
    await waitForChatRoute(senderBrowser.client, chatId);
    const senderAfterRefresh = await captureScreenshot(
      senderBrowser.client,
      'sender-revoked-after-refresh.png',
    );

    receiverBrowser = await launchBrowser(receiver, chatId);
    await sleep(1_500);
    const receiverBeforeRefresh = await captureScreenshot(
      receiverBrowser.client,
      'receiver-revoked-before-refresh.png',
    );
    await receiverBrowser.client.send('Page.reload', { ignoreCache: true });
    await waitForChatRoute(receiverBrowser.client, chatId);
    const receiverAfterRefresh = await captureScreenshot(
      receiverBrowser.client,
      'receiver-revoked-after-refresh.png',
    );
    assertNoBrowserErrors(senderBrowser, 'sender after revoke refresh');
    assertNoBrowserErrors(receiverBrowser, 'receiver after revoke refresh');

    const result = {
      ok: true,
      mode: 'revoked-only',
      chatId,
      messageId: revokedMessageId,
      senderState,
      receiverState,
      sender: {
        beforeRefresh: senderBeforeRefresh,
        afterRefresh: senderAfterRefresh,
        ...browserEvidence(senderBrowser),
      },
      receiver: {
        beforeRefresh: receiverBeforeRefresh,
        afterRefresh: receiverAfterRefresh,
        ...browserEvidence(receiverBrowser),
      },
    };
    const resultPath = join(artifactDir, artifactName);
    writeFileSync(resultPath, `${JSON.stringify(result, null, 2)}\n`);
    console.log(JSON.stringify({ ...result, resultPath }, null, 2));
  } finally {
    await receiverBrowser?.cleanup();
    await senderBrowser?.cleanup();
  }
}

async function readMessageState(token, chatId, messageId) {
  const messages = await listMessages(token, chatId);
  return messages.find((item) => String(item?.msg_id) === String(messageId));
}

async function waitForChatRoute(client, chatId) {
  await waitForRuntimeValue(
    client,
    `(() => ({
      route: location.hash,
      ready: !!document.querySelector('flt-glass-pane, flutter-view, flt-scene-host')
    }))()`,
    (value) => value?.route.includes(`/chat/${chatId}`) && value?.ready,
    45_000,
    'Flutter Web chat page after refresh',
  );
  await sleep(1_000);
}

async function verifyExistingMedia(sender, receiver, chatId, messages) {
  const imageMessage = messages.find(
    (item) =>
      (!existingImageMessageId ||
        String(item?.msg_id) === existingImageMessageId) &&
      Number(item?.type) === 2 &&
      item?.content?.media?.media_id,
  );
  const videoMessage = messages.find(
    (item) =>
      (!existingVideoMessageId ||
        String(item?.msg_id) === existingVideoMessageId) &&
      Number(item?.type) === 3 &&
      item?.content?.media?.media_id &&
      item?.content?.media?.thumbnail_media_id,
  );
  assert(imageMessage, 'No existing image message with media_id');
  assert(videoMessage, 'No existing video message with thumbnail_media_id');

  let senderBrowser;
  let receiverBrowser;
  try {
    progress('existing sender media rendering');
    senderBrowser = await launchBrowser(sender, chatId);
    const senderImage = await verifyImageMessage(senderBrowser.client, imageMessage);
    const senderVideo = await verifyVideoMessage(senderBrowser.client, videoMessage);
    await prepareVideoPosterScreenshot(senderBrowser.client, videoMessage);
    const senderScreenshot = await captureScreenshot(
      senderBrowser.client,
      'sender-existing-media.png',
    );
    const senderEvidence = browserEvidence(senderBrowser);
    assertNoBrowserErrors(senderBrowser, 'sender existing media');
    await senderBrowser.cleanup();
    senderBrowser = null;

    progress('existing receiver media rendering');
    receiverBrowser = await launchBrowser(receiver, chatId);
    progress('existing receiver image decode');
    const receiverImage = await verifyImageMessage(
      receiverBrowser.client,
      imageMessage,
    );
    progress('existing receiver video poster and playback');
    const receiverVideo = await verifyVideoMessage(
      receiverBrowser.client,
      videoMessage,
    );
    await prepareVideoPosterScreenshot(receiverBrowser.client, videoMessage);
    const receiverScreenshot = await captureScreenshot(
      receiverBrowser.client,
      'receiver-existing-media.png',
    );
    const result = {
      ok: true,
      mode: 'existing-only',
      chatId,
      imageMessage: messageEvidence(imageMessage),
      videoMessage: messageEvidence(videoMessage),
      sender: {
        image: senderImage,
        video: senderVideo,
        screenshot: senderScreenshot,
        ...senderEvidence,
      },
      receiver: {
        image: receiverImage,
        video: receiverVideo,
        screenshot: receiverScreenshot,
        ...browserEvidence(receiverBrowser),
      },
    };
    assertNoBrowserErrors(receiverBrowser, 'receiver existing media');
    const resultPath = join(artifactDir, 'h5-existing-media-acceptance.json');
    writeFileSync(resultPath, `${JSON.stringify(result, null, 2)}\n`);
    progress('existing media completed');
    console.log(JSON.stringify({ ...result, resultPath }, null, 2));
  } catch (error) {
    const failure = {
      ok: false,
      mode: 'existing-only',
      error: error?.stack || String(error),
      sender: senderBrowser ? browserEvidence(senderBrowser) : null,
      receiver: receiverBrowser ? browserEvidence(receiverBrowser) : null,
    };
    writeFileSync(
      join(artifactDir, 'h5-existing-media-failure.json'),
      `${JSON.stringify(failure, null, 2)}\n`,
    );
    throw error;
  } finally {
    await receiverBrowser?.cleanup();
    await senderBrowser?.cleanup();
  }
}

async function login(username, label) {
  const body = await request('/api/v1/auth/login', {
    method: 'POST',
    data: {
      username,
      password,
      device_id: `h5-media-${label}-${Date.now()}`,
      device_type: 'web',
      device_name: `H5 Media Acceptance ${label}`,
    },
  });
  assert(body?.code === 0 && body?.data?.token, `Login failed for ${username}`);
  const me = await request('/api/v1/user/me', { token: body.data.token });
  assert(me?.code === 0 && me?.data?.uuid, `user/me failed for ${username}`);
  return { username, token: body.data.token, user: me.data };
}

async function ensurePrivateChat(sender, receiver) {
  const body = await request('/api/v1/chat/create', {
    method: 'POST',
    token: sender.token,
    data: { type: 1, member_ids: [receiver.user.uuid] },
  });
  const chatId = body?.data?.uuid || body?.data?.chat_id || body?.data?.id;
  assert(body?.code === 0 && chatId, `Create private chat failed: ${JSON.stringify(body)}`);
  return String(chatId);
}

async function listMessages(token, chatId) {
  const body = await request(
    `/api/v1/message/list?chat_id=${encodeURIComponent(chatId)}&page=1&page_size=100`,
    { token },
  );
  return Array.isArray(body?.data) ? body.data : body?.data?.list || [];
}

async function waitForNewMediaMessage(
  token,
  chatId,
  baselineIds,
  type,
  timeoutMs,
) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const messages = await listMessages(token, chatId);
    const found = messages.find(
      (item) =>
        Number(item?.type) === type &&
        !baselineIds.has(String(item?.msg_id)) &&
        item?.content?.media?.url,
    );
    if (found) return found;
    await sleep(4_000);
  }
  throw new Error(`Timed out waiting for H5 media message type ${type}`);
}

function assertMediaIds(message, needsThumbnail) {
  const media = message?.content?.media || {};
  assert(media.media_id, `Message ${message.msg_id} has no media_id`);
  if (needsThumbnail) {
    assert(
      media.thumbnail_media_id,
      `Video message ${message.msg_id} has no thumbnail_media_id`,
    );
  }
}

async function chooseFile(client, selector, filePath) {
  await client.send('Page.setInterceptFileChooserDialog', { enabled: true });
  const chooserPromise = new Promise((resolvePromise, reject) => {
    const timer = setTimeout(
      () => reject(new Error(`Timed out waiting for file chooser: ${selector}`)),
      15_000,
    );
    client.on('Page.fileChooserOpened', (event) => {
      clearTimeout(timer);
      resolvePromise(event);
    });
  });

  const viewport = await evaluate(
    client,
    '({ width: window.innerWidth, height: window.innerHeight })',
  );
  await clickAt(client, 28, Math.max(24, viewport.height - 24));
  await sleep(600);
  try {
    await clickAccessibilityLabel(client, ['相册', 'Album', 'Gallery']);
  } catch {
    // Flutter Web's CanvasKit semantics can omit the menu labels while the
    // visual controls remain available in the fixed mobile layout.
    await clickAt(client, 75, Math.max(24, viewport.height - 144));
  }
  const chooser = await chooserPromise;
  assert(
    chooser?.backendNodeId,
    `File chooser did not expose an input node: ${JSON.stringify(chooser)}`,
  );
  await client.send('DOM.setFileInputFiles', {
    files: [filePath],
    backendNodeId: chooser.backendNodeId,
  });
  await client.send('Page.setInterceptFileChooserDialog', { enabled: false });
  await sleep(1_000);
}

async function clickAccessibilityLabel(client, candidates) {
  const tree = await client.send('Accessibility.getFullAXTree');
  const matches = (tree?.nodes || []).filter((node) => {
    const name = String(node?.name?.value || '');
    return (
      node?.backendDOMNodeId &&
      candidates.some((candidate) => name === candidate || name.includes(candidate))
    );
  });
  const node =
    matches.find((item) => String(item?.role?.value || '') === 'button') ||
    matches[0];
  assert(node, `Accessibility control not found: ${JSON.stringify(candidates)}`);
  const resolved = await client.send('DOM.resolveNode', {
    backendNodeId: node.backendDOMNodeId,
  });
  const objectId = resolved?.object?.objectId;
  assert(objectId, `Could not resolve accessibility control: ${candidates.join(', ')}`);
  const bounds = await client.send('Runtime.callFunctionOn', {
    objectId,
    functionDeclaration:
      'function() { const r = this.getBoundingClientRect(); return { left: r.left, top: r.top, width: r.width, height: r.height }; }',
    returnByValue: true,
  });
  const rect = bounds?.result?.value;
  assert(
    rect && rect.width > 0 && rect.height > 0,
    `Accessibility control has no clickable bounds: ${candidates.join(', ')}`,
  );
  await clickAt(
    client,
    rect.left + rect.width / 2,
    rect.top + rect.height / 2,
  );
}

async function clickAt(client, x, y) {
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

async function verifyImageMessage(client, message) {
  const access = await accessURL(message.content.media.media_id, client.token);
  const value = await evaluate(
    client,
    `(() => new Promise((resolve) => {
      fetch(${JSON.stringify(access.url)})
        .then((response) => {
          if (!response.ok) throw new Error('HTTP ' + response.status);
          return response.blob();
        })
        .then((blob) => createImageBitmap(blob))
        .then((bitmap) => {
          const result = {
            found: true,
            complete: true,
            width: bitmap.width,
            height: bitmap.height,
            src: ${JSON.stringify(access.url)}
          };
          bitmap.close();
          resolve(result);
        })
        .catch((error) => resolve({
          found: false,
          complete: false,
          error: String(error)
        }));
    }))()`,
    true,
  );
  assert(
    value?.found && value?.complete && value?.width > 0 && value?.height > 0,
    `Image ${message.msg_id} did not decode: ${JSON.stringify(value)}`,
  );
  return {
    ...value,
    src: safeURL(value.src || ''),
  };
}

async function verifyVideoMessage(client, message) {
  const media = message.content.media;
  progress(`video ${message.msg_id}: resolve signed URLs`);
  const [videoAccess, thumbnailAccess] = await Promise.all([
    accessURL(media.media_id, client.token),
    accessURL(media.thumbnail_media_id, client.token),
  ]);
  progress(`video ${message.msg_id}: decode poster image`);
  const poster = await evaluate(
    client,
    `(() => fetch(${JSON.stringify(thumbnailAccess.url)})
      .then((response) => {
        if (!response.ok) throw new Error('HTTP ' + response.status);
        return response.blob();
      })
      .then((blob) => createImageBitmap(blob))
      .then((bitmap) => {
        const result = {
          decoded: true,
          width: bitmap.width,
          height: bitmap.height
        };
        bitmap.close();
        return result;
      })
      .catch((error) => ({ decoded: false, error: String(error) })))()`,
    true,
  );
  assert(poster?.decoded && poster.width > 0, 'Video poster did not decode');

  progress(`video ${message.msg_id}: start playback`);
  const playback = await evaluate(
    client,
    `(() => new Promise((resolve) => {
      fetch(${JSON.stringify(videoAccess.url)})
        .then((response) => {
          if (!response.ok) throw new Error('HTTP ' + response.status);
          return response.blob();
        })
        .then((blob) => {
          const objectUrl = URL.createObjectURL(blob);
          const video = document.createElement('video');
          video.muted = true;
          video.playsInline = true;
          video.preload = 'auto';
          video.style.cssText = 'position:fixed;left:-9999px;top:0;width:160px;height:90px';
          document.body.appendChild(video);
          const finish = (result) => {
            video.pause();
            video.remove();
            URL.revokeObjectURL(objectUrl);
            resolve(result);
          };
          const timer = setTimeout(() => finish({
            played: false,
            reason: 'timeout',
            readyState: video.readyState,
            currentTime: video.currentTime
          }), 30000);
          video.onerror = () => {
            clearTimeout(timer);
            finish({
              played: false,
              reason: 'media-error',
              mediaError: video.error ? {
                code: video.error.code,
                message: video.error.message
              } : null
            });
          };
          video.onloadedmetadata = async () => {
            try {
              await video.play();
              setTimeout(() => {
                clearTimeout(timer);
                finish({
                  played: video.currentTime > 0,
                  currentTime: video.currentTime,
                  paused: video.paused,
                  readyState: video.readyState,
                  width: video.videoWidth,
                  height: video.videoHeight,
                  duration: Number.isFinite(video.duration) ? video.duration : 0
                });
              }, 1500);
            } catch (error) {
              clearTimeout(timer);
              finish({ played: false, reason: String(error) });
            }
          };
          video.src = objectUrl;
          video.load();
        })
        .catch((error) => resolve({
          played: false,
          reason: String(error)
        }));
    }))()`,
    true,
  );
  assert(playback?.played, `Video did not play: ${JSON.stringify(playback)}`);
  progress(`video ${message.msg_id}: playback verified`);
  return {
    found: true,
    readyState: playback.readyState,
    videoWidth: playback.width,
    videoHeight: playback.height,
    duration: playback.duration,
    poster: safeURL(thumbnailAccess.url),
    posterMatches: true,
    posterDecode: poster,
    playback,
  };
}

async function prepareVideoPosterScreenshot(client, message) {
  await evaluate(client, `(() => {
    window.scrollTo(0, document.body.scrollHeight);
    return { found: true, messageId: ${JSON.stringify(message.msg_id)} };
  })()`);
  await sleep(750);
}

async function accessURL(mediaId, token) {
  const body = await request(
    `/api/v1/media/${encodeURIComponent(mediaId)}/access-url`,
    { token },
  );
  assert(body?.code === 0 && body?.data?.url, `Access URL failed for ${mediaId}`);
  return body.data;
}

async function launchBrowser(session, chatId) {
  const port = await freePort();
  const profile = mkdtempSync(join(tmpdir(), 'genericim-h5-media-'));
  const child = spawn(
    chromePath,
    [
      '--headless=new',
      `--remote-debugging-port=${port}`,
      `--user-data-dir=${profile}`,
      `--window-size=${viewportWidth},${viewportHeight}`,
      '--force-device-scale-factor=1',
      '--autoplay-policy=no-user-gesture-required',
      '--disable-background-timer-throttling',
      '--disable-extensions',
      '--enable-logging=stderr',
      '--no-first-run',
      '--no-default-browser-check',
      'about:blank',
    ],
    { stdio: ['ignore', 'ignore', 'pipe'], windowsHide: true },
  );
  const chromeLogs = [];
  child.stderr?.setEncoding('utf8');
  child.stderr?.on('data', (chunk) => {
    const lines = String(chunk)
      .split(/\r?\n/)
      .map(sanitizeChromeLog)
      .filter(Boolean);
    chromeLogs.push(...lines);
    if (chromeLogs.length > 200) chromeLogs.splice(0, chromeLogs.length - 200);
  });
  await waitForDebugPort(port);
  const version = await fetch(`http://127.0.0.1:${port}/json/version`).then(
    (response) => response.json(),
  );
  const browser = await connectCDP(version.webSocketDebuggerUrl);
  const lifecycle = [];
  child.on('exit', (code, signal) => {
    lifecycle.push({
      at: new Date().toISOString(),
      event: 'chrome.exit',
      code,
      signal,
    });
  });
  browser.on('Target.targetCrashed', (event) => {
    lifecycle.push({
      at: new Date().toISOString(),
      event: 'Target.targetCrashed',
      detail: event,
    });
  });
  browser.on('Target.targetDestroyed', (event) => {
    lifecycle.push({
      at: new Date().toISOString(),
      event: 'Target.targetDestroyed',
      detail: event,
    });
  });
  await browser.send('Target.setDiscoverTargets', { discover: true });
  const target = await browser.send('Target.createTarget', { url: 'about:blank' });
  const page = await waitForPageTarget(port, target.targetId);
  const client = await connectCDP(page.webSocketDebuggerUrl);
  client.token = session.token;
  const network = [];
  const requestMethods = new Map();
  const requestURLs = new Map();
  const errors = [];
  const consoleMessages = [];
  const navigations = [];
  const webSocketFrames = [];
  client.on('Network.responseReceived', (event) => {
    const method = requestMethods.get(event.requestId) || '';
    network.push({
      method,
      url: safeURL(event.response.url),
      status: event.response.status,
      statusText: event.response.statusText,
      mimeType: event.response.mimeType,
    });
  });
  client.on('Network.requestWillBeSent', (event) => {
    requestMethods.set(event.requestId, event.request.method);
    requestURLs.set(event.requestId, event.request.url);
    network.push({
      method: event.request.method,
      url: safeURL(event.request.url),
      status: 0,
    });
  });
  client.on('Network.loadingFailed', (event) => {
    network.push({
      method: requestMethods.get(event.requestId) || '',
      url: safeURL(requestURLs.get(event.requestId) || ''),
      status: -1,
      errorText: event.errorText,
      canceled: event.canceled,
      blockedReason: event.blockedReason,
      corsErrorStatus: event.corsErrorStatus,
    });
  });
  client.on('Runtime.exceptionThrown', (event) => {
    errors.push(event?.exceptionDetails?.exception?.description || event?.exceptionDetails?.text);
  });
  client.on('Runtime.consoleAPICalled', (event) => {
    consoleMessages.push({
      type: event.type,
      timestamp: event.timestamp,
      values: (event.args || []).map((item) => item.value ?? item.description ?? ''),
    });
  });
  client.on('Page.frameNavigated', (event) => {
    if (event.frame?.parentId) return;
    navigations.push({
      at: new Date().toISOString(),
      url: safeURL(event.frame?.url || ''),
    });
  });
  client.on('Inspector.targetCrashed', (event) => {
    lifecycle.push({
      at: new Date().toISOString(),
      event: 'Inspector.targetCrashed',
      detail: event,
    });
  });
  client.on('Inspector.detached', (event) => {
    lifecycle.push({
      at: new Date().toISOString(),
      event: 'Inspector.detached',
      detail: event,
    });
  });
  client.on('Network.webSocketFrameReceived', (event) => {
    const payload = String(event?.response?.payloadData || '');
    if (!payload) return;
    try {
      webSocketFrames.push(JSON.parse(payload));
    } catch {
      webSocketFrames.push(payload.slice(0, 1000));
    }
  });
  await client.send('Page.enable');
  await client.send('Runtime.enable');
  await client.send('Network.enable');
  await client.send('DOM.enable');
  await client.send('Accessibility.enable');
  await client.send('Page.addScriptToEvaluateOnNewDocument', {
    source: `(() => {
      localStorage.setItem('flutter.auth_token', ${JSON.stringify(JSON.stringify(session.token))});
      localStorage.setItem('flutter.user_id', ${JSON.stringify(JSON.stringify(session.user.uuid))});
      localStorage.setItem('flutter.auth_user_data', ${JSON.stringify(JSON.stringify(JSON.stringify(session.user)))});
    })();`,
  });
  try {
    await client.send('Page.navigate', {
      url: `${webUrl}/#/chat/${encodeURIComponent(chatId)}?name=${encodeURIComponent(session.username)}&type=${encodeURIComponent(configuredChatType)}`,
    });
  } catch (error) {
    if (!isNavigationTransientError(error)) throw error;
  }
  await waitForRuntimeValue(
    client,
    `(() => ({
      route: location.hash,
      ready: !!document.querySelector('flt-glass-pane, flutter-view, flt-scene-host')
    }))()`,
    (value) => value?.route.includes(`/chat/${chatId}`) && value?.ready,
    45_000,
    'Flutter Web chat page',
  );
  return {
    client,
    network,
    errors,
    consoleMessages,
    navigations,
    lifecycle,
    chromeLogs,
    webSocketFrames,
    cleanup: async () => {
      client.close();
      try {
        await browser.send('Target.closeTarget', { targetId: target.targetId });
      } catch {}
      browser.close();
      child.kill();
      await sleep(300);
      try {
        rmSync(profile, { recursive: true, force: true });
      } catch {}
    },
  };
}

function browserEvidence(browser) {
  return {
    network: relevantNetwork(browser.network),
    errors: browser.errors,
    consoleMessages: browser.consoleMessages,
    navigations: browser.navigations,
    lifecycle: browser.lifecycle,
    chromeLogs: browser.chromeLogs,
    webSocketFrames: browser.webSocketFrames,
  };
}

function assertNoBrowserErrors(browser, label) {
  const runtimeErrors = browser.errors || [];
  const consoleErrors = (browser.consoleMessages || [])
    .filter((message) => message.type === 'error')
    .map((message) => message.values.join(' '));
  assert(
    runtimeErrors.length === 0 && consoleErrors.length === 0,
    `${label} browser errors: ${JSON.stringify({
      runtimeErrors,
      consoleErrors,
    })}`,
  );
}

async function captureScreenshot(client, name) {
  const screenshot = await client.send('Page.captureScreenshot', {
    format: 'png',
    captureBeyondViewport: false,
  });
  const target = join(artifactDir, name);
  writeFileSync(target, Buffer.from(screenshot.data, 'base64'));
  return target;
}

function messageEvidence(message) {
  return {
    msgId: message.msg_id,
    seq: message.seq,
    type: message.type,
    media: message.content.media,
  };
}

async function request(path, { method = 'GET', token = '', data } = {}) {
  const response = await fetch(`${apiBase}${path}`, {
    method,
    headers: {
      ...(data ? { 'Content-Type': 'application/json' } : {}),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      'X-Client-Platform': 'web',
    },
    body: data ? JSON.stringify(data) : undefined,
  });
  const text = await response.text();
  let body;
  try {
    body = JSON.parse(text);
  } catch {
    throw new Error(`${method} ${path} returned non-JSON HTTP ${response.status}`);
  }
  if (!response.ok) {
    throw new Error(`${method} ${path} failed HTTP ${response.status}: ${text.slice(0, 500)}`);
  }
  return body;
}

async function waitForRuntimeValue(client, expression, predicate, timeoutMs, label) {
  const deadline = Date.now() + timeoutMs;
  let latest;
  while (Date.now() < deadline) {
    try {
      latest = await evaluate(client, expression);
    } catch (error) {
      if (isNavigationTransientError(error)) {
        await sleep(250);
        continue;
      }
      throw error;
    }
    if (predicate(latest)) return latest;
    await sleep(500);
  }
  throw new Error(`Timed out waiting for ${label}: ${JSON.stringify(latest)}`);
}

function isNavigationTransientError(error) {
  const message = String(error?.message || error);
  return (
    message.includes('Inspected target navigated') ||
    message.includes('Execution context was destroyed') ||
    message.includes('Cannot find context with specified id')
  );
}

async function evaluate(client, expression, awaitPromise = false) {
  const result = await client.send('Runtime.evaluate', {
    expression,
    awaitPromise,
    returnByValue: true,
  });
  if (result?.exceptionDetails) {
    throw new Error(result.exceptionDetails.text || 'Runtime.evaluate failed');
  }
  return result?.result?.value;
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
  throw new Error(`Chrome debugging port ${port} did not open`);
}

async function waitForPageTarget(port, targetId) {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    const targets = await fetch(`http://127.0.0.1:${port}/json/list`).then(
      (response) => response.json(),
    );
    const page = targets.find((item) => item.id === targetId);
    if (page?.webSocketDebuggerUrl) return page;
    await sleep(150);
  }
  throw new Error(`Chrome target ${targetId} was not ready`);
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
      const operation = pending.get(message.id);
      pending.delete(message.id);
      if (message.error) operation.reject(new Error(JSON.stringify(message.error)));
      else operation.resolve(message.result);
      return;
    }
    if (message.method) {
      for (const listener of listeners.get(message.method) || []) {
        listener(message.params || {});
      }
    }
  });
  return {
    send(method, params = {}) {
      const current = id++;
      socket.send(JSON.stringify({ id: current, method, params }));
      return new Promise((resolvePromise, reject) => {
        pending.set(current, { resolve: resolvePromise, reject });
      });
    },
    on(method, listener) {
      const current = listeners.get(method) || [];
      current.push(listener);
      listeners.set(method, current);
    },
    close() {
      socket.close();
    },
  };
}

function trim(value) {
  return value.replace(/\/+$/, '');
}

function safeURL(value) {
  try {
    const parsed = new URL(value);
    return `${parsed.origin}${parsed.pathname}`;
  } catch {
    return value;
  }
}

function sanitizeChromeLog(value) {
  return String(value || '').replace(
    /https?:\/\/[^\s"')]+/g,
    (match) => safeURL(match),
  );
}

function relevantNetwork(network) {
  return network.filter(
    (entry) =>
      entry.url.includes('/media/uploads/') ||
      entry.url.includes('/upload/image') ||
      entry.url.includes('/upload/video') ||
      entry.method === 'PUT' ||
      entry.url.includes('/access-url') ||
      entry.url.includes('/message/send'),
  );
}

function assertExpectedUploadPath(uploadRequests) {
  const successful = (entry) => entry.status >= 200 && entry.status < 300;
  if (expectedStorageProvider === 's3') {
    assert(
      uploadRequests.some(
        (entry) =>
          entry.method === 'POST' &&
          entry.url.includes('/media/uploads/init') &&
          successful(entry),
      ),
      'H5 did not complete the S3 direct-upload init request',
    );
    assert(
      uploadRequests.some(
        (entry) => entry.method === 'PUT' && successful(entry),
      ),
      'H5 did not complete a successful S3 PUT',
    );
    return;
  }
  for (const category of ['image', 'video']) {
    assert(
      uploadRequests.some(
        (entry) =>
          entry.method === 'POST' &&
          entry.url.includes(`/upload/${category}`) &&
          successful(entry),
      ),
      `H5 did not complete the ${expectedStorageProvider} proxy ${category} upload`,
    );
  }
}

function progress(stage) {
  console.log(`[${new Date().toISOString()}] ${stage}`);
}

function sleep(milliseconds) {
  return new Promise((resolvePromise) => setTimeout(resolvePromise, milliseconds));
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

main().catch((error) => {
  console.error(error?.stack || String(error));
  process.exitCode = 1;
});
