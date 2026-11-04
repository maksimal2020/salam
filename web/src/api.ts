export class ApiError extends Error {
  constructor(public status: number, public code: string, public data: any) {
    super(code);
  }
}

const TOKEN_KEY = 'token';
export const getToken = (): string | null => {
  try { return localStorage.getItem(TOKEN_KEY); } catch { return null; }
};
export const setToken = (t: string | null) => {
  try { if (t) localStorage.setItem(TOKEN_KEY, t); else localStorage.removeItem(TOKEN_KEY); } catch { /* storage unavailable */ }
};

export async function api<T = any>(path: string, opts: { method?: string; body?: unknown } = {}): Promise<T> {
  const token = getToken();
  let res: Response;
  try {
    res = await fetch('/api' + path, {
      method: opts.method ?? 'GET',
      headers: { ...(opts.body !== undefined ? { 'content-type': 'application/json' } : {}), ...(token ? { authorization: `Bearer ${token}` } : {}) },
      body: opts.body !== undefined ? JSON.stringify(opts.body) : undefined,
    });
  } catch {
    throw new ApiError(0, 'network', null);
  }
  let data: any = null;
  try { data = await res.json(); } catch { /* empty body */ }
  if (!res.ok) throw new ApiError(res.status, data?.code ?? 'server_error', data);
  return data as T;
}

export const qs = (o: Record<string, string | number | undefined | null | false>): string => {
  const p = new URLSearchParams();
  for (const [k, v] of Object.entries(o)) if (v !== undefined && v !== null && v !== false && v !== '') p.set(k, String(v));
  const s = p.toString();
  return s ? `?${s}` : '';
};

// ---- types of API answers
export interface City { id: string; name: string; region: string; label?: string; districts?: { id: string; name: string }[] }
export interface Meta {
  languages: { code: string; native: string }[];
  citizenships: { id: string; group: string; name: string }[];
  situations: { id: string; name: string }[];
  reference: { purposes: string[]; stages: string[]; flags: string[] };
  includeDemo: boolean;
}
export interface DocBrief { id: string; necessity: 'mandatory' | 'conditional' | 'service'; status: 'verified' | 'demo'; checked_at: string | null; situations: string[]; title: string; summary: string }
export interface Source { title: string; url: string }
export interface DocFull extends DocBrief {
  details: { who?: string; prepare?: string[]; how?: string[]; renewal?: string };
  details_fallback: boolean;
  deadline: Record<string, string> | null;
  cost: Record<string, string> | null;
  sources: Source[];
  where_kind: string;
  where_note: string | null;
}
export interface Institution {
  id: string; name: string; status: 'verified' | 'demo'; checked_at: string | null; mode: 'in_person' | 'online' | 'both';
  city: { id: string; name: string; region: string }; other_city: boolean; address: string | null;
  map: { query: string | null; lat: number | null; lon: number | null };
  hours: string | null; phone: string | null; site: string | null; booking_url: string | null;
  services: { id: string; title: string }[]; serves: ({ scope: 'country' } | { city: string; districts: string[] | null })[];
  citizenships: string[] | null; sources: Source[]; note: string | null;
}
export interface Places {
  needs_city: boolean; city: City | null; institutions: Institution[]; needs_district: boolean; districts: { id: string; name: string }[];
  where_kind?: string; where_note?: string | null; official_search?: { title: string; url: string } | null; sources?: Source[]; document?: DocBrief;
  services?: { id: string; title: string; official_search: { title: string; url: string } | null }[];
}
export interface Listing {
  id: number; category: string; title: string; body: string; lang: string; city: { id: string; name: string; region: string };
  price: string | null; extra: { employer?: string; pay?: string; schedule?: string; terms?: string }; duration_days: number;
  status: string; created_at: string; published_at: string | null; expires_at: string | null;
  moderation_note?: string | null; response_count?: number;
  author_email?: string; report_count?: number; reports?: { id: number; reason: string }[];
}
export interface User { id: number; email: string; role: 'user' | 'moderator'; displayName: string | null }
