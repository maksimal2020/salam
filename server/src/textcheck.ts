// Automatic checks of advertisement text. JS «\w» knows only Latin letters, so it is widened to any letter.

type Rules = {
  forbidden?: { id: string; patterns: string[] }[];
  passport?: string[];
  contact?: string[];
};

function widen(p: string): string {
  let out = '';
  let inClass = false;
  for (let i = 0; i < p.length; i++) {
    const ch = p[i];
    if (ch === '\\') {
      const next = p[i + 1];
      if (next === 'w') out += inClass ? '\\p{L}\\p{N}_' : '[\\p{L}\\p{N}_]';
      else out += ch + next;
      i++;
      continue;
    }
    if (ch === '[') inClass = true;
    if (ch === ']') inClass = false;
    out += ch;
  }
  return out;
}

export interface Verdict {
  ok: boolean;
  code?: 'forbidden' | 'passport' | 'contact';
  rule?: string;
}

export class TextChecker {
  private forbidden: { id: string; res: RegExp[] }[];
  private passport: RegExp[];
  private contact: RegExp[];

  constructor(rules: Rules) {
    const build = (ps: string[]) => ps.map((p) => new RegExp(widen(p), 'iu'));
    this.forbidden = (rules.forbidden ?? []).map((g) => ({ id: g.id, res: build(g.patterns) }));
    this.passport = build(rules.passport ?? []);
    this.contact = build(rules.contact ?? []);
  }

  check(...texts: (string | undefined | null)[]): Verdict {
    const t = texts.filter(Boolean).join('\n');
    for (const g of this.forbidden) if (g.res.some((r) => r.test(t))) return { ok: false, code: 'forbidden', rule: g.id };
    if (this.passport.some((r) => r.test(t))) return { ok: false, code: 'passport' };
    if (this.contact.some((r) => r.test(t))) return { ok: false, code: 'contact' };
    return { ok: true };
  }
}
