import { createPool, migrate } from './db.js';
import { config } from './config.js';
import { createApp } from './app.js';
import { ensureModerator } from './auth.js';
import { importContent, loadContent } from './content.js';

const pool = createPool();
const applied = await migrate(pool);
if (applied.length) console.log('migrations applied:', applied.join(', '));

const has = await pool.query('select count(*)::int as n from translations');
if (has.rows[0].n === 0) {
  const r = await importContent(pool, loadContent(config.contentDirs));
  console.log('content imported (first start):', r.counts);
}
if (config.seedModeratorEmail && config.seedModeratorPassword) {
  console.log('seed moderator:', await ensureModerator(pool, config.seedModeratorEmail, config.seedModeratorPassword));
}
if (config.includeDemo) console.log('WARNING: INCLUDE_DEMO_CONTENT=true — demo records are visible to users.');

const { app } = createApp(pool);
app.listen(config.port, () => console.log(`API on :${config.port}`));
