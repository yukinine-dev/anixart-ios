/* Local Figma importer. Generated scene data is embedded in ui.html.
 * No network, credentials, edits to existing pages, or external dependencies.
 */
figma.showUI(__html__, { width: 390, height: 450, themeColors: false });

let importing = false;

function rgb(hex) {
  const value = hex.replace('#', '');
  return {
    r: parseInt(value.slice(0, 2), 16) / 255,
    g: parseInt(value.slice(2, 4), 16) / 255,
    b: parseInt(value.slice(4, 6), 16) / 255,
  };
}

function paint(hex, opacity = 1) {
  return { type: 'SOLID', color: rgb(hex), opacity };
}

function decodeBase64(input) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  const length = Math.floor(input.length * 3 / 4) - (input.endsWith('==') ? 2 : input.endsWith('=') ? 1 : 0);
  const output = new Uint8Array(length);
  let value = 0;
  let bits = 0;
  let cursor = 0;
  for (let i = 0; i < input.length; i++) {
    const next = alphabet.indexOf(input[i]);
    if (next < 0) continue;
    value = (value << 6) | next;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      output[cursor++] = (value >>> bits) & 255;
    }
  }
  return output;
}

function escapeXML(value) {
  return String(value).replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&apos;' })[char]);
}

async function prepareFonts() {
  const fonts = {};
  let fallback = false;
  for (const weight of ['Regular', 'Medium', 'Bold']) {
    try {
      fonts[weight] = { family: 'Roboto', style: weight };
      await figma.loadFontAsync(fonts[weight]);
    } catch (_) {
      fonts[weight] = { family: 'Inter', style: weight };
      await figma.loadFontAsync(fonts[weight]);
      fallback = true;
    }
  }
  return { fonts, fallback };
}

async function applyAppearance(node, spec, styles) {
  if (spec.type !== 'vector' && spec.type !== 'text') {
    node.fills = spec.fill ? [paint(spec.fill)] : [];
    if (spec.fill && styles[spec.fill]) await node.setFillStyleIdAsync(styles[spec.fill]);
    if (spec.gradient) {
      node.fills = [{
        type: 'GRADIENT_LINEAR',
        gradientTransform: [[0, -1, 1], [1, 0, 0]],
        gradientStops: spec.gradient.map(stop => ({ position: stop.position, color: { ...rgb(stop.color), a: stop.opacity } })),
      }];
    }
    if (spec.stroke) {
      node.strokes = [paint(spec.stroke, spec.strokeOpacity === undefined ? 1 : spec.strokeOpacity)];
      node.strokeWeight = spec.strokeWidth || 1;
      node.strokeAlign = 'INSIDE';
    }
  }
  if (spec.radius !== undefined) {
    if (Array.isArray(spec.radius)) {
      [node.topLeftRadius, node.topRightRadius, node.bottomRightRadius, node.bottomLeftRadius] = spec.radius;
    } else node.cornerRadius = spec.radius;
  }
  if (spec.opacity !== undefined) node.opacity = spec.opacity;
  const effects = [];
  if (spec.blur) effects.push({ type: 'LAYER_BLUR', radius: spec.blur, visible: true });
  if (spec.materialBlur) effects.push({ type: 'BACKGROUND_BLUR', radius: spec.materialBlur, visible: true });
  if (spec.shadow) effects.push({ type: 'DROP_SHADOW', color: { ...rgb(spec.shadow.color), a: spec.shadow.opacity }, offset: { x: spec.shadow.x, y: spec.shadow.y }, radius: spec.shadow.radius, spread: 0, visible: true, blendMode: 'NORMAL' });
  if (effects.length) node.effects = effects;
}

async function createLayer(spec, parent, context) {
  let node;
  if (spec.type === 'group') node = spec.component ? figma.createComponent() : figma.createFrame();
  else if (spec.type === 'rect' || spec.type === 'image') node = figma.createRectangle();
  else if (spec.type === 'ellipse') node = figma.createEllipse();
  else if (spec.type === 'text') node = figma.createText();
  else if (spec.type === 'vector') {
    node = figma.createNodeFromSvg(`<svg xmlns="http://www.w3.org/2000/svg" width="${spec.w}" height="${spec.h}" viewBox="${escapeXML(spec.viewBox)}">${spec.body}</svg>`);
  } else throw new Error(`Неизвестный слой: ${spec.type}`);

  parent.appendChild(node);
  node.name = spec.name;
  node.x = spec.x;
  node.y = spec.y;
  if (spec.type !== 'vector' && spec.type !== 'text') node.resize(spec.w, spec.h);

  if (spec.type === 'group') {
    node.clipsContent = Boolean(spec.clip);
    node.layoutMode = 'NONE';
  }
  await applyAppearance(node, spec, context.paintStyles);
  if (spec.type === 'image') {
    if (!context.images[spec.key]) throw new Error(`Постер не найден: ${spec.key}`);
    node.fills = [{ type: 'IMAGE', imageHash: context.images[spec.key], scaleMode: spec.fit || 'FILL' }];
  }
  if (spec.type === 'text') {
    node.fontName = context.fonts[spec.weight];
    node.fontSize = spec.size;
    node.characters = spec.text;
    node.lineHeight = { unit: 'PIXELS', value: spec.lineHeight };
    node.textAlignHorizontal = { left: 'LEFT', center: 'CENTER', right: 'RIGHT' }[spec.align];
    node.textAutoResize = 'HEIGHT';
    node.resize(spec.w, spec.h);
    node.fills = [paint(spec.color)];
    if (context.paintStyles[spec.color]) await node.setFillStyleIdAsync(context.paintStyles[spec.color]);
    if (spec.underline) node.textDecoration = 'UNDERLINE';
    const styleKey = `${spec.weight}/${spec.size}/${spec.lineHeight}`;
    if (context.textStyles[styleKey]) await node.setTextStyleIdAsync(context.textStyles[styleKey]);
  }
  for (const child of spec.children || []) await createLayer(child, node, context);
  return node;
}

function collectTextStyles(root, map) {
  if (root.type === 'text') map[`${root.weight}/${root.size}/${root.lineHeight}`] = root;
  for (const child of root.children || []) collectTextStyles(child, map);
}

function uniquePageName(base) {
  const names = figma.root.children.map(page => page.name);
  let candidate = base;
  let suffix = 2;
  while (names.includes(candidate)) candidate = `${base} (${suffix++})`;
  return candidate;
}

figma.ui.onmessage = async message => {
  if (message.type !== 'import' || importing) return;
  importing = true;
  // Only newly created objects are rolled back if this import fails.
  const createdPages = [];
  const createdStyles = [];
  const previousPage = figma.currentPage;
  try {
    const data = message.data;
    if (!data || data.version !== 1 || !Array.isArray(data.pages)) throw new Error('Неверный формат макета');
    const { fonts, fallback } = await prepareFonts();
    const pages = data.pages
      .filter(page => message.theme === 'both' || page.theme === message.theme)
      .map(page => ({ ...page, screens: page.screens.filter(screen => message.kit || !screen.kit) }));
    if (!pages.length) throw new Error('Выберите хотя бы одну тему');
    const images = {};
    for (const [key, asset] of Object.entries(data.assets)) {
      images[key] = figma.createImage(decodeBase64(asset.data)).hash;
    }
    const textSpecs = {};
    for (const page of pages) for (const screen of page.screens) collectTextStyles(screen.root, textSpecs);
    const textStyles = {};
    for (const [key, spec] of Object.entries(textSpecs)) {
      const style = figma.createTextStyle();
      createdStyles.push(style);
      style.name = `Anixart / ${fonts[spec.weight].family} / ${key}`;
      style.fontName = fonts[spec.weight];
      style.fontSize = spec.size;
      style.lineHeight = { unit: 'PIXELS', value: spec.lineHeight };
      textStyles[key] = style.id;
    }
    let firstPage;
    let firstFrames;
    const total = pages.reduce((sum, page) => sum + page.screens.length, 0);
    let done = 0;
    for (const pageSpec of pages) {
      const page = figma.createPage();
      createdPages.push(page);
      page.name = uniquePageName(pageSpec.name);
      await figma.setCurrentPageAsync(page);
      page.backgrounds = [paint(pageSpec.theme === 'dark' ? '#151518' : '#E8E8ED')];
      const paintStyles = {};
      for (const [name, hex] of Object.entries(data.themes[pageSpec.theme])) {
        if (paintStyles[hex]) continue;
        const style = figma.createPaintStyle();
        createdStyles.push(style);
        style.name = `Anixart / ${pageSpec.theme} / ${name}`;
        style.paints = [paint(hex)];
        paintStyles[hex] = style.id;
      }
      const context = { fonts, images, paintStyles, textStyles };
      const frames = [];
      for (let i = 0; i < pageSpec.screens.length; i++) {
        const screen = pageSpec.screens[i];
        const frame = await createLayer(screen.root, page, context);
        frame.name = `${String(i + 1).padStart(2, '0')} · ${screen.name}`;
        frame.x = screen.kit ? 0 : (i % 4) * 465;
        frame.y = screen.kit ? Math.ceil(i / 4) * 940 : Math.floor(i / 4) * 940;
        frame.setPluginData('source', screen.source || '');
        frame.setPluginData('notes', screen.notes || '');
        frame.setPluginData('export-id', screen.id);
        frames.push(frame);
        done++;
        figma.ui.postMessage({ type: 'progress', text: `Создано ${done} из ${total}\n${screen.name}` });
        // Yield between screens so Figma remains responsive during a large import.
        await new Promise(resolve => setTimeout(resolve, 0));
      }
      if (!firstPage) {
        firstPage = page;
        firstFrames = frames;
      }
    }
    await figma.setCurrentPageAsync(firstPage || createdPages[0]);
    figma.currentPage.selection = (firstFrames || []).slice(0, 4);
    if (firstFrames && firstFrames.length) figma.viewport.scrollAndZoomIntoView(firstFrames.slice(0, 4));
    const warning = fallback ? '\nRoboto недоступен: использован Inter. Установите шрифты из папки fonts для точного вида.' : '';
    figma.ui.postMessage({ type: 'complete', text: `Готово: ${total} фреймов на новых страницах.${warning}\nМакет можно сохранить как .fig: File → Save local copy.` });
    figma.notify('Макет Anixart создан');
  } catch (error) {
    await figma.setCurrentPageAsync(previousPage);
    for (const page of createdPages) page.remove();
    for (const style of createdStyles) style.remove();
    figma.ui.postMessage({ type: 'error', text: `Не удалось импортировать: ${error.message}` });
  } finally {
    importing = false;
  }
};
