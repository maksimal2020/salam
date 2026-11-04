import express, { type NextFunction, type Request, type Response } from 'express';
import fs from 'node:fs';
import path from 'node:path';
import type { Pool } from './db.js';
import { config } from './config.js';
import { authMiddleware } from './auth.js';
import { TextChecker } from './textcheck.js';
import { importContent, loadContent } from './content.js';
import { publicRoutes } from './routes/public.js';
import { adsRoutes } from './routes/ads.js';
import { accountRoutes } from './routes/account.js';

export function createApp(pool: Pool) {
  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', true);
  app.use(express.json({ limit: '64kb' }));

  // Method, path and status only: never request bodies (they may hold a position) and never query strings.
  app.use((req, res, next) => {
    res.on('finish', () => { if (process.env.NODE_ENV !== 'test') console.log(`${req.method} ${req.path} ${res.statusCode}`); });
    next();
  });
  app.use(authMiddleware(pool));

  let checker: Promise<TextChecker> | null = null;
  const getChecker = () => (checker ??= pool.query("select value from settings where key = 'moderation'").then((r) => new TextChecker(r.rows[0]?.value ?? {})));
  const reloadContent = async () => {
    await importContent(pool, loadContent(config.contentDirs));
    checker = null;
  };

  const api = express.Router();
  api.use(publicRoutes(pool));
  api.use(adsRoutes({ pool, checker: getChecker }));
  api.use(accountRoutes({ pool, reloadContent }));
  api.use((_req, res) => res.status(404).json({ code: 'not_found' }));
  app.use('/api', api);

  // The built interface (if present) is served from the same address.
  if (fs.existsSync(path.join(config.webDir, 'index.html'))) {
    app.use(express.static(config.webDir, { index: false, maxAge: '1h', setHeaders: (res, p) => { if (/sw\.js$|index\.html$|manifest/.test(p)) res.setHeader('Cache-Control', 'no-cache'); } }));
    app.get('*', (_req, res) => { res.setHeader('Cache-Control', 'no-cache'); res.sendFile(path.join(config.webDir, 'index.html')); });
  }

  app.use((err: any, _req: Request, res: Response, _next: NextFunction) => {
    if (err?.type === 'entity.parse.failed') return res.status(400).json({ code: 'validation' });
    console.error(err?.message ?? err);
    res.status(500).json({ code: 'server_error' });
  });
  return { app, reloadContent };
}
