// Rule engine for «Мой список». Pure functions: no database, easy to test.

export interface Profile {
  citizenship?: string;
  purpose?: string;
  stage?: string;
  flags?: Record<string, boolean>;
}

export interface DocRow {
  id: string;
  sort: number;
  situations: string[];
  necessity: 'mandatory' | 'conditional' | 'service';
  status: 'verified' | 'demo' | 'draft';
  rules: { stages: string[] | null; purposes: string[] | null; groups: string[] | null; requires_flags: string[] };
}

export interface CitizenshipRow {
  id: string;
  grp: string;
}

export type ClarifyItem =
  | { type: 'missing'; field: 'citizenship' | 'purpose' | 'stage' }
  | { type: 'other_country' }
  | { type: 'depends_on_citizenship'; docId: string };

export interface ChecklistResult {
  items: { id: string; necessity: DocRow['necessity']; status: DocRow['status']; sort: number; situations: string[] }[];
  clarify: ClarifyItem[];
}

export function evaluateChecklist(docs: DocRow[], citizenships: CitizenshipRow[], profile: Profile, includeDemo: boolean): ChecklistResult {
  const clarify: ClarifyItem[] = [];
  const cit = citizenships.find((c) => c.id === profile.citizenship);
  if (!cit) clarify.push({ type: 'missing', field: 'citizenship' });
  if (!profile.purpose) clarify.push({ type: 'missing', field: 'purpose' });
  if (!profile.stage) clarify.push({ type: 'missing', field: 'stage' });
  if (cit?.grp === 'other') clarify.push({ type: 'other_country' });

  // Without the three basic answers we do not guess: only the questions to clarify are returned.
  if (!cit || !profile.purpose || !profile.stage) return { items: [], clarify };

  const flags = profile.flags ?? {};
  const items: ChecklistResult['items'] = [];
  for (const d of docs) {
    if (d.status === 'draft') continue;
    if (d.status === 'demo' && !includeDemo) continue;
    const r = d.rules;
    if (r.stages && !r.stages.includes(profile.stage)) continue;
    if (r.purposes && !r.purposes.includes(profile.purpose)) continue;
    if ((r.requires_flags ?? []).some((f) => !flags[f])) continue;
    if (r.groups) {
      if (cit.grp === 'other') {
        clarify.push({ type: 'depends_on_citizenship', docId: d.id });
        continue;
      }
      if (!r.groups.includes(cit.grp)) continue;
    }
    items.push({ id: d.id, necessity: d.necessity, status: d.status, sort: d.sort, situations: d.situations });
  }
  const stageRank = (it: { situations: string[] }) => (it.situations.includes('before_arrival') ? 0 : 1);
  items.sort((a, b) => stageRank(a) - stageRank(b) || a.sort - b.sort);
  return { items, clarify };
}
