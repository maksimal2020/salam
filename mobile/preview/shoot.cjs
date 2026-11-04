const { chromium } = require('/opt/npm-tools/node_modules/playwright');
const fs = require('fs');
const html = fs.readFileSync(__dirname + '/index.html', 'utf8');
const moscow = { id: 'moscow', name: 'Москва', region: 'г. Москва' };
const khimki = { id: 'khimki', name: 'Химки', region: 'Московская область' };
const kazan = { id: 'kazan', name: 'Казань', region: 'Республика Татарстан' };
const prof = { citizenship: 'KG', purpose: 'work', stage: 'in_russia', flags: { has_contract: true } };
const S = [
  ['01_language', 'language', { city: null }],
  ['02_city_choose', 'cityChoose', {}],
  ['03_city_denied', 'cityDenied', {}],
  ['04_city_confirm', 'cityConfirm', {}],
  ['05_city_manual', 'cityManual', {}],
  ['06_docs', 'docs', { city: moscow, n: 3 }],
  ['07_doc_card', 'doc', { id: 'patent' }],
  ['08_where_district', 'docWhere', { id: 'inn', city: moscow, district: null }],
  ['09_where_district_sheet', 'districtSheet', { city: moscow, district: null }],
  ['10_where_moscow_addresses', 'docWhere', { id: 'migration_registration', city: moscow, district: null }],
  ['11_where_other_city', 'docWhere', { id: 'inn', city: khimki, district: null }],
  ['12_where_no_addresses', 'docWhere', { id: 'inn', city: kazan, district: null }],
  ['13_where_tab', 'whereTab', { city: moscow }],
  ['14_list_form', 'checklistForm', { city: moscow, profile: prof }],
  ['15_list_result', 'checklistResult', { city: moscow, profile: prof, marks: {} }],
  ['16_tips', 'tips', { city: moscow }],
  ['17_ads', 'ads', { city: moscow }],
  ['18_ad_form', 'adForm', {}],
  ['19_ad_form_error', 'adFormError', {}],
  ['20_auth', 'auth', {}],
  ['21_mod', 'mod', {}],
  ['22_docs_tg', 'docs', { lang: 'tg', city: moscow, n: 3 }],
  ['23_lang_sheet', 'langSheet', { lang: 'ru', city: moscow }],
  ['24_data', 'data', { city: moscow }],
  ['25_offline', 'docs', { city: moscow, offline: true, n: 2 }],
];
(async () => {
  const b = await chromium.launch();
  const ctx = await b.newContext({ viewport: { width: 440, height: 900 }, deviceScaleFactor: 2 });
  const page = await ctx.newPage();
  await page.route('http://mock.local/**', async (r) => {
    const u = new URL(r.request().url());
    if (u.pathname.startsWith('/api/')) {
      const res = await fetch('http://localhost:3111' + u.pathname + u.search, {
        method: r.request().method(), headers: r.request().headers(), body: r.request().postData() ?? undefined,
      });
      return r.fulfill({ status: res.status, contentType: 'application/json', body: await res.text() });
    }
    return r.fulfill({ contentType: 'text/html; charset=utf-8', body: html });
  });
  await page.goto('http://mock.local/');
  // ad ids for detail screens
  const ads = await page.evaluate(async () => (await (await fetch('/api/listings')).json()).listings);
  const housing = ads.find((l) => l.category === 'housing' && l.lang === 'ru');
  S.push(['26_ad_detail', 'ad', { id: housing.id, city: moscow }]);
  S.push(['27_ad_respond', 'ad', { id: housing.id, city: moscow, msg: 'Здравствуйте! Комната ещё свободна? Могу посмотреть в субботу.' }]);
  S.push(['28_ad_login', 'adLogin', {}]);
  for (const [name, screen, opts] of S) {
    await page.evaluate(([s, o]) => window.show(s, o), [screen, opts]);
    await page.waitForTimeout(80);
    await page.locator('.phone').screenshot({ path: `${__dirname}/shots/${name}.png` });
    console.log('ok', name);
  }
  await b.close();
})().catch((e) => { console.error(e); process.exit(1); });
