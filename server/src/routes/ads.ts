import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import type { Pool } from '../db.js';
import { LANGS } from '../content.js';
import { requireUser, rateLimit } from '../auth.js';
import { config } from '../config.js';
import type { TextChecker } from '../textcheck.js';

const CATEGORIES = ['work', 'housing', 'market', 'services', 'free'] as const;
const short = z.string().trim().max(200).optional().nullable();

const ListingInput = z.object({
  category: z.enum(CATEGORIES),
  title: z.string().trim().min(5).max(120),
  body: z.string().trim().min(10).max(4000),
  lang: z.enum(LANGS),
  city_id: z.string().min(1),
  price: z.string().trim().max(80).optional().nullable(),
  duration_days: z.number().int().min(1).max(30).default(14),
  extra: z.object({ employer: short, pay: short, schedule: short, terms: short }).optional(),
}).superRefine((v, ctx) => {
  if (v.category === 'work') {
    if (!v.extra?.employer?.trim()) ctx.addIssue({ code: 'custom', path: ['extra', 'employer'], message: 'required' });
    if (!v.extra?.pay?.trim()) ctx.addIssue({ code: 'custom', path: ['extra', 'pay'], message: 'required' });
  }
});

export interface AdsDeps {
  pool: Pool;
  checker: () => Promise<TextChecker>;
}

const SELECT = `l.*, c.name as city_name, c.region as city_region`;
const JOIN = `from listings l join cities c on c.id = l.city_id`;
const PUBLIC = `l.status = 'published' and l.expires_at > now()`;

export function listingOut(l: any, opts: { owner?: boolean; mod?: boolean } = {}) {
  const out: any = {
    id: l.id, category: l.category, title: l.title, body: l.body, lang: l.lang,
    city: { id: l.city_id, name: l.city_name, region: l.city_region },
    price: l.price, extra: l.extra, duration_days: l.duration_days,
    status: l.status, created_at: l.created_at, published_at: l.published_at, expires_at: l.expires_at,
  };
  if (opts.owner || opts.mod) {
    out.moderation_note = l.moderation_note;
    out.response_count = l.response_count !== undefined ? Number(l.response_count) : undefined;
  }
  if (opts.mod) {
    out.author_id = l.author_id; out.author_email = l.author_email;
    out.report_count = Number(l.report_count ?? 0); out.reviewed_at = l.reviewed_at;
  }
  // an expired record is shown to its author as such
  if (out.status === 'published' && l.expires_at && new Date(l.expires_at) < new Date()) out.status = 'expired';
  return out;
}

export function adsRoutes({ pool, checker }: AdsDeps): Router {
  const r = Router();

  const fail = (res: Response, status: number, code: string, extra: object = {}) => res.status(status).json({ code, ...extra });

  const validate = async (req: Request, res: Response) => {
    const parsed = ListingInput.safeParse(req.body);
    if (!parsed.success) { fail(res, 400, 'validation', { fields: parsed.error.issues.map((i) => i.path.join('.')) }); return null; }
    const v = parsed.data;
    const city = await pool.query('select 1 from cities where id = $1', [v.city_id]);
    if (!city.rowCount) { fail(res, 400, 'validation', { fields: ['city_id'] }); return null; }
    const mod = await (await checker()).check(v.title, v.body, v.price, v.extra?.employer, v.extra?.pay, v.extra?.schedule, v.extra?.terms);
    if (!mod.ok) { fail(res, 422, mod.code!, { rule: mod.rule }); return null; }
    return v;
  };

  const premoderated = async (category: string) => {
    const s = (await pool.query("select value from settings where key = 'moderation'")).rows[0]?.value ?? {};
    return (s.premoderate_categories ?? ['work']).includes(category);
  };

  // ---- public reading (no account needed)
  r.get('/listings', async (req, res) => {
    const where = [PUBLIC];
    const args: unknown[] = [];
    const add = (sql: string, v: unknown) => { args.push(v); where.push(sql.replace('?', `$${args.length}`)); };
    if (typeof req.query.category === 'string' && (CATEGORIES as readonly string[]).includes(req.query.category)) add('l.category = ?', req.query.category);
    if (typeof req.query.city === 'string' && req.query.city) add('l.city_id = ?', req.query.city);
    if (typeof req.query.lang === 'string' && req.query.lang) add('l.lang = ?', req.query.lang);
    if (typeof req.query.q === 'string' && req.query.q.trim()) {
      args.push(`%${req.query.q.trim().replace(/[%_\\]/g, '')}%`);
      where.push(`(l.title ilike $${args.length} or l.body ilike $${args.length})`);
    }
    const limit = Math.min(Number(req.query.limit ?? 30) || 30, 100);
    const offset = Math.max(Number(req.query.offset ?? 0) || 0, 0);
    const rows = (await pool.query(
      `select ${SELECT} ${JOIN} where ${where.join(' and ')} order by l.published_at desc limit ${limit} offset ${offset}`, args)).rows;
    res.json({ listings: rows.map((l) => listingOut(l)) });
  });

  r.get('/listings/:id', async (req, res) => {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) return fail(res, 404, 'not_found');
    const l = (await pool.query(`select ${SELECT} ${JOIN} where l.id = $1`, [id])).rows[0];
    if (!l) return fail(res, 404, 'not_found');
    const isPublic = l.status === 'published' && new Date(l.expires_at) > new Date();
    const isOwner = req.user && Number(l.author_id) === req.user.id;
    const isMod = req.user?.role === 'moderator';
    if (!isPublic && !isOwner && !isMod) return fail(res, 404, 'not_found');
    res.json(listingOut(l, { owner: !!isOwner, mod: false }));
  });

  // ---- writing (account needed)
  r.post('/listings', requireUser, rateLimit(20, 60_000), async (req, res) => {
    const v = await validate(req, res);
    if (!v) return;
    const pre = await premoderated(v.category);
    const row = (await pool.query(
      `insert into listings (author_id, category, title, body, lang, city_id, price, extra, duration_days, status, published_at, expires_at)
       values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10, $11, $12) returning id, status`,
      [req.user!.id, v.category, v.title, v.body, v.lang, v.city_id, v.price || null, JSON.stringify(v.extra ?? {}), v.duration_days,
       pre ? 'pending' : 'published', pre ? null : new Date(), pre ? null : new Date(Date.now() + v.duration_days * 86400_000)])).rows[0];
    res.status(201).json({ id: row.id, status: row.status });
  });

  r.patch('/listings/:id', requireUser, async (req, res) => {
    const id = Number(req.params.id);
    const cur = (await pool.query('select * from listings where id = $1 and author_id = $2', [id, req.user!.id])).rows[0];
    if (!cur) return fail(res, 404, 'not_found');
    if (!['pending', 'published', 'rejected'].includes(cur.status)) return fail(res, 409, 'not_editable');
    const v = await validate(req, res);
    if (!v) return;
    const pre = await premoderated(v.category);
    // an edited ad goes through review again
    const status = pre ? 'pending' : 'published';
    const expires = status === 'pending' ? null : new Date(Date.now() + v.duration_days * 86400_000);
    await pool.query(
      `update listings set category=$2, title=$3, body=$4, lang=$5, city_id=$6, price=$7, extra=$8, duration_days=$9, status=$10,
         published_at = case when $10 = 'published' then coalesce(published_at, now()) else null end,
         expires_at = $11, reviewed_at = null, moderation_note = null, updated_at = now() where id = $1`,
      [id, v.category, v.title, v.body, v.lang, v.city_id, v.price || null, JSON.stringify(v.extra ?? {}), v.duration_days, status, expires]);
    res.json({ id, status });
  });

  r.post('/listings/:id/withdraw', requireUser, async (req, res) => {
    const r2 = await pool.query(
      "update listings set status = 'withdrawn', updated_at = now() where id = $1 and author_id = $2 and status in ('pending','published') returning id",
      [Number(req.params.id), req.user!.id]);
    if (!r2.rowCount) return fail(res, 404, 'not_found');
    res.json({ id: r2.rows[0].id, status: 'withdrawn' });
  });

  r.post('/listings/:id/respond', requireUser, rateLimit(30, 60_000), async (req, res) => {
    const body = z.object({ message: z.string().trim().min(2).max(2000), contact: z.string().trim().max(200).optional().nullable() }).safeParse(req.body);
    if (!body.success) return fail(res, 400, 'validation');
    const l = (await pool.query(`select id, author_id from listings l where id = $1 and ${PUBLIC}`, [Number(req.params.id)])).rows[0];
    if (!l) return fail(res, 404, 'not_found');
    if (Number(l.author_id) === req.user!.id) return fail(res, 403, 'own_listing');
    const today = await pool.query("select count(*)::int as n from listing_responses where from_user_id = $1 and created_at > now() - interval '1 day'", [req.user!.id]);
    if (today.rows[0].n >= 20) return fail(res, 429, 'rate_limited');
    await pool.query('insert into listing_responses (listing_id, from_user_id, message, contact) values ($1,$2,$3,$4)',
      [l.id, req.user!.id, body.data.message, body.data.contact || null]);
    res.status(201).json({ ok: true });
  });

  r.post('/listings/:id/report', requireUser, rateLimit(20, 60_000), async (req, res) => {
    const body = z.object({ reason: z.string().trim().min(3).max(500) }).safeParse(req.body);
    if (!body.success) return fail(res, 400, 'validation');
    const id = Number(req.params.id);
    const l = (await pool.query(`select id, status from listings l where id = $1 and ${PUBLIC}`, [id])).rows[0];
    if (!l) return fail(res, 404, 'not_found');
    await pool.query('insert into reports (listing_id, reporter_id, reason) values ($1,$2,$3) on conflict (listing_id, reporter_id) do nothing', [id, req.user!.id, body.data.reason]);
    const n = (await pool.query("select count(*)::int as n from reports where listing_id = $1 and status = 'open'", [id])).rows[0].n;
    if (n >= config.reportsAutoHide) {
      const hid = await pool.query("update listings set status = 'hidden', moderation_note = 'auto: reports', updated_at = now() where id = $1 and status = 'published' returning id", [id]);
      if (hid.rowCount) await pool.query("insert into moderation_log (listing_id, action, reason) values ($1,'auto_hide','reports')", [id]);
    }
    res.status(201).json({ ok: true });
  });

  // ---- author's own pages
  r.get('/my/listings', requireUser, async (req, res) => {
    const rows = (await pool.query(
      `select ${SELECT}, (select count(*) from listing_responses x where x.listing_id = l.id) as response_count ${JOIN}
       where l.author_id = $1 order by l.created_at desc`, [req.user!.id])).rows;
    res.json({ listings: rows.map((l) => listingOut(l, { owner: true })) });
  });

  r.get('/my/listings/:id/responses', requireUser, async (req, res) => {
    const id = Number(req.params.id);
    const own = await pool.query('select 1 from listings where id = $1 and author_id = $2', [id, req.user!.id]);
    if (!own.rowCount) return fail(res, 404, 'not_found');
    const rows = (await pool.query(
      `select x.id, x.message, x.contact, x.created_at, u.display_name from listing_responses x join users u on u.id = x.from_user_id
       where x.listing_id = $1 order by x.created_at desc`, [id])).rows;
    res.json({ responses: rows.map((x) => ({ id: x.id, message: x.message, contact: x.contact, created_at: x.created_at, from: x.display_name })) });
  });

  r.get('/my/responses', requireUser, async (req, res) => {
    const rows = (await pool.query(
      `select x.id, x.message, x.created_at, l.id as listing_id, l.title, l.status from listing_responses x join listings l on l.id = x.listing_id
       where x.from_user_id = $1 order by x.created_at desc`, [req.user!.id])).rows;
    res.json({ responses: rows });
  });

  return r;
}
