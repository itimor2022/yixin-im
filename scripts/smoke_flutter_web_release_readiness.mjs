#!/usr/bin/env node

import { spawn } from 'node:child_process';
import { existsSync, readFileSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';

const apiBase = trimTrailingSlash(
  process.env.GENERIC_IM_SERVER_URL || 'http://localhost:8080',
);
const staticDir = resolve(process.env.GENERIC_IM_RELEASE_STATIC_DIR || 'build/web');
const port = Number(process.env.GENERIC_IM_RELEASE_WEB_PORT || 5186);
const host = process.env.GENERIC_IM_RELEASE_WEB_HOST || '127.0.0.1';
const webUrl = `http://localhost:${port}/`;

async function main() {
  const startedAt = new Date().toISOString();
  const checks = [];
  const warnings = [];

  checks.push(await runCheck('build-files', checkBuildFiles));
  checks.push(await runCheck('manifest', checkManifest));
  checks.push(await runCheck('index-html', checkIndexHtml));
  checks.push(await runCheck('api-health', checkApiHealth));

  const server = await startStaticServer();
  try {
    checks.push(await runCheck('static-root', () => checkStaticRoute('/')));
    checks.push(await runCheck('static-manifest', () => checkStaticRoute('/manifest.json')));
    checks.push(await runCheck('static-bootstrap', () => checkStaticRoute('/flutter_bootstrap.js')));
    checks.push(await runCheck('static-service-worker', () => checkStaticRoute('/flutter_service_worker.js')));
    checks.push(await runCheck('spa-fallback', checkSpaFallback));
    checks.push(await runCheck('asset-404', checkMissingAsset404));
    const bootstrap = await runCheck('client-bootstrap', checkClientBootstrap);
    checks.push(bootstrap);
    if (bootstrap.warning) warnings.push(bootstrap.warning);
  } finally {
    await server.stop();
  }

  const ok = checks.every((item) => item.ok);
  console.log(
    JSON.stringify(
      {
        ok,
        startedAt,
        finishedAt: new Date().toISOString(),
        apiBase,
        staticDir,
        webUrl,
        checks,
        warnings,
      },
      null,
      2,
    ),
  );
  if (!ok) process.exit(1);
}

function trimTrailingSlash(value) {
  return value.replace(/\/+$/, '');
}

async function runCheck(name, fn) {
  try {
    const result = await fn();
    return { ...result, name, ok: true };
  } catch (error) {
    return {
      name,
      ok: false,
      error: error?.message || String(error),
    };
  }
}

function checkBuildFiles() {
  const required = [
    'index.html',
    'manifest.json',
    'favicon.png',
    'flutter_bootstrap.js',
    'flutter.js',
    'main.dart.js',
    'flutter_service_worker.js',
    'icons/Icon-192.png',
    'icons/Icon-512.png',
    'icons/Icon-maskable-192.png',
    'icons/Icon-maskable-512.png',
  ];
  const files = required.map((relativePath) => {
    const filePath = join(staticDir, relativePath);
    if (!existsSync(filePath)) {
      throw new Error(`Missing required web artifact: ${relativePath}`);
    }
    const stat = statSync(filePath);
    if (!stat.isFile() || stat.size <= 0) {
      throw new Error(`Invalid web artifact: ${relativePath}`);
    }
    return { path: relativePath, size: stat.size };
  });
  return { files };
}

function checkManifest() {
  const manifest = readJson(join(staticDir, 'manifest.json'));
  const requiredTextFields = ['name', 'short_name', 'start_url', 'display'];
  for (const field of requiredTextFields) {
    if (!String(manifest[field] || '').trim()) {
      throw new Error(`manifest.${field} is missing`);
    }
  }
  if (manifest.display !== 'standalone') {
    throw new Error(`manifest.display should be standalone, got ${manifest.display}`);
  }
  const icons = Array.isArray(manifest.icons) ? manifest.icons : [];
  const expectedSizes = new Set(['192x192', '512x512']);
  for (const size of expectedSizes) {
    if (!icons.some((icon) => icon.sizes === size && icon.type === 'image/png')) {
      throw new Error(`manifest missing PNG icon ${size}`);
    }
  }
  for (const icon of icons) {
    if (!icon.src) continue;
    const iconPath = join(staticDir, icon.src);
    if (!existsSync(iconPath)) {
      throw new Error(`manifest icon file missing: ${icon.src}`);
    }
  }
  return {
    manifestName: manifest.name,
    shortName: manifest.short_name,
    display: manifest.display,
    startUrl: manifest.start_url,
    icons: icons.length,
  };
}

function checkIndexHtml() {
  const html = readFileSync(join(staticDir, 'index.html'), 'utf8');
  const required = [
    '<base href="/">',
    'name="viewport"',
    'rel="manifest"',
    'flutter_bootstrap.js',
  ];
  for (const marker of required) {
    if (!html.includes(marker)) {
      throw new Error(`index.html missing ${marker}`);
    }
  }
  return {
    title: (html.match(/<title>(.*?)<\/title>/i) || [])[1] || '',
    hasThemeColor: html.includes('name="theme-color"'),
  };
}

async function checkApiHealth() {
  const health = await fetchText(`${apiBase}/health`);
  const ping = await fetchJson(`${apiBase}/api/v1/ping`);
  return {
    healthStatus: health.status,
    pingStatus: ping.status,
    pingCode: ping.json?.code,
    pingMessage: ping.json?.message,
  };
}

async function checkStaticRoute(path) {
  const response = await fetchText(`${webUrl}${path.replace(/^\/+/, '')}`);
  if (response.status !== 200) {
    throw new Error(`${path} expected 200, got ${response.status}`);
  }
  return {
    status: response.status,
    contentType: response.contentType,
    bytes: response.text.length,
  };
}

async function checkSpaFallback() {
  const response = await fetchText(`${webUrl}chat/release-readiness-deep-link`);
  if (response.status !== 200) {
    throw new Error(`SPA fallback expected 200, got ${response.status}`);
  }
  if (!response.contentType.includes('text/html')) {
    throw new Error(`SPA fallback expected text/html, got ${response.contentType}`);
  }
  if (!response.text.includes('flutter_bootstrap.js')) {
    throw new Error('SPA fallback did not return Flutter index.html');
  }
  return {
    status: response.status,
    contentType: response.contentType,
  };
}

async function checkMissingAsset404() {
  const response = await fetchText(`${webUrl}assets/release-readiness-missing.js`);
  if (response.status !== 404) {
    throw new Error(`Missing asset expected 404, got ${response.status}`);
  }
  return { status: response.status };
}

async function checkClientBootstrap() {
  const result = await fetchJson(`${apiBase}/api/v1/client/bootstrap`);
  const raw = JSON.stringify(result.json || {});
  const warning = raw.includes('10.0.2.2')
    ? 'client/bootstrap contains Android emulator address 10.0.2.2; Flutter Web has a local guard, but production should return browser-reachable HTTPS/WSS endpoints.'
    : '';
  return {
    status: result.status,
    code: result.json?.code,
    hasAndroidEmulatorAddress: raw.includes('10.0.2.2'),
    warning,
  };
}

async function startStaticServer() {
  const existing = await canFetchRoot();
  if (existing) {
    return { stop: async () => {} };
  }

  const child = spawn(process.execPath, ['scripts/serve_flutter_web_spa.mjs'], {
    cwd: process.cwd(),
    env: {
      ...process.env,
      GENERIC_IM_WEB_HOST: host,
      GENERIC_IM_WEB_PORT: String(port),
      GENERIC_IM_WEB_STATIC_DIR: staticDir,
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let stdout = '';
  let stderr = '';
  child.stdout.on('data', (chunk) => {
    stdout += chunk.toString('utf8');
  });
  child.stderr.on('data', (chunk) => {
    stderr += chunk.toString('utf8');
  });

  const deadline = Date.now() + 12000;
  while (Date.now() < deadline) {
    if (child.exitCode !== null) {
      throw new Error(
        `Static server exited early: ${child.exitCode}\n${stdout}\n${stderr}`,
      );
    }
    if (await canFetchRoot()) {
      return {
        stop: async () => {
          child.kill('SIGTERM');
          await sleep(500);
          if (child.exitCode === null) child.kill('SIGKILL');
        },
      };
    }
    await sleep(250);
  }

  child.kill('SIGTERM');
  throw new Error(`Static server did not start\n${stdout}\n${stderr}`);
}

async function canFetchRoot() {
  try {
    const response = await fetch(`${webUrl}`, {
      signal: AbortSignal.timeout(1000),
    });
    return response.status === 200;
  } catch {
    return false;
  }
}

async function fetchText(url) {
  const response = await fetch(url, { signal: AbortSignal.timeout(8000) });
  const text = await response.text();
  if (response.status >= 500) {
    throw new Error(`${url} returned ${response.status}: ${text.slice(0, 200)}`);
  }
  return {
    status: response.status,
    contentType: response.headers.get('content-type') || '',
    text,
  };
}

async function fetchJson(url) {
  const response = await fetch(url, { signal: AbortSignal.timeout(8000) });
  const text = await response.text();
  let json;
  try {
    json = JSON.parse(text);
  } catch {
    throw new Error(`${url} did not return JSON: ${text.slice(0, 200)}`);
  }
  if (!response.ok) {
    throw new Error(`${url} returned ${response.status}: ${text.slice(0, 200)}`);
  }
  return {
    status: response.status,
    json,
  };
}

function readJson(filePath) {
  return JSON.parse(readFileSync(filePath, 'utf8'));
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

main().catch((error) => {
  console.error(error?.stack || error?.message || String(error));
  process.exit(1);
});
