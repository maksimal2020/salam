import { Link } from 'react-router-dom';
import { api, type Listing } from '../api';
import { Empty, ErrorBox, Loading } from '../components';
import { useAsync } from '../hooks';
import { useI18n } from '../i18n';
import { useStore } from '../store';

export function MyAdsPage() {
  const { t, tk, fmtDate } = useI18n();
  const { user, logout } = useStore();
  const res = useAsync(user ? `mine|${user.id}` : null, () => api<{ listings: Listing[] }>('/my/listings'));
  const sent = useAsync(user ? `sent|${user.id}` : null, () => api<{ responses: { id: number; listing_id: number; title: string; message: string; created_at: string }[] }>('/my/responses'));
  if (!user) return <p className="notice"><Link to="/login">{t('ads.loginToAct')}</Link></p>;
  return (
    <section>
      <Link to="/ads" className="back">← {t('common.back')}</Link>
      <h1>{t('ads.mine')}</h1>
      <p className="muted" data-testid="account-email">{user.email}{user.role === 'moderator' ? ` · ${t('mod.title')}` : ''}</p>
      <div className="row">
        <Link className="btn btn-primary btn-small" to="/ads/new">{t('ads.new')}</Link>
        {user.role === 'moderator' && <Link className="btn btn-small" to="/mod">{t('mod.title')}</Link>}
        <button className="btn btn-small btn-link" onClick={() => logout()} data-testid="logout">{t('auth.logout')}</button>
      </div>
      {res.loading && !res.data && <Loading />}
      <ErrorBox error={res.error} onRetry={res.reload} />
      {res.data && res.data.listings.length === 0 && <Empty>{t('ads.empty')}</Empty>}
      <div className="stack">
        {res.data?.listings.map((l) => (
          <Link key={l.id} to={`/ads/${l.id}`} className="card card-user card-link" data-testid="my-ad" data-id={l.id}>
            <div className="badges"><span className={`tag tag-status-${l.status}`}>{tk('ads.status', l.status)}</span><span className="tag">{tk('ads.cat', l.category)}</span></div>
            <h3>{l.title}</h3>
            <p className="muted small">{t('ads.responses')}: {l.response_count ?? 0}{l.expires_at ? ` · ${t('ads.until', { date: fmtDate(l.expires_at) })}` : ''}</p>
            {l.moderation_note && <p className="small">{t('ads.rejectedReason', { reason: l.moderation_note })}</p>}
          </Link>
        ))}
      </div>
      {sent.data && sent.data.responses.length > 0 && (
        <>
          <h2>{t('ads.respond')}</h2>
          <ul className="list-plain">{sent.data.responses.map((r) => <li key={r.id} className="card"><Link to={`/ads/${r.listing_id}`}>{r.title}</Link><p className="small preline">{r.message}</p></li>)}</ul>
        </>
      )}
    </section>
  );
}
