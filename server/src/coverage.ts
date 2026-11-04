import type { Pool } from './db.js';
import { evaluateChecklist, type DocRow, type CitizenshipRow } from './checklist.js';
import { matchInstitutions, type InstRow } from './places.js';

export interface Coverage {
  scenarios: { group: string; purpose: string; stage: string; lostDocument: boolean; total: number; verified: number; demo: number; clarify: number; state: 'verified' | 'partial' | 'demo' | 'missing' }[];
  cities: { id: string; name: string; region: string }[];
  documents: { id: string; verified: boolean; cells: Record<string, 'verified' | 'demo' | 'district' | 'missing'>; whereKind: string }[];
  otherCities: number;
}

export async function computeCoverage(pool: Pool): Promise<Coverage> {
  const docs = (await pool.query('select id, sort, situations, necessity, status, rules, where_kind from documents order by sort')).rows as (DocRow & { where_kind: string })[];
  const cits = (await pool.query('select id, grp from citizenships')).rows as CitizenshipRow[];
  const insts = (await pool.query('select id, city_id, services, citizenships, serves, status, mode from institutions')).rows as InstRow[];
  const cities = (await pool.query('select id, name, region from cities order by name')).rows;
  const rep: Record<string, string> = { eaeu: 'KG', visa_free: 'TJ', other: 'OTHER' };

  const scenarios: Coverage['scenarios'] = [];
  const purposes = ['work', 'study', 'private', 'tourism'];
  for (const group of ['eaeu', 'visa_free', 'other']) {
    const variants: { purpose: string; stage: string; lost: boolean }[] = [];
    for (const purpose of purposes) for (const stage of ['before', 'in_russia']) variants.push({ purpose, stage, lost: false });
    variants.push({ purpose: 'work', stage: 'in_russia', lost: true });
    for (const v of variants) {
      const r = evaluateChecklist(docs, cits, { citizenship: rep[group], purpose: v.purpose, stage: v.stage, flags: { lost_document: v.lost } }, true);
      const verified = r.items.filter((i) => i.status === 'verified').length;
      const demo = r.items.filter((i) => i.status === 'demo').length;
      const total = r.items.length;
      const clarify = r.clarify.filter((c) => c.type !== 'other_country').length;
      const state = total === 0 ? 'missing' : verified === total && clarify === 0 ? 'verified' : verified > 0 ? 'partial' : 'demo';
      scenarios.push({ group, purpose: v.purpose, stage: v.stage, lostDocument: v.lost, total, verified, demo, clarify, state });
    }
  }

  const involved = new Set<string>(cities.filter((c) => c.id === 'moscow').map((c) => c.id));
  for (const i of insts) {
    involved.add(i.city_id);
    for (const s of i.serves) if ('city' in s) involved.add(s.city);
  }
  const shown = cities.filter((c) => involved.has(c.id));
  const documents: Coverage['documents'] = docs.filter((d) => d.status !== 'draft').map((d) => {
    const cells: Record<string, 'verified' | 'demo' | 'district' | 'missing'> = {};
    for (const c of shown) {
      const { matched, needsDistrict } = matchInstitutions(insts, { cityId: c.id, service: d.id, includeDemo: true });
      cells[c.id] = matched.some((m) => m.status === 'verified') ? 'verified' : matched.length ? 'demo' : needsDistrict ? 'district' : 'missing';
    }
    return { id: d.id, verified: d.status === 'verified', cells, whereKind: d.where_kind };
  });
  return { scenarios, cities: shown, documents, otherCities: cities.length - shown.length };
}
