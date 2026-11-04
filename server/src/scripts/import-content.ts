import { createPool, migrate } from '../db.js';
import { config } from '../config.js';
import { importContent, loadContent } from '../content.js';
const pool = createPool();
await migrate(pool);
try {
  const r = await importContent(pool, loadContent(config.contentDirs));
  console.log('imported:', r.counts);
  for (const w of r.warnings) console.log('warning:', w);
} catch (e: any) {
  console.error(e.message);
  process.exitCode = 1;
}
await pool.end();
