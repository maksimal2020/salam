import fs from 'node:fs';
import path from 'node:path';
import { config } from '../config.js';
import { loadContent, validateContent } from '../content.js';

const c = loadContent(config.contentDirs);
const rep = validateContent(c);

// Every key used in the interface code must exist in the Russian master file.
const webSrc = path.resolve(config.contentDirs[0], '..', 'web', 'src');
const used = new Set<string>();
const walk = (d: string) => {
  for (const f of fs.readdirSync(d)) {
    const p = path.join(d, f);
    if (fs.statSync(p).isDirectory()) walk(p);
    else if (/\.(tsx?|jsx?)$/.test(f)) {
      const src = fs.readFileSync(p, 'utf8');
      for (const m of src.matchAll(/\bt\(\s*['"`]([a-zA-Z0-9_.]+)['"`]/g)) used.add(m[1]);
      for (const m of src.matchAll(/\btk\(\s*['"`]([a-zA-Z0-9_.]+)['"`]/g)) used.add(`${m[1]}.*`);
      for (const m of src.matchAll(/\bt\(\s*`([a-zA-Z0-9_.]+?\.)\$\{/g)) used.add(`${m[1]}*`);
    }
  }
};
if (fs.existsSync(webSrc)) walk(webSrc);
for (const k of used) {
  if (k.endsWith('.*')) {
    if (!Object.keys(c.i18n.ru).some((x) => x.startsWith(k.slice(0, -1)))) rep.errors.push(`интерфейс использует группу ключей ${k}, её нет в ru.json`);
  } else if (!(k in c.i18n.ru)) rep.errors.push(`интерфейс использует ключ ${k}, его нет в ru.json`);
}

console.log(`Проверено: ${c.documents.length} документов, ${c.institutions.length} учреждений, ${c.tips.length} советов, ${c.cities.length} городов, ${used.size} ключей интерфейса.`);
for (const w of rep.warnings) console.log('предупреждение:', w);
for (const e of rep.errors) console.log('ОШИБКА:', e);
if (rep.errors.length) process.exitCode = 1;
else console.log('Ошибок нет.');
