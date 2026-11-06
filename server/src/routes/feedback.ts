import { Router } from 'express';
import { z } from 'zod';
import type { Pool } from '../db.js';
import { LANGS } from '../content.js';
import { rateLimit, requireModerator } from '../auth.js';

const FeedbackInput = z.object({
  message: z.string().trim().min(5).max(4000),
  email: z.string().trim().max(200).optional().nullable(),
  lang: z.enum(LANGS).optional(),
});

export interface FeedbackDeps {
  pool: Pool;
}

/**
 * Обратная связь: «сообщите о неточности — проверим и исправим» + пожелания, что добавить.
 * Отправить может любой пользователь, авторизация не нужна (но если вошёл — сохраняем, кто написал).
 */
export function feedbackRoutes({ pool }: FeedbackDeps): Router {
  const r = Router();

  r.post('/feedback', rateLimit(10, 60_000), async (req, res) => {
    const parsed = FeedbackInput.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ code: 'validation', fields: parsed.error.issues.map((i) => i.path.join('.')) });
    const v = parsed.data;
    await pool.query(
      `insert into feedback (user_id, email, message, lang) values ($1, $2, $3, $4)`,
      [req.user?.id ?? null, v.email?.trim() || null, v.message, v.lang ?? null],
    );
    res.status(201).json({ ok: true });
  });

  // ---------------- moderation (moderator role): просмотр и отметка «обработано»
  const mod = Router();
  mod.use(requireModerator);

  mod.get('/feedback', async (req, res) => {
    const status = req.query.status === 'resolved' ? 'resolved' : 'new';
    const rows = (await pool.query(
      `select f.id, f.message, f.email, f.lang, f.status, f.created_at, u.email as user_email
       from feedback f left join users u on u.id = f.user_id
       where f.status = $1 order by f.created_at desc limit 200`,
      [status],
    )).rows;
    const counts = (await pool.query(`select count(*)::int as n from feedback where status = 'new'`)).rows[0];
    res.json({
      feedback: rows.map((f) => ({
        id: Number(f.id), message: f.message, email: f.email ?? f.user_email ?? null,
        lang: f.lang, status: f.status, createdAt: f.created_at,
      })),
      newCount: counts.n,
    });
  });

  mod.post('/feedback/:id/resolve', async (req, res) => {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) return res.status(404).json({ code: 'not_found' });
    const r2 = await pool.query(`update feedback set status = 'resolved' where id = $1 returning id`, [id]);
    if (!r2.rowCount) return res.status(404).json({ code: 'not_found' });
    res.json({ id, status: 'resolved' });
  });

  r.use('/mod', mod);
  return r;
}
