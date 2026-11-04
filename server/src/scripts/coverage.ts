import fs from 'node:fs';
import path from 'node:path';
import { createPool } from '../db.js';
import { config } from '../config.js';
import { computeCoverage } from '../coverage.js';

const pool = createPool();
const cov = await computeCoverage(pool);
const sym = { verified: '✅ проверено', partial: '🟡 частично', demo: '🟠 демо', missing: '⬜ нет данных' } as const;
const cell = { verified: '✅', demo: '🟠 демо', district: '❓ нужен район', missing: '—' } as const;
const root = path.resolve(config.contentDirs[0], '..');
let md = '# Таблица покрытия\n\nСоздана командой `npm run coverage`. ✅ — подтверждено источником, 🟠 — демонстрационные данные, — нет данных.\n\n## Сценарии (гражданство × цель × этап)\n\n';
md += '| Группа | Цель | Этап | Утерян документ | Шагов | Проверено | Демо | К уточнению | Статус |\n|---|---|---|---|---|---|---|---|---|\n';
for (const s of cov.scenarios) md += `| ${s.group} | ${s.purpose} | ${s.stage} | ${s.lostDocument ? 'да' : 'нет'} | ${s.total} | ${s.verified} | ${s.demo} | ${s.clarify} | ${sym[s.state]} |\n`;
md += '\n## Учреждения по документам и городам\n\n| Документ | ' + cov.cities.map((c) => c.name).join(' | ') + ' |\n|---|' + cov.cities.map(() => '---').join('|') + '|\n';
for (const d of cov.documents) {
  md += `| ${d.id}${d.whereKind !== 'institutions' ? ' (без учреждения)' : ''} | ` + cov.cities.map((c) => (d.whereKind !== 'institutions' ? 'n/a' : cell[d.cells[c.id]])).join(' | ') + ' |\n';
}
md += `\nЕщё ${cov.otherCities} городов в справочнике без единой записи об учреждении.\n`;
fs.mkdirSync(path.join(root, 'docs'), { recursive: true });
fs.writeFileSync(path.join(root, 'docs', 'COVERAGE.md'), md);
console.log('docs/COVERAGE.md written');
await pool.end();
