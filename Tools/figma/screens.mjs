import { Scene, WATCH_LISTS, THEMES } from './scene.mjs';

const W = 393;
const H = 852;
const CONTENT_BOTTOM = 757;

export const SCREEN_SPECS = [
  ['home', 'Главная · Аниме', 'Anixart/Features/Home/HomeView.swift', 'Начальная вкладка Аниме; публичная выдача API.'],
  ['custom-empty', 'Моя вкладка · пустое состояние', 'Anixart/Features/Home/CustomFilterTabView.swift', 'Моя вкладка ещё не настроена.'],
  ['discover', 'Обзор', 'Anixart/Features/Discover/DiscoverView.swift', 'Без входа: баннеры, обсуждаемые релизы, комментарии недели. Тексты комментариев — примеры.'],
  ['catalog', 'Каталог', 'Anixart/Features/Catalog/CatalogView.swift', 'Сетка с постерами шириной 112 pt. Поиск виден, фильтр не применён.'],
  ['search', 'Поиск · результаты', 'Anixart/Features/Home/HomeView.swift', 'Поиск с главной, запрос «Киберпанк», результаты показаны без клавиатуры.'],
  ['bookmarks', 'Закладки · Смотрю', 'Anixart/Features/Bookmarks/BookmarksView.swift', 'Вход выполнен; содержимое списка — демонстрационное. Полоса вкладок в начальном положении.'],
  ['bookmarks-guest', 'Закладки · без входа', 'Anixart/Features/Bookmarks/BookmarksView.swift', 'Точное сообщение SignInPromptView для закладок.'],
  ['profile', 'Профиль · свой аккаунт', 'Anixart/Features/Profile/ProfileViews.swift', 'Демонстрационный профиль anime_fan: без обложки, социальных ссылок и витрины значков. Аватары не загружены.'],
  ['profile-stats', 'Профиль · статистика', 'Anixart/Features/Profile/ProfileViews.swift', 'Тот же профиль после вертикальной прокрутки. Поисковая шапка остаётся сверху. Числа — примеры.'],
  ['profile-guest', 'Профиль · без входа', 'Anixart/Features/Profile/ProfileViews.swift', 'Состояние гостя после окончания загрузки сессии.'],
  ['release', 'Релиз · первый экран', 'Anixart/Features/Release/ReleaseDetailView.swift', 'Киберпанк: Бегущие по краю. Постер и общие данные из API; релиз ещё не добавлен в список.'],
  ['release-info', 'Релиз · описание и рейтинг', 'Anixart/Features/Release/ReleaseDetailView.swift', 'Тот же релиз после прокрутки к фактам и рейтингу.'],
  ['voiceovers', 'Выберите вариант', 'Anixart/Features/Episodes/EpisodePickerView.swift', 'Озвучки из API для релиза 18846; фильтр Все. ПЛЕЕР у AniLibria иллюстрирует доступность прямого источника.'],
  ['episodes', 'Выберите серию', 'Anixart/Features/Episodes/EpisodePickerView.swift', 'AniLibria / Libria. Просмотренные серии и позиция продолжения — пример состояния аккаунта.'],
  ['comments', 'Комментарии', 'Anixart/Features/Comments/CommentsView.swift', 'Вход выполнен; имена, комментарии, оценки и даты — демонстрационные.'],
  ['schedule', 'Расписание', 'Anixart/Features/Schedule/ScheduleView.swift', 'Выбрана суббота; публичное расписание API.'],
  ['notifications', 'Уведомления', 'Anixart/Features/Notifications/NotificationsView.swift', 'Демонстрационные события: новая серия, релиз франшизы и заявка в друзья.'],
  ['settings', 'Настройки', 'Anixart/Features/Settings/SettingsView.swift', 'Большой модальный экран; вход выполнен. Версия взята из project.yml, а не установленной сборки.'],
  ['auth', 'Аккаунт · вход', 'Anixart/Features/Auth/AuthView.swift', 'Большой модальный экран. Пустые поля, кнопка Войти неактивна.'],
  ['filters', 'Фильтры каталога', 'Anixart/Features/Catalog/FilterSheet.swift', 'Большой модальный экран с системным Form. Показана первая видимая область; ниже есть остальные фильтры.'],
  ['list-picker', 'В список', 'Anixart/Features/Release/ReleaseSheets.swift', 'Модальное окно medium; текущий список Смотрю.'],
  ['rating-picker', 'Оценка', 'Anixart/Features/Release/ReleaseSheets.swift', 'Модальное окно medium; пример выбранной оценки 4. Распределение голосов из API.'],
  ['tab-settings', 'Настройки вкладки', 'Anixart/Features/Home/CustomTabSettingsView.swift', 'Начальное состояние Моя вкладка: закрытые поля, кнопки закреплены внизу.'],
  ['player-picker', 'Выберите плеер', 'Anixart/Features/Player/PlayerPickerSheet.swift', 'Окно на large detent, выбран Веб-плеер; прямой поток доступен на Libria. Веб-интерфейс стороннего источника не реконструируется.'],
];

export function countText(value) {
  const number = value || 0;
  if (number >= 1000000) return `${(Math.round(number / 100000) / 10).toString().replace('.', ',')} млн`;
  if (number >= 10000) return `${(Math.round(number / 100) / 10).toString().replace('.', ',')} тыс.`;
  return String(number).replace(/\B(?=(\d{3})+(?!\d))/g, '\u2009');
}

function episodeText(release) {
  if (release.episodes_released != null && release.episodes_released === release.episodes_total) return `${release.episodes_total} эп`;
  if (release.status_id === 3) return `${release.episodes_total ?? '?'} эп`;
  if (release.episodes_released == null && release.episodes_total == null) return null;
  return `${release.episodes_released ?? '?'} из ${release.episodes_total ?? '?'} эп`;
}

function ratingColor(grade) {
  if (grade >= 4.25) return '#2EB366';
  if (grade >= 3.5) return '#8CB333';
  if (grade >= 2.5) return '#E6AD26';
  return '#D94D40';
}

function statusBar(s) {
  s.group('iOS / Статус-бар', 0, 0, W, 59, () => {
    s.text('Время', '9:41', 27, 19, 54, 15, { weight: 'Medium', align: 'center' });
    s.rect('Dynamic Island', 134, 11, 125, 37, '#000000', 19);
    [5, 8, 11, 14].forEach((height, i) => s.rect('Сотовая сеть', 300 + i * 4, 33 - height, 3, height, s.p.primary, 0.8));
    s.icon('wifi', 321, 19, 18);
    s.rect('Батарея / корпус', 346, 21, 25, 12, null, 3.5, { stroke: s.p.secondary, strokeWidth: 1 });
    s.rect('Батарея / заряд', 348, 23, 19, 8, s.p.primary, 1.7);
    s.rect('Батарея / контакт', 372, 25, 2, 4, s.p.secondary, 1);
  });
}

function homeIndicator(s, color = s.p.primary) {
  s.rect('iOS / Home indicator', 129.5, 838, 134, 5, color, 2.5);
}

function tabs(s, selected) {
  s.group('iOS / Нижняя панель · 5 вкладок', 16, 764, 361, 61, () => {
    s.rect('Liquid Glass / приближённый материал', 0, 0, 361, 61, s.p.glass, 31, { stroke: s.p.glassStroke, strokeOpacity: 0.7, strokeWidth: 0.7, materialBlur: 20, opacity: 0.97 });
    const options = [['Главная', 'house'], ['Обзор', 'grid'], ['Каталог', 'search'], ['Закладки', 'bookmark'], ['Профиль', 'person']];
    options.forEach(([label, icon], i) => {
      const x = 5 + i * 70;
      s.group(`Tab / ${label}${i === selected ? ' / выбрана' : ''}`, x, 4, 71, 53, () => {
        if (i === selected) s.rect('Выбранная вкладка / фон', 0, 0, 71, 53, s.p.accentSoft, 26);
        const color = i === selected ? s.p.accent : s.p.secondary;
        s.icon(icon, 23.5, 5, 24, color);
        s.text('Подпись', label, 0, 34, 71, 10, { weight: 'Medium', align: 'center', color });
      });
    });
  });
  homeIndicator(s);
}

function navButton(s, icon, x, y, color = s.p.accent) {
  s.rect('iOS / Круглая кнопка панели', x, y, 36, 36, s.p.glass, 18, { stroke: s.p.glassStroke, strokeWidth: 0.5, materialBlur: 12 });
  s.icon(icon, x + 8, y + 8, 20, color);
}

function navigation(s, title, { large = false, back = false, trailing, subtitle } = {}) {
  s.group('iOS / Навигационная панель', 0, 59, W, large ? 94 : 44, () => {
    s.rect('Фон навигации', 0, 0, W, large ? 94 : 44, s.p.bg);
    if (back) navButton(s, 'chevron-left', 16, 3);
    if (!large) {
      s.text('Название экрана', title, 58, subtitle ? 3 : 11, 277, 17, { weight: 'Medium', align: 'center' });
      if (subtitle) s.text('Источник', subtitle, 58, 25, 277, 12, { color: s.p.secondary, align: 'center' });
    }
    if (trailing) navButton(s, trailing, 341, 3);
    if (large) s.text('Большой заголовок', title, 16, 47, 361, 34, { weight: 'Bold', maxLines: 1 });
  });
  return large ? 153 : 103;
}

function searchHeader(s, title = 'Поиск аниме') {
  s.group('Шапка / Поиск, настройки, уведомления', 16, 67, 361, 42, () => {
    s.rect('Поиск / GlassPill', 0, 0, 297, 42, s.p.glass, 21, { materialBlur: 14 });
    s.icon('search', 14, 11, 20, s.p.secondary);
    s.text('Поиск / placeholder', title, 42, 11, 232, 17, { color: s.p.secondary, maxLines: 1 });
    s.icon('gear', 309, 11, 20, s.p.secondary);
    s.icon('bell', 341, 11, 20, s.p.secondary);
  });
}

function searchField(s, title, y, { cancel = false, placeholder = false } = {}) {
  s.group('iOS / Строка поиска', 16, y, 361, 36, () => {
    const width = cancel ? 283 : 361;
    s.rect('Поле', 0, 0, width, 36, s.p.subtle, 10);
    s.icon('search', 9, 8, 19, s.p.secondary);
    s.text('Запрос', title, 35, 8, width - 66, 17, { color: placeholder ? s.p.secondary : s.p.primary, maxLines: 1 });
    if (cancel) {
      s.icon('x-circle', width - 26, 9, 17, s.p.secondary);
      s.text('Отмена', 'Отмена', width + 10, 8, 68, 17, { color: s.p.accent, align: 'right' });
    }
  });
}

function homeStrip(s, selected) {
  s.group('Главная / Полоса вкладок', 0, 117, W, 56, () => {
    s.icon('sliders', 12, 17, 20, s.p.secondary);
    const titles = selected === 'custom' ? ['Моя вкладка', 'Аниме', 'Дунхуа', 'Последнее'] : ['Моя вкладка', 'Аниме', 'Дунхуа', 'Последнее'];
    let x = selected === 'custom' ? 58 : 218.5 - s.width('Моя вкладка', 20) - 28 - s.width('Аниме', 20, 'Medium') / 2;
    s.group('Прокручиваемая область вкладок', 44, 0, W - 44, 56, () => {
      x -= 44;
      for (const title of titles) {
        const isSelected = title === (selected === 'custom' ? 'Моя вкладка' : 'Аниме');
        const width = s.width(title, 20, isSelected ? 'Medium' : 'Regular');
        s.text(`Вкладка / ${title}`, title, x, 10, width + 1, 20, { weight: isSelected ? 'Medium' : 'Regular', color: isSelected ? s.p.primary : s.p.secondary, maxLines: 1 });
        if (isSelected) s.rect('Индикатор выбранной вкладки', x, 43, width, 4, s.p.primary, 2);
        x += width + 28;
      }
    }, { clip: true });
  });
  s.line(0, 173, W);
}

function ratingBadge(s, grade, x, y, compact = false) {
  if (!(grade > 0)) return;
  const height = compact ? 17 : 20;
  const width = compact ? 36 : 42;
  s.rect('RatingBadge / фон', x, y, width, height, ratingColor(grade), height / 2);
  s.icon('star-fill', x + (compact ? 5 : 6), y + 4, compact ? 8 : 10, '#FFFFFF');
  s.text('RatingBadge / значение', grade.toFixed(1), x + (compact ? 15 : 18), y + 2, compact ? 18 : 21, compact ? 11 : 12, { weight: 'Medium', color: '#FFFFFF', maxLines: 1, lineHeight: compact ? 13 : 15 });
}

function poster(s, release, x, y, width = 112) {
  s.image('ReleasePoster / 3:4, radius 10', release.imageKey, x, y, width, width * 4 / 3, 10, { stroke: s.p.separator, strokeWidth: 0.5 });
}

function releaseCard(s, release, x, y, options = {}) {
  const height = 203;
  s.group(`ReleaseCard / ${release.title_ru}`, x, y, 112, height, () => {
    poster(s, release, 0, 0);
    ratingBadge(s, release.grade, 5, 5, true);
    const titleHeight = s.text('Название релиза', release.title_ru, 0, 155.33, 112, 12, { maxLines: 2, lineHeight: 14 });
    const detail = episodeText(release) || release.year || '';
    s.text('Серии / метаданные', detail, 0, 161.33 + titleHeight, 112, 11, { color: s.p.secondary, maxLines: 1, lineHeight: 13 });
  }, options);
  return height;
}

function releaseListCard(s, release, x, y, options = {}) {
  s.group(`ReleaseListRow / ${release.title_ru}`, x, y, 369, 152, () => {
    s.rect('GlassCard / radius 16', 0, 0, 369, 152, s.p.glass, 16, { stroke: s.p.glassStroke, strokeWidth: 0.7, strokeOpacity: 0.8, materialBlur: 14 });
    poster(s, release, 12, 12, 96);
    const titleHeight = s.text('Название релиза', release.title_ru, 120, 12, 203, 17, { weight: 'Medium', maxLines: 2, lineHeight: 20 });
    s.icon('ellipsis', 331, 12, 22, s.p.secondary);
    const metaY = 16 + titleHeight;
    const episodes = episodeText(release) || '';
    s.text('Количество серий', episodes, 120, metaY, 139, 15, { color: s.p.secondary, maxLines: 1, lineHeight: 18 });
    if (release.grade > 0) {
      const x = 120 + s.width(episodes, 15) + 7;
      s.text('Разделитель метаданных', '•', x, metaY, 9, 15, { color: s.p.tertiary });
      s.text('Рейтинг', release.grade.toFixed(1), x + 13, metaY, 29, 15, { color: ratingColor(release.grade), lineHeight: 18, maxLines: 1 });
      s.icon('star-fill', x + 40, metaY + 5, 9, ratingColor(release.grade));
    }
    if (release.description) s.text('Описание / 3 строки', release.description, 120, metaY + 22, 237, 13, { color: s.p.secondary, maxLines: 3, lineHeight: 16 });
  }, options);
}

function releaseRow(s, release, x, y, { watching = false, continueWatching = false, chevron = true, component = false } = {}) {
  s.group(`ReleaseRow / ${release.title_ru}`, x, y, 361, 118, () => {
    poster(s, release, 0, 8, 76);
    const titleHeight = s.text('Название релиза', release.title_ru, 88, 8, 246, 15, { weight: 'Medium', maxLines: 2, lineHeight: 18 });
    let metaY = 12 + titleHeight;
    if (release.title_original) {
      s.text('Оригинальное название', release.title_original, 88, metaY, 246, 12, { color: s.p.secondary, maxLines: 1, lineHeight: 14 });
      metaY += 18;
    }
    ratingBadge(s, release.grade, 88, metaY);
    s.icon('film', 136, metaY + 3, 13, s.p.secondary);
    s.text('Серии', episodeText(release) || '—', 153, metaY + 3, 101, 12, { color: s.p.secondary, maxLines: 1, lineHeight: 14 });
    const season = ['', 'зима', 'весна', 'лето', 'осень'][release.season || 0] || '';
    s.text('Сезон / год', [season, release.year].filter(Boolean).join(' '), 256, metaY + 3, 78, 12, { color: s.p.secondary, maxLines: 1, lineHeight: 14 });
    if (watching) {
      const width = Math.ceil(s.width('Смотрю', 11, 'Medium'));
      s.rect('Статус / фон', 88, metaY + 24, width + 12, 17, s.p.accentSoft, 8.5);
      s.text('Статус', 'Смотрю', 94, metaY + 26, width, 11, { weight: 'Medium', color: s.p.accent, lineHeight: 13, maxLines: 1 });
    }
    if (continueWatching) {
      s.icon('play-circle', 88, metaY + 25, 13, s.p.accent);
      s.text('Продолжить просмотр', 'Серия 4 · AniLibria', 104, metaY + 25, 221, 12, { color: s.p.accent, maxLines: 1 });
    }
    if (chevron) s.icon('chevron-right', 346, 51, 12, s.p.tertiary);
  }, { component });
}

function pill(s, label, x, y, width, { selected = false, icon, color, height = 34, size = 15, fill = false } = {}) {
  const foreground = color || (selected ? s.p.accent : s.p.primary);
  s.rect(`${label} / Capsule`, x, y, width, height, selected ? s.p.accentSoft : fill ? s.p.subtle : null, height / 2, selected || fill ? {} : { stroke: s.p.separator });
  if (icon) s.icon(icon, x + 13, y + (height - 17) / 2, 17, foreground);
  s.text(label, label, x + (icon ? 37 : 10), y + (height - Math.ceil(size * 1.2)) / 2, width - (icon ? 49 : 20), size, { color: foreground, weight: selected ? 'Medium' : 'Regular', align: icon ? 'left' : 'center', maxLines: 1 });
}

function segmented(s, labels, selected, x, y, width) {
  s.rect('iOS / SegmentedControl', x, y, width, 32, s.p.subtle, 8);
  const segmentWidth = width / labels.length;
  s.rect('Выбранный сегмент', x + selected * segmentWidth + 2, y + 2, segmentWidth - 4, 28, s.meta.theme === 'light' ? '#FFFFFF' : '#636366', 6);
  labels.forEach((label, i) => s.text(`Сегмент / ${label}`, label, x + i * segmentWidth + 3, y + 8, segmentWidth - 6, 13, { weight: selected === i ? 'Medium' : 'Regular', align: 'center', maxLines: 1, lineHeight: 16 }));
}

function avatar(s, x, y, size = 40, online = false) {
  s.ellipse('Avatar / заглушка', x, y, size, size, s.p.subtle);
  if (online) s.ellipse('Avatar / онлайн', x + size * .78, y + size * .78, size * .22, size * .22, s.p.green, { stroke: s.p.bg, strokeWidth: size * .035 });
}

function signInPrompt(s, message) {
  const y = 361;
  s.icon('person', 175.5, y, 42, s.p.tertiary);
  s.ellipse('SignInPrompt / вопрос', 205, y + 27, 18, 18, s.p.bg);
  s.text('SignInPrompt / ?', '?', 205, y + 27, 18, 13, { align: 'center', color: s.p.tertiary, weight: 'Medium' });
  s.text('SignInPrompt / заголовок', 'Нужен аккаунт', 32, y + 56, 329, 17, { weight: 'Medium', align: 'center' });
  const height = s.text('SignInPrompt / сообщение', message, 32, y + 91, 329, 15, { align: 'center', color: s.p.secondary, lineHeight: 18 });
  const buttonY = y + 105 + height;
  s.rect('Войти / borderedProminent', 159, buttonY, 75, 34, s.p.accent, 8);
  s.text('Войти', 'Войти', 169, buttonY + 7, 55, 17, { align: 'center', color: '#FFFFFF', lineHeight: 20 });
}

function bookmarkStrip(s) {
  s.group('Закладки / Полоса разделов', 0, 153, W, 50, () => {
    let x = 16;
    ['Коллекции', 'История', 'Избранное', ...WATCH_LISTS.map(x => x[0])].forEach(label => {
      const width = s.width(label, 15, label === 'Смотрю' ? 'Medium' : 'Regular') + 24;
      pill(s, label, x, 8, width, { selected: label === 'Смотрю', height: 32, fill: true });
      x += width + 8;
    });
  }, { clip: true });
  s.line(0, 203, W);
}

function profileChips(s, y) {
  s.group('Профиль / Выбор секции', 0, y, W, 62, () => {
    s.group('Секции / горизонтальная прокрутка', 0, 0, 345, 62, () => {
      let x = 16;
      [['Статистика', 'chart'], ['Оценки релизов', 'star'], ['Коллекции', 'layers']].forEach(([label, icon], i) => {
        const width = s.width(label, 15, i === 0 ? 'Medium' : 'Regular') + 50;
        s.rect(`Секция / ${label}`, x, 12, width, 38, i === 0 ? s.p.subtle : null, 10, { stroke: s.p.separator });
        s.icon(icon, x + 12, 22, 17, i === 0 ? s.p.primary : s.p.secondary);
        s.text('Название секции', label, x + 37, 22, width - 47, 15, { color: i === 0 ? s.p.primary : s.p.secondary, weight: i === 0 ? 'Medium' : 'Regular', maxLines: 1, lineHeight: 18 });
        x += width + 12;
      });
    }, { clip: true });
    s.icon('gear', 359, 21, 20, s.p.secondary);
  });
}

function donut(s, x, y) {
  const counts = [12, 37, 184, 6, 3];
  const total = counts.reduce((a, b) => a + b, 0);
  let cursor = -Math.PI / 2;
  let body = '';
  counts.forEach((count, i) => {
    const angle = count / total * Math.PI * 2;
    const end = cursor + angle - .004 * Math.PI * 2;
    const r = 50.4;
    const startPoint = [70 + Math.cos(cursor) * r, 70 + Math.sin(cursor) * r];
    const endPoint = [70 + Math.cos(end) * r, 70 + Math.sin(end) * r];
    body += `<path d="M${startPoint[0]} ${startPoint[1]}A${r} ${r} 0 ${angle > Math.PI ? 1 : 0} 1 ${endPoint[0]} ${endPoint[1]}" fill="none" stroke="${s.p[WATCH_LISTS[i][2]]}" stroke-width="39.2"/>`;
    cursor += angle;
  });
  s.vector('DonutChart / 5 списков', body, x, y, 140, 140);
}

function profileStatistics(s, y) {
  s.group('ProfileStatisticsSection', 0, y, W, 337, () => {
    WATCH_LISTS.forEach(([title, , color], i) => {
      s.ellipse('Цвет списка', 16, 11 + i * 28, 12, 12, s.p[color]);
      s.text('Название списка', title, 38, 8 + i * 28, 126, 15, { lineHeight: 18 });
      s.text('Количество', String([12, 37, 184, 6, 3][i]), 164, 8 + i * 28, 52, 15, { weight: 'Medium', lineHeight: 18 });
    });
    donut(s, 237, 0);
    const lines = [
      ['Просмотрено серий:', '2 148'],
      ['Время просмотра:', '35 дн. 19 ч.'],
      ['Жанры:', 'Приключения (38%), Драма (24%)'],
      ['Аудитория:', 'Сёнен (64%)'],
      ['Тематика:', 'Фэнтези (31%)'],
    ];
    lines.forEach(([label, value], i) => {
      s.text('Статистика / метка', label, 16, 164 + i * 26, s.width(label, 15, 'Medium') + 1, 15, { weight: 'Medium', lineHeight: 18 });
      const x = 22 + s.width(label, 15, 'Medium');
      s.text('Статистика / значение', value, x, 164 + i * 26, W - x - 16, 15, { color: s.p.secondary, lineHeight: 18, maxLines: 1 });
    });
    s.text('Узнать подробнее', 'Узнать подробнее', 16, 304, 361, 15, { weight: 'Medium', color: s.p.accent, align: 'center' });
  });
}

function profileActivity(s, y) {
  s.line(16, y, 361);
  s.text('Заголовок динамики', 'Динамика просмотра серий', 16, y + 24, 361, 20, { weight: 'Medium' });
  s.text('Нет данных', 'Данных о просмотрах пока нет', 32, y + 85, 329, 15, { align: 'center', color: s.p.secondary });
}

function releasePoster(s, release, assets) {
  s.group('Релиз / Постер и размытый фон', 0, 103, W, 380, () => {
    s.image('Фон / тот же постер, blur 28', release.imageKey, -28, -28, W + 56, 436, 0, { blur: 28 });
    s.rect('Затемнение / black 45%', 0, 0, W, 380, '#000000', 0, { opacity: 0.45 });
    const ratio = assets[release.imageKey].width / assets[release.imageKey].height || 3 / 4;
    const width = Math.min(361, 340 * ratio);
    s.image('Постер / scaledToFit, height 340', release.imageKey, (W - width) / 2, 20, width, 340, 14, { fit: 'FIT', shadow: { color: '#000000', opacity: .35, radius: 14, x: 0, y: 6 } });
  }, { clip: true });
}

function releaseFacts(s, release, y) {
  const season = ['', 'зима', 'весна', 'лето', 'осень'][release.season || 0] || '';
  const lines = [
    ['globe', `${release.country || 'Япония'}, ${season} ${release.year} г.`],
    ['play-rectangle', `${episodeText(release)}. по ~${release.duration || 25} мин.`],
    ['calendar', `${release.category?.name || 'Сериал'}, ${(release.status?.name || 'Вышел').toLowerCase()}`],
    ['target', `Первоисточник ${release.source || 'игра'}`],
    ['people', `Студия ${release.studio || 'Trigger'}, режиссёр ${release.director || 'Хироюки Имаиси'}, автор ${release.author || 'CD PROJEKT RED'}`],
  ];
  for (const [icon, line] of lines) {
    s.icon(icon, 16, y, 20, s.p.secondary);
    const height = s.text('Факт / ' + icon, line, 54, y, 323, 15, { lineHeight: 18 });
    y += Math.max(20, height) + 12;
  }
  return y - 12;
}

function histogram(s, release, x, y, width, { colored = false, showCount = false } = {}) {
  const counts = [5, 4, 3, 2, 1].map(i => release[`vote_${i}_count`] || 0);
  const maximum = colored ? Math.max(1, counts.reduce((a, b) => a + b, 0)) : Math.max(1, ...counts);
  counts.forEach((count, i) => {
    const labelWidth = 15;
    const barWidth = width - labelWidth - 8 - (showCount ? 60 : 0);
    s.text('Оценка', String(5 - i), x, y + i * 21, labelWidth, 12, { color: s.p.secondary, lineHeight: 14 });
    s.rect('Гистограмма / фон', x + labelWidth + 8, y + 4 + i * 21, barWidth, 9, s.p.subtle, 4.5);
    s.rect('Гистограмма / количество', x + labelWidth + 8, y + 4 + i * 21, Math.max(2, barWidth * count / maximum), 9, colored ? ratingColor(5 - i) : s.p.primary, 4.5, { opacity: colored ? 1 : .85 });
    if (showCount) s.text('Количество голосов', countText(count), x + width - 52, y + i * 21, 52, 11, { color: s.p.secondary, align: 'right', lineHeight: 14, maxLines: 1 });
  });
}

function stars(s, x, y, selected = 0, size = 30, spacing = 10) {
  for (let i = 1; i <= 5; i++) s.icon(i <= selected ? 'star-fill' : 'star', x + (i - 1) * (size + spacing), y, size, selected ? (i <= selected ? s.p.accent : s.p.secondary) : s.p.secondary);
}

function comment(s, x, y, { user, date, message, score, replies = 0, spoiler = false, showsRelease = false }) {
  const width = 361;
  let height = 40;
  s.group(`CommentRow / ${user}`, x, y, width, 250, () => {
    avatar(s, 0, 8);
    const userWidth = s.width(user, 15, 'Medium');
    s.text('Автор', user, 52, 8, userWidth + 1, 15, { weight: 'Medium', lineHeight: 18 });
    s.text('Дата', date, 62 + userWidth, 8, width - 62 - userWidth, 15, { color: s.p.secondary, lineHeight: 18, maxLines: 1 });
    let contentY = 32;
    if (showsRelease) {
      s.text('Релиз комментария', 'Киберпанк: Бегущие по краю', 52, contentY, 309, 12, { color: s.p.accent, maxLines: 1 });
      contentY += 20;
    }
    if (spoiler) {
      s.rect('Скрытый спойлер', 52, contentY, 309, 49, s.p.subtle, 8);
      s.icon('eye-slash', 60, contentY + 16, 17, s.p.secondary);
      s.text('Предупреждение о спойлере', 'Содержит спойлер — нажмите, чтобы прочитать', 83, contentY + 8, 270, 12, { color: s.p.secondary, lineHeight: 15 });
      contentY += 55;
    } else contentY += s.text('Текст комментария', message, 52, contentY, 309, 15, { lineHeight: 18 }) + 6;
    s.text('На момент серии', 'На момент выхода 10 серии', 52, contentY, 309, 12, { color: s.p.secondary });
    contentY += 24;
    if (!showsRelease) s.text('Ответить', 'Ответить', 52, contentY, 105, 15, { color: s.p.secondary, lineHeight: 18 });
    s.icon('chevron-down', 259, contentY + 2, 16, s.p.secondary);
    s.text('Оценка комментария', String(score), 279, contentY, 50, 15, { align: 'center', weight: 'Medium', color: s.p.green, lineHeight: 18 });
    s.icon('chevron-up', 341, contentY + 2, 16, s.p.secondary);
    contentY += 26;
    if (replies) {
      s.text('Показать ответы', `Показать ${replies} ответов`, 52, contentY, 177, 15, { weight: 'Medium' });
      s.icon('chevron-right', 213, contentY + 3, 12);
      contentY += 24;
    }
    height = contentY + 8;
  });
  s.parent.children[s.parent.children.length - 1].h = height;
  return height;
}

function hint(s, text, x, y, width) {
  const height = s.text('Подсказка', text, x + 16, y + 16, width - 66, 15, { color: s.p.secondary, lineHeight: 18 });
  s.icon('x-circle', x + width - 36, y + 16, 20, s.p.secondary);
  // Insert the border before text/icon, to keep text on top in both formats.
  s.parent.children.splice(s.parent.children.length - 2, 0, { type: 'rect', name: 'Подсказка / рамка', x, y, w: width, h: height + 32, radius: 14, stroke: s.p.separator, fill: null });
  return height + 32;
}

function sheetBase(s, { top = 59, grouped = true } = {}, build) {
  s.rect('Модальное окно / затемнение фона', 0, 0, W, H, '#000000', 0, { opacity: s.meta.theme === 'light' ? .28 : .5 });
  s.group('iOS / Sheet', 0, top, W, H - top, () => {
    s.rect('Sheet / фон', 0, 0, W, H - top + 24, grouped ? s.p.grouped : s.p.bg, [24, 24, 0, 0]);
    build();
  }, { clip: true, radius: [24, 24, 0, 0] });
  homeIndicator(s);
}

function sheetNav(s, title, { large = false, left = 'Отмена', right } = {}) {
  s.rect('Sheet / навигация', 0, 0, W, large ? 100 : 56, s.p.grouped);
  if (left) s.text('Закрытие / действие слева', left, 20, 16, 112, 17, { color: s.p.accent, maxLines: 1 });
  if (right) s.text('Действие справа', right, 240, 16, 133, 17, { weight: 'Medium', color: s.p.accent, align: 'right', maxLines: 1 });
  if (!large) {
    const margin = Math.max(left ? s.width(left, 17) + 32 : 20, right ? s.width(right, 17, 'Medium') + 32 : 20);
    s.text('Заголовок Sheet', title, margin, 16, W - margin * 2, 17, { weight: 'Medium', align: 'center', maxLines: 1 });
  }
  else s.text('Заголовок Sheet', title, 20, 55, 353, 34, { weight: 'Bold', maxLines: 1 });
  return large ? 108 : 68;
}

function formSection(s, title, y, rows, { footer, rowHeight = 44 } = {}) {
  if (title) {
    s.text('Form / заголовок секции', title.toUpperCase(), 36, y, 321, 13, { color: s.p.secondary, maxLines: 1, lineHeight: 16 });
    y += 24;
  }
  const height = rows.length * rowHeight;
  s.rect('Form / группа строк', 20, y, 353, height, s.p.surface, 10);
  rows.forEach((row, i) => {
    const rowY = y + i * rowHeight;
    if (i) s.line(36, rowY, 337);
    if (row.icon) s.icon(row.icon, 36, rowY + 12, 20, row.color || s.p.primary);
    const labelX = row.icon ? 68 : 36;
    s.text('Form / ' + row.label, row.label, labelX, rowY + 12, row.value ? row.labelWidth || 177 : 319 - (row.icon ? 32 : 0), 17, { color: row.color || s.p.primary, maxLines: 1, lineHeight: 20 });
    if (row.value !== undefined) s.text('Form / значение', row.value, row.valueX || 207, rowY + 12, row.chevron ? 140 : 150, row.valueSize || 17, { color: row.valueColor || s.p.secondary, align: 'right', maxLines: 1, lineHeight: 20 });
    if (row.chevron) s.icon('chevron-right', 350, rowY + 16, 10, s.p.tertiary);
  });
  y += height;
  if (footer) y += s.text('Form / пояснение', footer, 36, y + 9, 321, 12, { color: s.p.secondary, lineHeight: 16 }) + 9;
  return y + 28;
}

function mainHome(s, data, { custom = false } = {}) {
  statusBar(s);
  searchHeader(s);
  homeStrip(s, custom ? 'custom' : 'anime');
  s.group('Главная / Содержимое выбранной вкладки', 0, 174, W, CONTENT_BOTTOM - 174, () => {
    if (custom) {
      s.icon('sliders', 174.5, 206, 44, s.p.tertiary);
      s.text('Пустая вкладка / заголовок', 'Это ваша вкладка', 32, 264, 329, 17, { weight: 'Medium', align: 'center' });
      s.text('Пустая вкладка / сообщение', 'Настройте её под себя и укажите,\nчто хотели бы здесь видеть', 32, 299, 329, 15, { color: s.p.secondary, align: 'center', lineHeight: 18 });
      s.rect('Настроить / borderedProminent', 136, 349, 121, 34, s.p.accent, 8);
      s.text('Настроить', 'Настроить', 146, 356, 101, 17, { align: 'center', color: '#FFFFFF', lineHeight: 20 });
    } else data.home.slice(0, 4).forEach((release, i) => releaseListCard(s, release, 12, 4 + i * 160));
  }, { clip: true });
  tabs(s, 0);
}

function mainRelease(s, data, assets, { watching = false } = {}) {
  const release = data.detail;
  statusBar(s);
  navigation(s, '', { back: true });
  s.group('Релиз / Прокручиваемая область', 0, 103, W, CONTENT_BOTTOM - 103, () => {
    // Source coordinates below start at the content origin, not the screen origin.
    s.group('Релиз / Верхняя область', 0, -103, W, 1000, () => {
      releasePoster(s, release, assets);
      s.icon('info', 16, 495, 20, s.p.secondary);
      const titleHeight = s.text('Название релиза', release.title_ru, 46, 495, 331, 22, { weight: 'Bold', lineHeight: 26 });
      const subtitleY = 499 + titleHeight;
      s.text('Оригинальное название', release.title_original || '', 48, subtitleY, 305, 15, { color: s.p.secondary, maxLines: 1, lineHeight: 18 });
      const statusY = subtitleY + 30;
      pill(s, watching ? 'Смотрю' : 'Не смотрю', 16, statusY, 131, { icon: 'chevron-down', height: 44, color: watching ? s.p.green : s.p.primary });
      pill(s, countText(release.favorites_count), 157, statusY, 123, { icon: 'bookmark', height: 44 });
      s.rect('Комментарии / кнопка', 290, statusY, 52, 48, null, 24, { stroke: s.p.separator });
      s.icon('bubble', 306, statusY + 14, 20);
      const playY = statusY + 60;
      s.rect('Воспроизвести / Capsule, primary 92%', 16, playY, 325, 56, s.p.primary, 28, { opacity: .92 });
      s.icon('play', 84, playY + 18, 20, s.p.bg);
      s.text('Воспроизвести', 'Воспроизвести', 116, playY + 16, 177, 20, { weight: 'Medium', color: s.p.bg, maxLines: 1, lineHeight: 24 });
      s.icon('ellipsis', 353, playY + 17, 24);
      let factsY = playY + 80;
      if (release.lastEpisodeLine) {
        s.text('Последняя добавленная серия', release.lastEpisodeLine, 40, playY + 60, 313, 12, { color: s.p.secondary, maxLines: 1, lineHeight: 14 });
        factsY += 18;
      }
      releaseFacts(s, release, factsY);
    });
  }, { clip: true });
  tabs(s, 0);
}

export function makeScreens(data, fonts, assets, theme) {
  const output = [];
  for (const [id, name, source, notes] of SCREEN_SPECS) {
    const s = new Scene({ id, name, source, notes, theme }, fonts);
    const p = s.p;
    if (id === 'home' || id === 'custom-empty') mainHome(s, data, { custom: id === 'custom-empty' });
    if (id === 'discover') {
      statusBar(s);
      navigation(s, 'Обзор', { large: true, trailing: 'calendar' });
      s.group('Обзор / Лента', 0, 153, W, CONTENT_BOTTOM - 153, () => {
        data.banners.slice(0, 2).forEach((banner, i) => {
          s.group(`BannerCarousel / ${banner.title}`, 16 + i * 312, 16, 300, 150, () => {
            s.image('Баннер', banner.imageKey, 0, 0, 300, 150, 14);
            s.rect('Градиент / black 75% → clear', 0, 0, 300, 150, null, 0, { gradient: [{ position: 0, color: '#000000', opacity: .75 }, { position: 1, color: '#000000', opacity: 0 }] });
            let textHeight = 0;
            const labels = s.group('Баннер / нижние подписи', 12, 0, 276, 80, () => {
              textHeight = s.text('Заголовок баннера', banner.title, 0, 0, 276, 17, { weight: 'Medium', color: '#FFFFFF', maxLines: 2, lineHeight: 20 });
              if (banner.description) textHeight += 2 + s.text('Описание баннера', banner.description, 0, textHeight + 2, 276, 12, { color: '#FFFFFF', opacity: .85, maxLines: 2, lineHeight: 14 });
            });
            labels.h = textHeight;
            labels.y = 150 - 12 - textHeight;
          }, { clip: true, radius: 14 });
        });
        s.text('SectionHeader', 'Сейчас обсуждают', 16, 190, 361, 20, { weight: 'Medium' });
        data.discussing.slice(0, 4).forEach((release, i) => releaseCard(s, release, 16 + i * 124, 226));
        s.text('SectionHeader', 'Комментарии недели', 16, 453, 361, 20, { weight: 'Medium' });
        comment(s, 16, 489, { user: 'anime_fan', date: '2 дн. назад', message: 'Нравится, как история и музыка работают вместе. Очень атмосферный сериал.', score: 128, showsRelease: true });
      }, { clip: true });
      tabs(s, 1);
    }
    if (id === 'catalog') {
      statusBar(s);
      navigation(s, 'Каталог', { large: true, trailing: 'filter' });
      searchField(s, 'Название аниме', 153, { placeholder: true });
      s.group('Каталог / LazyVGrid', 0, 197, W, CONTENT_BOTTOM - 197, () => {
        data.catalog.slice(0, 9).forEach((release, i) => releaseCard(s, release, 16 + (i % 3) * 124, 16 + Math.floor(i / 3) * 227));
      }, { clip: true });
      tabs(s, 2);
    }
    if (id === 'search') {
      statusBar(s);
      navigation(s, 'Поиск', { back: true });
      searchField(s, 'Киберпанк', 111);
      s.group('Поиск / Список результатов', 0, 155, W, CONTENT_BOTTOM - 155, () => {
        const releases = data.search.length ? data.search : [data.detail];
        releases.slice(0, 5).forEach((release, i) => {
          releaseRow(s, release, 16, i * 118);
          s.line(104, (i + 1) * 118, 289);
        });
      }, { clip: true });
      tabs(s, 0);
    }
    if (id === 'bookmarks') {
      statusBar(s);
      navigation(s, 'Закладки', { large: true, trailing: 'sort' });
      bookmarkStrip(s);
      s.group('Закладки / Список Смотрю', 0, 204, W, CONTENT_BOTTOM - 204, () => {
        [data.detail, ...data.discussing].slice(0, 4).forEach((release, i) => {
          releaseRow(s, release, 16, 8 + i * 118, { watching: true });
          s.line(104, 126 + i * 118, 289);
        });
      }, { clip: true });
      tabs(s, 3);
    }
    if (id === 'bookmarks-guest' || id === 'profile-guest') {
      statusBar(s);
      navigation(s, id === 'bookmarks-guest' ? 'Закладки' : 'Профиль', { large: true });
      signInPrompt(s, id === 'bookmarks-guest' ? 'Закладки, история и избранное привязаны к аккаунту.' : 'Войдите, чтобы вести списки, оценивать и комментировать.');
      tabs(s, id === 'bookmarks-guest' ? 3 : 4);
    }
    if (id === 'profile' || id === 'profile-stats') {
      statusBar(s);
      searchHeader(s, 'Поиск пользователей');
      s.group('Профиль / Прокручиваемое содержимое', 0, 117, W, CONTENT_BOTTOM - 117, () => {
        if (id === 'profile') {
          avatar(s, 140.5, 28, 112, true);
          s.text('Никнейм', 'anime_fan', 32, 156, 329, 22, { weight: 'Bold', align: 'center', lineHeight: 26 });
          s.text('Статус профиля', 'Смотрю истории, которые остаются со мной', 32, 190, 329, 15, { color: p.secondary, align: 'center', lineHeight: 18 });
          s.rect('Рейтинг профиля / рамка', 53, 218, 42, 22, null, 6, { stroke: p.green });
          s.text('Рейтинг профиля', '842', 59, 220, 30, 15, { color: p.green, align: 'center', weight: 'Medium', lineHeight: 18 });
          s.text('Дата регистрации', '• на проекте с 12 мая 2023 г.', 103, 220, 237, 15, { color: p.secondary, lineHeight: 18 });
          s.rect('Редактировать / контурная Capsule', 16, 254, 303, 46, null, 23, { stroke: p.separator });
          s.text('Редактировать', 'Редактировать', 29, 267, 277, 17, { weight: 'Medium', align: 'center', lineHeight: 20 });
          s.ellipse('Меню профиля / фон', 331, 254, 46, 46, p.subtle);
          s.icon('ellipsis', 343, 266, 22);
          s.rect('Добавить социальные сети', 167.5, 314, 58, 36, p.subtle, 12);
          s.icon('plus', 187.5, 323, 18);
          s.rect('SectionDivider', 0, 364, W, 8, p.subtle);
          s.text('Друзья / количество', '18 друзей', 16, 386, 245, 17, { weight: 'Medium' });
          s.text('Друзья / имена', 'viewer_01, viewer_02, viewer_03', 16, 408, 244, 15, { color: p.secondary, maxLines: 1 });
          [0, 1, 2].forEach(i => avatar(s, 271 + i * 32, 386, 42));
          s.rect('SectionDivider', 0, 442, W, 8, p.subtle);
          profileChips(s, 450);
          profileStatistics(s, 512);
        } else {
          profileChips(s, 0);
          profileStatistics(s, 74);
          profileActivity(s, 439);
        }
      }, { clip: true });
      tabs(s, 4);
    }
    if (id === 'release') mainRelease(s, data, assets);
    if (id === 'release-info') {
      statusBar(s);
      navigation(s, '', { back: true });
      s.group('Релиз / Содержимое после прокрутки', 0, 103, W, CONTENT_BOTTOM - 103, () => {
        const release = data.detail;
        let y = releaseFacts(s, release, 12) + 24;
        y += s.text('Жанры / ссылки', release.genres || 'фантастика, экшен', 16, y, 361, 15, { underline: true, lineHeight: 18 }) + 12;
        y += s.text('Описание / 5 строк', release.description, 16, y, 361, 15, { lineHeight: 21, maxLines: 5 }) + 12;
        s.text('Подробнее', 'Подробнее...', 16, y, 361, 15, { weight: 'Medium', align: 'center' });
        y += 45;
        s.line(16, y, 361);
        y += 24;
        s.text('SectionHeader / Рейтинг', 'Рейтинг', 16, y, 361, 20, { weight: 'Medium' });
        y += 36;
        s.text('Средняя оценка', (release.grade || 0).toFixed(1), 16, y, 110, 54, { weight: 'Bold', lineHeight: 64 });
        s.text('Количество голосов', `${countText(release.vote_count)} голосов`, 16, y + 66, 134, 12, { color: p.secondary });
        histogram(s, release, 164, y, 213);
        y += 117;
        avatar(s, 16, y, 42);
        stars(s, 97, y + 6, 0, 28, 25);
      }, { clip: true });
      tabs(s, 0);
    }
    if (id === 'voiceovers') {
      statusBar(s);
      navigation(s, 'Выберите вариант', { back: true, trailing: 'refresh' });
      s.group('Выбор озвучки / ScrollView', 0, 103, W, CONTENT_BOTTOM - 103, () => {
        pill(s, 'Все', 16, 12, 91, { selected: true, icon: 'check', height: 48, size: 20 });
        pill(s, 'Озвучки', 119, 12, 111, { height: 48, size: 20 });
        pill(s, 'Субтитры', 242, 12, 135, { height: 48, size: 20 });
        let y = 72;
        y += hint(s, 'Напротив каждого варианта озвучки указано общее количество доступных серий. Статистика просмотров обновляется ежедневно.', 16, y, 361) + 12;
        data.types.slice(0, 7).forEach(type => {
          if (type.imageKey) s.image('Озвучка / иконка студии', type.imageKey, 16, y + 12, 56, 56, 14);
          else {
            s.rect('Озвучка / заглушка', 16, y + 12, 56, 56, p.subtle, 14);
            s.icon('mic', 34, y + 30, 20, p.secondary);
          }
          const badge = type.is_sub ? 'СУБТИТРЫ' : type.id === 2 ? 'ПЛЕЕР' : '';
          const badgeWidth = badge ? Math.ceil(s.width(badge, 10, 'Medium')) + 8 : 0;
          const titleWidth = 211 - (badge ? badgeWidth + 8 : 0);
          s.text('Название озвучки', type.name, 86, y + 19, titleWidth, 20, { maxLines: 1, lineHeight: 24 });
          if (badge) {
            const badgeX = Math.min(86 + s.width(type.name, 20) + 8, 297 - badgeWidth);
            s.rect('Озвучка / badge', badgeX, y + 23, badgeWidth, 17, null, 4, { stroke: badge === 'ПЛЕЕР' ? p.green : p.secondary });
            s.text('Название badge', badge, badgeX + 4, y + 25, badgeWidth - 8, 10, { color: badge === 'ПЛЕЕР' ? p.green : p.secondary, weight: 'Medium', lineHeight: 12, maxLines: 1 });
          }
          s.text('Количество эпизодов', `${type.episodes_count || 10} эпизодов`, 86, y + 47, 206, 15, { color: p.secondary, lineHeight: 18 });
          s.text('Просмотры озвучки', type.view_count >= 1000 ? `${Math.floor(type.view_count / 1000)}K` : String(type.view_count || 0), 304, y + 31, 49, 15, { align: 'right', color: p.secondary, maxLines: 1, lineHeight: 18 });
          s.icon('eye', 360, y + 31, 17, p.secondary);
          s.line(96, y + 80, 297);
          y += 80;
        });
      }, { clip: true });
      tabs(s, 0);
    }
    if (id === 'episodes') {
      statusBar(s);
      navigation(s, 'Выберите серию', { back: true, subtitle: 'Источник Libria', trailing: 'ellipsis' });
      s.group('Серии / Список', 0, 103, W, CONTENT_BOTTOM - 103, () => {
        pill(s, 'Libria', 16, 10, 96, { selected: true, icon: 'play-circle', height: 36 });
        pill(s, 'Kodik', 122, 10, 81, { height: 36 });
        s.line(0, 56, W);
        s.text('Название озвучки', 'AniLibria', 16, 80, 361, 34, { weight: 'Bold', color: p.secondary, lineHeight: 41 });
        let y = 133;
        y += hint(s, 'Если серия не запускается ни через какой видеоплеер, попробуйте сменить источник, если это доступно. Любая реклама в видео к приложению отношения не имеет.', 16, y, 361) + 12;
        for (let i = 1; i <= 7; i++) {
          s.text('Название серии', `${i} серия`, 16, y + 12, 291, 20, { color: i < 4 ? p.secondary : p.primary, lineHeight: 24 });
          s.text('Качество', '1080p', 16, y + 40, 66, 12, { color: p.secondary, lineHeight: 14 });
          if (i === 4) {
            s.icon('refresh', 81, y + 39, 13, p.accent);
            s.text('Продолжить / позиция', '12:34', 99, y + 40, 69, 12, { color: p.accent, lineHeight: 14 });
          }
          if (i < 4) s.icon('check-circle', 309, y + 24, 20, p.accent);
          s.icon('ellipsis', 349, y + 22, 22, p.secondary);
          s.line(16, y + 69, 377);
          y += 70;
        }
      }, { clip: true });
      tabs(s, 0);
    }
    if (id === 'comments') {
      statusBar(s);
      navigation(s, 'Комментарии', { back: true, trailing: 'sort' });
      s.group('Комментарии / Список', 0, 103, W, 543, () => {
        let y = 8;
        const comments = [
          { user: 'viewer_01', date: '2 ч. назад', message: 'Пересмотрел ещё раз. Визуальный стиль и саундтрек всё так же впечатляют.', score: 24, replies: 12 },
          { user: 'viewer_02', date: 'вчера', message: '', score: 18, spoiler: true },
          { user: 'anime_fan', date: '2 дн. назад', message: 'Короткая, но очень насыщенная история. Мне понравилось.', score: 7 },
        ];
        comments.forEach(item => {
          y += comment(s, 16, y, item);
          s.line(68, y, 325);
          y += 8;
        });
      }, { clip: true });
      s.group('Комментарии / Composer', 0, 646, W, 111, () => {
        s.rect('Composer / фон bar', 0, 0, W, 111, p.bg);
        s.line(0, 0, W);
        s.text('Composer / placeholder', 'Ваш комментарий', 16, 17, 361, 20, { color: p.tertiary });
        pill(s, 'Спойлер', 16, 55, 124, { icon: 'eye-slash', height: 38 });
        pill(s, 'Правила', 152, 55, 126, { icon: 'clipboard', height: 38 });
        s.ellipse('Отправить / фон', 333, 52, 44, 44, p.subtle);
        s.icon('arrow-up', 345, 64, 20, p.tertiary);
      });
      tabs(s, 0);
    }
    if (id === 'schedule') {
      statusBar(s);
      navigation(s, 'Расписание', { large: true, back: true });
      segmented(s, ['По', 'Вт', 'Ср', 'Че', 'Пя', 'Су', 'Во'], 5, 16, 161, 361);
      s.group('Расписание / Суббота', 0, 201, W, CONTENT_BOTTOM - 201, () => {
        const releases = data.schedule.length ? data.schedule : data.home;
        releases.slice(0, 4).forEach((release, i) => {
          releaseRow(s, release, 16, 8 + i * 118);
          s.line(104, 126 + i * 118, 289);
        });
      }, { clip: true });
      tabs(s, 1);
    }
    if (id === 'notifications') {
      statusBar(s);
      navigation(s, 'Уведомления', { large: true, back: true });
      const rows = [
        [data.discussing[0], data.discussing[0].title_ru, '5 серия · AniLibria', '5 мин. назад', true],
        [data.discussing[1], data.discussing[1].title_ru, 'Добавлено в знакомую вам франшизу', '2 ч. назад', true],
        [null, 'viewer_01', 'Активность в друзьях', 'вчера', false],
        [data.detail, data.detail.title_ru, '10 серия · AniLibria', '3 дн. назад', false],
      ];
      let y = 161;
      for (const [release, title, subtitle, date, isNew] of rows) {
        if (release) s.image('Уведомление / изображение', release.imageKey, 16, y + 8, 44, 58, 6);
        else s.icon('people', 28, y + 23, 20, p.secondary);
        const titleHeight = s.text('Уведомление / заголовок', title, 72, y + 8, 266, 15, { weight: 'Medium', maxLines: 2, lineHeight: 18 });
        const subtitleHeight = s.text('Уведомление / текст', subtitle, 72, y + 11 + titleHeight, 266, 12, { color: p.secondary, maxLines: 2, lineHeight: 14 });
        s.text('Уведомление / дата', date, 72, y + 14 + titleHeight + subtitleHeight, 266, 11, { color: p.tertiary, lineHeight: 13 });
        if (isNew) s.ellipse('Уведомление / новое', 346, y + 14, 8, 8, p.accent);
        s.icon('chevron-right', 371, y + 34, 10, p.tertiary);
        y += Math.max(82, titleHeight + subtitleHeight + 43);
        s.line(72, y, 321);
      }
      tabs(s, 0);
    }
    if (['settings', 'auth', 'filters', 'tab-settings'].includes(id)) {
      mainHome(s, data);
      sheetBase(s, {}, () => {
        if (id === 'settings') {
          let y = sheetNav(s, 'Настройки', { left: null, right: 'Готово' });
          y = formSection(s, 'Аккаунт', y, [{ label: 'Вы вошли как', value: 'anime_fan' }, { label: 'Выйти', color: p.red }]);
          y = formSection(s, 'Уведомления', y, [{ label: 'Уведомления', icon: 'bell', chevron: true }]);
          y = formSection(s, 'Правовая информация', y, [{ label: 'Правила сообщества', icon: 'shield', color: p.accent }, { label: 'Пользовательское соглашение', icon: 'document', color: p.accent }]);
          y = formSection(s, 'Диагностика', y, [{ label: 'Проверить Kodik', icon: 'stethoscope', chevron: true }]);
          formSection(s, null, y, [{ label: 'Версия', value: data.appVersion }], { footer: 'Неофициальный клиент Anixart для iOS. Приложение не связано с командой Anixart и использует её общедоступный API.' });
        }
        if (id === 'auth') {
          sheetNav(s, 'Аккаунт', { large: true, left: 'Закрыть' });
          s.rect('Form / Режим', 20, 115, 353, 49, p.surface, 10);
          segmented(s, ['Вход', 'Регистрация', 'Сброс пароля'], 0, 36, 124, 321);
          let y = formSection(s, null, 192, [{ label: 'Никнейм или email', color: p.tertiary }, { label: 'Пароль', color: p.tertiary }]);
          s.rect('Form / Войти', 20, y, 353, 44, p.surface, 10);
          s.text('Войти / неактивна', 'Войти', 36, y + 12, 321, 17, { weight: 'Medium', color: p.tertiary, align: 'center', lineHeight: 20 });
          y += 72;
          const text = 'Приложение использует официальное API Anixart. Вход через VK, Google, Telegram и Яндекс требует SDK этих сервисов и пока не подключён — используйте никнейм и пароль.';
          s.rect('Form / Примечание', 20, y, 353, 101, p.surface, 10);
          s.text('Примечание про способы входа', text, 36, y + 12, 321, 12, { color: p.secondary, lineHeight: 15 });
        }
        if (id === 'filters') {
          let y = sheetNav(s, 'Фильтры', { large: true, left: 'Сбросить', right: 'Применить' });
          y = formSection(s, 'Сортировка', y, [{ label: 'Порядок', value: 'По дате добавления ▼', valueSize: 15, labelWidth: 83, valueX: 143 }]);
          y = formSection(s, 'Сезон и год', y, [{ label: 'Сезон', value: 'Любой', chevron: true }, { label: 'Год от', value: '—', valueColor: p.tertiary }, { label: 'Год до', value: '—', valueColor: p.tertiary }]);
          y = formSection(s, 'Количество эпизодов', y, [{ label: 'Эпизодов', value: 'Любое', chevron: true }, { label: 'Длительность эпизода', value: 'Любая', chevron: true, labelWidth: 211 }]);
          formSection(s, 'Категория и статус', y, [{ label: 'Категория', value: 'Неважно', chevron: true }, { label: 'Статус', value: 'Неважно', chevron: true }, { label: 'Первоисточник', value: 'Неважно', chevron: true }]);
        }
        if (id === 'tab-settings') {
          sheetNav(s, 'Настройки вкладки', { left: 'Закрыть' });
          s.rect('Настройки вкладки / подсказка', 16, 72, 361, 76, null, 12, { stroke: p.separator });
          s.text('Настройки вкладки / текст подсказки', 'Выберите с помощью фильтров то, что хотите видеть на своей вкладке. Изменения будут доступны только на этом устройстве.', 30, 86, 333, 13, { color: p.secondary, lineHeight: 16 });
          let y = 168;
          for (const title of ['Страна', 'Категория', 'Жанры', 'Исключить закладки', 'Варианты озвучек', 'Студия']) {
            s.text('FilterFieldBox / название', title, 16, y, 361, 15, { color: p.secondary, lineHeight: 18 });
            s.rect('FilterValueLabel / рамка', 16, y + 24, 361, 46, null, 12, { stroke: p.separator });
            s.text('FilterValueLabel / placeholder', 'Неважно', 30, y + 37, 313, 17, { color: p.secondary, lineHeight: 20 });
            s.icon('chevron-down', 351, y + 40, 12, p.secondary);
            y += 70;
            const footnote = title === 'Жанры' ? 'Покажем релизы хотя бы с одним выбранным жанром.' : title === 'Исключить закладки' ? 'Исключит из выдачи все релизы, содержащиеся в вышеуказанных списках закладок.' : null;
            if (footnote) y += 6 + s.text('FilterFieldBox / пояснение', footnote, 16, y + 6, 361, 12, { color: p.tertiary, lineHeight: 14 });
            y += 20;
          }
          s.rect('Закреплённые действия / фон', 0, 696, W, 98, p.grouped);
          s.line(0, 696, W);
          s.rect('Сбросить / bordered', 38, 706, 133, 50, p.subtle, 12);
          s.text('Сбросить', 'Сбросить', 48, 722, 113, 17, { color: p.accent, align: 'center' });
          s.rect('Применить / borderedProminent', 206, 706, 153, 50, p.accent, 12);
          s.text('Применить', 'Применить', 216, 722, 133, 17, { color: '#FFFFFF', align: 'center' });
        }
      });
    }
    if (['list-picker', 'rating-picker'].includes(id)) {
      mainRelease(s, data, assets, { watching: id === 'list-picker' });
      sheetBase(s, { top: 426 }, () => {
        if (id === 'list-picker') {
          const y = sheetNav(s, 'В список', { large: true });
          formSection(s, null, y, [...WATCH_LISTS.map(([label, icon], i) => ({ label, icon, value: i === 0 ? '✓' : '', valueColor: p.accent })), { label: 'Убрать из списков', color: p.red }]);
        } else {
          const y = sheetNav(s, 'Оценка', { large: true });
          stars(s, 101.5, y + 8, 4);
          histogram(s, data.detail, 16, y + 62, 361, { colored: true, showCount: true });
          s.text('Убрать оценку', 'Убрать оценку', 16, y + 184, 361, 17, { color: p.red, align: 'center' });
        }
        s.rect('iOS / Индикатор Sheet', 178.5, 7, 36, 5, p.tertiary, 2.5);
      });
    }
    if (id === 'player-picker') {
      // Use the same episode screen behind the presentation, rather than inventing
      // a native design for a third party's web video player.
      statusBar(s);
      navigation(s, 'Выберите серию', { back: true, subtitle: 'Источник Libria' });
      s.text('Озвучка на фоне', 'AniLibria', 16, 179, 361, 34, { color: p.secondary, weight: 'Bold' });
      tabs(s, 0);
      sheetBase(s, { top: 105, grouped: false }, () => {
        s.rect('iOS / Индикатор Sheet', 178.5, 7, 36, 5, p.tertiary, 2.5);
        s.text('Выберите плеер', 'Выберите плеер', 24, 24, 345, 22, { weight: 'Medium', lineHeight: 26 });
        s.text('Найденный источник', 'Видео найдено на «Libria»', 24, 54, 345, 15, { color: p.secondary, lineHeight: 18 });
        const options = [
          ['Веб-плеер', 'Просмотр в плеере источника. Стандартный вариант.'],
          ['Встроенный плеер', 'Простой и удобный, не требует отдельного скачивания.'],
          ['Сторонний плеер', 'Просмотр в любом плеере, который установлен на вашем устройстве.'],
        ];
        let y = 90;
        options.forEach(([label, summary], i) => {
          s.rect('PlayerChoice / рамка', 24, y, 345, 102, null, 14, { stroke: i === 0 ? p.accent : p.separator });
          s.text('PlayerChoice / название', label, 40, y + 16, 313, 20, { weight: 'Medium', lineHeight: 24 });
          s.text('PlayerChoice / описание', summary, 40, y + 44, 313, 15, { color: p.secondary, lineHeight: 18 });
          y += 114;
        });
        s.line(24, y + 6, 345);
        s.icon('check-square', 24, y + 25, 22, p.accent);
        s.text('Спрашивать всегда', 'Спрашивать всегда', 58, y + 24, 311, 20, { lineHeight: 24 });
        s.text('Продолжить', 'Продолжить', 189, y + 68, 180, 20, { weight: 'Medium', align: 'right', lineHeight: 24 });
      });
    }
    output.push(s.export());
  }
  return output;
}

export function makeKit(data, fonts, theme) {
  const s = new Scene({ id: 'components', name: 'Палитра и базовые компоненты', source: 'Anixart/Support/Theme.swift; Anixart/Support/Typography.swift; Anixart/Components/', notes: 'Нативные компоненты в Figma; экраны не переведены на Auto Layout и не являются instances этих образцов.', theme, kit: true, w: 1800, h: 920 }, fonts);
  const p = THEMES[theme];
  s.text('Название набора', 'Anixart · текущие стили и компоненты', 32, 28, 1700, 28, { weight: 'Bold' });
  s.text('Примечание', 'Roboto · размеры из Theme.swift и Typography.swift · системные иконки и Liquid Glass приближены', 32, 74, 1700, 15, { color: p.secondary });
  const colors = [['Accent', p.accent], ['Смотрю', p.green], ['В планах', p.plan], ['Просмотрено', p.completed], ['Отложено', p.hold], ['Брошено', p.red], ['Primary', p.primary], ['Secondary', p.secondary]];
  colors.forEach(([label, color], i) => {
    s.rect(`Цвет / ${label}`, 32 + i * 210, 123, 178, 64, color, 10);
    s.text('Название цвета', label, 32 + i * 210, 199, 178, 15, { weight: 'Medium' });
    s.text('HEX', color, 32 + i * 210, 226, 178, 12, { color: p.secondary });
  });
  s.text('Типографика / заголовок', 'Типографика', 32, 290, 330, 20, { weight: 'Medium' });
  let y = 334;
  [['Large title', 34, 'Bold'], ['Title 2', 22, 'Bold'], ['Title 3', 20, 'Regular'], ['Headline', 17, 'Medium'], ['Body', 17, 'Regular'], ['Subheadline', 15, 'Regular'], ['Footnote', 13, 'Regular'], ['Caption', 12, 'Regular'], ['Caption 2', 11, 'Regular']].forEach(([label, size, weight]) => {
    s.text('Образец шрифта', `${label} · ${size}`, 32, y, 350, size, { weight, maxLines: 1 });
    y += Math.ceil(size * 1.2) + 14;
  });
  s.text('Компоненты / заголовок', 'Общие элементы', 445, 290, 1000, 20, { weight: 'Medium' });
  releaseCard(s, data.detail, 445, 334, { component: true });
  releaseListCard(s, data.detail, 593, 334, { component: true });
  releaseRow(s, data.detail, 998, 334, { watching: true, component: true });
  s.group('Component / Поисковая шапка', 445, 567, 393, 60, () => {
    s.rect('GlassPill', 16, 8, 289, 42, p.glass, 21, { materialBlur: 14 });
    s.icon('search', 30, 19, 20, p.secondary);
    s.text('Placeholder', 'Поиск аниме', 58, 19, 228, 17, { color: p.secondary });
    s.icon('gear', 317, 19, 20, p.secondary);
    s.icon('bell', 353, 19, 20, p.secondary);
  }, { component: true });
  s.group('Component / WatchList chips', 880, 567, 870, 60, () => {
    let x = 0;
    WATCH_LISTS.forEach(([label, icon, color]) => {
      const width = s.width(label, 15) + 56;
      pill(s, label, x, 10, width, { icon, color: p[color], height: 40 });
      x += width + 12;
    });
  }, { component: true });
  s.group('Component / RatingBadge', 445, 664, 90, 44, () => ratingBadge(s, data.detail.grade, 10, 12), { component: true });
  s.group('Component / Аватар онлайн', 577, 655, 64, 64, () => avatar(s, 8, 8, 48, true), { component: true });
  s.group('Component / Оценка 4 из 5', 683, 655, 220, 64, () => stars(s, 10, 17, 4), { component: true });
  s.group('Component / Подсказка', 948, 650, 393, 131, () => hint(s, 'Статистика просмотров обновляется ежедневно.', 16, 8, 361), { component: true });
  s.group('Component / Диаграмма списков', 1408, 334, 140, 140, () => donut(s, 0, 0), { component: true });
  s.text('Постер / размеры', 'Постер 3:4 · grid 112 · row 76 · home 96 · radius 10\nGlassCard radius 16 · row gap 12 · section gap 24 · tab gap 28', 445, 823, 1300, 15, { color: p.secondary, lineHeight: 20 });
  return s.export();
}
