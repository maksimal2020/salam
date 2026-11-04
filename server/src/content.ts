import fs from 'node:fs';
import path from 'node:path';
import type { Pool } from './db.js';

export const LANGS = ['ru', 'tg', 'uz', 'ky', 'kk'] as const;
export type Lang = (typeof LANGS)[number];

type Json = any;

export interface Content {
  i18n: Record<string, Record<string, string>>;
  reference: Json;
  situations: Json[];
  cities: Json[];
  documents: Json[];
  institutions: Json[];
  tips: Json[];
  moderation: Json;
}

function readJson(file: string): Json | undefined {
  if (!fs.existsSync(file)) return undefined;
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function mergeById(base: Json[], extra: Json[] | undefined): Json[] {
  if (!extra) return base;
  const map = new Map(base.map((x) => [x.id, x]));
  for (const x of extra) map.set(x.id, x);
  return [...map.values()];
}

/** Later directories add to and override earlier ones (by id / by key). */
export function loadContent(dirs: string[]): Content {
  const c: Content = { i18n: {}, reference: {}, situations: [], cities: [], documents: [], institutions: [], tips: [], moderation: {} };
  for (const dir of dirs) {
    const i18nDir = path.join(dir, 'i18n');
    if (fs.existsSync(i18nDir)) {
      for (const f of fs.readdirSync(i18nDir).filter((x) => x.endsWith('.json'))) {
        const lang = f.replace('.json', '');
        c.i18n[lang] = { ...(c.i18n[lang] ?? {}), ...readJson(path.join(i18nDir, f)) };
      }
    }
    const ref = readJson(path.join(dir, 'reference.json'));
    if (ref) {
      c.reference = {
        ...c.reference,
        ...ref,
        citizenships: mergeById(c.reference.citizenships ?? [], ref.citizenships),
      };
    }
    c.situations = mergeById(c.situations, readJson(path.join(dir, 'situations.json')));
    c.cities = mergeById(c.cities, readJson(path.join(dir, 'cities.json')));
    c.documents = mergeById(c.documents, readJson(path.join(dir, 'catalog', 'documents.json')));
    c.institutions = mergeById(c.institutions, readJson(path.join(dir, 'institutions.json')));
    c.tips = mergeById(c.tips, readJson(path.join(dir, 'tips.json')));
    const mod = readJson(path.join(dir, 'moderation.json'));
    if (mod) c.moderation = { ...c.moderation, ...mod };
  }
  return c;
}

const CYRILLIC_LANGS = ['tg', 'ky', 'kk'];
const CYR = /[А-Яа-яЁёӘәҒғҚқҢңӨөҰұҮүҺһІіӢӣӮӯҶҷҲҳ]/;
const LAT = /[A-Za-z]/;

export interface Report {
  errors: string[];
  warnings: string[];
}

export function validateContent(c: Content): Report {
  const errors: string[] = [];
  const warnings: string[] = [];
  const ru = c.i18n.ru ?? {};

  for (const lang of LANGS) {
    const d = c.i18n[lang];
    if (!d) { errors.push(`i18n/${lang}.json отсутствует`); continue; }
    for (const k of Object.keys(ru)) if (!(k in d)) errors.push(`i18n/${lang}: нет ключа ${k}`);
    for (const k of Object.keys(d)) if (!(k in ru)) errors.push(`i18n/${lang}: лишний ключ ${k}`);
    // placeholders must match the Russian master
    for (const [k, v] of Object.entries(d)) {
      const a = (ru[k]?.match(/\{\w+\}/g) ?? []).sort().join();
      const b = (v.match(/\{\w+\}/g) ?? []).sort().join();
      if (ru[k] !== undefined && a !== b) errors.push(`i18n/${lang}: ключ ${k} — не совпадают подстановки (${a} ≠ ${b})`);
    }
    if (CYRILLIC_LANGS.includes(lang)) {
      for (const [k, v] of Object.entries(d)) {
        for (const w of v.match(/[A-Za-zА-Яа-яЁёӘәҒғҚқҢңӨөҰұҮүҺһІіӢӣӮӯҶҷҲҳ]+/g) ?? []) {
          if (CYR.test(w) && LAT.test(w)) errors.push(`i18n/${lang}: ключ ${k} — смешение алфавитов в слове «${w}»`);
        }
      }
    }
  }

  const cityIds = new Set<string>();
  for (const city of c.cities) {
    if (cityIds.has(city.id)) errors.push(`город ${city.id} повторяется`);
    cityIds.add(city.id);
    if (!city.name || !city.region) errors.push(`город ${city.id}: нужны name и region`);
    if (typeof city.lat !== 'number' || typeof city.lon !== 'number') errors.push(`город ${city.id}: нужны lat/lon`);
  }

  const topics = new Set(Object.keys(ru).filter((k) => k.startsWith('topic.')).map((k) => k.slice(6)));
  const docIds = new Set(c.documents.map((d) => d.id));
  const situationIds = new Set(c.situations.map((s) => s.id));
  const hasSrc = (x: Json) => Array.isArray(x.sources) && x.sources.some((s: Json) => s && typeof s.url === 'string' && s.url.startsWith('http'));

  for (const d of c.documents) {
    if (!['verified', 'demo', 'draft'].includes(d.status)) errors.push(`документ ${d.id}: неверный status`);
    for (const s of d.situations ?? []) if (!situationIds.has(s)) errors.push(`документ ${d.id}: неизвестная ситуация ${s}`);
    for (const lang of LANGS) {
      if (!d.title?.[lang]) errors.push(`документ ${d.id}: нет title.${lang}`);
      if (!d.summary?.[lang]) errors.push(`документ ${d.id}: нет summary.${lang}`);
      if (!d.details?.[lang] && lang !== 'ru') warnings.push(`документ ${d.id}: подробности на ${lang} не переведены (показывается русский)`);
    }
    if (!d.details?.ru) errors.push(`документ ${d.id}: нет details.ru`);
    if (d.status === 'verified') {
      if (!d.checked_at) errors.push(`документ ${d.id}: verified требует checked_at`);
      if (!hasSrc(d)) errors.push(`документ ${d.id}: verified требует официальную ссылку в sources`);
    }
    if ((d.deadline || d.cost) && d.status !== 'verified') {
      errors.push(`документ ${d.id}: сроки и стоимость допустимы только у verified-записей`);
    }
  }

  const districtsByCity = new Map(c.cities.map((x) => [x.id, new Set<string>((x.districts ?? []).map((d: Json) => d.id))]));
  for (const i of c.institutions) {
    if (!cityIds.has(i.city_id)) errors.push(`учреждение ${i.id}: неизвестный город ${i.city_id}`);
    for (const s of i.services ?? []) if (!docIds.has(s)) errors.push(`учреждение ${i.id}: неизвестная услуга ${s}`);
    if (!Array.isArray(i.serves) || !i.serves.length) errors.push(`учреждение ${i.id}: пустое serves`);
    for (const sv of i.serves ?? []) {
      if (sv.scope === 'country') continue;
      if (!cityIds.has(sv.city)) { errors.push(`учреждение ${i.id}: serves ссылается на неизвестный город ${sv.city}`); continue; }
      for (const dist of sv.districts ?? []) if (!districtsByCity.get(sv.city)?.has(dist)) errors.push(`учреждение ${i.id}: неизвестный район ${dist} города ${sv.city}`);
    }
    if (i.status === 'verified') {
      if (!i.checked_at) errors.push(`учреждение ${i.id}: verified требует checked_at`);
      if (!hasSrc(i)) errors.push(`учреждение ${i.id}: verified требует официальный источник`);
      if (!i.address && !(i.mode === 'online' && i.site)) errors.push(`учреждение ${i.id}: verified требует адрес`);
    }
  }

  for (const t of c.tips) {
    if (!topics.has(t.topic)) errors.push(`совет ${t.id}: неизвестная тема ${t.topic}`);
    if (t.city_id && !cityIds.has(t.city_id)) errors.push(`совет ${t.id}: неизвестный город ${t.city_id}`);
    for (const lang of LANGS) if (!t.title?.[lang] || !t.body?.[lang]) errors.push(`совет ${t.id}: нет перевода ${lang}`);
    if (!t.updated_at) errors.push(`совет ${t.id}: нужна updated_at`);
  }

  for (const g of c.moderation.forbidden ?? []) for (const p of g.patterns) {
    try { new RegExp(p.replace(/\\w/g, '[\\p{L}\\p{N}_]'), 'iu'); } catch (e) { errors.push(`moderation ${g.id}: плохое выражение ${p}`); }
  }
  for (const code of ['languages', 'citizenships', 'purposes', 'stages', 'flags']) if (!c.reference[code]) errors.push(`reference.json: нет ${code}`);
  return { errors, warnings };
}

export async function importContent(pool: Pool, c: Content): Promise<{ counts: Record<string, number>; warnings: string[] }> {
  const rep = validateContent(c);
  if (rep.errors.length) throw new Error('Контент не прошёл проверку:\n - ' + rep.errors.join('\n - '));
  const client = await pool.connect();
  try {
    await client.query('begin');
    // Города не очищаются целиком: на них ссылаются объявления, поэтому ниже они обновляются на месте.
    for (const t of ['tips', 'institutions', 'documents', 'situations', 'citizenships', 'translations', 'languages', 'settings']) {
      await client.query(`delete from ${t}`);
    }
    for (const [i, l] of c.reference.languages.entries()) {
      await client.query('insert into languages (code, native, sort) values ($1,$2,$3)', [l.code, l.native, i]);
    }
    for (const [lang, d] of Object.entries(c.i18n)) {
      for (const [k, v] of Object.entries(d)) await client.query('insert into translations (lang, key, value) values ($1,$2,$3)', [lang, k, v]);
    }
    for (const x of c.reference.citizenships) {
      await client.query('insert into citizenships (id, grp, names, status, note) values ($1,$2,$3,$4,$5)', [x.id, x.group, x.names, x.status ?? 'demo', x.note ?? null]);
    }
    for (const s of c.situations) await client.query('insert into situations (id, sort, names) values ($1,$2,$3)', [s.id, s.sort ?? 0, s.names]);
    for (const x of c.cities) {
      await client.query(
        `insert into cities (id,name,region,lat,lon,aliases,pilot,districts) values ($1,$2,$3,$4,$5,$6,$7,$8)
         on conflict (id) do update set name=excluded.name, region=excluded.region, lat=excluded.lat, lon=excluded.lon,
           aliases=excluded.aliases, pilot=excluded.pilot, districts=excluded.districts`,
        [x.id, x.name, x.region, x.lat, x.lon, x.aliases ?? [], !!x.pilot, x.districts ? JSON.stringify(x.districts) : null]);
    }
    // Города, которых больше нет в контенте, удаляются, но только если на них нет объявлений: иначе понятная ошибка вместо потери данных.
    const gone = await client.query('select id from cities where id <> all($1::text[])', [c.cities.map((x) => x.id)]);
    for (const row of gone.rows) {
      const used = await client.query('select 1 from listings where city_id = $1 limit 1', [row.id]);
      if (used.rowCount) throw new Error(`Город ${row.id} убран из контента, но на него есть объявления. Верните его в content/cities.json или перенесите объявления.`);
      await client.query('delete from cities where id = $1', [row.id]);
    }
    for (const d of c.documents) {
      await client.query(
        `insert into documents (id,sort,situations,necessity,status,checked_at,rules,title,summary,details,deadline,cost,sources,where_kind,where_note,official_search)
         values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16)`,
        [d.id, d.sort ?? 0, d.situations ?? [], d.necessity, d.status, d.checked_at ?? null, d.rules, d.title, d.summary, d.details ?? {},
         d.deadline ?? null, d.cost ?? null, JSON.stringify(d.sources ?? []), d.where_kind ?? 'institutions', d.where_note ?? null, d.official_search ?? null]);
    }
    for (const i of c.institutions) {
      await client.query(
        `insert into institutions (id,city_id,name,services,mode,address,map_query,lat,lon,hours,phone,site,booking_url,serves,citizenships,status,checked_at,sources,note)
         values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19)`,
        [i.id, i.city_id, i.name, i.services ?? [], i.mode, i.address ?? null, i.map_query ?? null, i.lat ?? null, i.lon ?? null, i.hours ?? null,
         i.phone ?? null, i.site ?? null, i.booking_url ?? null, JSON.stringify(i.serves), i.citizenships ?? null, i.status, i.checked_at ?? null,
         JSON.stringify(i.sources ?? []), i.note ?? null]);
    }
    for (const t of c.tips) {
      await client.query('insert into tips (id,topic,city_id,kind,status,updated_at,title,body,source) values ($1,$2,$3,$4,$5,$6,$7,$8,$9)',
        [t.id, t.topic, t.city_id ?? null, t.kind ?? 'editorial', t.status, t.updated_at, t.title, t.body, t.source ?? null]);
    }
    await client.query('insert into settings (key, value) values ($1,$2)', ['reference', JSON.stringify({
      purposes: c.reference.purposes, stages: c.reference.stages, flags: c.reference.flags, where_to_check: c.reference.where_to_check ?? [],
    })]);
    await client.query('insert into settings (key, value) values ($1,$2)', ['moderation', JSON.stringify(c.moderation)]);
    await client.query('commit');
  } catch (e) {
    await client.query('rollback');
    throw e;
  } finally {
    client.release();
  }
  return {
    counts: {
      translations: Object.values(c.i18n).reduce((n, d) => n + Object.keys(d).length, 0),
      cities: c.cities.length, documents: c.documents.length, institutions: c.institutions.length, tips: c.tips.length,
    },
    warnings: rep.warnings,
  };
}
