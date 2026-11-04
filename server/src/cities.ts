export interface CityRow {
  id: string;
  name: string;
  region: string;
  lat: number;
  lon: number;
  aliases: string[];
  pilot: boolean;
  districts: { id: string; name: string }[] | null;
}

export function norm(s: string): string {
  return s.toLowerCase().replace(/ё/g, 'е').replace(/[ʻʼ'’`]/g, '').replace(/[-–—_.,()]/g, ' ').replace(/\s+/g, ' ').trim();
}

/** Names alone are not enough: homonyms are told apart by their region. */
export function searchCities(all: CityRow[], q: string, limit = 12): CityRow[] {
  const nq = norm(q);
  if (!nq) return [];
  const scored: { c: CityRow; score: number }[] = [];
  for (const c of all) {
    const names = [norm(c.name), ...c.aliases.map(norm)];
    const region = norm(c.region);
    let score = 0;
    for (const n of names) {
      if (n === nq) score = Math.max(score, 100);
      else if (n.startsWith(nq)) score = Math.max(score, 80);
      else if (n.split(' ').some((w) => w.startsWith(nq))) score = Math.max(score, 60);
      else if (n.includes(nq)) score = Math.max(score, 40);
    }
    // «железногорск красноярский» also works
    if (!score && nq.includes(' ')) {
      const parts = nq.split(' ');
      if (parts.every((p) => names.some((n) => n.includes(p)) || region.includes(p))) score = 30;
    }
    if (score && c.pilot) score += 1;
    if (score) scored.push({ c, score });
  }
  return scored.sort((a, b) => b.score - a.score || a.c.name.localeCompare(b.c.name, 'ru')).slice(0, limit).map((x) => x.c);
}

export function haversineKm(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371;
  const rad = (d: number) => (d * Math.PI) / 180;
  const dLat = rad(lat2 - lat1);
  const dLon = rad(lon2 - lon1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

export type LocateResult =
  | { status: 'candidate'; city: CityRow; distanceKm: number }
  | { status: 'no_match'; distanceKm: number }
  | { status: 'outside'; distanceKm: number };

export function locate(all: CityRow[], lat: number, lon: number, maxKm: number, outsideKm: number): LocateResult {
  let best: CityRow | null = null;
  let bestD = Infinity;
  for (const c of all) {
    const d = haversineKm(lat, lon, c.lat, c.lon);
    if (d < bestD) { best = c; bestD = d; }
  }
  if (!best) return { status: 'no_match', distanceKm: Infinity };
  const distanceKm = Math.round(bestD);
  if (bestD <= maxKm) return { status: 'candidate', city: best, distanceKm };
  return { status: bestD > outsideKm ? 'outside' : 'no_match', distanceKm };
}
