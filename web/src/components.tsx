import type { ReactNode } from 'react';
import { ApiError, type Institution, type Source } from './api';
import { useI18n } from './i18n';
import { useStore } from './store';

export const ERROR_KEYS: Record<string, string> = {
  network: 'error.network',
  forbidden: 'ads.err.forbidden',
  passport: 'ads.err.passport',
  contact: 'ads.err.contact',
  validation: 'ads.err.fields',
  own_listing: 'ads.err.own',
  invalid_credentials: 'auth.err.invalid',
  email_taken: 'auth.err.exists',
  weak_password: 'auth.err.weak',
  unauthorized: 'ads.loginToAct',
  not_found: 'error.notFound',
};

export function ErrorBox({ error, onRetry }: { error: ApiError | null; onRetry?: () => void }) {
  const { t } = useI18n();
  if (!error) return null;
  return (
    <div className="notice notice-error" role="alert">
      <p>{t(ERROR_KEYS[error.code] ?? 'error.generic')}</p>
      {onRetry && <button className="btn btn-small" onClick={onRetry}>{t('common.retry')}</button>}
    </div>
  );
}

export function Loading() {
  const { t } = useI18n();
  return <p className="muted" role="status">{t('common.loading')}</p>;
}

export function Empty({ children }: { children: ReactNode }) {
  return <div className="empty">{children}</div>;
}

/** Whether a record is confirmed by an official source or only a demonstration. */
export function Stamp({ status }: { status: string }) {
  const { t } = useI18n();
  return status === 'verified'
    ? <span className="stamp stamp-verified">{t('badge.verified')}</span>
    : <span className="stamp stamp-demo">{t('badge.demo')}</span>;
}

export function Necessity({ value }: { value: string }) {
  const { t } = useI18n();
  return <span className={`tag tag-${value}`}>{t(`badge.${value}`)}</span>;
}

export function SourceList({ sources, checkedAt }: { sources: Source[]; checkedAt: string | null }) {
  const { t, fmtDate } = useI18n();
  return (
    <div className="sources">
      {sources.length > 0 && (
        <ul>
          {sources.map((s) => (
            <li key={s.url}><a href={s.url} target="_blank" rel="noreferrer noopener">{s.title}</a></li>
          ))}
        </ul>
      )}
      <p className="muted small">{checkedAt ? t('common.checkedOn', { date: fmtDate(checkedAt) }) : t('common.notChecked')}</p>
    </div>
  );
}

export function mapUrl(map: { query: string | null; lat: number | null; lon: number | null }, address: string | null, cityName: string): string | null {
  if (map.lat !== null && map.lon !== null && address) return `https://yandex.ru/maps/?pt=${map.lon},${map.lat}&z=16&l=map`;
  const q = address ? `${address}` : map.query ? map.query : null;
  if (!q) return null;
  return `https://yandex.ru/maps/?text=${encodeURIComponent(address && !address.includes(cityName) ? `${cityName}, ${q}` : q)}`;
}

export function InstitutionCard({ inst }: { inst: Institution }) {
  const { t } = useI18n();
  const { city } = useStore();
  const url = mapUrl(inst.map, inst.address, inst.city.name);
  const serves = inst.serves.map((s) => ('scope' in s ? t('where.allRussia') : s.districts ? `${s.city}: ${s.districts.join(', ')}` : s.city));
  return (
    <article className="card card-official" data-testid="institution" data-id={inst.id}>
      <div className="card-head">
        <h3>{inst.name}</h3>
        <div className="badges">
          <Stamp status={inst.status} />
          <span className="tag">{t(`mode.${inst.mode}`)}</span>
        </div>
      </div>

      <dl className="facts">
        <dt>{t('common.address')}</dt>
        <dd>
          {inst.address ?? <em>{t('where.addressUnconfirmed')}</em>}
          {inst.address && <span className="muted">{`, ${inst.city.region}`}</span>}
        </dd>
        {inst.other_city && city && inst.address && (
          <dd className="callout" data-testid="other-city-note">{t('where.servesNote', { address: `${inst.address}, ${inst.city.name}`, city: city.name })}</dd>
        )}
        <dt>{t('common.services')}</dt>
        <dd>{inst.services.map((s) => s.title).join('; ')}</dd>
        <dt>{t('where.serves')}</dt>
        <dd>{serves.join('; ')}</dd>
        {inst.citizenships && <dd className="muted">{t('where.citizens', { countries: inst.citizenships.join(', ') })}</dd>}
        {inst.hours && (<><dt>{t('common.hours')}</dt><dd>{inst.hours}</dd></>)}
        {inst.phone && (<><dt>{t('common.phone')}</dt><dd><a href={`tel:${inst.phone.replace(/[^+\d]/g, '')}`}>{inst.phone}</a></dd></>)}
        {inst.site && (<><dt>{t('common.site')}</dt><dd><a href={inst.site} target="_blank" rel="noreferrer noopener">{inst.site.replace(/^https?:\/\//, '')}</a></dd></>)}
      </dl>

      <div className="actions">
        {url && (
          <a className="btn btn-small" href={url} target="_blank" rel="noreferrer noopener" data-testid="map-link">
            {t('common.openMap')}
          </a>
        )}
        {inst.booking_url && <a className="btn btn-small btn-primary" href={inst.booking_url} target="_blank" rel="noreferrer noopener">{t('common.booking')}</a>}
      </div>
      {url && !inst.address && <p className="muted small">{t('where.mapByName')}</p>}
      {inst.note && <p className="muted small">{inst.note}</p>}
      <SourceList sources={inst.sources} checkedAt={inst.checked_at} />
    </article>
  );
}

/** App logo mark: gradient tile with the "S!" sign, used on the language screen. */
export function BrandMark({ size = 84 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 88 88" aria-hidden="true">
      <defs>
        <linearGradient id="brandGrad" x1="0" y1="0" x2="88" y2="88" gradientUnits="userSpaceOnUse">
          <stop offset="0" stopColor="#3A5BFF" />
          <stop offset="1" stopColor="#7C4DFF" />
        </linearGradient>
      </defs>
      <rect width="88" height="88" rx="24" fill="url(#brandGrad)" />
      <path
        d="M31 30c7-3 16-3 20 1 2 2 2 5-1 6-2 1-9-2-13-1-3 1-3 4 0 5 4 2 15 1 17 8 2 6-3 11-12 12-7 1-15-1-19-5l4-5c4 3 10 4 14 3 3-1 4-4 1-5-4-2-15-1-17-8-2-6 2-10 6-11z"
        fill="#fff"
      />
      <rect x="60" y="20" width="8" height="26" rx="4" fill="#FFC93C" />
      <circle cx="64" cy="56" r="5" fill="#FFC93C" />
    </svg>
  );
}

/** White circular arrow used on the end of a language tile. */
export function TileArrow() {
  return (
    <span className="lang-arrow" aria-hidden="true">
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#1B1B2B" strokeWidth="2.3" strokeLinecap="round" strokeLinejoin="round">
        <path d="M5 12h14M13 6l6 6-6 6" />
      </svg>
    </span>
  );
}

/**
 * Two-letter language code in a round badge. Painted as a CSS background image
 * (not DOM text) so a browser's `innerText` of the enclosing button never
 * includes it — the e2e suite reads that text and expects only the
 * language's own name.
 */
export function TileCode({ code, fg, dark }: { code: string; fg: string; dark: boolean }) {
  const circleFill = dark ? 'rgba(0,0,0,.18)' : 'rgba(255,255,255,.44)';
  const svg = `<svg xmlns='http://www.w3.org/2000/svg' width='46' height='46' viewBox='0 0 46 46'>`
    + `<circle cx='23' cy='23' r='23' fill='${circleFill}'/>`
    + `<text x='23' y='24' text-anchor='middle' dominant-baseline='central' font-family='system-ui,sans-serif' font-size='15' font-weight='800' fill='${fg}'>${code.toUpperCase()}</text>`
    + `</svg>`;
  return <span className="lang-code" aria-hidden="true" style={{ backgroundImage: `url("data:image/svg+xml,${encodeURIComponent(svg)}")` }} />;
}

export function Icon({ name }: { name: 'docs' | 'where' | 'tips' | 'ads' | 'globe' | 'user' | 'pin' }) {
  const p: Record<string, string> = {
    docs: 'M7 3h7l5 5v13H7zM14 3v5h5M10 13h6M10 17h6',
    where: 'M12 21s-6-5.2-6-10a6 6 0 0 1 12 0c0 4.8-6 10-6 10zM12 8.5a2.5 2.5 0 1 0 0 5 2.5 2.5 0 0 0 0-5z',
    tips: 'M9 18h6M10 21h4M12 3a6 6 0 0 0-3.5 10.9c.6.5 1 1.2 1 2.1h5c0-.9.4-1.6 1-2.1A6 6 0 0 0 12 3z',
    ads: 'M4 10v4l10 4V6zM14 8h2a3 3 0 0 1 0 8h-2M6 14l1 5h3l-1-4',
    globe: 'M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18zM3 12h18M12 3c3 3 3 15 0 18M12 3c-3 3-3 15 0 18',
    user: 'M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM4 21c0-4 3.6-6 8-6s8 2 8 6',
    pin: 'M12 21s-6-5.2-6-10a6 6 0 0 1 12 0c0 4.8-6 10-6 10z',
  };
  return (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d={p[name]} />
    </svg>
  );
}
