import { LANGS, type Lang } from './content.js';

export function isLang(x: unknown): x is Lang {
  return typeof x === 'string' && (LANGS as readonly string[]).includes(x);
}

export function langOf(x: unknown): Lang {
  return isLang(x) ? x : 'ru';
}

/** Value for the language, otherwise the Russian master text. */
export function pick(obj: Record<string, string> | null | undefined, lang: Lang): string {
  if (!obj) return '';
  return obj[lang] ?? obj.ru ?? '';
}

export function str(x: unknown): string | undefined {
  return typeof x === 'string' && x.length ? x : undefined;
}
