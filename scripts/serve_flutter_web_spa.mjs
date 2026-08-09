#!/usr/bin/env node

import { createReadStream, existsSync, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { extname, join, resolve, sep } from 'node:path';

const host = process.env.GENERIC_IM_WEB_HOST || '127.0.0.1';
const port = Number(process.env.GENERIC_IM_WEB_PORT || 5185);
const rootDir = resolve(process.env.GENERIC_IM_WEB_STATIC_DIR || 'build/web');
const indexPath = join(rootDir, 'index.html');

if (!existsSync(indexPath)) {
  console.error(`Missing Flutter Web index.html: ${indexPath}`);
  process.exit(1);
}

const server = createServer((request, response) => {
  const requestUrl = new URL(request.url || '/', `http://${host}:${port}`);
  const pathName = safeDecodePath(requestUrl.pathname);
  const filePath = resolve(rootDir, pathName === '/' ? 'index.html' : `.${pathName}`);
  const isInsideRoot = filePath === rootDir || filePath.startsWith(`${rootDir}${sep}`);

  if (!isInsideRoot) {
    response.writeHead(403);
    response.end('Forbidden');
    return;
  }

  const resolvedPath = resolveFilePath(filePath, pathName);
  if (!resolvedPath) {
    response.writeHead(404);
    response.end('Not found');
    return;
  }

  response.writeHead(200, {
    'Content-Type': contentType(resolvedPath),
    'Cache-Control': 'no-store',
  });
  createReadStream(resolvedPath).pipe(response);
});

server.listen(port, host, () => {
  console.log(`Serving ${rootDir} at http://localhost:${port}/`);
});

function safeDecodePath(pathName) {
  try {
    return decodeURIComponent(pathName);
  } catch {
    return '/';
  }
}

function resolveFilePath(filePath, pathName) {
  if (existsSync(filePath) && statSync(filePath).isFile()) {
    return filePath;
  }

  const hasFileExtension = extname(pathName) !== '';
  if (!hasFileExtension) {
    return indexPath;
  }

  return '';
}

function contentType(filePath) {
  switch (extname(filePath)) {
    case '.html':
      return 'text/html; charset=utf-8';
    case '.js':
      return 'application/javascript; charset=utf-8';
    case '.mjs':
      return 'application/javascript; charset=utf-8';
    case '.css':
      return 'text/css; charset=utf-8';
    case '.json':
      return 'application/json; charset=utf-8';
    case '.wasm':
      return 'application/wasm';
    case '.png':
      return 'image/png';
    case '.jpg':
    case '.jpeg':
      return 'image/jpeg';
    case '.svg':
      return 'image/svg+xml';
    case '.ico':
      return 'image/x-icon';
    case '.ttf':
      return 'font/ttf';
    case '.otf':
      return 'font/otf';
    case '.woff':
      return 'font/woff';
    case '.woff2':
      return 'font/woff2';
    default:
      return 'application/octet-stream';
  }
}
