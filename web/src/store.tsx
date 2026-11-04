import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import { api, getToken, setToken, type City, type Meta, type User } from './api';
import { useI18n } from './i18n';

function load<T>(key: string, fallback: T): T {
  try { const v = localStorage.getItem(key); return v ? (JSON.parse(v) as T) : fallback; } catch { return fallback; }
}
function save(key: string, v: unknown) {
  try { localStorage.setItem(key, JSON.stringify(v)); } catch { /* storage unavailable */ }
}

// Only the confirmed city and region are remembered, never coordinates.
export type SavedCity = Pick<City, 'id' | 'name' | 'region'>;
export interface Profile { citizenship?: string; purpose?: string; stage?: string; flags: Record<string, boolean> }

interface Store {
  meta: Meta | null;
  city: SavedCity | null;
  cityAsked: boolean;
  setCity: (c: SavedCity | null) => void;
  skipCity: () => void;
  district: string | null;
  setDistrict: (d: string | null) => void;
  cityPickerOpen: boolean;
  openCityPicker: () => void;
  closeCityPicker: () => void;
  profile: Profile;
  setProfile: (p: Profile) => void;
  marks: Record<string, boolean>;
  toggleMark: (id: string) => void;
  user: User | null;
  login: (token: string, user: User) => void;
  logout: () => Promise<void>;
}
const Ctx = createContext<Store>(null as unknown as Store);
export const useStore = () => useContext(Ctx);

export function StoreProvider({ children }: { children: ReactNode }) {
  const { lang } = useI18n();
  const [meta, setMeta] = useState<Meta | null>(null);
  const [city, setCityState] = useState<SavedCity | null>(() => load('city', null));
  const [cityAsked, setCityAsked] = useState<boolean>(() => load('cityAsked', false));
  const [district, setDistrictState] = useState<string | null>(() => load('district', null));
  const [cityPickerOpen, setPickerOpen] = useState(false);
  const [profile, setProfileState] = useState<Profile>(() => load('profile', { flags: {} }));
  const [marks, setMarks] = useState<Record<string, boolean>>(() => load('marks', {}));
  const [user, setUser] = useState<User | null>(null);

  useEffect(() => {
    api<Meta>(`/meta?lang=${lang}`).then(setMeta).catch(() => { /* offline: cached by the service worker */ });
  }, [lang]);

  useEffect(() => {
    if (!getToken()) return;
    api<{ user: User }>('/me').then((r) => setUser(r.user)).catch(() => setToken(null));
  }, []);

  const setCity = useCallback((c: SavedCity | null) => {
    setCityState(c); save('city', c);
    setCityAsked(true); save('cityAsked', true);
    // the district belongs to a city, so it is reset on every change
    setDistrictState(null); save('district', null);
  }, []);
  const skipCity = useCallback(() => { setCityAsked(true); save('cityAsked', true); }, []);
  const setDistrict = useCallback((d: string | null) => { setDistrictState(d); save('district', d); }, []);
  const setProfile = useCallback((p: Profile) => { setProfileState(p); save('profile', p); }, []);
  const toggleMark = useCallback((id: string) => {
    setMarks((m) => { const n = { ...m, [id]: !m[id] }; save('marks', n); return n; });
  }, []);
  const login = useCallback((token: string, u: User) => { setToken(token); setUser(u); }, []);
  const logout = useCallback(async () => {
    try { await api('/auth/logout', { method: 'POST', body: {} }); } catch { /* ignore */ }
    setToken(null); setUser(null);
  }, []);

  const value = useMemo<Store>(() => ({
    meta, city, cityAsked, setCity, skipCity, district, setDistrict, cityPickerOpen,
    openCityPicker: () => setPickerOpen(true), closeCityPicker: () => setPickerOpen(false),
    profile, setProfile, marks, toggleMark, user, login, logout,
  }), [meta, city, cityAsked, setCity, skipCity, district, setDistrict, cityPickerOpen, profile, setProfile, marks, toggleMark, user, login, logout]);
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}
