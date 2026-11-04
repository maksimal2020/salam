import { createPool, migrate } from '../db.js';
const pool = createPool();
console.log('applied:', await migrate(pool));
await pool.end();
