import { Router } from 'express';
import { z } from 'zod';
import type { Pool } from '../db.js';
import { hashPassword, verifyPassword, createSession, destroySession, bearer, requireUser, requireModerator, rateLimit } from '../auth.js';
import { listingOut } from './ads.js';

export interface AccountDeps {
  pool: Pool;
  reloadContent: () => Promise<void>;
}

export function accountRoutes({ pool, reloadContent }: AccountDeps): Router {
  const r = Router();
  const userOut = (u: any) => ({ id: u.id, email: u.email, role: u.role, displayName: u.display_name ?? u.displayName ?? null });

  r.post('/auth/register', rateLimit(10, 60_000), async (req, res) => {
    const body = z.object({
      email: z.string().trim().toLowerCase().email().max(200),
      password: z.string().min(1).max(200),
      displayName: z.string().trim().max(60).optional(),
    }).safeParse(req.body);
    if (!body.success) return res.status(400).json({ code: 'validation' });
    if (body.data.password.length < 8) return res.status(400).json({ code: 'weak_password' });
    const exists = await pool.query('select 1 from users where email = $1', [body.data.email]);
    if (exists.rowCount) return res.status(409).json({ code: 'email_taken' });
    const u = (await pool.query('insert into users (email, password_hash, display_name) values ($1,$2,$3) returning *',
      [body.data.email, hashPassword(body.data.password), body.data.displayName || null])).rows[0];
    res.status(201).json({ token: await createSession(pool, u.id), user: userOut(u) });
  });

  r.post('/auth/login', rateLimit(20, 60_000), async (req, res) => {
    const body = z.object({ email: z.string().trim().toLowerCase(), password: z.string() }).safeParse(req.body);
    if (!body.success) return res.status(400).json({ code: 'validation' });
    const u = (await pool.query('select * from users where email = $1', [body.data.email])).rows[0];
    if (!u || !verifyPassword(body.data.password, u.password_hash)) return res.status(401).json({ code: 'invalid_credentials' });
    res.json({ token: await createSession(pool, u.id), user: userOut(u) });
  });

  r.post('/auth/logout', async (req, res) => {
    const t = bearer(req);
    if (t) await destroySession(pool, t);
    res.json({ ok: true });
  });

  r.get('/me', requireUser, (req, res) => res.json({ user: userOut(req.user) }));

  // ---------------- moderation (moderator role)
  const mod = Router();
  mod.use(requireModerator);

  const QUEUE_SELECT = `l.*, c.name as city_name, c.region as city_region, u.email as author_email,
    (select count(*) from reports x where x.listing_id = l.id and x.status = 'open') as report_count,
    (select count(*) from listing_responses x where x.listing_id = l.id) as response_count`;
  const QUEUE_FROM = `from listings l join cities c on c.id = l.city_id join users u on u.id = l.author_id`;

  mod.get('/queue', async (req, res) => {
    const kind = String(req.query.kind ?? 'pending');
    const where =
      kind === 'reported' ? "l.status in ('published','pending','hidden') and exists (select 1 from reports x where x.listing_id = l.id and x.status = 'open')"
      : kind === 'recent' ? "l.status = 'published' and l.reviewed_at is null"
      : "l.status = 'pending'";
    const rows = (await pool.query(`select ${QUEUE_SELECT} ${QUEUE_FROM} where ${where} order by l.created_at desc limit 100`)).rows;
    const out = [];
    for (const l of rows) {
      const item: any = listingOut(l, { mod: true });
      item.reports = (await pool.query("select id, reason, created_at from reports where listing_id = $1 and status = 'open' order by created_at", [l.id])).rows;
      out.push(item);
    }
    const counts = (await pool.query(`select
      (select count(*) from listings where status = 'pending')::int as pending,
      (select count(distinct listing_id) from reports where status = 'open')::int as reported,
      (select count(*) from listings where status = 'published' and reviewed_at is null)::int as recent`)).rows[0];
    res.json({ listings: out, counts });
  });

  const act = async (id: number, moderatorId: number, action: string, reason: string | null, sql: string, args: unknown[] = []) => {
    const r2 = await pool.query(sql, [id, ...args]);
    if (!r2.rowCount) return false;
    await pool.query('insert into moderation_log (listing_id, moderator_id, action, reason) values ($1,$2,$3,$4)', [id, moderatorId, action, reason]);
    return true;
  };

  const PUBLISH = `update listings set status = 'published', moderation_note = null, reviewed_at = now(), reviewed_by = ${'$2'},
    published_at = coalesce(published_at, now()),
    expires_at = case when expires_at is null or expires_at < now() then now() + (duration_days || ' days')::interval else expires_at end,
    updated_at = now() where id = $1 and status in ('pending','published','hidden','rejected') returning id`;

  mod.post('/listings/:id/approve', async (req, res) => {
    const id = Number(req.params.id);
    const ok = await act(id, req.user!.id, 'approve', null, PUBLISH, [req.user!.id]);
    if (!ok) return res.status(404).json({ code: 'not_found' });
    await pool.query("update reports set status = 'dismissed' where listing_id = $1 and status = 'open'", [id]);
    res.json({ id, status: 'published' });
  });

  mod.post('/listings/:id/restore', async (req, res) => {
    const id = Number(req.params.id);
    const ok = await act(id, req.user!.id, 'restore', null, PUBLISH.replace("status in ('pending','published','hidden','rejected')", "status = 'hidden'"), [req.user!.id]);
    if (!ok) return res.status(404).json({ code: 'not_found' });
    await pool.query("update reports set status = 'dismissed' where listing_id = $1 and status = 'open'", [id]);
    res.json({ id, status: 'published' });
  });

  for (const [name, status] of [['reject', 'rejected'], ['hide', 'hidden']] as const) {
    mod.post(`/listings/:id/${name}`, async (req, res) => {
      const body = z.object({ reason: z.string().trim().min(3).max(500) }).safeParse(req.body);
      if (!body.success) return res.status(400).json({ code: 'validation' });
      const id = Number(req.params.id);
      const ok = await act(id, req.user!.id, name, body.data.reason,
        `update listings set status = '${status}', moderation_note = $3, reviewed_at = now(), reviewed_by = $2, updated_at = now()
         where id = $1 and status in ('pending','published','hidden') returning id`, [req.user!.id, body.data.reason]);
      if (!ok) return res.status(404).json({ code: 'not_found' });
      await pool.query("update reports set status = 'actioned' where listing_id = $1 and status = 'open'", [id]);
      res.json({ id, status });
    });
  }

  mod.post('/reload-content', async (_req, res) => {
    await reloadContent();
    res.json({ ok: true });
  });

  r.use('/mod', mod);
  return r;
}
