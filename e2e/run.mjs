// End-to-end checks in a real browser. Starts its own API + database, runs the scenarios, prints a report.
import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import path from 'node:path';
import fs from 'node:fs';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(path.join(root, 'server', 'package.json'));
const pg = require('pg');
const { chromium } = require('playwright');

const ADMIN = process.env.TEST_ADMIN_URL ?? 'postgres://app:app@127.0.0.1:5433/postgres';
const DB = 'migrant_e2e';
const PORT = Number(process.env.E2E_PORT ?? 3200);
const BASE = `http://127.0.0.1:${PORT}`;
const SHOTS = process.env.E2E_SHOTS ?? path.join(root, 'e2e', 'screenshots');
fs.mkdirSync(SHOTS, { recursive: true });
const MOD = { email: 'mod@e2e.local', password: 'moderator-pass-1' };

// ------------------------------------------------------------------ environment
async function resetDb() {
  const c = new pg.Client({ connectionString: ADMIN });
  await c.connect();
  await c.query(`drop database if exists ${DB} with (force)`);
  await c.query(`create database ${DB}`);
  await c.end();
}

async function startServer() {
  const env = {
    ...process.env, NODE_ENV: 'test', PORT: String(PORT), DATABASE_URL: ADMIN.replace(/\/[^/]*$/, `/${DB}`), RATE_LIMIT: 'off',
    INCLUDE_DEMO_CONTENT: 'true', SEED_MODERATOR_EMAIL: MOD.email, SEED_MODERATOR_PASSWORD: MOD.password,
    CONTENT_DIRS: [path.join(root, 'content'), path.join(root, 'e2e', 'fixtures', 'content')].join(','),
  };
  const log = fs.openSync(path.join(SHOTS, 'server.log'), 'w');
  const child = spawn(path.join(root, 'node_modules', '.bin', 'tsx'), [path.join(root, 'server', 'src', 'index.ts')], { env, cwd: root, stdio: ['ignore', log, log] });
  for (let i = 0; i < 80; i++) {
    try { if ((await fetch(`${BASE}/api/health`)).ok) return child; } catch { /* not yet */ }
    await new Promise((r) => setTimeout(r, 250));
  }
  throw new Error('server did not start; see ' + path.join(SHOTS, 'server.log'));
}

const api = async (method, url, body, token) => {
  const r = await fetch(BASE + '/api' + url, { method, headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) }, body: body ? JSON.stringify(body) : undefined });
  return { status: r.status, json: await r.json().catch(() => null) };
};

// ------------------------------------------------------------------ helpers
const MOSCOW = { latitude: 55.7558, longitude: 37.6173 };
const DUSHANBE = { latitude: 38.5598, longitude: 68.787 };
const BAKU = { latitude: 40.4093, longitude: 49.8671 };
const MOBILE = { viewport: { width: 390, height: 844 }, deviceScaleFactor: 1, isMobile: true, hasTouch: true };

let browser;
const contexts = [];
async function newCtx(opts = {}, init = {}) {
  const ctx = await browser.newContext({ ...MOBILE, baseURL: BASE, ...opts });
  // state is applied only once, so later changes made by the test survive reloads
  await ctx.addInitScript((i) => {
    try {
      if (localStorage.getItem('__init')) return;
      localStorage.setItem('__init', '1');
      if (i.lang) localStorage.setItem('lang', i.lang);
      if (i.city) localStorage.setItem('city', JSON.stringify(i.city));
      if (i.cityAsked) localStorage.setItem('cityAsked', 'true');
    } catch { /* ignore */ }
  }, init);
  contexts.push(ctx);
  const page = await ctx.newPage();
  page.on('pageerror', (e) => { throw e; });
  return { ctx, page };
}
const CITY = { moscow: { id: 'moscow', name: 'Москва', region: 'г. Москва' }, kazan: { id: 'kazan', name: 'Казань', region: 'Республика Татарстан' } };
const ready = { lang: 'ru', cityAsked: true };
const i18n = async (lang) => (await api('GET', `/i18n/${lang}`)).json.strings;
const rawKeys = /\b(nav|common|badge|mode|error|city|docs|list|where|tips|topic|ads|auth|mod|data|group|flag|purpose|lang|app|offline)\.[A-Za-z_]+(\.[A-Za-z_]+)*\b/;
const text = (page) => page.locator('body').innerText();
const ids = (page, sel) => page.locator(sel).evaluateAll((els) => els.map((e) => e.getAttribute('data-id')));

async function pickCityManual(page, query, cityId) {
  await page.getByTestId('city-search').fill(query);
  await page.locator(`[data-city="${cityId}"]`).click();
}

// ------------------------------------------------------------------ scenarios
const results = [];
async function scenario(name, fn) {
  const t0 = Date.now();
  try { await fn(); results.push({ name, ok: true, ms: Date.now() - t0 }); }
  catch (e) { results.push({ name, ok: false, err: e, ms: Date.now() - t0 }); }
}

async function run() {
  // ---- 1. five languages
  await scenario('Языки: первый экран показывает названия языков на самих языках', async () => {
    const { page } = await newCtx({}, { cityAsked: true });
    await page.goto('/');
    await page.getByTestId('language-screen').waitFor();
    const labels = await page.locator('button[data-lang]').allInnerTexts();
    assert.deepEqual(labels, ['Русский', 'Тоҷикӣ', 'Oʻzbekcha', 'Кыргызча', 'Қазақша']);
    await page.screenshot({ path: path.join(SHOTS, '01-language.png') });
  });

  await scenario('Языки: переключение всех пяти языков меняет меню, заголовки, документы, советы и объявления', async () => {
    const { page } = await newCtx({}, { cityAsked: true });
    await page.goto('/');
    await page.locator('button[data-lang="ru"]').click();
    const seen = new Set();
    for (const lang of ['ru', 'tg', 'uz', 'ky', 'kk']) {
      const S = await i18n(lang);
      await page.getByTestId('lang-chip').click();
      await page.locator(`button[data-lang="${lang}"]`).click();
      await page.getByTestId('tab-docs').getByText(S['nav.docs'], { exact: true }).waitFor();
      assert.equal(await page.locator('html').getAttribute('lang'), lang);
      for (const [k, key] of [['docs', 'nav.docs'], ['where', 'nav.where'], ['tips', 'nav.tips'], ['ads', 'nav.ads']]) {
        assert.equal((await page.getByTestId(`tab-${k}`).innerText()).trim(), S[key], `${lang} tab ${k}`);
      }
      // documents: the card title comes in the chosen language
      await page.goto('/docs'); await page.waitForSelector('[data-testid=doc-card]');
      assert.equal(await page.locator('h1').first().innerText(), S['docs.title']);
      const doc = (await api('GET', `/documents/patent?lang=${lang}`)).json;
      assert.ok((await text(page)).includes(doc.title), `${lang}: title of patent`);
      seen.add(doc.title);
      assert.ok(!rawKeys.test(await text(page)), `${lang}: raw key on /docs`);
      for (const p of ['/where', '/tips', '/ads', '/list', '/data']) {
        await page.goto(p); await page.waitForTimeout(250);
        assert.ok(!rawKeys.test(await text(page)), `${lang}: raw key on ${p}: ${(await text(page)).match(rawKeys)?.[0]}`);
      }
      await page.goto('/tips'); await page.waitForSelector('[data-testid=tip]');
      assert.equal(await page.locator('h1').first().innerText(), S['tips.title']);
      await page.goto('/ads');
      assert.equal(await page.locator('h1').first().innerText(), S['ads.title']);
      await page.screenshot({ path: path.join(SHOTS, `02-lang-${lang}.png`) });
    }
    assert.equal(seen.size, 5, 'five different translations of the same document title');
  });

  await scenario('Языки: выбор сохраняется после перезагрузки', async () => {
    const { page } = await newCtx({}, { cityAsked: true });
    await page.goto('/'); await page.locator('button[data-lang="uz"]').click();
    const S = await i18n('uz');
    await page.getByTestId('tab-docs').getByText(S['nav.docs']).waitFor();
    await page.reload();
    await page.getByTestId('tab-docs').getByText(S['nav.docs']).waitFor();
  });

  // ---- 2. city selection
  await scenario('Город: ручной выбор, одноимённые города различаются регионом, выбор сохраняется', async () => {
    const { page } = await newCtx({}, {});
    await page.goto('/'); await page.locator('button[data-lang="ru"]').click();
    await page.getByTestId('city-picker').waitFor();
    assert.ok(await page.getByTestId('city-detect').isVisible() && await page.getByTestId('city-manual').isVisible());
    await page.getByTestId('city-manual').click();
    await page.getByTestId('city-search').fill('Железногорск');
    await page.getByTestId('city-results').waitFor();
    const rows = await page.locator('[data-testid=city-results] button').allInnerTexts();
    assert.equal(rows.length, 2);
    assert.ok(rows.some((r) => r.includes('Курская область')) && rows.some((r) => r.includes('Красноярский край')), rows.join(' | '));
    await page.locator('[data-city="zheleznogorsk_krsk"]').click();
    await page.getByTestId('city-picker').waitFor({ state: 'detached' });
    assert.ok((await page.getByTestId('city-chip').innerText()).includes('Железногорск, Красноярский край'));
    await page.reload();
    assert.ok((await page.getByTestId('city-chip').innerText()).includes('Железногорск, Красноярский край'));
    const stored = await page.evaluate(() => JSON.parse(localStorage.getItem('city')));
    assert.deepEqual(Object.keys(stored).sort(), ['id', 'name', 'region']);
    await page.screenshot({ path: path.join(SHOTS, '03-city-chip.png') });
  });

  await scenario('Город: поиск без результатов и поиск латиницей', async () => {
    const { page } = await newCtx({}, { lang: 'ru' });
    await page.goto('/');
    await page.getByTestId('city-manual').click();
    await page.getByTestId('city-search').fill('Атлантида');
    await page.getByTestId('city-noresults').waitFor();
    await page.getByTestId('city-search').fill('Moskva');
    await page.locator('[data-city="moscow"]').waitFor();
  });

  await scenario('Город: автоопределение — найден город, пользователь подтверждает, координаты не сохраняются', async () => {
    const { ctx, page } = await newCtx({ permissions: ['geolocation'], geolocation: MOSCOW }, { lang: 'ru' });
    const requests = [];
    page.on('request', (r) => { if (r.url().includes('/api/')) requests.push({ m: r.method(), u: r.url(), b: r.postData() }); });
    await page.goto('/');
    await page.getByTestId('city-detect').click();
    await page.getByTestId('city-candidate').waitFor();
    assert.ok((await page.getByTestId('city-candidate').innerText()).includes('Москва, г. Москва'));
    await page.getByTestId('city-confirm').click();
    assert.ok((await page.getByTestId('city-chip').innerText()).includes('Москва, г. Москва'));
    const locate = requests.find((r) => r.u.includes('/cities/locate'));
    assert.equal(locate.m, 'POST');
    assert.ok(!/55\.7|37\.6/.test(locate.u), 'coordinates must not appear in the URL');
    const dump = await page.evaluate(() => JSON.stringify({ ...localStorage }) + document.cookie);
    assert.ok(!/55\.75|37\.61|latitude|longitude/.test(dump), 'no coordinates in browser storage');
    await ctx.storageState();
  });

  await scenario('Город: автоопределение — пользователь отклоняет найденный город и выбирает вручную', async () => {
    const { page } = await newCtx({ permissions: ['geolocation'], geolocation: MOSCOW }, { lang: 'ru' });
    await page.goto('/');
    await page.getByTestId('city-detect').click();
    await page.getByTestId('city-candidate').waitFor();
    await page.getByTestId('city-reject').click();
    await pickCityManual(page, 'Казань', 'kazan');
    assert.ok((await page.getByTestId('city-chip').innerText()).includes('Казань, Республика Татарстан'));
  });

  await scenario('Город: геолокация за пределами РФ и вдали от городов из списка ведёт к ручному поиску', async () => {
    for (const [pos, key] of [[DUSHANBE, 'city.outside'], [BAKU, 'city.notFoundNear']]) {
      const { page } = await newCtx({ permissions: ['geolocation'], geolocation: pos }, { lang: 'ru' });
      await page.goto('/');
      await page.getByTestId('city-detect').click();
      await page.getByTestId('city-message').waitFor();
      const S = await i18n('ru');
      assert.equal((await page.getByTestId('city-message').innerText()).trim(), S[key]);
      assert.ok(await page.getByTestId('city-search').isVisible());
    }
  });

  await scenario('Город: отказ в геолокации и недоступная геолокация — сообщение и ручной поиск', async () => {
    const S = await i18n('ru');
    // denied: no permission granted
    {
      const { page } = await newCtx({ permissions: [] }, { lang: 'ru' });
      await page.addInitScript(() => {
        const deny = (ok, err) => setTimeout(() => err({ code: 1, PERMISSION_DENIED: 1, POSITION_UNAVAILABLE: 2, TIMEOUT: 3, message: 'denied' }), 20);
        Object.defineProperty(navigator, 'geolocation', { value: { getCurrentPosition: deny }, configurable: true });
      });
      await page.goto('/');
      await page.getByTestId('city-detect').click();
      await page.getByTestId('city-message').waitFor();
      assert.equal((await page.getByTestId('city-message').innerText()).trim(), S['city.denied']);
      await pickCityManual(page, 'Москва', 'moscow');
      assert.ok((await page.getByTestId('city-chip').innerText()).includes('Москва'));
    }
    // really denied by the browser
    {
      const { page } = await newCtx({ permissions: [] }, { lang: 'ru' });
      await page.goto('/');
      await page.getByTestId('city-detect').click();
      await page.getByTestId('city-message').waitFor({ timeout: 15000 });
      const msg = (await page.getByTestId('city-message').innerText()).trim();
      assert.ok([S['city.denied'], S['city.unavailable']].includes(msg), msg);
      assert.ok(await page.getByTestId('city-search').isVisible());
    }
    // unavailable
    {
      const { page } = await newCtx({}, { lang: 'ru' });
      await page.addInitScript(() => {
        Object.defineProperty(navigator, 'geolocation', { value: { getCurrentPosition: (ok, err) => setTimeout(() => err({ code: 2, PERMISSION_DENIED: 1, POSITION_UNAVAILABLE: 2, TIMEOUT: 3, message: 'na' }), 20) }, configurable: true });
      });
      await page.goto('/');
      await page.getByTestId('city-detect').click();
      await page.getByTestId('city-message').waitFor();
      assert.equal((await page.getByTestId('city-message').innerText()).trim(), S['city.unavailable']);
    }
  });

  await scenario('Город: можно пропустить выбор — каталог доступен, для учреждений нужен город', async () => {
    const { page } = await newCtx({}, { lang: 'ru' });
    const S = await i18n('ru');
    await page.goto('/');
    await page.getByTestId('city-skip').click();
    assert.equal((await page.getByTestId('city-chip').innerText()).trim(), S['city.none']);
    await page.waitForSelector('[data-testid=doc-card]');
    await page.goto('/docs/inn/where');
    await page.getByTestId('need-city').waitFor();
    await page.goto('/where');
    await page.getByTestId('need-city').waitFor();
    assert.equal(await page.locator('[data-testid=institution]').count(), 0);
  });

  // ---- 3. «Где оформить в моём городе»
  await scenario('Где оформить: кнопка на карточке документа, учреждения этого документа в городе', async () => {
    const { page } = await newCtx({}, { ...ready, city: CITY.moscow });
    await page.goto('/docs/inn');
    await page.getByTestId('where-button').click();
    await page.getByTestId('where-doc').waitFor();
    await page.waitForSelector('[data-testid=institution]');
    const got = await ids(page, '[data-testid=institution]');
    assert.ok(got.includes('mfc_moscow') && got.includes('fns_moscow'), got.join());
    assert.ok(!got.includes('mmc_moscow'), 'institution without this service must not appear');
    const demoCard = page.locator('[data-id=mfc_moscow]');
    assert.ok((await demoCard.innerText()).includes('Адрес не подтверждён'));
    assert.ok((await demoCard.innerText()).includes('Демо, не проверено'));
    assert.ok((await demoCard.innerText()).includes('Не проверено'));
    const href = await demoCard.getByTestId('map-link').getAttribute('href');
    assert.ok(href.startsWith('https://yandex.ru/maps/?text='));
    await page.screenshot({ path: path.join(SHOTS, '04-where-moscow.png'), fullPage: true });
  });

  await scenario('Где оформить: уточнение района предлагается вручную и сужает список', async () => {
    const { page } = await newCtx({}, { ...ready, city: CITY.moscow });
    await page.goto('/docs/inn/where');
    await page.getByTestId('district-prompt').waitFor();
    assert.equal(await page.locator('[data-id=fx_fns_cao]').count(), 0);
    await page.getByTestId('district-select').selectOption('cao');
    await page.locator('[data-id=fx_fns_cao]').waitFor();
    assert.equal(await page.locator('[data-id=fx_fns_sao]').count(), 0);
    const card = page.locator('[data-id=fx_fns_cao]');
    const t = await card.innerText();
    for (const part of ['ТЕСТОВАЯ улица, 2', 'Пн–Пт 09:00–18:00', '+7 000 000-00-00', 'example.test', 'Проверено:', 'ТЕСТОВЫЙ источник', 'ЦАО', 'Очно']) assert.ok(t.includes(part), `card lacks «${part}»`);
    assert.ok((await card.getByTestId('map-link').getAttribute('href')).includes('yandex.ru/maps'));
    assert.ok((await card.locator('a', { hasText: 'Запись' }).getAttribute('href')).includes('example.test/booking'));
    await page.getByTestId('district-select').selectOption('svao');
    await page.locator('[data-id=fx_fns_sao]').waitFor();
    assert.equal(await page.locator('[data-id=fx_fns_cao]').count(), 0);
  });

  await scenario('Где оформить: учреждение из другого города показывает фактический адрес и поясняет, что обслуживает ваш город', async () => {
    const { page } = await newCtx({}, { ...ready, city: { id: 'khimki', name: 'Химки', region: 'Московская область' } });
    await page.goto('/docs/inn/where');
    await page.locator('[data-id=fx_center_for_khimki]').waitFor();
    const note = await page.getByTestId('other-city-note').innerText();
    assert.ok(note.includes('ТЕСТОВАЯ улица, 1, Москва') && note.includes('Химки'), note);
    assert.equal(await page.locator('[data-testid=institution]').count(), 1);
  });

  await scenario('Где оформить: смена города обновляет адреса; нет подтверждённых адресов — понятное сообщение и ссылка на официальный поиск', async () => {
    const { page } = await newCtx({}, { ...ready, city: CITY.moscow });
    await page.goto('/docs/fx_service/where');
    await page.locator('[data-id=fx_online_service]').waitFor();
    // change the city from the header
    await page.getByTestId('city-chip').click();
    await page.getByTestId('city-manual').click();
    await pickCityManual(page, 'Казань', 'kazan');
    await page.getByTestId('no-places').waitFor();
    assert.equal(await page.locator('[data-testid=institution]').count(), 0);
    assert.ok((await page.getByTestId('no-places').innerText()).includes('Казань'));
    const link = page.getByTestId('official-search');
    assert.equal(await link.getAttribute('href'), 'https://example.test/search');
    // a document without an official search link says so
    await page.goto('/docs/patent/where');
    await page.getByTestId('no-official-search').waitFor();
    assert.equal(await page.locator('[data-testid=institution]').count(), 0);
    // back to Moscow: the addresses return
    await page.getByTestId('city-chip').click();
    await page.getByTestId('city-manual').click();
    await pickCityManual(page, 'Москва', 'moscow');
    await page.locator('[data-id=mmc_moscow]').waitFor();
    await page.screenshot({ path: path.join(SHOTS, '05-where-kazan-none.png') });
  });

  await scenario('Где оформить: документ без учреждения объясняет, что учреждения нет', async () => {
    const { page } = await newCtx({}, { ...ready, city: CITY.moscow });
    await page.goto('/docs/bank_account/where');
    await page.getByTestId('no-institution').waitFor();
  });

  await scenario('Где оформить: раздел «Где оформить» — фильтры по услуге и формату, смена города', async () => {
    const { page } = await newCtx({}, { ...ready, city: CITY.moscow });
    await page.goto('/where');
    await page.waitForSelector('[data-testid=institution]');
    const all = await page.locator('[data-testid=institution]').count();
    await page.getByTestId('service-filter').selectOption('lost_passport');
    await page.waitForFunction((n) => document.querySelectorAll('[data-testid=institution]').length !== n, all);
    assert.equal(await page.locator('[data-testid=institution]').count(), 4);
    await page.getByTestId('service-filter').selectOption('');
    await page.locator('[data-mode=online]').click();
    await page.waitForFunction(() => [...document.querySelectorAll('[data-testid=institution]')].every((e) => /онлайн/i.test(e.textContent)));
    await page.getByTestId('city-chip').click();
    await page.getByTestId('city-manual').click();
    await pickCityManual(page, 'Казань', 'kazan');
    // Портал Госуслуг обслуживает всю страну (serves: scope country), поэтому для Казани
    // в режиме «онлайн» он остаётся единственным результатом — не «нет адресов». (gosuslugi_notification
    // matches the stale Moscow list too, so wait for the count to actually settle at 1, not just for it to appear.)
    await page.waitForFunction(() => document.querySelectorAll('[data-testid=institution]').length === 1);
    assert.deepEqual(await ids(page, '[data-testid=institution]'), ['gosuslugi_notification']);
  });

  // ---- 4. tips and the city filter
  await scenario('Советы: поиск, тема, фильтр по городу обновляется при смене города', async () => {
    const { page } = await newCtx({}, { ...ready, city: CITY.moscow });
    await page.goto('/tips');
    await page.waitForSelector('[data-testid=tip]');
    let got = await ids(page, '[data-testid=tip]');
    assert.ok(got.includes('tip_moscow_commute') && !got.includes('fx_tip_kazan'));
    const card = page.locator('[data-id=tip_moscow_commute]');
    const t = await card.innerText();
    assert.ok(t.includes('Совет редакции') && t.includes('Москва') && t.includes('Обновлено'), t);
    await page.getByTestId('tips-local').check();
    await page.waitForFunction(() => document.querySelectorAll('[data-testid=tip]').length === 1);
    await page.getByTestId('tips-local').uncheck();
    await page.getByTestId('tips-search').fill('мошенник');
    await page.getByTestId('tips-search').fill('предоплат');
    await page.waitForFunction(() => document.querySelectorAll('[data-testid=tip]').length >= 1 && document.querySelectorAll('[data-testid=tip]').length < 6);
    await page.getByTestId('tips-search').fill('');
    await page.getByTestId('city-chip').click();
    await page.getByTestId('city-manual').click();
    await pickCityManual(page, 'Казань', 'kazan');
    await page.waitForSelector('[data-id=fx_tip_kazan]');
    got = await ids(page, '[data-testid=tip]');
    assert.ok(!got.includes('tip_moscow_commute'));
    await page.screenshot({ path: path.join(SHOTS, '06-tips.png'), fullPage: true });
  });

  // ---- 5. checklist
  await scenario('Мой список: разные ситуации дают разные шаги, отметки сохраняются', async () => {
    const run1 = async (cit, purpose, stage, flags = []) => {
      const { page } = await newCtx({}, { ...ready, city: CITY.moscow });
      await page.goto('/list');
      await page.getByTestId('citizenship-select').selectOption(cit);
      await page.locator(`[data-purpose=${purpose}]`).check();
      await page.locator(`[data-stage=${stage}]`).check();
      for (const f of flags) await page.locator(`[data-flag=${f}]`).check();
      await page.getByTestId('list-build').click();
      await page.getByTestId('progress').or(page.getByTestId('clarify')).first().waitFor();
      return { page, items: await ids(page, '[data-testid=list-items] > li') };
    };
    let r = await run1('TJ', 'work', 'in_russia');
    assert.ok(r.items.includes('patent') && !r.items.includes('work_right_eaeu') && r.items.includes('migration_registration'), r.items.join());
    // expanding a step shows the full procedure and the addresses right there, without navigating away
    await r.page.locator('[data-testid=step-toggle-patent]').click();
    await r.page.locator('[data-testid=step-details-patent] [data-testid=doc-deadline]').waitFor();
    await r.page.locator('[data-testid=step-details-patent] [data-testid=institution]').first().waitFor();
    const stepDetails = await r.page.locator('[data-testid=step-details-patent]').innerText();
    assert.ok(stepDetails.includes('Как подать заявление') || stepDetails.includes('Кому и при каких условиях'), stepDetails);
    await r.page.screenshot({ path: path.join(SHOTS, '07a-checklist-step-expanded.png'), fullPage: true });
    await r.page.locator('[data-testid=step-toggle-patent]').click();
    await r.page.locator('[data-testid=step-details-patent]').waitFor({ state: 'hidden' });
    // mark, reload, still marked
    await r.page.locator('[data-id=patent] input[type=checkbox]').check();
    assert.ok((await r.page.getByTestId('progress').innerText()).includes('1 из'));
    await r.page.reload();
    await r.page.waitForSelector('[data-id=patent]');
    assert.ok(await r.page.locator('[data-id=patent] input[type=checkbox]').isChecked());
    await r.page.screenshot({ path: path.join(SHOTS, '07-checklist-tj.png'), fullPage: true });

    r = await run1('KG', 'work', 'in_russia');
    assert.ok(r.items.includes('work_right_eaeu') && !r.items.includes('patent'), r.items.join());

    r = await run1('UZ', 'tourism', 'before');
    assert.deepEqual(r.items, ['passport_valid', 'entry_documents']);

    r = await run1('KZ', 'study', 'in_russia');
    assert.ok(r.items.includes('study_enrollment') && !r.items.includes('patent'));

    r = await run1('TJ', 'work', 'in_russia', ['lost_document']);
    assert.ok(r.items.includes('lost_passport') && r.items.includes('lost_migration_docs'));

    r = await run1('OTHER', 'work', 'in_russia');
    const clarify = await r.page.getByTestId('clarify').innerText();
    assert.ok(clarify.includes('Для этой страны правила пока не загружены'), clarify);
    assert.ok(!r.items.includes('patent'));
    assert.ok(clarify.includes('Патент на работу'), 'documents that depend on citizenship are listed for clarification');
    await r.page.screenshot({ path: path.join(SHOTS, '08-checklist-other.png'), fullPage: true });
  });

  await scenario('Мой список: демо-записи помечены, подтверждённая запись показывает срок и стоимость', async () => {
    const { page } = await newCtx({}, { ...ready, city: CITY.moscow });
    // snils остаётся demo-записью без подтверждённых срока/стоимости: оба раздела просто не
    // показываются (см. mobile/doc_screen.dart, web/Doc.tsx — плейсхолдер "Не подтверждено" убран).
    await page.goto('/docs/snils');
    await page.getByTestId('demo-warning').waitFor();
    assert.equal(await page.getByTestId('doc-deadline').count(), 0);
    assert.equal(await page.getByTestId('doc-cost').count(), 0);
    await page.goto('/docs/fx_service');
    assert.ok((await page.getByTestId('doc-deadline').innerText()).includes('до 10 рабочих дней'));
    assert.ok((await page.getByTestId('doc-cost').innerText()).includes('1000 руб.'));
    assert.equal(await page.getByTestId('demo-warning').count(), 0);
    assert.ok((await text(page)).includes('Проверено'));
    // patent теперь тоже настоящая verified-запись (реальные данные с mc.mos.ru).
    await page.goto('/docs/patent');
    assert.equal(await page.getByTestId('demo-warning').count(), 0);
    assert.ok((await page.getByTestId('doc-deadline').innerText()).includes('30 календарных дней'));
    assert.ok((await page.getByTestId('doc-cost').innerText()).includes('26 000'));
  });

  // ---- 6. advertisements: complete path
  await scenario('Объявления: публикация, просмотр из другой сессии, отклик, жалоба, модерация, снятие', async () => {
    const S = await i18n('ru');
    const A = await newCtx({ ...MOBILE }, { ...ready, city: CITY.moscow });           // author, phone
    const B = await newCtx({ viewport: { width: 1280, height: 800 }, isMobile: false, hasTouch: false }, { ...ready, city: CITY.moscow }); // reader, desktop
    const M = await newCtx({}, { ...ready, city: CITY.moscow });                       // moderator

    // author registers and posts a housing ad (published at once)
    await A.page.goto('/register');
    await A.page.getByTestId('auth-email').fill('author@e2e.local');
    await A.page.getByTestId('auth-password').fill('author-pass-123');
    await A.page.getByTestId('auth-submit').click();
    await A.page.waitForURL('**/ads');
    await A.page.goto('/ads/new');
    await A.page.getByTestId('ad-category').selectOption('housing');
    await A.page.getByTestId('ad-title-input').fill('Комната рядом с метро');
    await A.page.getByTestId('ad-body').fill('Сдаётся комната в двухкомнатной квартире, рядом остановка и магазин.');
    await A.page.getByTestId('ad-price').fill('25 000 в месяц');
    await A.page.getByTestId('ad-lang-select').selectOption('ru');
    await A.page.getByTestId('ad-submit').click();
    await A.page.getByTestId('ad-title').waitFor();
    assert.equal(await A.page.getByTestId('ad-title').innerText(), 'Комната рядом с метро');
    const adUrl = A.page.url();
    await A.page.screenshot({ path: path.join(SHOTS, '09-ad-author.png'), fullPage: true });

    // another device, no account: sees it in the list and the detail page
    await B.page.goto('/ads');
    await B.page.locator('[data-testid=listing-card]', { hasText: 'Комната рядом с метро' }).waitFor();
    await B.page.locator('[data-testid=listing-card]', { hasText: 'Комната рядом с метро' }).click();
    await B.page.getByTestId('ad-title').waitFor();
    assert.ok((await text(B.page)).includes('Объявление пользователя'));
    assert.ok(!(await text(B.page)).includes('author@e2e.local'), 'author e-mail is never shown');
    assert.equal(await B.page.getByTestId('respond-form').count(), 0);
    assert.ok(await B.page.getByText(S['ads.loginToAct']).isVisible());
    await B.page.screenshot({ path: path.join(SHOTS, '10-ad-reader.png'), fullPage: true });

    // reader registers and responds through the form
    await B.page.goto('/register', { waitUntil: 'load' });
    await B.page.getByTestId('auth-email').fill('reader@e2e.local');
    await B.page.getByTestId('auth-password').fill('reader-pass-1234');
    await B.page.getByTestId('auth-submit').click();
    await B.page.waitForURL('**/ads');
    await B.page.goto(adUrl.replace(BASE, ''));
    await B.page.getByTestId('respond-form').waitFor();
    await B.page.getByTestId('respond-message').fill('Здравствуйте! Комната ещё свободна?');
    await B.page.getByTestId('respond-contact').fill('Telegram @reader_e2e');
    await B.page.getByTestId('respond-send').click();
    await B.page.getByTestId('respond-sent').waitFor();

    // the author sees the response, with the contact the reader chose to share
    await A.page.goto('/ads/mine');
    const mine = A.page.locator('[data-testid=my-ad]', { hasText: 'Комната рядом с метро' });
    await mine.waitFor();
    assert.ok((await mine.innerText()).includes(`${S['ads.responses']}: 1`), await mine.innerText());
    await mine.click();
    await A.page.getByTestId('responses').getByText('Telegram @reader_e2e').waitFor();
    const box = await A.page.getByTestId('responses').innerText();
    assert.ok(box.includes('Комната ещё свободна') && box.includes('Telegram @reader_e2e'), box);

    // vacancy: waits for the moderator, invisible to others
    await A.page.goto('/ads/new');
    await A.page.getByTestId('ad-category').selectOption('work');
    await A.page.getByTestId('ad-title-input').fill('Требуется упаковщик на склад');
    await A.page.getByTestId('ad-employer').fill('ООО «Тест»');
    await A.page.getByTestId('ad-pay').fill('70 000 в месяц');
    await A.page.getByTestId('ad-schedule').fill('2/2, по 12 часов');
    await A.page.getByTestId('ad-terms').fill('Трудовой договор');
    await A.page.getByTestId('ad-body').fill('Склад, упаковка товаров. Обучение на месте, форму выдают.');
    await A.page.getByTestId('ad-submit').click();
    await A.page.getByTestId('ad-status').waitFor();
    assert.equal((await A.page.getByTestId('ad-status').innerText()).trim(), S['ads.status.pending']);
    assert.ok((await text(A.page)).includes(S['ads.pendingNote']));
    await B.page.goto('/ads');
    await B.page.locator('[data-testid=listing-card]', { hasText: 'Комната рядом с метро' }).waitFor();
    assert.equal(await B.page.locator('[data-testid=listing-card]', { hasText: 'упаковщик' }).count(), 0);

    // moderator logs in and approves
    await M.page.goto('/login');
    await M.page.getByTestId('auth-email').fill(MOD.email);
    await M.page.getByTestId('auth-password').fill(MOD.password);
    await M.page.getByTestId('auth-submit').click();
    await M.page.waitForURL('**/mod');
    const item = M.page.locator('[data-testid=mod-item]', { hasText: 'упаковщик' });
    await item.waitFor();
    assert.ok((await item.innerText()).includes('ООО «Тест»'));
    await M.page.screenshot({ path: path.join(SHOTS, '11-moderation.png'), fullPage: true });
    await item.getByTestId('mod-approve').click();
    await M.page.waitForFunction(() => ![...document.querySelectorAll('[data-testid=mod-item]')].some((e) => e.textContent.includes('упаковщик')));
    await B.page.goto('/ads');
    await B.page.locator('[data-testid=listing-card]', { hasText: 'упаковщик' }).waitFor();
    await B.page.locator('[data-category=work]').click();
    await B.page.waitForFunction(() => document.querySelectorAll('[data-testid=listing-card]').length === 1);
    assert.ok((await B.page.locator('[data-testid=listing-card]').innerText()).includes('упаковщик'));

    // the reader reports the housing ad; the moderator hides it with a reason
    await B.page.goto(adUrl.replace(BASE, ''));
    await B.page.getByTestId('report-open').click();
    await B.page.getByTestId('report-reason').fill('Подозрительное объявление');
    await B.page.getByTestId('report-send').click();
    await B.page.getByTestId('report-sent').waitFor();
    await M.page.goto('/mod');
    await M.page.locator('[data-kind=reported]').click();
    const rep = M.page.locator('[data-testid=mod-item]', { hasText: 'Комната рядом с метро' });
    await rep.waitFor();
    assert.ok((await rep.innerText()).includes('Подозрительное объявление'));
    await rep.getByTestId('mod-reason').fill('Нужна проверка владельца');
    await rep.getByTestId('mod-hide').click();
    await M.page.waitForFunction(() => document.querySelectorAll('[data-testid=mod-item]').length === 0);
    await B.page.goto('/ads');
    await B.page.waitForSelector('[data-testid=listing-card]');
    assert.equal(await B.page.locator('[data-testid=listing-card]', { hasText: 'Комната рядом с метро' }).count(), 0);
    await A.page.goto('/ads/mine');
    const mine2 = A.page.locator('[data-testid=my-ad]', { hasText: 'Комната рядом с метро' });
    assert.ok((await mine2.innerText()).includes(S['ads.status.hidden']));
    assert.ok((await mine2.innerText()).includes('Нужна проверка владельца'));

    // the author withdraws the vacancy
    await A.page.locator('[data-testid=my-ad]', { hasText: 'упаковщик' }).click();
    await A.page.getByTestId('ad-withdraw').click();
    await A.page.waitForURL('**/ads/mine');
    await B.page.goto('/ads');
    await B.page.waitForTimeout(300);
    assert.equal(await B.page.locator('[data-testid=listing-card]', { hasText: 'упаковщик' }).count(), 0);
  });

  await scenario('Объявления: запрещённые предложения, паспортные данные и контакты отклоняются; язык объявления указан', async () => {
    const S = await i18n('ru');
    const { page } = await newCtx({}, { ...ready, city: CITY.moscow });
    const r = await api('POST', '/auth/register', { email: 'rules@e2e.local', password: 'rules-pass-123' });
    await page.addInitScript((t) => { localStorage.setItem('token', t); }, r.json.token);
    await page.goto('/ads/new');
    const post = async (title, body, category = 'services') => {
      await page.getByTestId('ad-category').selectOption(category);
      await page.getByTestId('ad-title-input').fill(title);
      await page.getByTestId('ad-body').fill(body);
      await page.getByTestId('ad-submit').click();
    };
    await post('Помогу с документами', 'Продаю патент без экзамена, быстро и недорого.');
    await page.locator('.notice-error').waitFor();
    assert.equal((await page.locator('.notice-error').innerText()).trim(), S['ads.err.forbidden']);
    await post('Услуги', 'Фиктивная регистрация для патента.');
    await page.waitForFunction((m) => document.querySelector('.notice-error')?.textContent.trim() === m, S['ads.err.forbidden']);
    await post('Услуги переводчика', 'Перевожу документы. Паспорт 4510 123456.');
    await page.waitForFunction((m) => document.querySelector('.notice-error')?.textContent.trim() === m, S['ads.err.passport']);
    await post('Услуги электрика', 'Звоните +7 999 123-45-67 в любое время.');
    await page.waitForFunction((m) => document.querySelector('.notice-error')?.textContent.trim() === m, S['ads.err.contact']);
    // a valid ad in Uzbek shows its language
    await page.getByTestId('ad-lang-select').selectOption('uz');
    await post('Elektrik xizmati', 'Elektr montaj ishlari, tez va sifatli bajaraman.');
    await page.getByTestId('ad-lang').waitFor();
    assert.ok((await page.getByTestId('ad-lang').innerText()).includes('Oʻzbekcha'));
    assert.equal(await page.getByTestId('ad-title').getAttribute('lang'), 'uz');
    await page.goto('/ads');
    const card = page.locator('[data-testid=listing-card]', { hasText: 'Elektrik xizmati' });
    await card.waitFor();
    assert.ok((await card.innerText()).includes('Oʻzbekcha'));
  });

  await scenario('Объявления: фильтр по городу следует за выбранным городом', async () => {
    const t1 = (await api('POST', '/auth/register', { email: 'seed@e2e.local', password: 'seed-pass-1234' })).json.token;
    const mk = (title, city) => api('POST', '/listings', { category: 'market', title, body: 'Описание объявления для проверки фильтра города.', lang: 'ru', city_id: city, price: '100', duration_days: 7 }, t1);
    await mk('Холодильник в Москве', 'moscow'); await mk('Диван в Казани', 'kazan');
    const { page } = await newCtx({}, { ...ready, city: CITY.moscow });
    await page.goto('/ads');
    await page.locator('[data-testid=listing-card]', { hasText: 'Холодильник в Москве' }).waitFor();
    assert.equal(await page.locator('[data-testid=listing-card]', { hasText: 'Диван в Казани' }).count(), 0);
    await page.getByTestId('city-chip').click();
    await page.getByTestId('city-manual').click();
    await pickCityManual(page, 'Казань', 'kazan');
    await page.locator('[data-testid=listing-card]', { hasText: 'Диван в Казани' }).waitFor();
    assert.equal(await page.locator('[data-testid=listing-card]', { hasText: 'Холодильник в Москве' }).count(), 0);
    await page.getByTestId('ads-all-cities').check();
    await page.locator('[data-testid=listing-card]', { hasText: 'Холодильник в Москве' }).waitFor();
    await page.getByTestId('ads-search').fill('диван');
    await page.waitForFunction(() => document.querySelectorAll('[data-testid=listing-card]').length === 1);
  });

  // ---- 6b. Обратная связь
  await scenario('Обратная связь: доступна без аккаунта, короткое сообщение отклоняется, отправленное попадает к модератору', async () => {
    const { page } = await newCtx({}, { ...ready, city: CITY.moscow });
    await page.goto('/feedback');
    await page.getByTestId('feedback-message').fill('нет');
    await page.getByTestId('feedback-submit').click();
    await page.locator('.notice-error').waitFor();
    assert.equal(await page.getByTestId('feedback-sent').count(), 0);

    await page.getByTestId('feedback-message').fill('Адрес ММЦ в разделе патент указан неверно, проверьте пожалуйста.');
    await page.getByTestId('feedback-email').fill('tester@e2e.local');
    await page.getByTestId('feedback-submit').click();
    await page.getByTestId('feedback-sent').waitFor();

    // обычный пользователь не может читать очередь обратной связи
    const plainTok = (await api('POST', '/auth/register', { email: 'feedback-plain-e2e@e2e.local', password: 'seed-pass-1234' })).json.token;
    assert.equal((await api('GET', '/mod/feedback', undefined, plainTok)).status, 403);

    // модератор (посеянный при старте сервера) видит отправленное сообщение
    const modTok = (await api('POST', '/auth/login', { email: MOD.email, password: MOD.password })).json.token;
    const q = await api('GET', '/mod/feedback', undefined, modTok);
    assert.equal(q.status, 200);
    assert.ok(q.json.feedback.some((f) => f.message.includes('ММЦ') && f.email === 'tester@e2e.local'));
  });

  // ---- 7. PWA
  await scenario('PWA: манифест, иконки, service worker и работа без сети', async () => {
    const { ctx, page } = await newCtx({}, { ...ready, city: CITY.moscow });
    await page.goto('/docs');
    await page.waitForSelector('[data-testid=doc-card]');
    const m = await (await fetch(`${BASE}/manifest.webmanifest`)).json();
    assert.equal(m.display, 'standalone');
    for (const i of m.icons) assert.equal((await fetch(BASE + i.src)).status, 200);
    await page.evaluate(() => navigator.serviceWorker.ready);
    await page.reload(); await page.waitForSelector('[data-testid=doc-card]');
    await ctx.setOffline(true);
    await page.reload();
    await page.waitForSelector('[data-testid=doc-card]', { timeout: 10000 });
    await ctx.setOffline(false);
  });
}

// ------------------------------------------------------------------ main
await resetDb();
const server = await startServer();
browser = await chromium.launch();
try {
  await run();
} finally {
  for (const c of contexts) await c.close().catch(() => {});
  await browser.close();
  server.kill();
}

let failed = 0;
for (const r of results) {
  console.log(`${r.ok ? 'OK  ' : 'FAIL'} ${r.name} (${r.ms} мс)`);
  if (!r.ok) { failed++; console.log('     ' + String(r.err?.stack ?? r.err).split('\n').slice(0, 6).join('\n     ')); }
}
console.log(`\n${results.length - failed} из ${results.length} сценариев прошли`);
process.exit(failed ? 1 : 0);
