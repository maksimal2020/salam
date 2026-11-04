import { useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { ApiError, api, type Listing } from '../api';
import { ErrorBox, Loading } from '../components';
import { useAsync } from '../hooks';
import { LANGS, useI18n } from '../i18n';
import { useStore } from '../store';

interface Resp { id: number; message: string; contact: string | null; created_at: string }

export function AdPage() {
  const { id = '' } = useParams();
  const { t, tk, fmtDate } = useI18n();
  const { user } = useStore();
  const nav = useNavigate();
  const ad = useAsync(`${id}|${user?.id ?? 0}`, () => api<Listing>(`/listings/${id}`));
  const a = ad.data;
  const mine = a && user && a.moderation_note !== undefined; // owner fields are present only for the author
  const responses = useAsync(mine ? `r|${id}` : null, () => api<{ responses: Resp[] }>(`/my/listings/${id}/responses`));

  const [message, setMessage] = useState('');
  const [contact, setContact] = useState('');
  const [sent, setSent] = useState(false);
  const [err, setErr] = useState<ApiError | null>(null);
  const [reportOpen, setReportOpen] = useState(false);
  const [reason, setReason] = useState('');
  const [reported, setReported] = useState(false);

  if (ad.loading && !a) return <Loading />;
  if (ad.error) return <ErrorBox error={ad.error} onRetry={ad.reload} />;
  if (!a) return null;

  async function respond(e: React.FormEvent) {
    e.preventDefault(); setErr(null);
    try { await api(`/listings/${id}/respond`, { method: 'POST', body: { message, contact: contact || null } }); setSent(true); setMessage(''); setContact(''); }
    catch (x) { setErr(x as ApiError); }
  }
  async function report(e: React.FormEvent) {
    e.preventDefault(); setErr(null);
    try { await api(`/listings/${id}/report`, { method: 'POST', body: { reason } }); setReported(true); setReportOpen(false); }
    catch (x) { setErr(x as ApiError); }
  }
  async function withdraw() {
    try { await api(`/listings/${id}/withdraw`, { method: 'POST', body: {} }); nav('/ads/mine'); } catch (x) { setErr(x as ApiError); }
  }

  const live = a.status === 'published';
  return (
    <article className="card card-user detail">
      <Link to="/ads" className="back">← {t('common.back')}</Link>
      <div className="badges">
        <span className="tag tag-user">{t('badge.user')}</span>
        <span className="tag">{tk('ads.cat', a.category)}</span>
        <span className="tag" lang={a.lang} data-testid="ad-lang">{t('ads.lang')}: {LANGS.find((x) => x.code === a.lang)?.native}</span>
        {mine && <span className={`tag tag-status-${a.status}`} data-testid="ad-status">{tk('ads.status', a.status)}</span>}
      </div>
      <h1 lang={a.lang} data-testid="ad-title">{a.title}</h1>
      <p className="muted">{a.city.name}, {a.city.region}{a.price ? ` · ${a.price}` : ''}</p>
      {a.category === 'work' && (
        <dl className="facts">
          {a.extra.employer && (<><dt>{t('ads.field.employer')}</dt><dd>{a.extra.employer}</dd></>)}
          {a.extra.pay && (<><dt>{t('ads.field.pay')}</dt><dd>{a.extra.pay}</dd></>)}
          {a.extra.schedule && (<><dt>{t('ads.field.schedule')}</dt><dd>{a.extra.schedule}</dd></>)}
          {a.extra.terms && (<><dt>{t('ads.field.terms')}</dt><dd>{a.extra.terms}</dd></>)}
        </dl>
      )}
      <p className="preline" lang={a.lang}>{a.body}</p>
      {a.published_at && <p className="muted small">{t('ads.published', { date: fmtDate(a.published_at) })}{a.expires_at ? ` · ${t('ads.until', { date: fmtDate(a.expires_at) })}` : ''}</p>}
      {mine && a.status === 'pending' && <p className="notice">{t('ads.pendingNote')}</p>}
      {mine && a.moderation_note && <p className="notice notice-error">{t('ads.rejectedReason', { reason: a.moderation_note })}</p>}

      {mine && (
        <div className="row">
          {['pending', 'published', 'rejected'].includes(a.status) && <Link className="btn btn-small" to={`/ads/${a.id}/edit`} data-testid="ad-edit">{t('ads.edit')}</Link>}
          {['pending', 'published'].includes(a.status) && <button className="btn btn-small" onClick={withdraw} data-testid="ad-withdraw">{t('ads.withdraw')}</button>}
        </div>
      )}
      <ErrorBox error={err} />

      {mine && (
        <section data-testid="responses">
          <h2>{t('ads.responses')}</h2>
          {responses.data && responses.data.responses.length === 0 && <p className="muted">{t('ads.noResponses')}</p>}
          <ul className="list-plain">
            {responses.data?.responses.map((r) => (
              <li key={r.id} className="card"><p className="preline">{r.message}</p>{r.contact && <p className="small"><strong>{r.contact}</strong></p>}<p className="muted small">{fmtDate(r.created_at)}</p></li>
            ))}
          </ul>
        </section>
      )}

      {!mine && live && (
        <>
          {!user && <p className="notice"><Link to="/login" state={{ from: `/ads/${id}` }}>{t('ads.loginToAct')}</Link></p>}
          {user && !sent && (
            <form className="stack" onSubmit={respond} data-testid="respond-form">
              <h2>{t('ads.respond')}</h2>
              <label className="field"><span>{t('ads.respondMessage')}</span><textarea className="input" rows={4} required minLength={2} maxLength={2000} value={message} onChange={(e) => setMessage(e.target.value)} data-testid="respond-message" /></label>
              <label className="field"><span>{t('ads.respondContact')}</span><input className="input" maxLength={200} value={contact} onChange={(e) => setContact(e.target.value)} data-testid="respond-contact" /></label>
              <p className="muted small">{t('ads.respondHint')}</p>
              <button className="btn btn-primary" type="submit" data-testid="respond-send">{t('ads.respond')}</button>
            </form>
          )}
          {sent && <p className="notice notice-ok" role="status" data-testid="respond-sent">{t('ads.respondSent')}</p>}
          {user && !reported && !reportOpen && <button className="btn btn-link" onClick={() => setReportOpen(true)} data-testid="report-open">{t('ads.report')}</button>}
          {reportOpen && (
            <form className="stack" onSubmit={report} data-testid="report-form">
              <label className="field"><span>{t('ads.reportReason')}</span><textarea className="input" rows={3} required minLength={3} maxLength={500} value={reason} onChange={(e) => setReason(e.target.value)} data-testid="report-reason" /></label>
              <button className="btn" type="submit" data-testid="report-send">{t('ads.report')}</button>
            </form>
          )}
          {reported && <p className="notice notice-ok" role="status" data-testid="report-sent">{t('ads.reportSent')}</p>}
        </>
      )}
    </article>
  );
}
