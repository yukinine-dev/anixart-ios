import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';

// Read dimensions from the actual file, not its HTTP content-type or extension.
export function imageInfo(bytes) {
  if (bytes.length >= 24 && bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))) {
    return { mime: 'image/png', width: bytes.readUInt32BE(16), height: bytes.readUInt32BE(20) };
  }
  if (bytes.length >= 10 && /^GIF8[79]a$/.test(bytes.toString('ascii', 0, 6))) {
    return { mime: 'image/gif', width: bytes.readUInt16LE(6), height: bytes.readUInt16LE(8) };
  }
  if (bytes[0] === 0xFF && bytes[1] === 0xD8) {
    let p = 2;
    while (p + 4 <= bytes.length) {
      if (bytes[p] !== 0xFF) break;
      while (bytes[p] === 0xFF) p++;
      const marker = bytes[p++];
      if (marker === 0xD9 || marker === 0xDA) break;
      if (marker === 0x01 || (marker >= 0xD0 && marker <= 0xD7)) continue;
      if (p + 2 > bytes.length) break;
      const length = bytes.readUInt16BE(p);
      if (length < 2 || p + length > bytes.length) break;
      if ([0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF].includes(marker) && length >= 7) {
        return { mime: 'image/jpeg', height: bytes.readUInt16BE(p + 3), width: bytes.readUInt16BE(p + 5) };
      }
      p += length;
    }
  }
  if (bytes.toString('ascii', 0, 4) === 'RIFF' && bytes.toString('ascii', 8, 12) === 'WEBP') {
    for (let p = 12; p + 8 <= bytes.length;) {
      const chunk = bytes.toString('ascii', p, p + 4);
      const length = bytes.readUInt32LE(p + 4);
      const start = p + 8;
      if (start + length > bytes.length) break;
      if (chunk === 'VP8X' && length >= 10) {
        return { mime: 'image/webp', width: 1 + bytes.readUIntLE(start + 4, 3), height: 1 + bytes.readUIntLE(start + 7, 3) };
      }
      if (chunk === 'VP8 ' && length >= 10 && bytes.toString('hex', start + 3, start + 6) === '9d012a') {
        return { mime: 'image/webp', width: bytes.readUInt16LE(start + 6) & 0x3FFF, height: bytes.readUInt16LE(start + 8) & 0x3FFF };
      }
      if (chunk === 'VP8L' && length >= 5 && bytes[start] === 0x2F) {
        const bits = bytes.readUInt32LE(start + 1);
        return { mime: 'image/webp', width: 1 + (bits & 0x3FFF), height: 1 + ((bits >>> 14) & 0x3FFF) };
      }
      p = start + length + (length & 1);
    }
  }
  throw new Error('Unsupported or truncated image');
}

function browserPath() {
  const candidates = [
    process.env.ANIXART_FIGMA_BROWSER,
    process.env.PROGRAMFILES && join(process.env.PROGRAMFILES, 'Google', 'Chrome', 'Application', 'chrome.exe'),
    process.env['PROGRAMFILES(X86)'] && join(process.env['PROGRAMFILES(X86)'], 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
    process.env.LOCALAPPDATA && join(process.env.LOCALAPPDATA, 'Google', 'Chrome', 'Application', 'chrome.exe'),
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
    '/usr/bin/chromium', '/usr/bin/chromium-browser', '/usr/bin/google-chrome', '/usr/bin/microsoft-edge',
  ];
  const browser = candidates.find(path => path && existsSync(path));
  if (!browser) throw new Error('WebP → PNG needs Chrome or Edge. Install one or set ANIXART_FIGMA_BROWSER to its executable. Cached PNG exports need only Node.js.');
  return browser;
}

// Figma createImage accepts only PNG/JPEG/GIF. Chromium provides a local,
// lossless WebP decoder, without npm packages, upload services or a user profile.
export function normalizeImages(data, directory) {
  const jobs = Object.entries(data.assets).flatMap(([key, asset]) => {
    const bytes = readFileSync(join(directory, asset.file));
    const info = imageInfo(bytes);
    Object.assign(asset, info);
    return info.mime === 'image/webp' ? [{ key, data: bytes.toString('base64') }] : [];
  });
  if (!jobs.length) return false;
  const browser = browserPath();
  const base = process.platform === 'win32' && process.env.LOCALAPPDATA ? join(process.env.LOCALAPPDATA, 'Temp', 'opencode') : tmpdir();
  mkdirSync(base, { recursive: true });
  const temporary = mkdtempSync(join(base, 'anixart-figma-images-'));
  try {
    const html = `<!doctype html><meta charset="utf-8"><pre id="result">pending</pre>
      ${jobs.map(job => `<img data-key="${job.key}" src="data:image/webp;base64,${job.data}">`).join('')}
      <script>window.onload = () => {
        try {
          const result = Array.from(document.images, image => {
            if (!image.naturalWidth) throw new Error('Invalid WebP: ' + image.dataset.key);
            const scale = Math.min(1, 4096 / Math.max(image.naturalWidth, image.naturalHeight));
            const canvas = document.createElement('canvas');
            canvas.width = Math.max(1, Math.round(image.naturalWidth * scale));
            canvas.height = Math.max(1, Math.round(image.naturalHeight * scale));
            canvas.getContext('2d').drawImage(image, 0, 0, canvas.width, canvas.height);
            return { key: image.dataset.key, png: canvas.toDataURL('image/png').split(',')[1] };
          });
          document.getElementById('result').textContent = JSON.stringify({ result });
        } catch (error) {
          document.getElementById('result').textContent = JSON.stringify({ error: error.message });
        }
      };</script>`;
    const input = join(temporary, 'convert.html');
    writeFileSync(input, html);
    const run = spawnSync(browser, [
      '--headless=new', '--disable-gpu', '--disable-extensions', '--disable-background-networking',
      '--disable-component-update', '--disable-sync', '--no-first-run', '--no-default-browser-check',
      `--user-data-dir=${join(temporary, 'profile')}`, '--dump-dom', '--virtual-time-budget=10000',
      pathToFileURL(input).href,
    ], { encoding: 'utf8', timeout: 60000, maxBuffer: 64 * 1024 * 1024, windowsHide: true });
    if (run.error || run.status !== 0) throw new Error(`WebP decoder failed: ${run.error?.message || run.stderr.slice(0, 400)}`);
    const output = run.stdout.match(/<pre id="result">([\s\S]*?)<\/pre>/)?.[1];
    if (!output || output === 'pending') throw new Error('WebP decoder did not finish');
    const converted = JSON.parse(output);
    if (converted.error) throw new Error(`WebP decoder: ${converted.error}`);
    for (const { key, png } of converted.result) {
      const bytes = Buffer.from(png, 'base64');
      const info = imageInfo(bytes);
      if (info.mime !== 'image/png') throw new Error(`PNG conversion failed: ${key}`);
      const file = `${key}.png`;
      writeFileSync(join(directory, file), bytes);
      Object.assign(data.assets[key], { file, ...info, convertedFrom: 'image/webp' });
    }
    console.log(`Converted ${jobs.length} WebP images to Figma-compatible PNG, locally.`);
    return true;
  } finally {
    // This is a unique directory created above, never the person's browser data.
    rmSync(temporary, { recursive: true, force: true, maxRetries: 3 });
  }
}
