import { createPool, migrate } from './db.js';
import { config } from './config.js';
import { createApp } from './app.js';
import { ensureModerator } from './auth.js';
import { importContent, loadContent } from './content.js';

const pool = createPool();
const applied = await migrate(pool);
if (applied.length) console.log('migrations applied:', applied.join(', '));

// Контент из content/ перечитывается в базу при КАЖДОМ старте, а не только при первом: это
// единственный источник правды для текстов/учреждений/документов, и importContent() внутри
// полностью и атомарно (в одной транзакции) заменяет свои таблицы, не трогая аккаунты и
// объявления — так что это безопасно и дёшево делать каждый раз. Иначе правки в content/*.json
// не доходят до пользователя после перезапуска уже существующей базы (ровно так и произошло:
// пользователь обновил файлы и перезапустил docker compose, но карточки остались старыми,
// потому что раньше импорт срабатывал только при пустой таблице translations).
const r = await importContent(pool, loadContent(config.contentDirs));
console.log('content imported:', r.counts);
if (config.seedModeratorEmail && config.seedModeratorPassword) {
  console.log('seed moderator:', await ensureModerator(pool, config.seedModeratorEmail, config.seedModeratorPassword));
}
if (config.includeDemo) console.log('WARNING: INCLUDE_DEMO_CONTENT=true — demo records are visible to users.');

const { app } = createApp(pool);
app.listen(config.port, () => console.log(`API on :${config.port}`));
