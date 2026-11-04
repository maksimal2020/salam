// Which institutions handle a document for a given city / district / citizenship.

export interface InstRow {
  id: string;
  city_id: string;
  services: string[];
  citizenships: string[] | null;
  serves: ({ scope: 'country' } | { city: string; districts: string[] | null })[];
  status: 'verified' | 'demo' | 'draft';
  mode: string;
}

export interface MatchResult<T extends InstRow> {
  matched: T[];
  /** Some institutions serve only certain districts and the user has not chosen one. */
  needsDistrict: boolean;
}

export function matchInstitutions<T extends InstRow>(
  all: T[],
  opts: { cityId: string; districtId?: string | null; citizenship?: string | null; service?: string | null; mode?: string | null; includeDemo: boolean },
): MatchResult<T> {
  const matched: T[] = [];
  let needsDistrict = false;
  for (const i of all) {
    if (i.status === 'draft') continue;
    if (i.status === 'demo' && !opts.includeDemo) continue;
    if (opts.service && !i.services.includes(opts.service)) continue;
    if (opts.mode && opts.mode !== 'all' && i.mode !== opts.mode && i.mode !== 'both') continue;
    if (opts.citizenship && i.citizenships && !i.citizenships.includes(opts.citizenship)) continue;

    let serves = false;
    let unknownDistrict = false;
    for (const s of i.serves) {
      if ('scope' in s) { serves = true; continue; }
      if (s.city !== opts.cityId) continue;
      if (!s.districts) { serves = true; continue; }
      if (!opts.districtId) { unknownDistrict = true; continue; }
      if (s.districts.includes(opts.districtId)) serves = true;
    }
    if (serves) matched.push(i);
    else if (unknownDistrict) needsDistrict = true;
  }
  return { matched, needsDistrict };
}
