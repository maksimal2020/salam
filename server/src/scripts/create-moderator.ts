import { createPool, migrate } from '../db.js';
import { ensureModerator } from '../auth.js';
const [email, password] = process.argv.slice(2);
if (!email || !password) { console.error('usage: npm run create-moderator -- <email> <password>'); process.exit(1); }
const pool = createPool();
await migrate(pool);
console.log(await ensureModerator(pool, email, password));
await pool.end();
