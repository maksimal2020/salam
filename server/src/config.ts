import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..', '..');

function list(v: string | undefined, fallback: string[]): string[] {
  return v ? v.split(',').map((s) => s.trim()).filter(Boolean) : fallback;
}

export const config = {
  port: Number(process.env.PORT ?? 3000),
  databaseUrl: process.env.DATABASE_URL ?? 'postgres://app:app@127.0.0.1:5433/migrant',
  contentDirs: list(process.env.CONTENT_DIRS, [path.join(root, 'content')]).map((p) => path.resolve(p)),
  migrationsDir: path.join(root, 'server', 'migrations'),
  webDir: process.env.WEB_DIR ?? path.join(root, 'web', 'dist'),
  // Demo records are shown only while this is true. Turn it off before launch.
  includeDemo: (process.env.INCLUDE_DEMO_CONTENT ?? 'true') === 'true',
  seedModeratorEmail: process.env.SEED_MODERATOR_EMAIL,
  seedModeratorPassword: process.env.SEED_MODERATOR_PASSWORD,
  rateLimit: (process.env.RATE_LIMIT ?? 'on') === 'on',
  // The distance within which a detected position is offered as the user's city.
  locateMaxKm: 70,
  // Farther than this from every listed city we assume the user is outside Russia.
  locateOutsideKm: 700,
  reportsAutoHide: 3,
  sessionDays: 30,
};
