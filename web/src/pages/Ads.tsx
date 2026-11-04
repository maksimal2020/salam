import { useState } from 'react';
import { Link } from 'react-router-dom';
import { api, qs, type Listing } from '../api';
import { Empty, ErrorBox, Loading } from '../components';
import { useAsync, useDebounced } from '../hooks';
import { LANGS, useI18n } from '../i18n';
import { useStore } from '../store';

export const CATEGORIES = ['work', 'housing', 'market', 'services', 'free'] as const;

export function ListingCard({ l }: { l: Listing }) {
  const { t, tk, fmtDate } = useI18n();
  return (
    <Link to={`/ads/${l.id}`} className="card card-user card-link" data-testid="listing-card" data-id={l.id}>
      <div className="badges">
        <span className="tag tag-user">{t('badge.user')}</span>
        <span className="tag">{tk('ads.cat', l.category)}</span>
        <span className="tag" title={t('ads.lang')} lang={l.lang}>{LANGS.find((x) => x.code === l.lang)?.native ?? l.lang}</span>
      </div>
      <h3 lang={l.lang}>{l.title}</h3>
      <p className="muted small">{l.city.name}, {l.city.region}{l.price ? ` · ${l.price}` : ''}{l.extra?.pay ? ` · ${l.extra.pay}` : ''}</p>
      {l.published_at && <p className="muted small">{t('ads.published', { date: fmtDate(l.published_at) })}{l.expires_at ? ` · ${t('ads.until', { date: fmtDate(l.expires_at) })}` : ''}</p>}
    </Link>
  );
}

export function AdsPage() {
  const { t, tk, lang } = useI18n();
  const { city, user, openCityPicker } = useStore();
  const [category, setCategory] = useState('');
  const [q, setQ] = useState('');
  const [allCities, setAllCities] = useState(false);
  const dq = useDebounced(q, 250);
  const cityId = allCities ? undefined : city?.id;
  const res = useAsync(`${category}|${dq}|${cityId ?? ''}`, () => api<{ listings: Listing[] }>(`/listings${qs({ category, q: dq, city: cityId })}`));

  return (
    <section>
      <h1>{t('ads.title')}</h1>
      <div className="row">
        <Link className="btn btn-primary btn-small" to="/ads/new" data-testid="ads-new">{t('ads.new')}</Link>
        {user && <Link className="btn btn-small" to="/ads/mine" data-testid="ads-mine">{t('ads.mine')}</Link>}
        {user?.role === 'moderator' && <Link className="btn btn-small" to="/mod" data-testid="ads-mod">{t('mod.title')}</Link>}
      </div>
      <div className="chips" role="group">
        <button className={`chip${category === '' ? ' is-on' : ''}`} aria-pressed={category === ''} onClick={() => setCategory('')}>{t('common.all')}</button>
        {CATEGORIES.map((c) => <button key={c} className={`chip${category === c ? ' is-on' : ''}`} aria-pressed={category === c} onClick={() => setCategory(c)} data-category={c}>{tk('ads.cat', c)}</button>)}
      </div>
      <input type="search" className="input" value={q} onChange={(e) => setQ(e.target.value)} placeholder={t('ads.search')} aria-label={t('ads.search')} data-testid="ads-search" />
      <div className="row">
        <button className="chip chip-city" onClick={openCityPicker} data-testid="ads-city">{city ? `${city.name}, ${city.region}` : t('city.none')}</button>
        <label className="choice"><input type="checkbox" checked={allCities} onChange={(e) => setAllCities(e.target.checked)} data-testid="ads-all-cities" /> {t('ads.allCities')}</label>
      </div>
      {res.loading && !res.data && <Loading />}
      <ErrorBox error={res.error} onRetry={res.reload} />
      {res.data && res.data.listings.length === 0 && <Empty>{t('ads.empty')}</Empty>}
      <div className="stack" data-lang-ui={lang}>{res.data?.listings.map((l) => <ListingCard key={l.id} l={l} />)}</div>
    </section>
  );
}
