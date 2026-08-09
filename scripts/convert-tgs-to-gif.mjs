import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import puppeteer from '../.tools/sticker-converter/node_modules/puppeteer-core/lib/esm/puppeteer/puppeteer-core.js';
import {
  GIFEncoder,
  applyPalette,
  quantize,
} from '../.tools/sticker-converter/node_modules/gifenc/dist/gifenc.esm.js';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

const packConfigs = {
  cubigator: { dir: 'cubigator', prefix: 'cubigator', count: 30 },
  duck: { dir: 'duck', prefix: 'duck', count: 29 },
  premium_gifts: { dir: 'premium_gifts', prefix: 'premium_gifts', count: 30 },
};

function argValue(name, fallback) {
  const index = process.argv.indexOf(`--${name}`);
  if (index === -1 || index + 1 >= process.argv.length) return fallback;
  return process.argv[index + 1];
}

const packName = argValue('pack', 'cubigator');
const config = packConfigs[packName];
if (!config) {
  throw new Error(`Unknown pack: ${packName}`);
}

const browserPath =
  argValue('browser', '') ||
  process.env.CHROME_EXE ||
  path.join(process.env.LOCALAPPDATA || '', 'Google/Chrome/Application/chrome.exe');
const limit = Number(argValue('limit', config.count));
const size = Number(argValue('size', 128));
const frames = Number(argValue('frames', 24));
const fps = Number(argValue('fps', 12));
const delay = Math.round(1000 / fps);

const sourceDir = path.join(
  repoRoot,
  'backend',
  'assets',
  'sticker_sources',
  config.dir,
);
const outputDir = path.join(repoRoot, 'backend', 'uploads', 'stickers', config.dir);
fs.mkdirSync(outputDir, { recursive: true });
const lottieWebPath = path.join(
  repoRoot,
  '.tools',
  'sticker-converter',
  'node_modules',
  'lottie-web',
  'build',
  'player',
  'lottie_canvas.min.js',
);

if (!fs.existsSync(browserPath)) {
  throw new Error(`Browser not found: ${browserPath}`);
}
if (!fs.existsSync(lottieWebPath)) {
  throw new Error(`lottie-web not found: ${lottieWebPath}`);
}

function encodeGif(frameData) {
  const gif = GIFEncoder();
  for (const rgba of frameData) {
    const palette = quantize(rgba, 256, {
      format: 'rgba4444',
      oneBitAlpha: 96,
    });
    const transparentIndex = palette.findIndex((color) => color[3] < 128);
    const indexed = applyPalette(rgba, palette, 'rgba4444');
    gif.writeFrame(indexed, size, size, {
      palette,
      delay,
      repeat: 0,
      dispose: 2,
      transparent: transparentIndex >= 0,
      transparentIndex: Math.max(0, transparentIndex),
    });
  }
  gif.finish();
  return Buffer.from(gif.bytes());
}

const browser = await puppeteer.launch({
  executablePath: browserPath,
  headless: 'new',
  args: ['--disable-gpu', '--disable-dev-shm-usage', '--no-sandbox'],
});

try {
  const page = await browser.newPage();
  await page.setViewport({ width: size, height: size, deviceScaleFactor: 1 });
  await page.setContent(`<!doctype html>
<html>
<body style="margin:0;background:transparent;overflow:hidden">
  <div id="stage" style="width:${size}px;height:${size}px"></div>
</body>
</html>`);
  await page.addScriptTag({ path: lottieWebPath });

  await page.waitForFunction(() => Boolean(window.lottie));

  for (let i = 1; i <= limit; i++) {
    const baseName = `${config.prefix}_${String(i).padStart(2, '0')}`;
    const inputPath = path.join(sourceDir, `${baseName}.json`);
    const outputPath = path.join(outputDir, `${baseName}.gif`);
    if (!fs.existsSync(inputPath)) {
      console.warn(`Skipped missing input: ${inputPath}`);
      continue;
    }

    const animationData = JSON.parse(fs.readFileSync(inputPath, 'utf8'));
    const frameData = await page.evaluate(
      async ({ animationData, frameCount, size }) => {
        const stage = document.getElementById('stage');
        stage.innerHTML = '';
        const animation = window.lottie.loadAnimation({
          container: stage,
          renderer: 'canvas',
          loop: false,
          autoplay: false,
          animationData,
          rendererSettings: {
            clearCanvas: true,
            progressiveLoad: false,
            preserveAspectRatio: 'xMidYMid meet',
          },
        });

        await new Promise((resolve) => {
          animation.addEventListener('DOMLoaded', resolve);
          setTimeout(resolve, 1000);
        });

        const totalFrames = Math.max(1, Math.floor(animation.totalFrames || animationData.op || 1));
        const outputCanvas = document.createElement('canvas');
        outputCanvas.width = size;
        outputCanvas.height = size;
        const outputContext = outputCanvas.getContext('2d', { willReadFrequently: true });
        const frames = [];

        for (let frameIndex = 0; frameIndex < frameCount; frameIndex++) {
          const frame = Math.floor((totalFrames * frameIndex) / frameCount);
          animation.goToAndStop(frame, true);
          await new Promise((resolve) => requestAnimationFrame(resolve));
          await new Promise((resolve) => requestAnimationFrame(resolve));
          const sourceCanvas = stage.querySelector('canvas');
          outputContext.clearRect(0, 0, size, size);
          if (sourceCanvas) {
            outputContext.drawImage(sourceCanvas, 0, 0, size, size);
          }
          frames.push(Array.from(outputContext.getImageData(0, 0, size, size).data));
        }

        animation.destroy();
        stage.innerHTML = '';
        return frames;
      },
      { animationData, frameCount: frames, size },
    );

    const hasVisiblePixels = frameData.some((frame) => {
      for (let px = 3; px < frame.length; px += 4) {
        if (frame[px] > 10) return true;
      }
      return false;
    });
    if (!hasVisiblePixels) {
      console.warn(`Rendered blank frames: ${inputPath}`);
    }

    fs.writeFileSync(
      outputPath,
      encodeGif(frameData.map((frame) => Uint8Array.from(frame))),
    );
    console.log(`Converted ${outputPath}`);
  }
} finally {
  await browser.close();
}
