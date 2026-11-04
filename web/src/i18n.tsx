import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import { api } from './api';

export const LANGS = [
  { code: 'ru', native: 'Русский', locale: 'ru-RU' },
  { code: 'tg', native: 'Тоҷикӣ', locale: 'tg-TJ' },
  { code: 'uz', native: 'Oʻzbekcha', locale: 'uz-UZ' },
  { code: 'ky', native: 'Кыргызча', locale: 'ky-KG' },
  { code: 'kk', native: 'Қазақша', locale: 'kk-KZ' },
] as const;
export type LangCode = (typeof LANGS)[number]['code'];

const read = (k: string): string | null => { try { return localStorage.getItem(k); } catch { return null; } };
const write = (k: string, v: string) => { try { localStorage.setItem(k, v); } catch { /* storage unavailable */ } };

interface I18n {
  lang: LangCode;
  chosen: boolean;
  setLang: (l: LangCode) => void;
  t: (key: string, params?: Record<string, string | number>) => string;
  /** t for keys built from data, e.g. tk('topic', id) */
  tk: (group: string, id: string, params?: Record<string, string | number>) => string;
  fmtDate: (iso: string | null | undefined) => string;
  ready: boolean;
  offline: boolean;
}
const Ctx = createContext<I18n>(null as unknown as I18n);
export const useI18n = () => useContext(Ctx);

export function I18nProvider({ children }: { children: ReactNode }) {
  const saved = read('lang') as LangCode | null;
  const [lang, setLangState] = useState<LangCode>(saved && LANGS.some((l) => l.code === saved) ? saved : 'ru');
  const [chosen, setChosen] = useState(!!saved);
  const [strings, setStrings] = useState<Record<string, string>>(() => {
    try { return JSON.parse(read(`strings:${saved ?? 'ru'}`) ?? '{}'); } catch { return {}; }
  });
  const [ready, setReady] = useState(Object.keys(strings).length > 0);
  const [offline, setOffline] = useState(false);

  useEffect(() => {
    document.documentElement.lang = lang;
    let alive = true;
    api<{ strings: Record<string, string> }>(`/i18n/${lang}`)
      .then((r) => { if (!alive) return; setStrings(r.strings); setReady(true); setOffline(false); write(`strings:${lang}`, JSON.stringify(r.strings)); })
      .catch(() => {
        if (!alive) return;
        setOffline(true);
        try { const c = JSON.parse(read(`strings:${lang}`) ?? 'null'); if (c) { setStrings(c); setReady(true); } } catch { /* ignore */ }
      });
    return () => { alive = false; };
  }, [lang]);

  const setLang = useCallback((l: LangCode) => { write('lang', l); setLangState(l); setChosen(true); }, []);

  const t = useCallback((key: string, params?: Record<string, string | number>) => {
    let s = strings[key] ?? key;
    if (params) for (const [k, v] of Object.entries(params)) s = s.replace(new RegExp(`\\{${k}\\}`, 'g'), String(v));
    return s;
  }, [strings]);

  const tk = useCallback((group: string, id: string, params?: Record<string, string | number>) => t(`${group}.${id}`, params), [t]);

  const fmtDate = useCallback((iso: string | null | undefined) => {
    if (!iso) return '';
    const d = new Date(iso.length === 10 ? `${iso}T12:00:00` : iso);
    if (Number.isNaN(d.getTime())) return iso;
    const locale = LANGS.find((l) => l.code === lang)?.locale ?? 'ru-RU';
    try { return new Intl.DateTimeFormat(locale, { day: 'numeric', month: 'long', year: 'numeric' }).format(d); } catch { return iso.slice(0, 10); }
  }, [lang]);

  const value = useMemo(() => ({ lang, chosen, setLang, t, tk, fmtDate, ready, offline }), [lang, chosen, setLang, t, tk, fmtDate, ready, offline]);
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}
