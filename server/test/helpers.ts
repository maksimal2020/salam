import path from 'node:path';
import type { AddressInfo } from 'node:net';
import pg from 'pg';

const admin = process.env.TEST_ADMIN_URL ?? 'postgres://app:app@127.0.0.1:5433/postgres';
const TEST_DB = 'migrant_test';
process.env.DATABASE_URL = admin.replace(/\/[^/]*$/, `/${TEST_DB}`);
process.env.NODE_ENV = 'test';
process.env.RATE_LIMIT = 'off';
process.env.INCLUDE_DEMO_CONTENT = 'true';
const root = path.resolve(import.meta.dirname, '..', '..');
process.env.CONTENT_DIRS = [path.join(root, 'content'), path.join(root, 'e2e', 'fixtures', 'content')].join(',');

export async function setup() {
  const a = new pg.Client({ connectionString: admin });
  await a.connect();
  const ex = await a.query('select 1 from pg_database where datname = $1', [TEST_DB]);
  if (!ex.rowCount) await a.query(`create database ${TEST_DB}`);
  await a.end();
  const { createPool, migrate } = await import('../src/db.js');
  const { createApp } = await import('../src/app.js');
  const { importContent, loadContent } = await import('../src/content.js');
  const { config } = await import('../src/config.js');
  const pool = createPool();
  await migrate(pool);
  await pool.query('truncate users restart identity cascade');
  await importContent(pool, loadContent(config.contentDirs));
  const { app } = createApp(pool);
  const server = app.listen(0);
  const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}/api`;
  async function call(method: string, url: string, body?: unknown, token?: string) {
    const res = await fetch(base + url, {
      method, headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    let json: any = null;
    try { json = await res.json(); } catch { /* empty */ }
    return { status: res.status, json };
  }
  return { pool, call, close: async () => { server.close(); await pool.end(); } };
}
