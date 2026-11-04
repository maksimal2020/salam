import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { setup } from './helpers.js';
import { evaluateChecklist } from '../src/checklist.js';

let env: Awaited<ReturnType<typeof setup>>;
before(async () => { env = await setup(); });
after(async () => { await env.close(); });
const get = (u: string, t?: string) => env.call('GET', u, undefined, t);
const post = (u: string, b?: unknown, t?: string) => env.call('POST', u, b ?? {}, t);

async function user(email: string) {
  const r = await post('/auth/register', { email, password: 'password123', displayName: email.split('@')[0] });
  assert.equal(r.status, 201);
  return r.json.token as string;
}

// ---------------------------------------------------------------- languages
test('all five language packs are complete and share the same keys', async () => {
  const ru = (await get('/i18n/ru')).json;
  const n = Object.keys(ru.strings).length;
  assert.ok(n > 200);
  for (const lang of ['tg', 'uz', 'ky', 'kk']) {
    const r = (await get(`/i18n/${lang}`)).json;
    assert.equal(Object.keys(r.strings).length, n, lang);
    assert.deepEqual(r.missing, [], lang);
    assert.notEqual(r.strings['nav.docs'], ru.strings['nav.docs'], `${lang} must be translated`);
  }
});

test('documents come back in the requested language and Russian fallback is flagged', async () => {
  const kk = (await get('/documents/patent?lang=kk')).json;
  const ru = (await get('/documents/patent?lang=ru')).json;
  assert.notEqual(kk.title, ru.title);
  assert.equal(kk.details_fallback, true);
  assert.equal(ru.details_fallback, false);
  assert.equal(kk.deadline, null);          // demo record: no terms or prices
  assert.equal(kk.cost, null);
});

test('verified record shows terms and cost, demo record never does', async () => {
  const v = (await get('/documents/fx_service?lang=ru')).json;
  assert.equal(v.deadline.ru, 'до 10 рабочих дней (тест)');
  assert.equal(v.cost.ru, '1000 руб. (тест)');
});

// ---------------------------------------------------------------- checklist
const ids = (r: any) => r.json.items.map((i: any) => i.id);
const list = (p: object) => post('/checklist', { lang: 'ru', ...p });

test('checklist: citizen of a visa-free non-EAEU country working in Russia', async () => {
  const r = await list({ citizenship: 'TJ', purpose: 'work', stage: 'in_russia' });
  assert.ok(ids(r).includes('patent'));
  assert.ok(!ids(r).includes('work_right_eaeu'));
  assert.ok(!ids(r).includes('lost_passport'));
  assert.ok(ids(r).includes('fx_service'));
});

test('checklist: EAEU citizen working in Russia gets a different set', async () => {
  const r = await list({ citizenship: 'KG', purpose: 'work', stage: 'in_russia' });
  assert.ok(ids(r).includes('work_right_eaeu'));
  assert.ok(!ids(r).includes('patent'));
  assert.ok(!ids(r).includes('russian_exam'));
});

test('checklist: before arrival shows only pre-arrival steps', async () => {
  const r = await list({ citizenship: 'UZ', purpose: 'tourism', stage: 'before' });
  assert.deepEqual(ids(r), ['passport_valid', 'entry_documents']);
});

test('checklist: study purpose', async () => {
  const r = await list({ citizenship: 'KZ', purpose: 'study', stage: 'in_russia' });
  assert.ok(ids(r).includes('study_enrollment'));
  assert.ok(!ids(r).includes('patent'));
});

test('checklist: lost document flag adds recovery steps', async () => {
  const r = await list({ citizenship: 'TJ', purpose: 'work', stage: 'in_russia', flags: { lost_document: true } });
  assert.ok(ids(r).includes('lost_passport') && ids(r).includes('lost_migration_docs'));
});

test('checklist: unknown country and missing answers are reported, not guessed', async () => {
  const other = (await list({ citizenship: 'OTHER', purpose: 'work', stage: 'in_russia' })).json;
  assert.ok(other.clarify.some((c: any) => c.type === 'other_country'));
  assert.ok(other.clarify.some((c: any) => c.type === 'depends_on_citizenship' && c.docId === 'patent'));
  assert.ok(!other.items.some((i: any) => i.id === 'patent'));
  assert.ok(other.where_to_check.length > 0);
  const none = (await list({ purpose: 'work' })).json;
  assert.deepEqual(none.items, []);
  assert.ok(none.clarify.some((c: any) => c.type === 'missing' && c.field === 'citizenship'));
  assert.ok(none.clarify.some((c: any) => c.type === 'missing' && c.field === 'stage'));
});

test('checklist: demo records are left out when demo content is switched off', async () => {
  const docs = (await env.pool.query('select * from documents order by sort')).rows;
  const cits = (await env.pool.query('select id, grp from citizenships')).rows;
  const off = evaluateChecklist(docs, cits, { citizenship: 'TJ', purpose: 'work', stage: 'in_russia' }, false);
  assert.deepEqual(off.items.map((i) => i.id), ['fx_service']);   // only the verified fixture remains
  const on = evaluateChecklist(docs, cits, { citizenship: 'TJ', purpose: 'work', stage: 'in_russia' }, true);
  assert.ok(on.items.length > off.items.length);
});

// ---------------------------------------------------------------- cities
test('city search tells homonyms apart by region', async () => {
  const r = (await get('/cities?q=' + encodeURIComponent('Железногорск'))).json.cities;
  assert.equal(r.length, 2);
  assert.notEqual(r[0].region, r[1].region);
  assert.ok(r.every((c: any) => c.label.includes(c.region)));
  const lat = (await get('/cities?q=Moskva')).json.cities;
  assert.equal(lat[0].id, 'moscow');
  assert.deepEqual((await get('/cities?q=zzzzzz')).json.cities, []);
});

test('locate: city candidate, nothing nearby, and outside Russia', async () => {
  const msk = (await post('/cities/locate', { lat: 55.76, lon: 37.62 })).json;
  assert.equal(msk.status, 'candidate');
  assert.equal(msk.city.id, 'moscow');
  assert.equal((await post('/cities/locate', { lat: 38.56, lon: 68.77 })).json.status, 'outside');   // Dushanbe
  assert.equal((await post('/cities/locate', { lat: 40.4, lon: 49.9 })).json.status, 'no_match');    // Baku
  assert.equal((await post('/cities/locate', { lat: 'x', lon: 1 })).status, 400);
});

test('the detected position is not stored anywhere', async () => {
  const before = await env.pool.query("select count(*)::int n from information_schema.columns where table_schema='public' and column_name in ('user_lat','user_lon')");
  assert.equal(before.rows[0].n, 0);
  await post('/cities/locate', { lat: 12.3456789, lon: 98.7654321 });
  const dump = JSON.stringify((await env.pool.query('select * from listings')).rows) + JSON.stringify((await env.pool.query('select * from users')).rows);
  assert.ok(!dump.includes('12.3456789'));
});

// ---------------------------------------------------------------- where to apply
const places = (doc: string, q: string) => get(`/documents/${doc}/places?lang=ru&${q}`).then((r) => r.json);

test('places: no city chosen asks for a city', async () => {
  const r = await places('inn', '');
  assert.equal(r.needs_city, true);
  assert.deepEqual(r.institutions, []);
});

test('places: Moscow shows institutions for this document only', async () => {
  const r = await places('inn', 'city=moscow');
  const idsM = r.institutions.map((i: any) => i.id);
  assert.ok(idsM.includes('mfc_moscow') && idsM.includes('fns_moscow'));
  assert.ok(!idsM.includes('mmc_moscow'));            // it does not handle INN
  assert.ok(!idsM.includes('fx_fns_cao'));            // district-only, district not chosen
  assert.equal(r.needs_district, true);
  assert.equal(r.districts.length, 12);
});

test('places: choosing a district narrows the list', async () => {
  const caoFull = (await places('inn', 'city=moscow&district=cao')).institutions;
  const cao = caoFull.map((i: any) => i.id);
  assert.ok(cao.includes('fx_fns_cao') && !cao.includes('fx_fns_sao'));
  assert.equal(caoFull[0].status, 'verified');         // confirmed records come first
  const svao = (await places('inn', 'city=moscow&district=svao')).institutions.map((i: any) => i.id);
  assert.ok(svao.includes('fx_fns_sao') && !svao.includes('fx_fns_cao'));
});

test('places: an institution in another city is shown with its real address', async () => {
  const r = await places('inn', 'city=khimki');
  assert.equal(r.institutions.length, 1);
  const i = r.institutions[0];
  assert.equal(i.id, 'fx_center_for_khimki');
  assert.equal(i.other_city, true);
  assert.equal(i.city.name, 'Москва');
  assert.equal(i.address, 'ТЕСТОВАЯ улица, 1, Москва');
  assert.deepEqual(i.serves, [{ city: 'Химки', districts: null }]);
  assert.ok(i.hours && i.phone && i.site && i.booking_url && i.checked_at && i.sources.length);
});

test('places: a city without any confirmed address gets an empty list and the official search link', async () => {
  const none = await places('patent', 'city=kazan');
  assert.deepEqual(none.institutions, []);
  assert.equal(none.official_search, null);            // no link for this document
  const withLink = await places('fx_service', 'city=kazan');
  assert.deepEqual(withLink.institutions, []);
  assert.equal(withLink.official_search.url, 'https://example.test/search');   // the official search is offered instead
  assert.equal((await places('fx_service', 'city=moscow')).institutions.length, 1);
  const noAddr = await places('inn', 'city=kazan');
  assert.deepEqual(noAddr.institutions, []);
  assert.equal((await get('/documents/inn/places?city=atlantis')).status, 404);
});

test('places: embassies are filtered by citizenship', async () => {
  const all = (await places('lost_passport', 'city=moscow')).institutions.map((i: any) => i.id);
  assert.equal(all.length, 4);
  const tj = (await places('lost_passport', 'city=moscow&citizenship=TJ')).institutions.map((i: any) => i.id);
  assert.deepEqual(tj, ['emb_tj']);
});

test('institutions list supports service and mode filters', async () => {
  const r = (await get('/institutions?city=moscow&service=inn&lang=ru')).json;
  assert.ok(r.institutions.every((i: any) => i.services.some((s: any) => s.id === 'inn')));
  const online = (await get('/institutions?city=moscow&mode=online')).json;
  assert.ok(online.institutions.every((i: any) => ['online', 'both'].includes(i.mode)));
  assert.equal((await get('/institutions')).json.needs_city, true);
});

test('institutions/nearby: sorted by distance, flags institutions without confirmed coordinates', async () => {
  // Координаты в центре Москвы — рядом с fx_fns_cao/fx_fns_sao/fx_online_service (55.75, 37.62).
  const near = (await get('/institutions/nearby?lat=55.75&lon=37.62&lang=ru')).json;
  assert.ok(near.institutions.length > 1);
  for (let k = 1; k < near.institutions.length; k++) {
    assert.ok(near.institutions[k - 1].distance_km <= near.institutions[k].distance_km, 'отсортировано по расстоянию');
  }
  for (const i of near.institutions) {
    assert.equal(typeof i.distance_km, 'number');
    assert.equal(typeof i.distance_approx, 'boolean');
  }
  // Институт с подтверждёнными координатами (fx_fns_cao, 55.75/37.62) должен оказаться
  // ближе, чем пришлось бы считать по центру города — и без approx.
  const cao = near.institutions.find((i: any) => i.id === 'fx_fns_cao');
  assert.ok(cao);
  assert.equal(cao.distance_approx, false);
  assert.ok(cao.distance_km < 1);
  // Учреждение без подтверждённых координат (mmc_moscow) попадает в список по центру
  // города и честно помечено approx: true — это не точное расстояние до здания.
  const mmc = near.institutions.find((i: any) => i.id === 'mmc_moscow');
  assert.ok(mmc);
  assert.equal(mmc.distance_approx, true);
  // Чисто онлайн-канал (mode=online) — не физическое место, в «рядом со мной» не попадает,
  // даже если у него координаты есть.
  assert.ok(!near.institutions.some((i: any) => i.id === 'fx_online_service'));
  assert.ok(!near.institutions.some((i: any) => i.id === 'amina_app'));
  // Фильтр по услуге сохраняется.
  const onlyInn = (await get('/institutions/nearby?lat=55.75&lon=37.62&service=inn')).json;
  assert.ok(onlyInn.institutions.every((i: any) => i.services.some((s: any) => s.id === 'inn')));
  // Без lat/lon — ошибка валидации, а не пустой список с виду успешного ответа.
  assert.equal((await get('/institutions/nearby')).status, 400);
});

// ---------------------------------------------------------------- tips
test('tips: city filter shows local tips only for the chosen city', async () => {
  const general = (await get('/tips?lang=ru')).json.tips;
  assert.ok(general.every((t: any) => t.city === null));
  const msk = (await get('/tips?lang=ru&city=moscow')).json.tips;
  assert.ok(msk.some((t: any) => t.id === 'tip_moscow_commute'));
  assert.ok(!msk.some((t: any) => t.id === 'fx_tip_kazan'));
  const kzn = (await get('/tips?lang=ru&city=kazan')).json.tips;
  assert.ok(kzn.some((t: any) => t.id === 'fx_tip_kazan') && !kzn.some((t: any) => t.id === 'tip_moscow_commute'));
  const local = (await get('/tips?lang=ru&city=kazan&local=1')).json.tips;
  assert.deepEqual(local.map((t: any) => t.id), ['fx_tip_kazan']);
  assert.ok(msk.every((t: any) => t.updated_at));
  const found = (await get('/tips?lang=uz&q=pasport')).json.tips;
  assert.ok(Array.isArray(found));
});

test('coverage table lists scenarios and cities', async () => {
  const c = (await get('/coverage')).json;
  assert.equal(c.scenarios.length, 27);
  const states = new Set(c.scenarios.map((s: any) => s.state));
  assert.ok(states.has('partial') && states.has('demo'));
  assert.ok(c.cities.some((x: any) => x.id === 'moscow'));
  assert.ok(c.documents.find((d: any) => d.id === 'inn').cells.moscow);
});

// ---------------------------------------------------------------- accounts and ads
test('ads: full path — publish, see from another session, respond, moderate', async () => {
  const author = await user('author@test.local');
  const other = await user('reader@test.local');
  const modTok = await (async () => {
    const { ensureModerator } = await import('../src/auth.js');
    await ensureModerator(env.pool, 'mod@test.local', 'modpassword1');
    return (await post('/auth/login', { email: 'mod@test.local', password: 'modpassword1' })).json.token as string;
  })();

  // posting needs an account
  assert.equal((await post('/listings', {})).status, 401);

  // housing ad is published at once
  const h = await post('/listings', { category: 'housing', title: 'Комната у метро', body: 'Сдаётся комната, рядом метро, без посредников.', lang: 'ru', city_id: 'moscow', price: '25 000 в месяц', duration_days: 14 }, author);
  assert.equal(h.status, 201);
  assert.equal(h.json.status, 'published');

  // a vacancy waits for the moderator
  const w = await post('/listings', { category: 'work', title: 'Требуется упаковщик', body: 'Склад, сменный график, оформление по договору.', lang: 'ru', city_id: 'moscow', extra: { employer: 'ООО Тест', pay: '70 000', schedule: '2/2', terms: 'Трудовой договор' } }, author);
  assert.equal(w.json.status, 'pending');
  assert.equal((await get('/listings?category=work')).json.listings.length, 0);   // not visible yet
  assert.equal((await get(`/listings/${w.json.id}`)).status, 404);

  // anonymous visitor and another account both see the housing ad
  const anon = (await get('/listings?city=moscow')).json.listings;
  assert.equal(anon.length, 1);
  assert.equal(anon[0].title, 'Комната у метро');
  assert.ok(!JSON.stringify(anon).includes('author@test.local'), 'author contacts must not be published');
  assert.ok(!('author_id' in anon[0]));
  const seenByOther = await get(`/listings/${h.json.id}`, other);
  assert.equal(seenByOther.status, 200);
  assert.equal(seenByOther.json.lang, 'ru');

  // respond: account required, not to own ad
  assert.equal((await post(`/listings/${h.json.id}/respond`, { message: 'Здравствуйте' })).status, 401);
  assert.equal((await post(`/listings/${h.json.id}/respond`, { message: 'Здравствуйте' }, author)).status, 403);
  const resp = await post(`/listings/${h.json.id}/respond`, { message: 'Здравствуйте, комната свободна?', contact: 'Telegram: @reader_test' }, other);
  assert.equal(resp.status, 201);
  const mine = (await get('/my/listings', author)).json.listings.find((l: any) => l.id === h.json.id);
  assert.equal(mine.response_count, 1);
  const inbox = (await get(`/my/listings/${h.json.id}/responses`, author)).json.responses;
  assert.equal(inbox[0].message, 'Здравствуйте, комната свободна?');
  assert.equal(inbox[0].contact, 'Telegram: @reader_test');
  assert.equal((await get(`/my/listings/${h.json.id}/responses`, other)).status, 404);   // only the author reads responses

  // moderation: normal users have no access
  assert.equal((await get('/mod/queue', other)).status, 403);
  assert.equal((await get('/mod/queue')).status, 401);
  const q = (await get('/mod/queue?kind=pending', modTok)).json;
  assert.equal(q.listings.length, 1);
  assert.equal(q.listings[0].author_email, 'author@test.local');
  assert.equal(q.counts.pending, 1);
  assert.equal((await post(`/mod/listings/${w.json.id}/reject`, {}, modTok)).status, 400);   // reason is required
  assert.equal((await post(`/mod/listings/${w.json.id}/approve`, {}, modTok)).status, 200);
  assert.equal((await get('/listings?category=work')).json.listings.length, 1);
  const vac = (await get(`/listings/${w.json.id}`)).json;
  assert.equal(vac.extra.employer, 'ООО Тест');
  assert.ok(vac.expires_at);

  // moderator hides the housing ad; it disappears for everyone, the author sees the state
  assert.equal((await post(`/mod/listings/${h.json.id}/hide`, { reason: 'Подозрительная цена' }, modTok)).status, 200);
  assert.equal((await get(`/listings/${h.json.id}`, other)).status, 404);
  assert.equal((await get(`/listings/${h.json.id}`, author)).json.status, 'hidden');
  assert.equal((await post(`/listings/${h.json.id}/respond`, { message: 'Ещё актуально?' }, other)).status, 404);
  assert.equal((await post(`/mod/listings/${h.json.id}/restore`, {}, modTok)).status, 200);
  assert.equal((await get(`/listings/${h.json.id}`)).status, 200);
});

test('ads: rules reject forbidden offers, passport data and contact details', async () => {
  const t = await user('rules@test.local');
  const base = { category: 'services', lang: 'ru', city_id: 'moscow', duration_days: 7 };
  const bad = async (title: string, body: string, code: string) => {
    const r = await post('/listings', { ...base, title, body }, t);
    assert.equal(r.status, 422, `${title} / ${body}`);
    assert.equal(r.json.code, code, `${title} / ${body}`);
  };
  await bad('Помогу с документами', 'Продаю патент без экзамена, быстро.', 'forbidden');
  await bad('Регистрация', 'Фиктивная регистрация для патента, недорого.', 'forbidden');
  await bad('Регистрация', 'Оформлю регистрацию без проживания за деньги.', 'forbidden');
  await bad('Работа', 'Хорошая работа, нужно внести предоплату за трудоустройство.', 'forbidden');
  await bad('Hujjat', 'Hujjatlar sotiladi, soxta patent bor.', 'forbidden');
  await bad('Документы', 'Документы сатам, тез.', 'forbidden');
  await bad('Услуги переводчика', 'Перевожу документы. Мой паспорт 4510 123456 приложен.', 'passport');
  await bad('Услуги переводчика', 'Паспорт AB1234567, перевод и заверение.', 'passport');
  await bad('Услуги электрика', 'Звоните +7 (999) 123-45-67 в любое время.', 'contact');
  await bad('Услуги электрика', 'Пишите на ivan@example.com по любому вопросу.', 'contact');
  await bad('Услуги электрика', 'Пишите в телеграм t.me/ivan_master, отвечу.', 'contact');
  // legitimate wording is not blocked
  const ok = await post('/listings', { ...base, title: 'Помощь с переводом', body: 'Перевожу документы на русский. Регистрация по месту проживания у вас должна быть настоящей.' }, t);
  assert.equal(ok.status, 201);
  const ok2 = await post('/listings', { ...base, category: 'housing', title: 'Комната с регистрацией', body: 'Комната, собственник предоставит регистрацию при реальном проживании.' }, t);
  assert.equal(ok2.status, 201);
  // work ads need an employer and pay
  const noEmployer = await post('/listings', { ...base, category: 'work', title: 'Работа курьером', body: 'Нужен курьер на полный день.' }, t);
  assert.equal(noEmployer.status, 400);
  // unknown city / short title
  assert.equal((await post('/listings', { ...base, title: 'Ок', body: 'Достаточно длинное описание.', city_id: 'atlantis' }, t)).status, 400);
});

test('ads: edit, withdraw, report, auto-hide, expiry, search and filters', async () => {
  const a = await user('owner@test.local');
  const readers = [await user('r1@test.local'), await user('r2@test.local'), await user('r3@test.local')];
  const mk = (title: string, o: object = {}) => post('/listings', { category: 'market', title, body: 'Продаю велосипед в хорошем состоянии.', lang: 'ru', city_id: 'kazan', price: '5000', duration_days: 14, ...o }, a);
  const l1 = (await mk('Велосипед горный')).json.id;
  const l2 = (await mk('Стол письменный', { lang: 'uz', city_id: 'spb' })).json.id;
  // filters and search
  assert.deepEqual((await get('/listings?city=kazan&q=' + encodeURIComponent('велосипед'))).json.listings.map((x: any) => x.id), [l1]);
  assert.deepEqual((await get('/listings?category=market&lang=uz')).json.listings.map((x: any) => x.id), [l2]);
  assert.equal((await get('/listings?category=market&city=kazan&q=nothing')).json.listings.length, 0);
  // edit by the author only
  assert.equal((await env.call('PATCH', `/listings/${l1}`, { category: 'market', title: 'Велосипед шоссейный', body: 'Продаю велосипед в отличном состоянии.', lang: 'ru', city_id: 'kazan' }, readers[0])).status, 404);
  const ed = await env.call('PATCH', `/listings/${l1}`, { category: 'market', title: 'Велосипед шоссейный', body: 'Продаю велосипед в отличном состоянии.', lang: 'ru', city_id: 'kazan' }, a);
  assert.equal(ed.status, 200);
  assert.equal((await get(`/listings/${l1}`)).json.title, 'Велосипед шоссейный');
  // an edit that breaks the rules is refused
  const badEd = await env.call('PATCH', `/listings/${l1}`, { category: 'market', title: 'Велосипед шоссейный', body: 'Звоните 89991234567 пожалуйста.', lang: 'ru', city_id: 'kazan' }, a);
  assert.equal(badEd.status, 422);
  // reports; three different people hide the ad automatically
  for (const t of readers) assert.equal((await post(`/listings/${l2}/report`, { reason: 'Похоже на обман' }, t)).status, 201);
  assert.equal((await get(`/listings/${l2}`)).status, 404);
  assert.equal((await get(`/listings/${l2}`, a)).json.status, 'hidden');
  // repeated report by the same person does not multiply
  await post(`/listings/${l1}/report`, { reason: 'Тест' }, readers[0]);
  await post(`/listings/${l1}/report`, { reason: 'Тест' }, readers[0]);
  const cnt = await env.pool.query("select count(*)::int n from reports where listing_id = $1", [l1]);
  assert.equal(cnt.rows[0].n, 1);
  // withdraw
  assert.equal((await post(`/listings/${l1}/withdraw`, {}, readers[0])).status, 404);
  assert.equal((await post(`/listings/${l1}/withdraw`, {}, a)).status, 200);
  assert.equal((await get(`/listings/${l1}`)).status, 404);
  // expiry
  const l3 = (await mk('Лампа настольная')).json.id;
  assert.equal((await get(`/listings/${l3}`)).status, 200);
  await env.pool.query("update listings set expires_at = now() - interval '1 hour' where id = $1", [l3]);
  assert.equal((await get(`/listings/${l3}`)).status, 404);
  assert.equal((await get('/listings?q=' + encodeURIComponent('лампа'))).json.listings.length, 0);
  assert.equal((await get('/my/listings', a)).json.listings.find((x: any) => x.id === l3).status, 'expired');
});

test('accounts: registration, login, wrong password, logout', async () => {
  assert.equal((await post('/auth/register', { email: 'weak@test.local', password: 'short' })).json.code, 'weak_password');
  const t = await user('login@test.local');
  assert.equal((await post('/auth/register', { email: 'LOGIN@test.local', password: 'password123' })).json.code, 'email_taken');
  assert.equal((await post('/auth/login', { email: 'login@test.local', password: 'nope-nope' })).json.code, 'invalid_credentials');
  const ok = await post('/auth/login', { email: 'login@test.local', password: 'password123' });
  assert.equal(ok.status, 200);
  assert.equal((await get('/me', ok.json.token)).json.user.role, 'user');
  await post('/auth/logout', {}, t);
  assert.equal((await get('/me', t)).status, 401);
});

// ---------------------------------------------------------------- content updates
test('re-importing content keeps listings that point at cities (content can be updated after launch)', async () => {
  const author = await user('reimport@example.com');
  const made = await post('/listings', { category: 'housing', title: 'Комната для проверки импорта', body: 'Сдаётся комната, рядом метро, без посредников.', lang: 'ru', city_id: 'moscow', price: '25 000 в месяц', duration_days: 14 }, author);
  assert.equal(made.status, 201);
  const { importContent, loadContent } = await import('../src/content.js');
  const { config } = await import('../src/config.js');
  await importContent(env.pool, loadContent(config.contentDirs));   // раньше падал: delete from cities нарушал listings_city_id_fkey
  const left = await env.pool.query('select count(*)::int as n from listings where title = $1', ['Комната для проверки импорта']);
  assert.equal(left.rows[0].n, 1);
  assert.equal((await get('/cities?q=Москва')).json.cities[0].id, 'moscow');
});
