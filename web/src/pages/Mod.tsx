import { useState } from 'react';
import { Link } from 'react-router-dom';
import { ApiError, api, type Listing } from '../api';
import { Empty, ErrorBox, Loading } from '../components';
import { useAsync } from '../hooks';
import { useI18n } from '../i18n';
import { useStore } from '../store';

type Kind = 'pending' | 'reported' | 'recent';
interface Queue { listings: Listing[]; counts: { pending: number; reported: number; recent: number } }

export function ModPage() {
  const { t, tk, fmtDate } = useI18n();
  const { user } = useStore();
  const [kind, setKind] = useState<Kind>('pending');
  const [reasons, setReasons] = useState<Record<number, string>>({});
  const [err, setErr] = useState<ApiError | null>(null);
  const q = useAsync(user?.role === 'moderator' ? `mod|${kind}` : null, () => api<Queue>(`/mod/queue?kind=${kind}`));

  if (!user) return <p className="notice"><Link to="/login" state={{ from: '/mod' }}>{t('auth.login')}</Link></p>;
  if (user.role !== 'moderator') return <p className="notice notice-error">{t('error.notFound')}</p>;

  async function act(id: number, action: string, needsReason: boolean) {
    setErr(null);
    try {
      await api(`/mod/listings/${id}/${action}`, { method: 'POST', body: needsReason ? { reason: reasons[id] ?? '' } : {} });
      q.reload();
    } catch (x) { setErr(x as ApiError); }
  }

  return (
    <section>
      <h1>{t('mod.title')}</h1>
      <div className="chips" role="group">
        {(['pending', 'reported', 'recent'] as Kind[]).map((k) => (
          <button key={k} className={`chip${kind === k ? ' is-on' : ''}`} aria-pressed={kind === k} onClick={() => setKind(k)} data-kind={k}>
            {t(`mod.${k}`)}{q.data ? ` (${q.data.counts[k]})` : ''}
          </button>
        ))}
      </div>
      {q.loading && !q.data && <Loading />}
      <ErrorBox error={q.error ?? err} onRetry={q.reload} />
      {q.data && q.data.listings.length === 0 && <Empty>{t('mod.empty')}</Empty>}
      <div className="stack">
        {q.data?.listings.map((l) => (
          <article key={l.id} className="card card-user" data-testid="mod-item" data-id={l.id}>
            <div className="badges"><span className="tag">{tk('ads.cat', l.category)}</span><span className={`tag tag-status-${l.status}`}>{tk('ads.status', l.status)}</span>
              {(l.report_count ?? 0) > 0 && <span className="tag tag-danger">{t('mod.reports', { n: l.report_count ?? 0 })}</span>}</div>
            <h3 lang={l.lang}>{l.title}</h3>
            <p className="muted small">{l.author_email} · {l.city.name} · {fmtDate(l.created_at)}</p>
            <p className="preline" lang={l.lang}>{l.body}</p>
            {l.category === 'work' && <p className="small">{[l.extra.employer, l.extra.pay, l.extra.schedule, l.extra.terms].filter(Boolean).join(' · ')}</p>}
            {l.reports && l.reports.length > 0 && <ul>{l.reports.map((r) => <li key={r.id} className="small">{r.reason}</li>)}</ul>}
            <label className="field"><span>{t('mod.reason')}</span>
              <input className="input" value={reasons[l.id] ?? ''} onChange={(e) => setReasons({ ...reasons, [l.id]: e.target.value })} data-testid="mod-reason" /></label>
            <div className="row">
              {l.status !== 'hidden' && <button className="btn btn-small btn-primary" onClick={() => act(l.id, 'approve', false)} data-testid="mod-approve">{t('mod.approve')}</button>}
              {l.status === 'hidden' && <button className="btn btn-small btn-primary" onClick={() => act(l.id, 'restore', false)} data-testid="mod-restore">{t('mod.restore')}</button>}
              <button className="btn btn-small" onClick={() => act(l.id, 'reject', true)} data-testid="mod-reject">{t('mod.reject')}</button>
              {l.status !== 'hidden' && <button className="btn btn-small" onClick={() => act(l.id, 'hide', true)} data-testid="mod-hide">{t('mod.hide')}</button>}
            </div>
          </article>
        ))}
      </div>
    </section>
  );
}
