import crypto from 'node:crypto';
import type { Request, Response, NextFunction } from 'express';
import type { Pool } from './db.js';
import { config } from './config.js';

export interface AuthUser {
  id: number;
  email: string;
  role: 'user' | 'moderator';
  displayName: string | null;
}

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Express {
    interface Request {
      user?: AuthUser;
    }
  }
}

export function hashPassword(password: string): string {
  const salt = crypto.randomBytes(16);
  const hash = crypto.scryptSync(password, salt, 64);
  return `${salt.toString('hex')}:${hash.toString('hex')}`;
}

export function verifyPassword(password: string, stored: string): boolean {
  const [saltHex, hashHex] = stored.split(':');
  if (!saltHex || !hashHex) return false;
  const expected = Buffer.from(hashHex, 'hex');
  const actual = crypto.scryptSync(password, Buffer.from(saltHex, 'hex'), expected.length);
  return crypto.timingSafeEqual(expected, actual);
}

const sha = (s: string) => crypto.createHash('sha256').update(s).digest('hex');

export async function createSession(pool: Pool, userId: number): Promise<string> {
  const token = crypto.randomBytes(32).toString('base64url');
  await pool.query('insert into sessions (token_hash, user_id, expires_at) values ($1,$2, now() + ($3 || \' days\')::interval)', [sha(token), userId, String(config.sessionDays)]);
  return token;
}

export async function destroySession(pool: Pool, token: string): Promise<void> {
  await pool.query('delete from sessions where token_hash = $1', [sha(token)]);
}

export function bearer(req: Request): string | null {
  const h = req.headers.authorization;
  return h && h.startsWith('Bearer ') ? h.slice(7) : null;
}

export function authMiddleware(pool: Pool) {
  return async (req: Request, _res: Response, next: NextFunction) => {
    try {
      const token = bearer(req);
      if (token) {
        const r = await pool.query(
          `select u.id, u.email, u.role, u.display_name from sessions s join users u on u.id = s.user_id
           where s.token_hash = $1 and s.expires_at > now()`, [sha(token)]);
        if (r.rowCount) {
          const u = r.rows[0];
          req.user = { id: Number(u.id), email: u.email, role: u.role, displayName: u.display_name };
        }
      }
      next();
    } catch (e) {
      next(e);
    }
  };
}

export function requireUser(req: Request, res: Response, next: NextFunction) {
  if (!req.user) return res.status(401).json({ code: 'unauthorized' });
  next();
}

export function requireModerator(req: Request, res: Response, next: NextFunction) {
  if (!req.user) return res.status(401).json({ code: 'unauthorized' });
  if (req.user.role !== 'moderator') return res.status(403).json({ code: 'forbidden_role' });
  next();
}

/** Tiny in-memory limiter: enough to slow guessing and spam on one node. */
export function rateLimit(max: number, windowMs: number) {
  const hits = new Map<string, number[]>();
  return (req: Request, res: Response, next: NextFunction) => {
    if (!config.rateLimit) return next();
    const key = `${req.ip}:${req.path}`;
    const now = Date.now();
    const arr = (hits.get(key) ?? []).filter((t) => now - t < windowMs);
    if (arr.length >= max) return res.status(429).json({ code: 'rate_limited' });
    arr.push(now);
    hits.set(key, arr);
    next();
  };
}

export async function ensureModerator(pool: Pool, email: string, password: string): Promise<'created' | 'promoted' | 'exists'> {
  const e = email.trim().toLowerCase();
  const r = await pool.query('select id, role from users where email = $1', [e]);
  if (r.rowCount) {
    if (r.rows[0].role === 'moderator') return 'exists';
    await pool.query("update users set role = 'moderator' where id = $1", [r.rows[0].id]);
    return 'promoted';
  }
  await pool.query("insert into users (email, password_hash, role, display_name) values ($1,$2,'moderator','Модератор')", [e, hashPassword(password)]);
  return 'created';
}
