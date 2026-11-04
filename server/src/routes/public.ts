import { Router } from 'express';
import { z } from 'zod';
import type { Pool } from '../db.js';
import { config } from '../config.js';
import { langOf, pick } from '../util.js';
import { evaluateChecklist, type DocRow } from '../checklist.js';
import { matchInstitutions, type InstRow } from '../places.js';
import { haversineKm } from '../geo.js';
import { searchCities, locate, norm, type CityRow } from '../cities.js';
import { computeCoverage } from '../coverage.js';

const visible = (col = 'status') => `(${col} = 'verified' or (${col} = 'demo' and $INCLUDE))`;
const vis = (col = 'status') => visible(col).replace('$INCLUDE', config.includeDemo ? 'true' : 'false');

export function publicRoutes(pool: Pool): Router {
  const r = Router();

  const allCities = async (): Promise<CityRow[]> => (await pool.query('select * from cities')).rows;
  const cityOut = (c: CityRow) => ({ id: c.id, name: c.name, region: c.region, label: `${c.name}, ${c.region}`, districts: c.districts ?? [] });

  r.get('/health', async (_req, res) => {
    await pool.query('select 1');
    res.json({ ok: true, includeDemo: config.includeDemo });
  });

  // ---- language packs: texts live in the database, not in the interface code
  r.get('/i18n/:lang', async (req, res) => {
    const lang = langOf(req.params.lang);
    const rows = (await pool.query("select lang, key, value from translations where lang in ('ru', $1)", [lang])).rows;
    const strings: Record<string, string> = {};
    for (const x of rows) if (x.lang === 'ru') strings[x.key] = x.value;
    const missing: string[] = [];
    if (lang !== 'ru') {
      const own = new Set<string>();
      for (const x of rows) if (x.lang === lang) { strings[x.key] = x.value; own.add(x.key); }
      for (const k of Object.keys(strings)) if (!own.has(k)) missing.push(k);
    }
    res.json({ lang, strings, missing });
  });

  r.get('/meta', async (req, res) => {
    const lang = langOf(req.query.lang);
    const [languages, cits, sits, ref] = await Promise.all([
      pool.query('select code, native from languages order by sort'),
      pool.query('select id, grp, names from citizenships'),
      pool.query('select id, names from situations order by sort'),
      pool.query("select value from settings where key = 'reference'"),
    ]);
    res.json({
      languages: languages.rows,
      citizenships: cits.rows.map((c) => ({ id: c.id, group: c.grp, name: pick(c.names, lang) })),
      situations: sits.rows.map((s) => ({ id: s.id, name: pick(s.names, lang) })),
      reference: ref.rows[0]?.value ?? {},
      includeDemo: config.includeDemo,
    });
  });

  // ---- cities
  r.get('/cities', async (req, res) => {
    const q = String(req.query.q ?? '');
    const all = await allCities();
    res.json({ cities: searchCities(all, q).map(cityOut) });
  });

  r.get('/cities/:id', async (req, res) => {
    const c = (await allCities()).find((x) => x.id === req.params.id);
    if (!c) return res.status(404).json({ code: 'not_found' });
    res.json(cityOut(c));
  });

  // The position arrives in the request body, is used for one calculation and is never stored or logged.
  r.post('/cities/locate', async (req, res) => {
    const body = z.object({ lat: z.number().min(-90).max(90), lon: z.number().min(-180).max(180) }).safeParse(req.body);
    if (!body.success) return res.status(400).json({ code: 'validation' });
    const result = locate(await allCities(), body.data.lat, body.data.lon, config.locateMaxKm, config.locateOutsideKm);
    if (result.status === 'candidate') return res.json({ status: 'candidate', city: cityOut(result.city), distanceKm: result.distanceKm });
    res.json({ status: result.status });
  });

  // ---- documents
  const docOut = (row: any, lang: ReturnType<typeof langOf>, full: boolean) => {
    const base = {
      id: row.id, necessity: row.necessity, status: row.status, checked_at: row.checked_at, situations: row.situations,
      title: pick(row.title, lang), summary: pick(row.summary, lang),
    };
    if (!full) return base;
    const own = row.details?.[lang];
    return {
      ...base,
      details: own ?? row.details?.ru ?? {},
      details_fallback: lang !== 'ru' && !own,
      // Terms and prices are shown only for records confirmed by a source.
      deadline: row.status === 'verified' ? row.deadline : null,
      cost: row.status === 'verified' ? row.cost : null,
      sources: row.sources,
      where_kind: row.where_kind,
      where_note: row.where_note,
    };
  };

  r.get('/documents', async (req, res) => {
    const lang = langOf(req.query.lang);
    const rows = (await pool.query(`select * from documents where ${vis()} order by sort`)).rows;
    const sit = String(req.query.situation ?? '');
    const q = norm(String(req.query.q ?? ''));
    let out = rows.filter((d) => !sit || d.situations.includes(sit));
    if (q) {
      out = out.filter((d) => [pick(d.title, lang), d.title.ru, pick(d.summary, lang)].some((s) => norm(s).includes(q)));
    }
    res.json({ documents: out.map((d) => docOut(d, lang, false)) });
  });

  r.get('/documents/:id', async (req, res) => {
    const lang = langOf(req.query.lang);
    const row = (await pool.query(`select * from documents where id = $1 and ${vis()}`, [req.params.id])).rows[0];
    if (!row) return res.status(404).json({ code: 'not_found' });
    res.json(docOut(row, lang, true));
  });

  // ---- personal checklist (no registration needed)
  r.post('/checklist', async (req, res) => {
    const body = z.object({
      citizenship: z.string().optional(), purpose: z.string().optional(), stage: z.string().optional(),
      flags: z.record(z.boolean()).optional(), lang: z.string().optional(),
    }).safeParse(req.body);
    if (!body.success) return res.status(400).json({ code: 'validation' });
    const lang = langOf(body.data.lang);
    const docs = (await pool.query('select * from documents order by sort')).rows as (DocRow & any)[];
    const cits = (await pool.query('select id, grp from citizenships')).rows;
    const result = evaluateChecklist(docs, cits, body.data, config.includeDemo);
    const byId = new Map(docs.map((d) => [d.id, d]));
    const ref = (await pool.query("select value from settings where key = 'reference'")).rows[0]?.value ?? {};
    res.json({
      items: result.items.map((i) => ({ ...docOut(byId.get(i.id), lang, false), necessity: i.necessity })),
      clarify: result.clarify.map((c) => (c.type === 'depends_on_citizenship' ? { ...c, title: pick(byId.get(c.docId).title, lang) } : c)),
      where_to_check: ref.where_to_check ?? [],
      includes_demo: result.items.some((i) => i.status === 'demo'),
    });
  });

  // ---- institutions
  const instOut = (i: any, lang: ReturnType<typeof langOf>, cityId: string, cities: Map<string, CityRow>, docs: Map<string, any>) => {
    const own = cities.get(i.city_id)!;
    const serves = (i.serves as any[]).map((s) => 'scope' in s
      ? { scope: 'country' }
      : { city: cities.get(s.city)?.name ?? s.city, districts: s.districts ? s.districts.map((d: string) => cities.get(s.city)?.districts?.find((x) => x.id === d)?.name ?? d) : null });
    return {
      id: i.id, name: pick(i.name, lang), status: i.status, checked_at: i.checked_at, mode: i.mode,
      city: { id: own.id, name: own.name, region: own.region },
      other_city: i.city_id !== cityId,
      address: i.address, map: { query: i.map_query, lat: i.lat, lon: i.lon },
      hours: i.hours, phone: i.phone, site: i.site, booking_url: i.booking_url,
      services: i.services.map((s: string) => ({ id: s, title: pick(docs.get(s)?.title, lang) || s })),
      serves, citizenships: i.citizenships, sources: i.sources, note: i.note,
    };
  };

  const loadPlaces = async (opts: { city: string; district?: string; citizenship?: string; service?: string; mode?: string; lang: ReturnType<typeof langOf> }) => {
    const cities = await allCities();
    const cityMap = new Map(cities.map((c) => [c.id, c]));
    const docs = new Map((await pool.query('select id, title from documents')).rows.map((d) => [d.id, d]));
    const insts = (await pool.query(`select * from institutions where ${vis()}`)).rows as (InstRow & any)[];
    const { matched, needsDistrict } = matchInstitutions(insts, {
      cityId: opts.city, districtId: opts.district, citizenship: opts.citizenship, service: opts.service, mode: opts.mode, includeDemo: config.includeDemo,
    });
    matched.sort((a, b) => Number(b.status === 'verified') - Number(a.status === 'verified') || (a.city_id === opts.city ? 0 : 1) - (b.city_id === opts.city ? 0 : 1));
    return {
      city: cityMap.get(opts.city) ?? null,
      institutions: matched.map((i) => instOut(i, opts.lang, opts.city, cityMap, docs)),
      needs_district: needsDistrict,
    };
  };

  r.get('/documents/:id/places', async (req, res) => {
    const lang = langOf(req.query.lang);
    const doc = (await pool.query(`select * from documents where id = $1 and ${vis()}`, [req.params.id])).rows[0];
    if (!doc) return res.status(404).json({ code: 'not_found' });
    const cityId = String(req.query.city ?? '');
    const head = { document: docOut(doc, lang, false), where_kind: doc.where_kind, where_note: doc.where_note, official_search: doc.official_search, sources: doc.sources };
    if (!cityId) return res.json({ ...head, needs_city: true, city: null, institutions: [], needs_district: false, districts: [] });
    const places = await loadPlaces({
      city: cityId, district: String(req.query.district ?? '') || undefined, citizenship: String(req.query.citizenship ?? '') || undefined,
      service: doc.id, lang,
    });
    if (!places.city) return res.status(404).json({ code: 'city_not_found' });
    res.json({
      ...head, needs_city: false, city: cityOut(places.city), institutions: places.institutions,
      needs_district: places.needs_district, districts: places.city.districts ?? [],
    });
  });

  r.get('/institutions', async (req, res) => {
    const lang = langOf(req.query.lang);
    const cityId = String(req.query.city ?? '');
    if (!cityId) return res.json({ needs_city: true, city: null, institutions: [], needs_district: false, districts: [], services: [] });
    const places = await loadPlaces({
      city: cityId, district: String(req.query.district ?? '') || undefined, citizenship: String(req.query.citizenship ?? '') || undefined,
      service: String(req.query.service ?? '') || undefined, mode: String(req.query.mode ?? '') || undefined, lang,
    });
    if (!places.city) return res.status(404).json({ code: 'city_not_found' });
    const docs = (await pool.query(`select id, title, official_search, sources, where_kind from documents where ${vis()} and where_kind = 'institutions' order by sort`)).rows;
    res.json({
      needs_city: false, city: cityOut(places.city), institutions: places.institutions, needs_district: places.needs_district,
      districts: places.city.districts ?? [],
      services: docs.map((d) => ({ id: d.id, title: pick(d.title, lang), official_search: d.official_search })),
    });
  });

  // ---- ближайшие учреждения по геопозиции (без привязки к выбранному городу:
  // рядом с границей города/области ближе может быть учреждение другого города)
  r.get('/institutions/nearby', async (req, res) => {
    const lang = langOf(req.query.lang);
    const lat = Number(req.query.lat);
    const lon = Number(req.query.lon);
    if (!Number.isFinite(lat) || !Number.isFinite(lon)) return res.status(400).json({ code: 'validation' });
    const service = String(req.query.service ?? '') || undefined;
    const citizenship = String(req.query.citizenship ?? '') || undefined;
    const cities = await allCities();
    const cityMap = new Map(cities.map((c) => [c.id, c]));
    const docs = new Map((await pool.query('select id, title from documents')).rows.map((d) => [d.id, d]));
    const insts = (await pool.query(`select * from institutions where ${vis()}`)).rows as (InstRow & any)[];
    const withDistance = insts
      // «Рядом со мной» — про физические места, куда можно дойти. Чисто онлайн-канал
      // (например, приложение «Амина») тут не при чём, даже если он привязан к городу.
      .filter((i) => i.mode !== 'online')
      .filter((i) => !service || i.services.includes(service))
      .filter((i) => !citizenship || !i.citizenships || i.citizenships.includes(citizenship))
      .map((i) => {
        // Точное расположение учреждения, если оно подтверждено (lat/lon заполнены при проверке
        // адреса); иначе — только центр его города, это грубее и помечается approx: true.
        const own = cityMap.get(i.city_id);
        const approx = i.lat == null || i.lon == null;
        const plat = approx ? own?.lat : i.lat;
        const plon = approx ? own?.lon : i.lon;
        const distanceKm = plat != null && plon != null ? haversineKm(lat, lon, plat, plon) : null;
        return { i, own, approx, distanceKm };
      })
      .filter((x): x is typeof x & { distanceKm: number } => x.distanceKm != null)
      .sort((a, b) => a.distanceKm - b.distanceKm)
      .slice(0, 15);
    res.json({
      institutions: withDistance.map((x) => ({
        ...instOut(x.i, lang, x.i.city_id, cityMap, docs),
        distance_km: Math.round(x.distanceKm * 10) / 10,
        distance_approx: x.approx,
      })),
    });
  });

  // ---- tips
  r.get('/tips', async (req, res) => {
    const lang = langOf(req.query.lang);
    const city = String(req.query.city ?? '');
    const topic = String(req.query.topic ?? '');
    const q = norm(String(req.query.q ?? ''));
    const local = req.query.local === '1';
    const rows = (await pool.query(
      `select t.*, c.name as city_name, c.region as city_region from tips t left join cities c on c.id = t.city_id where ${vis('t.status')} order by t.updated_at desc, t.id`)).rows;
    const out = rows
      .filter((t) => !t.city_id || t.city_id === city)               // local tips only for the chosen city
      .filter((t) => !local || t.city_id === city)
      .filter((t) => !topic || t.topic === topic)
      .filter((t) => !q || norm(pick(t.title, lang) + ' ' + pick(t.body, lang)).includes(q))
      .map((t) => ({
        id: t.id, topic: t.topic, kind: t.kind, status: t.status, updated_at: t.updated_at,
        title: pick(t.title, lang), body: pick(t.body, lang), source: t.source,
        city: t.city_id ? { id: t.city_id, name: t.city_name, region: t.city_region } : null,
      }));
    res.json({ tips: out });
  });

  r.get('/coverage', async (_req, res) => {
    res.json(await computeCoverage(pool));
  });

  return r;
}
