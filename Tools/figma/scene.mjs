import { readFileSync } from 'node:fs';
import { deflateRawSync } from 'node:zlib';

export const THEMES = {
  light: {
    bg: '#FFFFFF', grouped: '#F2F2F7', surface: '#FFFFFF', primary: '#000000',
    secondary: '#8A8A8E', tertiary: '#AEAEB2', separator: '#D1D1D6',
    subtle: '#F2F2F2', glass: '#F7F7F9', glassStroke: '#FFFFFF',
    accent: '#6B5CE8', accentSoft: '#E9E7FC', selected: '#E4E0F8',
    green: '#73C978', plan: '#C373C9', completed: '#6979CE',
    hold: '#FFD468', red: '#FF605B', rating: '#2EB366',
  },
  dark: {
    bg: '#000000', grouped: '#000000', surface: '#1C1C1E', primary: '#FFFFFF',
    secondary: '#98989F', tertiary: '#636366', separator: '#38383A',
    subtle: '#1C1C1E', glass: '#232325', glassStroke: '#68686C',
    accent: '#6B5CE8', accentSoft: '#201C39', selected: '#292345',
    green: '#73C978', plan: '#C373C9', completed: '#6979CE',
    hold: '#FFD468', red: '#FF605B', rating: '#2EB366',
  },
};

export const WATCH_LISTS = [
  ['Смотрю', 'play-circle', 'green'],
  ['В планах', 'clock', 'plan'],
  ['Просмотрено', 'check-circle', 'completed'],
  ['Отложено', 'pause-circle', 'hold'],
  ['Брошено', 'x-circle', 'red'],
];

// SF Symbols are system resources, not assets distributed by this project.
// These small editable vectors approximate only the symbols used in the mockup.
const ICONS = {
  search: '<circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 5 5"/>',
  house: '<path d="m3 10 9-7 9 7M5 9v11h5v-6h4v6h5V9"/>',
  grid: '<rect x="3" y="3" width="7" height="7" rx="1.3"/><rect x="14" y="3" width="7" height="7" rx="1.3"/><rect x="3" y="14" width="7" height="7" rx="1.3"/><rect x="14" y="14" width="7" height="7" rx="1.3"/>',
  bookmark: '<path d="M6 3h12v18l-6-4-6 4Z"/>',
  person: '<circle cx="12" cy="12" r="9.5"/><circle cx="12" cy="9" r="3"/><path d="M5.5 19c.7-3.6 3-5.2 6.5-5.2s5.8 1.6 6.5 5.2"/>',
  'person-fill': '<circle cx="12" cy="8" r="4" fill="currentColor" stroke="none"/><path d="M3.5 22v-2c0-5 3-7 8.5-7s8.5 2 8.5 7v2Z" fill="currentColor" stroke="none"/>',
  gear: '<path d="m9 3 .7-1h4.6l.7 1 .5 2 2 .9 1.8-.6 2.2 3.8-1.5 1.5v2.8l1.5 1.5-2.2 3.8-1.8-.6-2 .9-.5 2-.7 1H9l-.7-1-.5-2-2-.9-1.8.6-2.2-3.8 1.5-1.5v-2.8L1.8 9l2.2-3.8 1.8.6 2-.9Z"/><circle cx="12" cy="12" r="3.5"/>',
  bell: '<path d="M5 17h14l-2-3V9a5 5 0 0 0-10 0v5Z"/><path d="M10 21h4M12 2v2"/>',
  sliders: '<path d="M3 6h4m4 0h10M3 12h10m4 0h4M3 18h2m4 0h12"/><circle cx="9" cy="6" r="2"/><circle cx="15" cy="12" r="2"/><circle cx="7" cy="18" r="2"/>',
  filter: '<circle cx="12" cy="12" r="9.5"/><path d="M6 8h12M8 12h8M10 16h4"/>',
  calendar: '<rect x="3" y="5" width="18" height="16" rx="2.5"/><path d="M7 2v6M17 2v6M3 10h18M7 14h2m4 0h2m-8 4h2m4 0h2"/>',
  ellipsis: '<circle cx="5" cy="12" r="1.3" fill="currentColor" stroke="none"/><circle cx="12" cy="12" r="1.3" fill="currentColor" stroke="none"/><circle cx="19" cy="12" r="1.3" fill="currentColor" stroke="none"/>',
  'chevron-left': '<path d="m15 4-8 8 8 8"/>',
  'chevron-right': '<path d="m9 4 8 8-8 8"/>',
  'chevron-down': '<path d="m5 8 7 7 7-7"/>',
  'chevron-up': '<path d="m5 16 7-7 7 7"/>',
  check: '<path d="m4 12 5 5L20 6"/>',
  x: '<path d="m6 6 12 12M18 6 6 18"/>',
  'x-circle': '<circle cx="12" cy="12" r="9.5"/><path d="m8 8 8 8M16 8l-8 8"/>',
  'check-circle': '<circle cx="12" cy="12" r="9.5"/><path d="m7 12 3.5 3.5L17 9"/>',
  clock: '<circle cx="12" cy="12" r="9.5"/><path d="M12 6v6l4 2"/>',
  refresh: '<path d="M20 8a9 9 0 1 0 .2 8M20 3v6h-6"/>',
  sort: '<path d="M7 3v18m-4-4 4 4 4-4M17 21V3m-4 4 4-4 4 4"/>',
  play: '<path d="m7 3 14 9-14 9Z" fill="currentColor" stroke="none"/>',
  'play-circle': '<circle cx="12" cy="12" r="9.5"/><path d="m10 7 7 5-7 5Z" fill="currentColor" stroke="none"/>',
  'pause-circle': '<circle cx="12" cy="12" r="9.5"/><path d="M9 8v8M15 8v8"/>',
  star: '<path d="m12 2.5 3 6.2 6.9 1-5 4.8 1.2 6.8-6.1-3.2-6.1 3.2 1.2-6.8-5-4.8 6.9-1Z"/>',
  'star-fill': '<path d="m12 2.5 3 6.2 6.9 1-5 4.8 1.2 6.8-6.1-3.2-6.1 3.2 1.2-6.8-5-4.8 6.9-1Z" fill="currentColor" stroke="none"/>',
  info: '<circle cx="12" cy="12" r="9.5"/><path d="M12 10v7"/><circle cx="12" cy="6.5" r="1" fill="currentColor" stroke="none"/>',
  bubble: '<path d="M4 3h16a2 2 0 0 1 2 2v11a2 2 0 0 1-2 2h-8l-6 4v-4H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2Z"/>',
  film: '<rect x="3" y="3" width="18" height="18" rx="2"/><path d="M7 3v18M17 3v18M3 8h4m-4 8h4M17 8h4m-4 8h4"/>',
  'play-rectangle': '<rect x="2" y="5" width="20" height="14" rx="2.5"/><path d="m10 8 6 4-6 4Z" fill="currentColor" stroke="none"/>',
  globe: '<circle cx="12" cy="12" r="9.5"/><ellipse cx="12" cy="12" rx="4" ry="9.5"/><path d="M3 9h18M3 15h18"/>',
  target: '<circle cx="12" cy="12" r="9.5"/><circle cx="12" cy="12" r="5.5"/><circle cx="12" cy="12" r="1.5"/>',
  people: '<circle cx="9" cy="7" r="3"/><circle cx="18" cy="8" r="2.5"/><path d="M2 21v-3c0-4 3-6 7-6s7 2 7 6v3M17 13c4 0 5 2 5 6v2"/>',
  mic: '<rect x="8" y="2" width="8" height="13" rx="4"/><path d="M5 10v2a7 7 0 0 0 14 0v-2M12 19v3M8 22h8"/>',
  eye: '<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12Z"/><circle cx="12" cy="12" r="3"/>',
  'eye-slash': '<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12ZM3 3l18 18"/>',
  'arrow-up': '<path d="M12 21V3m-7 7 7-7 7 7"/>',
  plus: '<path d="M12 4v16M4 12h16"/>',
  shield: '<path d="m12 2 9 4v7c0 5-9 9-9 9s-9-4-9-9V6Z"/>',
  document: '<path d="M5 2h9l5 5v15H5ZM14 2v6h5M8 12h8M8 16h8"/>',
  clipboard: '<rect x="4" y="4" width="16" height="18" rx="2"/><rect x="8" y="2" width="8" height="5" rx="1.5"/><path d="M8 12h8M8 16h8"/>',
  stethoscope: '<path d="M3 3v5a6 6 0 0 0 12 0V3M3 3h2m8 0h2M9 14v3a5 5 0 0 0 10 0v-3"/><circle cx="19" cy="11" r="3"/>',
  chart: '<path d="M3 21V3M3 21h19"/><rect x="7" y="12" width="3" height="6" fill="currentColor"/><rect x="12" y="7" width="3" height="11" fill="currentColor"/><rect x="17" y="3" width="3" height="15" fill="currentColor"/>',
  layers: '<rect x="3" y="7" width="14" height="14" rx="2"/><path d="M7 7V3h14v14h-4"/>',
  crown: '<path d="m2 6 5 4 5-7 5 7 5-4-3 14H5Z" fill="currentColor" stroke="none"/>',
  'check-square': '<rect x="3" y="3" width="18" height="18" rx="3" fill="currentColor" stroke="none"/><path d="m7 12 3.5 3.5L17 9" stroke="white"/>',
  wifi: '<path d="M2 8c6-6 14-6 20 0M5 12c4-4 10-4 14 0M8 16c2-2 6-2 8 0"/><circle cx="12" cy="20" r="1" fill="currentColor"/>',
};

export function iconBody(name, color) {
  if (!ICONS[name]) throw new Error(`Unknown icon: ${name}`);
  return `<g color="${color}" fill="none" stroke="${color}" stroke-width="1.65" stroke-linecap="round" stroke-linejoin="round">${ICONS[name]}</g>`;
}

// Read the shipped TTF's metrics so Russian line wrapping follows Roboto,
// rather than a browser's platform-dependent fallback font. No npm dependency.
export class FontMetrics {
  constructor(path) {
    const data = readFileSync(path);
    this.data = data;
    const tables = {};
    for (let i = 0; i < data.readUInt16BE(4); i++) {
      const start = 12 + i * 16;
      tables[data.toString('ascii', start, start + 4)] = data.readUInt32BE(start + 8);
    }
    this.units = data.readUInt16BE(tables.head + 18);
    this.ascent = data.readInt16BE(tables.hhea + 4);
    this.descent = data.readInt16BE(tables.hhea + 6);
    this.hmtx = tables.hmtx;
    this.metricCount = data.readUInt16BE(tables.hhea + 34);
    const cmap = tables.cmap;
    const mappings = [];
    for (let i = 0; i < data.readUInt16BE(cmap + 2); i++) {
      const start = cmap + 4 + i * 8;
      const offset = cmap + data.readUInt32BE(start + 4);
      const format = data.readUInt16BE(offset);
      if (format === 4 || format === 12) mappings.push({ offset, format });
    }
    this.cmap = mappings.find(x => x.format === 12) || mappings.find(x => x.format === 4);
    if (!this.cmap) throw new Error(`No Unicode cmap in ${path}`);
  }

  glyph(code) {
    const { data, cmap } = this;
    const p = cmap.offset;
    if (cmap.format === 12) {
      const count = data.readUInt32BE(p + 12);
      for (let i = 0; i < count; i++) {
        const start = p + 16 + i * 12;
        const first = data.readUInt32BE(start);
        const last = data.readUInt32BE(start + 4);
        if (code >= first && code <= last) return data.readUInt32BE(start + 8) + code - first;
      }
      return 0;
    }
    const count = data.readUInt16BE(p + 6) / 2;
    const endBase = p + 14;
    const startBase = endBase + count * 2 + 2;
    const deltaBase = startBase + count * 2;
    const rangeBase = deltaBase + count * 2;
    for (let i = 0; i < count; i++) {
      if (code < data.readUInt16BE(startBase + i * 2) || code > data.readUInt16BE(endBase + i * 2)) continue;
      const delta = data.readInt16BE(deltaBase + i * 2);
      const range = data.readUInt16BE(rangeBase + i * 2);
      if (!range) return (code + delta) & 65535;
      const address = rangeBase + i * 2 + range + (code - data.readUInt16BE(startBase + i * 2)) * 2;
      if (address + 2 > data.length) return 0;
      const glyph = data.readUInt16BE(address);
      return glyph ? (glyph + delta) & 65535 : 0;
    }
    return 0;
  }

  measure(text, size) {
    let width = 0;
    for (const char of text) {
      const glyph = Math.min(this.metricCount - 1, this.glyph(char.codePointAt(0)));
      width += this.data.readUInt16BE(this.hmtx + glyph * 4);
    }
    return width / this.units * size;
  }

  baseline(size, lineHeight) {
    const actual = (this.ascent - this.descent) / this.units * size;
    return (lineHeight - actual) / 2 + this.ascent / this.units * size;
  }
}

export function wrapText(text, width, size, font, maxLines = Infinity) {
  const lines = [];
  for (const paragraph of String(text).split('\n')) {
    let current = '';
    for (const word of paragraph.split(/\s+/).filter(Boolean)) {
      const candidate = current ? `${current} ${word}` : word;
      if (current && font.measure(candidate, size) > width) {
        lines.push(current);
        current = '';
      }
      // Long studio names and URLs must not extend outside the text frame.
      if (font.measure(word, size) > width) {
        for (const char of word) {
          if (current && font.measure(current + char, size) > width) {
            lines.push(current);
            current = '';
          }
          current += char;
        }
      } else current = current ? `${current} ${word}` : word;
    }
    lines.push(current);
  }
  if (lines.length > maxLines) {
    lines.length = maxLines;
    let last = lines[maxLines - 1].trimEnd();
    while (last && font.measure(`${last}…`, size) > width) last = last.slice(0, -1).trimEnd();
    lines[maxLines - 1] = `${last}…`;
  }
  return lines;
}

export class Scene {
  constructor(meta, fonts) {
    this.meta = meta;
    this.fonts = fonts;
    this.p = THEMES[meta.theme];
    this.root = { type: 'group', name: meta.name, x: 0, y: 0, w: meta.w || 393, h: meta.h || 852, fill: this.p.bg, clip: true, children: [] };
    this.parent = this.root;
  }

  add(node) {
    this.parent.children.push(node);
    return node;
  }

  group(name, x, y, w, h, build, options = {}) {
    const group = this.add({ type: 'group', name, x, y, w, h, children: [], ...options });
    const parent = this.parent;
    this.parent = group;
    build(this);
    this.parent = parent;
    return group;
  }

  rect(name, x, y, w, h, fill, radius = 0, options = {}) {
    return this.add({ type: 'rect', name, x, y, w, h, fill, radius, ...options });
  }

  ellipse(name, x, y, w, h, fill, options = {}) {
    return this.add({ type: 'ellipse', name, x, y, w, h, fill, ...options });
  }

  line(x, y, w, color = this.p.separator) {
    return this.rect('Разделитель', x, y, w, 0.5, color);
  }

  text(name, text, x, y, w, size = 17, options = {}) {
    const weight = options.weight || 'Regular';
    const lineHeight = options.lineHeight || Math.ceil(size * 1.2);
    const lines = wrapText(text, w, size, this.fonts[weight], options.maxLines);
    const h = lines.length * lineHeight;
    this.add({ type: 'text', name, text: lines.join('\n'), x, y, w, h, size, weight, lineHeight, baseline: this.fonts[weight].baseline(size, lineHeight), color: this.p.primary, align: 'left', ...options });
    return h;
  }

  icon(name, x, y, size = 20, color = this.p.primary, options = {}) {
    return this.vector(`Иконка / ${name}`, iconBody(name, color), x, y, size, size, '0 0 24 24', options);
  }

  vector(name, body, x, y, w, h, viewBox = `0 0 ${w} ${h}`, options = {}) {
    return this.add({ type: 'vector', name, body, viewBox, x, y, w, h, ...options });
  }

  image(name, key, x, y, w, h, radius = 10, options = {}) {
    return this.add({ type: 'image', name, key, x, y, w, h, radius, ...options });
  }

  width(text, size = 17, weight = 'Regular') {
    return this.fonts[weight].measure(text, size);
  }

  export() {
    return { ...this.meta, w: this.root.w, h: this.root.h, root: this.root };
  }
}

export function xml(value) {
  return String(value).replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&apos;' })[char]);
}

function roundedPath(w, h, radii) {
  const [tl, tr, br, bl] = radii;
  return `M${tl} 0H${w - tr}Q${w} 0 ${w} ${tr}V${h - br}Q${w} ${h} ${w - br} ${h}H${bl}Q0 ${h} 0 ${h - bl}V${tl}Q0 0 ${tl} 0Z`;
}

export function renderSVG(screen, assets, fontsCSS = '') {
  let cursor = 0;
  const defs = [];
  const imageIds = new Map();
  function render(node) {
    const id = `layer-${++cursor}`;
    const label = `<title>${xml(node.name)}</title>`;
    const opacity = node.opacity === undefined ? '' : ` opacity="${node.opacity}"`;
    const stroke = node.stroke ? ` stroke="${node.stroke}" stroke-width="${node.strokeWidth || 1}" stroke-opacity="${node.strokeOpacity ?? 1}"` : '';
    let filter = '';
    if (node.blur || node.shadow) {
      const blur = node.blur ? `<feGaussianBlur stdDeviation="${node.blur}"/>` : '';
      const shadow = node.shadow ? `<feDropShadow dx="${node.shadow.x}" dy="${node.shadow.y}" stdDeviation="${node.shadow.radius / 2}" flood-color="${node.shadow.color}" flood-opacity="${node.shadow.opacity}"/>` : '';
      defs.push(`<filter id="blur-${id}" x="-30%" y="-30%" width="160%" height="160%">${blur}${shadow}</filter>`);
      filter = ` filter="url(#blur-${id})"`;
    }
    let fill = node.fill || 'none';
    if (node.gradient) {
      defs.push(`<linearGradient id="gradient-${id}" x1="0%" y1="100%" x2="0%" y2="0%">${node.gradient.map(stop => `<stop offset="${stop.position * 100}%" stop-color="${stop.color}" stop-opacity="${stop.opacity}"/>`).join('')}</linearGradient>`);
      fill = `url(#gradient-${id})`;
    }
    const box = `x="${node.x}" y="${node.y}" width="${node.w}" height="${node.h}"`;
    if (node.type === 'group') {
      let clip = '';
      const shape = Array.isArray(node.radius) ? `<path d="${roundedPath(node.w, node.h, node.radius)}"/>` : `<rect width="${node.w}" height="${node.h}" rx="${node.radius || 0}"/>`;
      if (node.clip) {
        defs.push(`<clipPath id="clip-${id}">${shape}</clipPath>`);
        clip = ` clip-path="url(#clip-${id})"`;
      }
      const background = node.fill ? shape.replace('/>', ` fill="${node.fill}"/>`) : '';
      return `<g id="${id}" data-name="${xml(node.name)}" transform="translate(${node.x} ${node.y})"${opacity}${clip}>${label}${background}${node.children.map(render).join('')}</g>`;
    }
    if (node.type === 'rect') {
      if (Array.isArray(node.radius)) return `<path id="${id}" transform="translate(${node.x} ${node.y})" d="${roundedPath(node.w, node.h, node.radius)}" fill="${fill}"${stroke}${opacity}${filter}>${label}</path>`;
      return `<rect id="${id}" ${box} rx="${node.radius || 0}" fill="${fill}"${stroke}${opacity}${filter}>${label}</rect>`;
    }
    if (node.type === 'ellipse') return `<ellipse id="${id}" cx="${node.x + node.w / 2}" cy="${node.y + node.h / 2}" rx="${node.w / 2}" ry="${node.h / 2}" fill="${node.fill || 'none'}"${stroke}${opacity}>${label}</ellipse>`;
    if (node.type === 'vector') return `<svg id="${id}" ${box} viewBox="${node.viewBox}"${opacity}>${label}${node.body}</svg>`;
    if (node.type === 'image') {
      const asset = assets[node.key];
      if (!asset) throw new Error(`Missing asset ${node.key}`);
      if (!imageIds.has(node.key)) {
        const imageId = `asset-${imageIds.size + 1}`;
        imageIds.set(node.key, imageId);
        defs.push(`<image id="${imageId}" width="${asset.width}" height="${asset.height}" xlink:href="data:${asset.mime};base64,${asset.data}"/>`);
      }
      const scale = Math[node.fit === 'FIT' ? 'min' : 'max'](node.w / asset.width, node.h / asset.height);
      const sx = scale / node.w;
      const sy = scale / node.h;
      const tx = (node.w - asset.width * scale) / (2 * node.w);
      const ty = (node.h - asset.height * scale) / (2 * node.h);
      // The same image/pattern structure Figma uses in its own SVG exports.
      // Store each poster once, even on an overview containing many screens.
      defs.push(`<pattern id="pattern-${id}" patternContentUnits="objectBoundingBox" width="1" height="1"><use xlink:href="#${imageIds.get(node.key)}" transform="matrix(${sx} 0 0 ${sy} ${tx} ${ty})"/></pattern>`);
      return `<rect id="${id}" ${box} rx="${node.radius || 0}" fill="url(#pattern-${id})"${stroke}${opacity}${filter}>${label}</rect>`;
    }
    if (node.type === 'text') {
      const weight = { Regular: 400, Medium: 500, Bold: 700 }[node.weight];
      const x = node.align === 'center' ? node.x + node.w / 2 : node.align === 'right' ? node.x + node.w : node.x;
      const anchor = { left: 'start', center: 'middle', right: 'end' }[node.align];
      const spans = node.text.split('\n').map((line, i) => `<tspan x="${x}" y="${node.y + node.baseline + i * node.lineHeight}">${xml(line)}</tspan>`).join('');
      return `<text id="${id}" font-family="Roboto" font-size="${node.size}" font-weight="${weight}" fill="${node.color}" text-anchor="${anchor}"${opacity}${node.underline ? ' text-decoration="underline"' : ''}>${label}${spans}</text>`;
    }
    throw new Error(`Unknown node type: ${node.type}`);
  }
  const body = render(screen.root);
  return `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="${screen.w}" height="${screen.h}" viewBox="0 0 ${screen.w} ${screen.h}"><title>${xml(screen.name)}</title><desc>${xml(screen.notes || '')} Источник: ${xml(screen.source || '')}</desc><defs>${fontsCSS ? `<style>${fontsCSS}</style>` : ''}${defs.join('')}</defs>${body}</svg>`;
}

export function walkNodes(root, visit) {
  visit(root);
  for (const child of root.children || []) walkNodes(child, visit);
}

export function crc32(buffer) {
  let crc = 0xFFFFFFFF;
  for (const byte of buffer) {
    crc ^= byte;
    for (let i = 0; i < 8; i++) crc = (crc >>> 1) ^ (0xEDB88320 & -(crc & 1));
  }
  return (crc ^ 0xFFFFFFFF) >>> 0;
}

// A portable ZIP writer keeps the design export independent of OS-specific tools.
export function zipFiles(files) {
  const entries = [];
  const directories = [];
  let offset = 0;
  for (const { name, data } of files) {
    const filename = Buffer.from(name.replaceAll('\\', '/'));
    const compressed = deflateRawSync(data, { level: 9 });
    const crc = crc32(data);
    const header = Buffer.alloc(30);
    header.writeUInt32LE(0x04034B50, 0);
    header.writeUInt16LE(20, 4);
    header.writeUInt16LE(0x800, 6);
    header.writeUInt16LE(8, 8);
    header.writeUInt16LE(0x21, 12); // 1980-01-01: deterministic archive metadata.
    header.writeUInt32LE(crc, 14);
    header.writeUInt32LE(compressed.length, 18);
    header.writeUInt32LE(data.length, 22);
    header.writeUInt16LE(filename.length, 26);
    entries.push(header, filename, compressed);
    const directory = Buffer.alloc(46);
    directory.writeUInt32LE(0x02014B50, 0);
    directory.writeUInt16LE(20, 4);
    directory.writeUInt16LE(20, 6);
    directory.writeUInt16LE(0x800, 8);
    directory.writeUInt16LE(8, 10);
    directory.writeUInt16LE(0x21, 14);
    directory.writeUInt32LE(crc, 16);
    directory.writeUInt32LE(compressed.length, 20);
    directory.writeUInt32LE(data.length, 24);
    directory.writeUInt16LE(filename.length, 28);
    directory.writeUInt32LE(offset, 42);
    directories.push(directory, filename);
    offset += header.length + filename.length + compressed.length;
  }
  const directory = Buffer.concat(directories);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054B50, 0);
  end.writeUInt16LE(files.length, 8);
  end.writeUInt16LE(files.length, 10);
  end.writeUInt32LE(directory.length, 12);
  end.writeUInt32LE(offset, 16);
  return Buffer.concat([...entries, directory, end]);
}
