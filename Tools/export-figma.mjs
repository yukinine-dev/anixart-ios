// Rebuild the Figma-compatible design from a cached, sanitized public API sample.
// Node 20+; no packages needed. --refresh-assets performs only catalogue reads.
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync, copyFileSync } from 'node:fs';
import { join, extname, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { Scene, FontMetrics, THEMES, renderSVG, walkNodes, zipFiles, xml } from './figma/scene.mjs';
import { SCREEN_SPECS, makeScreens, makeKit } from './figma/screens.mjs';
import { imageInfo, normalizeImages } from './figma/images.mjs';

const ROOT = fileURLToPath(new URL('../', import.meta.url));
const OUT = join(ROOT, 'design', 'figma');
const ASSETS = join(OUT, 'assets');
const CACHE = join(ASSETS, 'content.json');
const API = 'https://api-s.anixsekai.com/';
const FONTS = join(ROOT, 'Anixart', 'Resources', 'Fonts');
const WEIGHTS = ['Regular', 'Medium', 'Bold'];

mkdirSync(ASSETS, { recursive: true });

async function api(path, body) {
  const response = await fetch(new URL(path, API), {
    method: body === undefined ? 'GET' : 'POST',
    headers: body === undefined ? {} : { 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(30000),
  });
  if (!response.ok) throw new Error(`HTTP ${response.status}: ${path}`);
  const data = await response.json();
  if (data.code !== 0) throw new Error(`API code ${data.code}: ${path}`);
  return data;
}

function releaseSample(raw) {
  const keys = ['id', 'image', 'title_ru', 'title_original', 'title_alt', 'description', 'grade', 'year', 'season', 'episodes_released', 'episodes_total', 'status_id', 'country', 'studio', 'director', 'author', 'source', 'genres', 'duration', 'category', 'status', 'favorites_count', 'vote_count', 'vote_1_count', 'vote_2_count', 'vote_3_count', 'vote_4_count', 'vote_5_count'];
  const result = {};
  for (const key of keys) if (raw[key] !== undefined) result[key] = raw[key];
  result.title_ru = raw.title_ru || raw.title_original || 'Без названия';
  result.grade = Number(raw.grade) || 0;
  const update = raw.episode_last_update;
  if (update) {
    const values = [update.last_episode_update_name, update.last_episode_type_update_name, update.last_episode_source_update_name].filter(Boolean);
    if (values.length) result.lastEpisodeLine = 'Добавлено: ' + values.join(' | ');
  }
  return result;
}

async function refreshContent() {
  console.log('Fetching public catalogue samples (no account or token)…');
  const requests = {
    home: ['filter/0?extended_mode=false', { sort: 0, country: 'Япония' }],
    catalog: ['filter/0?extended_mode=false', { sort: 0 }],
    discussing: ['discover/discussing', null],
    banners: ['discover/interesting', null],
    detail: ['release/18846?extended_mode=true'],
    types: ['episode/18846'],
    schedule: ['schedule'],
    search: ['search/releases/0', { query: 'Киберпанк', searchBy: 0 }],
  };
  const names = Object.keys(requests);
  const responses = await Promise.allSettled(names.map(name => api(...requests[name])));
  const raw = {};
  for (let i = 0; i < names.length; i++) {
    if (responses[i].status === 'fulfilled') raw[names[i]] = responses[i].value;
    else throw new Error(`${names[i]}: ${responses[i].reason.message}`);
  }
  const data = {
    fetchedAt: new Date().toISOString(),
    api: API,
    provenance: 'Only public release, banner, schedule and voice-over fields are retained. No API comments, profiles, tokens or watch history are saved.',
    home: (raw.home.content || []).slice(0, 4).map(releaseSample),
    catalog: (raw.catalog.content || []).slice(0, 9).map(releaseSample),
    discussing: (raw.discussing.content || []).slice(0, 5).map(releaseSample),
    banners: (raw.banners.content || []).filter(x => x.is_hidden !== true).slice(0, 2).map(x => ({ id: x.id, title: x.title, description: x.description, image: x.image })),
    detail: releaseSample(raw.detail.release),
    types: (raw.types.types || []).slice(0, 7).map(x => ({ id: x.id, name: x.name, image: x.icon, is_sub: x.is_sub, episodes_count: x.episodes_count, view_count: x.view_count })),
    schedule: (raw.schedule.saturday || []).slice(0, 4).map(releaseSample),
    search: (raw.search.content || []).slice(0, 5).map(releaseSample),
    assets: {},
  };
  if (!data.home.length || !data.catalog.length || !data.discussing.length || !data.banners.length || !data.types.length) throw new Error('Public sample is empty; no misleading placeholder catalogue will be exported.');

  const byURL = new Map();
  const jobs = [];
  function register(object, prefix) {
    if (!object.image) return;
    const url = new URL(object.image);
    const allowed = ['s.anixmirai.com', 's3.anixmirai.com', 'static.anixart.tv', 's.anixart.tv', 'static.anixmirai.com'];
    if (url.protocol !== 'https:' || !allowed.includes(url.hostname)) throw new Error(`Unexpected image host: ${url.hostname}`);
    if (byURL.has(object.image)) {
      object.imageKey = byURL.get(object.image);
      return;
    }
    const key = `${prefix}-${object.id}`;
    object.imageKey = key;
    byURL.set(object.image, key);
    const extension = extname(url.pathname).toLowerCase();
    if (!['.jpg', '.jpeg', '.png', '.webp'].includes(extension)) throw new Error(`Unsupported image format: ${url.pathname}`);
    const file = key + extension;
    jobs.push(async () => {
      const response = await fetch(url, { signal: AbortSignal.timeout(30000) });
      if (!response.ok) throw new Error(`Image HTTP ${response.status}: ${url}`);
      const bytes = Buffer.from(await response.arrayBuffer());
      const mime = (response.headers.get('content-type') || '').split(';')[0];
      if (!mime.startsWith('image/')) throw new Error(`Not an image: ${url}`);
      const dimensions = imageInfo(bytes);
      writeFileSync(join(ASSETS, file), bytes);
      data.assets[key] = { file, source: object.image, mime, ...dimensions };
    });
  }
  for (const release of [...data.home, ...data.catalog, ...data.discussing, data.detail, ...data.schedule, ...data.search]) register(release, 'poster');
  for (const banner of data.banners) register(banner, 'banner');
  for (const type of data.types) register(type, 'voiceover');
  // Bound concurrency so refreshing the design does not flood the image host.
  for (let i = 0; i < jobs.length; i += 6) await Promise.all(jobs.slice(i, i + 6).map(job => job()));
  normalizeImages(data, ASSETS);
  writeFileSync(CACHE, JSON.stringify(data, null, 2) + '\n');
  return data;
}

function fontCSS() {
  return WEIGHTS.map(weight => `@font-face{font-family:Roboto;font-style:normal;font-weight:${{ Regular: 400, Medium: 500, Bold: 700 }[weight]};src:url(data:font/ttf;base64,${readFileSync(join(FONTS, `Roboto-${weight}.ttf`)).toString('base64')}) format('truetype');}`).join('');
}

function board(screens, fonts, theme) {
  const columns = 4;
  const gap = 64;
  const rowHeight = 954;
  const width = 96 + columns * 393 + (columns - 1) * gap;
  const height = 194 + Math.ceil(screens.length / columns) * rowHeight;
  const scene = new Scene({ id: 'board', name: `Anixart · ${theme === 'light' ? 'светлая' : 'тёмная'} тема`, theme, w: width, h: height, source: 'Текущий SwiftUI-код приложения', notes: 'Реконструкция интерфейса, а не снимки работающего приложения.' }, fonts);
  scene.root.fill = theme === 'light' ? '#E8E8ED' : '#151518';
  scene.text('Название макета', 'Anixart · текущий интерфейс', 48, 36, width - 96, 34, { weight: 'Bold' });
  scene.text('Описание макета', `${screens.length} экранов · iPhone 393 × 852 · ${theme === 'light' ? 'светлая тема' : 'тёмная тема'} · Roboto`, 48, 88, width - 96, 17, { color: scene.p.secondary });
  scene.text('Ограничения точности', 'Реконструкция по исходникам. Системные панели iOS 26 и Liquid Glass приближены; данные аккаунта — примеры.', 48, 119, width - 96, 15, { color: scene.p.secondary });
  screens.forEach((screen, i) => {
    const x = 48 + (i % columns) * (393 + gap);
    const y = 198 + Math.floor(i / columns) * rowHeight;
    scene.text('Подпись экрана', `${String(i + 1).padStart(2, '0')} · ${screen.name}`, x, y - 31, 393, 17, { weight: 'Medium', maxLines: 1 });
    const root = structuredClone(screen.root);
    root.x = x;
    root.y = y;
    scene.add(root);
    scene.text('Состояние экрана', screen.notes, x, y + 868, 393, 12, { color: scene.p.secondary, maxLines: 2, lineHeight: 15 });
  });
  return scene.export();
}

function previewHTML() {
  const cards = SCREEN_SPECS.map(([id, name, source, notes], i) => `<article><div class="caption"><span>${String(i + 1).padStart(2, '0')}</span><h2>${xml(name)}</h2></div><a class="screen-link" href="screens/light/${id}.svg" target="_blank" rel="noopener"><img data-screen="${id}" src="screens/light/${id}.svg" width="393" height="852" loading="lazy" alt="${xml(name)}"></a><p>${xml(notes)}</p><small>${xml(source)}</small></article>`).join('');
  return `<!doctype html>
<html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Anixart · текущий интерфейс</title><style>
@font-face{font-family:Roboto;src:url(fonts/Roboto-Regular.ttf)}@font-face{font-family:Roboto;font-weight:700;src:url(fonts/Roboto-Bold.ttf)}
*{box-sizing:border-box}body{margin:0;background:#eeeef2;color:#202024;font:15px/1.5 Roboto,Arial,sans-serif}header{padding:32px max(24px,calc((100vw - 1550px)/2));background:#fff;border-bottom:1px solid #d8d8de}h1{margin:0 0 6px;font-size:30px}header p{margin:0 0 18px;color:#686870}.actions{display:flex;gap:12px;flex-wrap:wrap;align-items:center}.actions a,button{border:1px solid #d8d8de;border-radius:9px;background:#fff;padding:9px 13px;color:#333;text-decoration:none;font:inherit;cursor:pointer}button[aria-pressed="true"]{background:#6b5ce8;color:white;border-color:#6b5ce8}main{max-width:1550px;margin:28px auto;padding:0 24px;display:grid;grid-template-columns:repeat(auto-fit,minmax(235px,1fr));gap:30px 24px}article{min-width:0}.caption{display:flex;align-items:baseline;gap:9px;margin-bottom:12px}.caption span{color:#909098;font-size:12px}h2{margin:0;font-size:15px}.screen-link{display:block;line-height:0;border:1px solid #d1d1d6;overflow:hidden;border-radius:16px;background:#fff}.screen-link:focus-visible{outline:3px solid #6b5ce8;outline-offset:4px}img{display:block;width:100%;height:auto}article p{font-size:12px;color:#686870;min-height:54px;margin:12px 0 5px}small{display:block;overflow-wrap:anywhere;color:#909098;font-size:10px}body.dark{background:#151518;color:#f0f0f2}body.dark header{background:#202024;border-color:#38383a}body.dark .actions a,body.dark button:not([aria-pressed="true"]){background:#28282c;color:#eee;border-color:#48484d}body.dark .screen-link{border-color:#48484d}footer{max-width:1550px;margin:24px auto;padding:0 24px 32px;color:#808088;font-size:12px}
</style></head><body><header><h1>Anixart · текущий интерфейс</h1><p>${SCREEN_SPECS.length} экранов в двух темах. Это макет по SwiftUI-коду, не скриншоты. Нажмите на экран, чтобы открыть его SVG.</p><div class="actions"><button data-theme="light" aria-pressed="true">Светлая</button><button data-theme="dark" aria-pressed="false">Тёмная</button><a id="board" href="Anixart-current-ui-light.svg" target="_blank" rel="noopener">Вся тема одним SVG</a><a href="Anixart-Figma.zip" download>Скачать комплект</a><a href="README.md">Как открыть в Figma</a></div></header><main>${cards}</main><footer>Постеры и баннеры — из публичного API Anixart. Образцы аккаунта и комментариев вымышлены. Файлы SVG содержат изображения и шрифты; импортёр Figma работает полностью офлайн.</footer><script>document.querySelectorAll('[data-theme]').forEach(button=>button.addEventListener('click',()=>{const theme=button.dataset.theme;document.body.classList.toggle('dark',theme==='dark');document.querySelectorAll('[data-theme]').forEach(x=>x.setAttribute('aria-pressed',String(x===button)));document.querySelectorAll('[data-screen]').forEach(image=>{const path='screens/'+theme+'/'+image.dataset.screen+'.svg';image.src=path;image.parentElement.href=path});document.getElementById('board').href='Anixart-current-ui-'+theme+'.svg'}));</script></body></html>`;
}

function collectFiles(directory, files = []) {
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) collectFiles(path, files);
    else if (!entry.name.endsWith('.zip')) files.push({ name: 'Anixart-Figma/' + relative(OUT, path).replaceAll('\\', '/'), data: readFileSync(path) });
  }
  return files;
}

const data = !existsSync(CACHE) || process.argv.includes('--refresh-assets') ? await refreshContent() : JSON.parse(readFileSync(CACHE, 'utf8'));
if (normalizeImages(data, ASSETS)) writeFileSync(CACHE, JSON.stringify(data, null, 2) + '\n');
const project = readFileSync(join(ROOT, 'project.yml'), 'utf8');
const version = project.match(/MARKETING_VERSION:\s*"([^"]+)"/)?.[1] || '—';
const build = project.match(/CURRENT_PROJECT_VERSION:\s*"([^"]+)"/)?.[1] || '—';
data.appVersion = `${version} (${build})`;
const fonts = Object.fromEntries(WEIGHTS.map(weight => [weight, new FontMetrics(join(FONTS, `Roboto-${weight}.ttf`))]));
const css = fontCSS();
const assets = Object.fromEntries(Object.entries(data.assets).map(([key, asset]) => [key, { ...asset, data: readFileSync(join(ASSETS, asset.file)).toString('base64') }]));
const pages = [];
for (const theme of ['light', 'dark']) {
  const screens = makeScreens(data, fonts, assets, theme);
  const directory = join(OUT, 'screens', theme);
  mkdirSync(directory, { recursive: true });
  for (const screen of screens) writeFileSync(join(directory, `${screen.id}.svg`), renderSVG(screen, assets, css));
  writeFileSync(join(OUT, `Anixart-current-ui-${theme}.svg`), renderSVG(board(screens, fonts, theme), assets, css));
  const kit = makeKit(data, fonts, theme);
  writeFileSync(join(OUT, `Anixart-components-${theme}.svg`), renderSVG(kit, assets, css));
  pages.push({ name: `Anixart / ${theme === 'light' ? 'Светлая' : 'Тёмная'}`, theme, screens: [...screens, kit] });
}

const fontOutput = join(OUT, 'fonts');
mkdirSync(fontOutput, { recursive: true });
for (const weight of WEIGHTS) copyFileSync(join(FONTS, `Roboto-${weight}.ttf`), join(fontOutput, `Roboto-${weight}.ttf`));
copyFileSync(join(FONTS, 'LICENSE.txt'), join(fontOutput, 'LICENSE.txt'));
writeFileSync(join(OUT, 'preview.html'), previewHTML());

const payload = { version: 1, themes: THEMES, assets, pages };
const plugin = join(OUT, 'figma-plugin');
mkdirSync(plugin, { recursive: true });
copyFileSync(join(ROOT, 'Tools', 'figma', 'manifest.json'), join(plugin, 'manifest.json'));
copyFileSync(join(ROOT, 'Tools', 'figma', 'importer.js'), join(plugin, 'code.js'));
const template = readFileSync(join(ROOT, 'Tools', 'figma', 'ui.template.html'), 'utf8');
writeFileSync(join(plugin, 'ui.html'), template.replace('__SCREEN_COUNT__', String(SCREEN_SPECS.length)).replace('__DESIGN_DATA__', JSON.stringify(payload).replaceAll('<', '\\u003c')));

const sources = [...new Set([
  ...SCREEN_SPECS.map(x => x[2]),
  'Anixart/App/RootView.swift', 'Anixart/Support/Theme.swift', 'Anixart/Support/Typography.swift',
  'Anixart/Components/ReleaseCard.swift', 'Anixart/Components/ReleaseListRow.swift', 'Anixart/Components/ReleasePoster.swift',
  'Anixart/Components/FilterFields.swift', 'Anixart/Features/Home/HomePreferences.swift',
  'Anixart/Features/Home/HomeTab.swift', 'Anixart/Features/Home/HomeTabListView.swift',
  'Anixart/Features/Profile/ProfileSections.swift', 'Anixart/Features/Player/PlayerChoice.swift',
  'Packages/AnixartKit/Sources/AnixartKit/Models/Release+Display.swift',
  'Packages/AnixartKit/Sources/AnixartKit/Models/Enums.swift',
  'project.yml',
])].map(path => ({ path, sha256: createHash('sha256').update(readFileSync(join(ROOT, path))).digest('hex') }));
let commit = 'unknown';
try { commit = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: ROOT, encoding: 'utf8' }).trim(); } catch {}
const manifest = {
  generatedAt: new Date().toISOString(),
  commit,
  sourceBasis: 'Current working tree, including uncommitted UI changes; source hashes below are authoritative.',
  viewport: { width: 393, height: 852 },
  screenCountPerTheme: SCREEN_SPECS.length,
  themes: ['light', 'dark'],
  accuracy: 'Source-based reconstruction, not simulator screenshots. System chrome, secondary colours and static Liquid Glass are approximations. No runtime visual equivalence is claimed.',
  excluded: 'Secondary account/security/social/theme/badge screens, every possible loading/error state and external web player content are not exhaustively modelled. Long screens show the viewport, not all off-screen content.',
  sampleFetchedAt: data.fetchedAt,
  accountData: 'Synthetic. Public API comments and user profiles are not retained.',
  sources,
  screens: pages.flatMap(page => page.screens.map(screen => {
    let layers = 0;
    let textLayers = 0;
    let components = 0;
    walkNodes(screen.root, node => { layers++; if (node.type === 'text') textLayers++; if (node.component) components++; });
    return { id: screen.id, theme: page.theme, name: screen.name, source: screen.source, notes: screen.notes, width: screen.w, height: screen.h, kit: Boolean(screen.kit), layers, textLayers, components };
  })),
};
writeFileSync(join(OUT, 'source-map.json'), JSON.stringify(manifest, null, 2) + '\n');

const archive = zipFiles(collectFiles(OUT));
writeFileSync(join(OUT, 'Anixart-Figma.zip'), archive);
console.log(`Exported ${SCREEN_SPECS.length * 2} screens, 2 component panels, ${Object.keys(assets).length} image assets.`);
console.log(`Preview: ${join(OUT, 'preview.html')}`);
console.log(`Figma SVG: ${join(OUT, 'Anixart-current-ui-light.svg')}`);
console.log(`Archive: ${(archive.length / 1024 / 1024).toFixed(1)} MB`);
