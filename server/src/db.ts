import pg from 'pg';
import fs from 'node:fs';
import path from 'node:path';
import { config } from './config.js';

// bigint ids -> numbers, dates -> 'YYYY-MM-DD' strings
pg.types.setTypeParser(20, (v) => Number(v));
pg.types.setTypeParser(1082, (v) => v);

export type Pool = pg.Pool;

export function createPool(url = config.databaseUrl): Pool {
  return new pg.Pool({ connectionString: url, max: 10 });
}

export async function migrate(pool: Pool): Promise<string[]> {
  await pool.query('create table if not exists schema_migrations (id text primary key, applied_at timestamptz not null default now())');
  const files = fs.readdirSync(config.migrationsDir).filter((f) => f.endsWith('.sql')).sort();
  const applied: string[] = [];
  for (const f of files) {
    const done = await pool.query('select 1 from schema_migrations where id = $1', [f]);
    if (done.rowCount) continue;
    const sql = fs.readFileSync(path.join(config.migrationsDir, f), 'utf8');
    const client = await pool.connect();
    try {
      await client.query('begin');
      await client.query(sql);
      await client.query('insert into schema_migrations (id) values ($1)', [f]);
      await client.query('commit');
      applied.push(f);
    } catch (e) {
      await client.query('rollback');
      throw e;
    } finally {
      client.release();
    }
  }
  return applied;
}
