import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { inflateRawSync } from 'node:zlib';
import { runInNewContext } from 'node:vm';
import { FontMetrics, Scene, wrapText, walkNodes, renderSVG, xml, crc32, zipFiles } from './scene.mjs';
import { imageInfo, normalizeImages } from './images.mjs';
import { SCREEN_SPECS, makeScreens, makeKit } from './screens.mjs';

const ROOT = fileURLToPath(new URL('../../', import.meta.url));
const OUT = join(ROOT, 'design', 'figma');
const read = path => readFileSync(join(OUT, path), 'utf8');
const pluginHTML = read('figma-plugin/ui.html');
const payload = JSON.parse(pluginHTML.match(/<script id="design-data" type="application\/json">([\s\S]*?)<\/script>/)[1]);
const sourceMap = JSON.parse(read('source-map.json'));
const content = JSON.parse(read('assets/content.json'));
const weights = ['Regular', 'Medium', 'Bold'];
const fonts = Object.fromEntries(weights.map(weight => [weight, new FontMetrics(join(ROOT, 'Anixart', 'Resources', 'Fonts', `Roboto-${weight}.ttf`))]));
const fontCSS = read('screens/light/home.svg').match(/<style>(.*?)<\/style>/)[1];
const project = readFileSync(join(ROOT, 'project.yml'), 'utf8');
content.appVersion = `${project.match(/MARKETING_VERSION:\s*"([^"]+)"/)[1]} (${project.match(/CURRENT_PROJECT_VERSION:\s*"([^"]+)"/)[1]})`;

// Structural validation for the controlled XML emitted by this generator.
// The final SVGs are also parsed/rendered in a browser during visual QA.
function checkSVG(svg) {
  assert.ok(svg.startsWith('<svg xmlns="http://www.w3.org/2000/svg"'));
  assert.doesNotMatch(svg, /\b(?:NaN|Infinity|undefined)\b|<script\b|<!DOCTYPE/i);
  assert.doesNotMatch(svg, /&(?!(?:amp|lt|gt|quot|apos|#\d+|#x[\da-f]+);)/i);
  const stack = [];
  for (const match of svg.matchAll(/<\/?([\w:-]+)\b[^>]*>/g)) {
    const [tag, name] = match;
    if (tag.startsWith('</')) assert.equal(stack.pop(), name, `Unbalanced XML: ${tag}`);
    else if (!tag.endsWith('/>')) stack.push(name);
  }
  assert.equal(stack.length, 0, 'Unclosed XML tags');
  const ids = [...svg.matchAll(/\bid="([^"]+)"/g)].map(match => match[1]);
  assert.equal(new Set(ids).size, ids.length, 'Duplicate SVG IDs');
  const references = [...svg.matchAll(/url\(#([^\)]+)\)|xlink:href="#([^"]+)"/g)].map(match => match[1] || match[2]);
  for (const id of references) assert.ok(ids.includes(id), `Unresolved SVG reference: ${id}`);
  for (const [, href] of svg.matchAll(/(?:xlink:)?href="([^"]+)"/g)) assert.match(href, /^(?:#|data:image\/(?:png|jpeg|gif);base64,)/);
}

function visit(root, callback) {
  callback(root);
  for (const child of root.children || []) visit(child, callback);
}

test('Roboto metrics and Russian wrapping are deterministic and bounded', () => {
  for (const font of Object.values(fonts)) {
    for (const char of 'АБВГДабвгдё0123456789') assert.ok(font.glyph(char.codePointAt(0)) > 0);
    assert.ok(font.measure('Настройки вкладки', 17) > 140);
    assert.ok(font.baseline(17, 21) > 0 && font.baseline(17, 21) < 21);
  }
  const text = 'Киберпанк: Бегущие по краю\nоченьдлинноеназваниестудиибезпробелов';
  const lines = wrapText(text, 112, 12, fonts.Regular, 3);
  assert.equal(lines.length, 3);
  assert.ok(lines.at(-1).endsWith('…'));
  for (const line of lines) assert.ok(fonts.Regular.measure(line, 12) <= 112);
  assert.deepEqual(wrapText('один\n\nдва', 100, 12, fonts.Regular), ['один', '', 'два']);
  assert.equal(xml('<&"\'>'), '&lt;&amp;&quot;&apos;&gt;');
});

test('all 48 screen scenes and both kits match the current export', () => {
  assert.equal(SCREEN_SPECS.length, 24);
  assert.equal(payload.version, 1);
  assert.equal(payload.pages.length, 2);
  assert.equal(sourceMap.screens.length, 50);
  for (const page of payload.pages) {
    const expected = [...makeScreens(content, fonts, payload.assets, page.theme), makeKit(content, fonts, page.theme)];
    assert.deepEqual(page.screens, expected, 'Rebuild the export after changing screen layouts');
    assert.equal(page.screens.length, 25);
    for (const screen of page.screens) {
      const record = sourceMap.screens.find(item => item.theme === page.theme && item.id === screen.id);
      let layers = 0;
      let textLayers = 0;
      let components = 0;
      assert.equal(screen.w, screen.kit ? 1800 : 393);
      assert.equal(screen.h, screen.kit ? 920 : 852);
      assert.ok(screen.root.clip);
      walkNodes(screen.root, node => {
        layers++;
        assert.ok(node.name);
        for (const key of ['x', 'y', 'w', 'h']) assert.ok(Number.isFinite(node[key]), `${screen.id}: invalid ${key}`);
        assert.ok(node.w > 0 && node.h > 0, `${screen.id}: nonpositive layer size`);
        if (node.component) components++;
        if (node.type === 'text') {
          textLayers++;
          assert.ok(weights.includes(node.weight));
          assert.equal(node.h, node.text.split('\n').length * node.lineHeight);
          for (const line of node.text.split('\n')) assert.ok(fonts[node.weight].measure(line, node.size) <= node.w + .1, `${screen.id}: overflowing text: ${line}`);
        }
        if (node.type === 'image') assert.ok(payload.assets[node.key], `${screen.id}: missing poster ${node.key}`);
      });
      assert.deepEqual({ layers, textLayers, components }, { layers: record.layers, textLayers: record.textLayers, components: record.components });
      const path = screen.kit ? `Anixart-components-${page.theme}.svg` : `screens/${page.theme}/${screen.id}.svg`;
      const svg = read(path);
      checkSVG(svg);
      assert.equal(svg, renderSVG(screen, payload.assets, fontCSS));
    }
    assert.equal(readdirSync(join(OUT, 'screens', page.theme)).filter(name => name.endsWith('.svg')).length, 24);
    const board = read(`Anixart-current-ui-${page.theme}.svg`);
    checkSVG(board);
    assert.match(board, /width="1860" height="5918" viewBox="0 0 1860 5918"/);
    const usedImages = new Set();
    for (const screen of page.screens.filter(screen => !screen.kit)) walkNodes(screen.root, node => { if (node.type === 'image') usedImages.add(node.key); });
    assert.equal([...board.matchAll(/<image\b/g)].length, usedImages.size, 'Each image should be embedded only once per board');
  }
});

test('public image cache is offline, correctly sized and compatible with Figma', () => {
  const before = JSON.stringify(content.assets);
  assert.equal(normalizeImages(content, join(OUT, 'assets')), false, 'A cached export must not need a browser or network');
  assert.equal(JSON.stringify(content.assets), before);
  assert.equal(Object.keys(payload.assets).length, 21);
  for (const [key, asset] of Object.entries(payload.assets)) {
    const bytes = Buffer.from(asset.data, 'base64');
    const info = imageInfo(bytes);
    assert.deepEqual(info, { mime: asset.mime, width: asset.width, height: asset.height });
    assert.ok(['image/png', 'image/jpeg', 'image/gif'].includes(info.mime));
    assert.ok(info.width > 0 && info.height > 0 && info.width <= 4096 && info.height <= 4096);
    assert.ok(bytes.equals(readFileSync(join(OUT, 'assets', content.assets[key].file))));
    assert.match(asset.source, /^https:\/\/(?:s|s3)\.anixmirai\.com\//);
  }
  const forbidden = /^(?:token|access_token|refresh_token|profile|profiles|comments|password|email|watch_history)$/i;
  function check(object) {
    for (const [key, value] of Object.entries(object || {})) {
      assert.ok(!forbidden.test(key), `Private API field was retained: ${key}`);
      if (value && typeof value === 'object') check(value);
    }
  }
  check(content);
});

test('small status labels and voice-over badges stay complete on one line', () => {
  for (const page of payload.pages) {
    const bookmarks = page.screens.find(screen => screen.id === 'bookmarks');
    walkNodes(bookmarks.root, node => {
      if (node.name === 'Статус') {
        assert.equal(node.text, 'Смотрю');
        assert.equal(node.h, 13);
      }
    });
    const voiceovers = page.screens.find(screen => screen.id === 'voiceovers');
    const badges = [];
    walkNodes(voiceovers.root, node => { if (node.name === 'Название badge') badges.push(node.text); });
    assert.deepEqual(badges, ['ПЛЕЕР', 'СУБТИТРЫ']);
  }
});

test('image header parser supports lossy, lossless and extended WebP', () => {
  function webp(chunk, body) {
    const bytes = Buffer.alloc(20 + body.length + (body.length & 1));
    bytes.write('RIFF', 0);
    bytes.writeUInt32LE(bytes.length - 8, 4);
    bytes.write('WEBP', 8);
    bytes.write(chunk, 12);
    bytes.writeUInt32LE(body.length, 16);
    body.copy(bytes, 20);
    return bytes;
  }
  const lossy = Buffer.alloc(10);
  lossy.set([0x9D, 1, 0x2A], 3);
  lossy.writeUInt16LE(300, 6);
  lossy.writeUInt16LE(150, 8);
  const lossless = Buffer.alloc(5);
  lossless[0] = 0x2F;
  lossless.writeUInt32LE(299 | (149 << 14), 1);
  const extended = Buffer.alloc(10);
  extended.writeUIntLE(299, 4, 3);
  extended.writeUIntLE(149, 7, 3);
  for (const [chunk, body] of [['VP8 ', lossy], ['VP8L', lossless], ['VP8X', extended]]) {
    assert.deepEqual(imageInfo(webp(chunk, body)), { mime: 'image/webp', width: 300, height: 150 });
  }
  assert.throws(() => imageInfo(Buffer.from('not an image')), /Unsupported or truncated/);
});

test('image patterns preserve FIT/FILL, rounded corners and external shadows', () => {
  const scene = new Scene({ name: 'Image test', theme: 'light', w: 200, h: 200 }, fonts);
  scene.image('FIT', 'sample', 0, 0, 100, 100, 14, { fit: 'FIT', shadow: { color: '#000000', opacity: .35, x: 0, y: 6, radius: 14 } });
  scene.image('FILL', 'sample', 100, 0, 100, 100, 10);
  const svg = renderSVG(scene.export(), { sample: { mime: 'image/png', data: 'AA==', width: 200, height: 100 } });
  checkSVG(svg);
  assert.equal([...svg.matchAll(/<image\b/g)].length, 1);
  assert.match(svg, /matrix\(0\.005 0 0 0\.005 0 0\.25\)/);
  assert.match(svg, /matrix\(0\.01 0 0 0\.01 -0\.5 0\)/);
  assert.match(svg, /rx="14" fill="url\(#pattern-layer-2\)" filter="url\(#blur-layer-2\)"/);
});

function openZIP(bytes) {
  const end = bytes.length - 22;
  assert.equal(bytes.readUInt32LE(end), 0x06054B50);
  const count = bytes.readUInt16LE(end + 10);
  const directorySize = bytes.readUInt32LE(end + 12);
  const directoryOffset = bytes.readUInt32LE(end + 16);
  assert.equal(directoryOffset + directorySize, end);
  let p = directoryOffset;
  const result = new Map();
  for (let i = 0; i < count; i++) {
    assert.equal(bytes.readUInt32LE(p), 0x02014B50);
    assert.equal(bytes.readUInt16LE(p + 8), 0x800);
    assert.equal(bytes.readUInt16LE(p + 10), 8);
    const crc = bytes.readUInt32LE(p + 16);
    const compressedSize = bytes.readUInt32LE(p + 20);
    const originalSize = bytes.readUInt32LE(p + 24);
    const nameLength = bytes.readUInt16LE(p + 28);
    const extraLength = bytes.readUInt16LE(p + 30);
    const commentLength = bytes.readUInt16LE(p + 32);
    const local = bytes.readUInt32LE(p + 42);
    const name = bytes.toString('utf8', p + 46, p + 46 + nameLength);
    assert.doesNotMatch(name, /(?:^|\/)\.\.(?:\/|$)|\\|^\//);
    assert.ok(!result.has(name), `Duplicate ZIP entry: ${name}`);
    assert.equal(bytes.readUInt32LE(local), 0x04034B50);
    assert.equal(bytes.readUInt32LE(local + 14), crc);
    const start = local + 30 + bytes.readUInt16LE(local + 26) + bytes.readUInt16LE(local + 28);
    const data = inflateRawSync(bytes.subarray(start, start + compressedSize));
    assert.equal(data.length, originalSize);
    assert.equal(crc32(data), crc, `ZIP checksum mismatch: ${name}`);
    result.set(name, data);
    p += 46 + nameLength + extraLength + commentLength;
  }
  assert.equal(p, end);
  return result;
}

test('ZIP has valid headers, UTF-8 paths, checksums and every deliverable', () => {
  assert.equal(crc32(Buffer.from('123456789')), 0xCBF43926);
  const example = [{ name: 'Макет/текст.txt', data: Buffer.from('Привет') }, { name: 'empty', data: Buffer.alloc(0) }];
  assert.ok(zipFiles(example).equals(zipFiles(example)), 'ZIP metadata must be deterministic');
  const small = openZIP(zipFiles(example));
  assert.ok(small.get('Макет/текст.txt').equals(example[0].data));
  const files = openZIP(readFileSync(join(OUT, 'Anixart-Figma.zip')));
  assert.ok(files.size > 80);
  for (const [name, bytes] of files) {
    assert.ok(name.startsWith('Anixart-Figma/'));
    assert.ok(!name.endsWith('.zip'), 'Archive must not contain itself');
    assert.ok(bytes.equals(readFileSync(join(OUT, name.slice('Anixart-Figma/'.length)))));
  }
  for (const name of ['README.md', 'preview.html', 'source-map.json', 'Anixart-current-ui-light.svg', 'Anixart-current-ui-dark.svg', 'figma-plugin/manifest.json', 'figma-plugin/code.js', 'figma-plugin/ui.html', 'fonts/LICENSE.txt', ...weights.map(weight => `fonts/Roboto-${weight}.ttf`)]) {
    assert.ok(files.has('Anixart-Figma/' + name), `Missing deliverable: ${name}`);
  }
});

test('source map and offline plugin files are current and self-contained', () => {
  for (const source of sourceMap.sources) {
    assert.ok(existsSync(join(ROOT, source.path)));
    assert.equal(createHash('sha256').update(readFileSync(join(ROOT, source.path))).digest('hex'), source.sha256);
  }
  const manifest = JSON.parse(read('figma-plugin/manifest.json'));
  assert.equal(manifest.api, '1.0.0');
  assert.equal(manifest.documentAccess, 'dynamic-page');
  assert.deepEqual(manifest.editorType, ['figma']);
  assert.deepEqual(manifest.networkAccess.allowedDomains, ['none']);
  assert.ok(existsSync(join(OUT, 'figma-plugin', manifest.main)));
  assert.ok(existsSync(join(OUT, 'figma-plugin', manifest.ui)));
  assert.equal(read('figma-plugin/code.js'), readFileSync(join(ROOT, 'Tools', 'figma', 'importer.js'), 'utf8'));
  assert.doesNotMatch(pluginHTML, /__DESIGN_DATA__|__SCREEN_COUNT__|<script\s+src=|fetch\(|XMLHttpRequest/);
  assert.equal([...read('preview.html').matchAll(/data-screen="/g)].length, 24);
});

// Deliberately stricter than a permissive stub: require loaded fonts, supported
// image bytes, valid geometry and async style APIs under dynamic-page access.
function mockFigma(options = {}) {
  let cursor = 0;
  let layerCount = 0;
  const loaded = new Set();
  const styles = new Map();
  const removedStyles = [];
  const messages = [];
  const images = new Map();
  const root = { children: [] };
  let currentPage;
  let zoomed;
  const notifications = [];
  const requireFont = font => assert.ok(loaded.has(`${font.family}/${font.style}`), `Unloaded font: ${font.family}/${font.style}`);

  class Node {
    constructor(type) {
      this.id = String(++cursor);
      this.type = type;
      this.name = type;
      this.children = [];
      this.pluginData = {};
      this.x = 0;
      this.y = 0;
      this.width = 100;
      this.height = 100;
      this.removed = false;
      if (type === 'TEXT') {
        let fontName = { family: 'Inter', style: 'Regular' };
        Object.defineProperty(this, 'fontName', { get: () => fontName, set: font => { requireFont(font); fontName = font; } });
        for (const key of ['fontSize', 'characters', 'lineHeight', 'textDecoration']) {
          let value;
          Object.defineProperty(this, key, { get: () => value, set: next => { requireFont(fontName); value = next; } });
        }
      }
      for (const key of ['fillStyleId', 'textStyleId']) Object.defineProperty(this, key, { get: () => this[`_${key}`], set: () => { throw new Error('Use asynchronous style APIs'); } });
    }
    appendChild(node) {
      if (node.parent) node.parent.children.splice(node.parent.children.indexOf(node), 1);
      node.parent = this;
      this.children.push(node);
    }
    resize(width, height) {
      assert.ok(Number.isFinite(width) && width > 0 && Number.isFinite(height) && height > 0);
      if (this.type === 'TEXT') requireFont(this.fontName);
      this.width = width;
      this.height = height;
    }
    async setFillStyleIdAsync(id) {
      const style = styles.get(id);
      assert.equal(style.type, 'PAINT');
      this._fillStyleId = id;
      this.fills = style.paints;
    }
    async setTextStyleIdAsync(id) {
      const style = styles.get(id);
      assert.equal(style.type, 'TEXT');
      this._textStyleId = id;
      this.fontName = style.fontName;
      this.fontSize = style.fontSize;
      this.lineHeight = style.lineHeight;
    }
    setPluginData(key, value) { this.pluginData[key] = value; }
    remove() {
      for (const child of [...this.children]) child.remove();
      this.parent.children.splice(this.parent.children.indexOf(this), 1);
      this.removed = true;
    }
  }

  function createPage() {
    const page = new Node('PAGE');
    page.name = `Page ${root.children.length + 1}`;
    page.parent = root;
    page.selection = [];
    root.children.push(page);
    return page;
  }
  const previousPage = createPage();
  previousPage.name = 'Моя существующая страница';
  currentPage = previousPage;
  const existing = new Node('FRAME');
  existing.name = 'Не менять';
  previousPage.appendChild(existing);
  previousPage.selection = [existing];
  function createStyle(type) {
    const style = { id: `style-${++cursor}`, type, name: '', remove() { styles.delete(this.id); removedStyles.push(this.id); } };
    styles.set(style.id, style);
    return style;
  }
  const existingStyle = createStyle('PAINT');
  existingStyle.name = 'Мой цвет';
  function create(type) {
    layerCount++;
    if (layerCount === options.failAtLayer) throw new Error('Injected layer failure');
    const node = new Node(type);
    currentPage.appendChild(node);
    return node;
  }
  const figma = {
    root,
    get currentPage() { return currentPage; },
    set currentPage(_) { throw new Error('Use setCurrentPageAsync'); },
    async setCurrentPageAsync(page) { assert.ok(root.children.includes(page) && !page.removed); currentPage = page; },
    showUI() {},
    ui: { postMessage: message => messages.push(message) },
    notify: message => notifications.push(message),
    viewport: { scrollAndZoomIntoView: frames => { zoomed = frames; } },
    async loadFontAsync(font) {
      if (options.missingFonts || (options.fallback && font.family === 'Roboto')) throw new Error('Font unavailable');
      loaded.add(`${font.family}/${font.style}`);
    },
    createImage(bytes) {
      const info = imageInfo(Buffer.from(bytes));
      assert.ok(['image/png', 'image/jpeg', 'image/gif'].includes(info.mime), 'Image type is unsupported');
      assert.ok(info.width > 0 && info.height > 0 && info.width <= 4096 && info.height <= 4096);
      const hash = createHash('sha256').update(bytes).digest('hex');
      images.set(hash, Buffer.from(bytes));
      return { hash };
    },
    createPage,
    createFrame: () => create('FRAME'),
    createComponent: () => create('COMPONENT'),
    createRectangle: () => create('RECTANGLE'),
    createEllipse: () => create('ELLIPSE'),
    createText: () => create('TEXT'),
    createNodeFromSvg(svg) {
      checkSVG(svg);
      const node = create('FRAME');
      node.svg = svg;
      node.width = Number(svg.match(/width="([^"]+)"/)[1]);
      node.height = Number(svg.match(/height="([^"]+)"/)[1]);
      return node;
    },
    createTextStyle: () => createStyle('TEXT'),
    createPaintStyle: () => createStyle('PAINT'),
  };
  const context = { figma, __html__: '<p>Test</p>', Uint8Array, setTimeout: callback => { callback(); return 0; } };
  runInNewContext(read('figma-plugin/code.js'), context);
  return { figma, context, styles, removedStyles, messages, images, previousPage, existing, existingStyle, notifications, get zoomed() { return zoomed; } };
}

const importMessage = (theme = 'both', kit = true) => ({ type: 'import', theme, kit, data: payload });

test('native importer creates 50 editable frames, components and styles without changing existing work', async () => {
  const mock = mockFigma();
  await mock.figma.ui.onmessage(importMessage());
  assert.equal(mock.messages.at(-1).type, 'complete');
  assert.equal(mock.figma.root.children.length, 3);
  assert.equal(mock.previousPage.children.length, 1);
  assert.equal(mock.previousPage.children[0], mock.existing);
  assert.equal(mock.existing.name, 'Не менять');
  assert.ok(mock.styles.has(mock.existingStyle.id));
  assert.equal(mock.previousPage.selection[0], mock.existing);
  assert.equal(mock.images.size, 21);
  assert.equal(mock.zoomed.length, 4);
  assert.equal(mock.figma.currentPage.name, 'Anixart / Светлая');
  assert.equal(mock.notifications.length, 1);
  for (let p = 0; p < 2; p++) {
    const page = mock.figma.root.children[p + 1];
    assert.equal(page.children.length, 25);
    for (let i = 0; i < page.children.length; i++) {
      const frame = page.children[i];
      const screen = payload.pages[p].screens[i];
      assert.equal(frame.width, screen.w);
      assert.equal(frame.height, screen.h);
      assert.equal(frame.pluginData['export-id'], screen.id);
      assert.equal(frame.pluginData.source, screen.source);
      let layers = 0;
      let texts = 0;
      let components = 0;
      visit(frame, node => {
        layers++;
        if (node.type === 'COMPONENT') components++;
        if (node.type === 'TEXT') {
          texts++;
          assert.equal(node.fontName.family, 'Roboto');
          assert.ok(node._textStyleId);
          assert.ok(typeof node.characters === 'string');
        }
      });
      const record = sourceMap.screens.find(item => item.theme === payload.pages[p].theme && item.id === screen.id);
      assert.deepEqual({ layers, texts, components }, { layers: record.layers, texts: record.textLayers, components: record.components });
    }
  }
});

test('single-theme import can omit the component panel', async () => {
  const mock = mockFigma();
  await mock.figma.ui.onmessage(importMessage('dark', false));
  assert.equal(mock.messages.at(-1).type, 'complete');
  assert.equal(mock.figma.root.children.length, 2);
  assert.equal(mock.figma.currentPage.name, 'Anixart / Тёмная');
  assert.equal(mock.figma.currentPage.children.length, 24);
  visit(mock.figma.currentPage, node => assert.notEqual(node.type, 'COMPONENT'));
});

test('repeated imports create uniquely named pages rather than replacing earlier frames', async () => {
  const mock = mockFigma();
  await mock.figma.ui.onmessage(importMessage('light', false));
  const first = mock.figma.currentPage;
  const ids = first.children.map(node => node.id);
  await mock.figma.ui.onmessage(importMessage('light', false));
  assert.equal(mock.messages.at(-1).type, 'complete');
  assert.equal(mock.figma.currentPage.name, 'Anixart / Светлая (2)');
  assert.deepEqual(first.children.map(node => node.id), ids);
  assert.equal(mock.figma.root.children.length, 3);
});

test('missing Roboto falls back to loaded Inter and reports the substitution', async () => {
  const mock = mockFigma({ fallback: true });
  await mock.figma.ui.onmessage(importMessage('light', false));
  assert.equal(mock.messages.at(-1).type, 'complete');
  assert.match(mock.messages.at(-1).text, /Roboto недоступен: использован Inter/);
  visit(mock.figma.currentPage, node => { if (node.type === 'TEXT') assert.equal(node.fontName.family, 'Inter'); });
  for (const style of mock.styles.values()) if (style.type === 'TEXT') assert.ok(style.name.startsWith('Anixart / Inter /'));
});

test('failed import rolls back only newly created pages and styles, then can retry', async () => {
  const mock = mockFigma({ failAtLayer: 45 });
  await mock.figma.ui.onmessage(importMessage());
  assert.equal(mock.messages.at(-1).type, 'error');
  assert.match(mock.messages.at(-1).text, /Injected layer failure/);
  assert.equal(mock.figma.currentPage, mock.previousPage);
  assert.deepEqual(mock.figma.root.children, [mock.previousPage]);
  assert.deepEqual(mock.previousPage.children, [mock.existing]);
  assert.deepEqual([...mock.styles.keys()], [mock.existingStyle.id]);
  assert.ok(mock.removedStyles.length > 0);
  await mock.figma.ui.onmessage(importMessage('light', false));
  assert.equal(mock.messages.at(-1).type, 'complete');
});

test('invalid input or unavailable fonts fail before modifying the document', async () => {
  for (const [options, message] of [[{ missingFonts: true }, importMessage()], [{}, { type: 'import', data: { version: 99 } }], [{}, importMessage('invalid')]]) {
    const mock = mockFigma(options);
    await mock.figma.ui.onmessage(message);
    assert.equal(mock.messages.at(-1).type, 'error');
    assert.deepEqual(mock.figma.root.children, [mock.previousPage]);
    assert.deepEqual([...mock.styles.keys()], [mock.existingStyle.id]);
  }
});

test('duplicate concurrent requests are ignored and base64 decoding preserves bytes', async () => {
  const mock = mockFigma();
  for (const length of [0, 1, 2, 3, 4, 255, 256, 1024]) {
    const bytes = Buffer.from(Array.from({ length }, (_, i) => i % 256));
    assert.ok(Buffer.from(mock.context.decodeBase64(bytes.toString('base64'))).equals(bytes));
  }
  await Promise.all([mock.figma.ui.onmessage(importMessage('light', false)), mock.figma.ui.onmessage(importMessage('light', false))]);
  assert.equal(mock.figma.root.children.length, 2);
  assert.equal(mock.messages.filter(message => message.type === 'complete').length, 1);
});
