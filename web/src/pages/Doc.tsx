import { Link, useParams } from 'react-router-dom';
import { api, type DocFull } from '../api';
import { ErrorBox, Loading, Necessity, SourceList, Stamp } from '../components';
import { useAsync } from '../hooks';
import { useI18n } from '../i18n';

export function DocPage() {
  const { id = '' } = useParams();
  const { t, lang } = useI18n();
  const doc = useAsync(`${id}|${lang}`, () => api<DocFull>(`/documents/${id}?lang=${lang}`));
  if (doc.loading && !doc.data) return <Loading />;
  if (doc.error) return <ErrorBox error={doc.error} onRetry={doc.reload} />;
  const d = doc.data!;
  const unconfirmed = <em>{t('docs.notConfirmed')}</em>;
  return (
    <article className="doc">
      <Link to="/docs" className="back">← {t('common.back')}</Link>
      <h1>{d.title}</h1>
      <div className="badges"><Necessity value={d.necessity} /><Stamp status={d.status} /></div>
      {d.status === 'demo' && <p className="notice notice-demo" data-testid="demo-warning">{t('docs.demoWarning')}</p>}
      {d.details_fallback && <p className="notice">{t('docs.fallbackNote')}</p>}

      <h2>{t('docs.purpose')}</h2>
      <p>{d.summary}</p>
      {d.details.who && (<><h2>{t('docs.who')}</h2><p>{d.details.who}</p></>)}
      {d.details.prepare && (<><h2>{t('docs.prepare')}</h2><ul>{d.details.prepare.map((x) => <li key={x}>{x}</li>)}</ul></>)}
      {d.details.how && (<><h2>{t('docs.how')}</h2><ol>{d.details.how.map((x) => <li key={x}>{x}</li>)}</ol></>)}
      {d.details.renewal && (<><h2>{t('docs.renewal')}</h2><p>{d.details.renewal}</p></>)}

      <h2>{t('docs.deadline')}</h2>
      <p data-testid="doc-deadline">{d.deadline ? (d.deadline[lang] ?? d.deadline.ru) : unconfirmed}</p>
      <h2>{t('docs.cost')}</h2>
      <p data-testid="doc-cost">{d.cost ? (d.cost[lang] ?? d.cost.ru) : unconfirmed}</p>

      <h2>{t('docs.sources')}</h2>
      <SourceList sources={d.sources} checkedAt={d.checked_at} />

      <div className="sticky-cta">
        <Link to={`/docs/${d.id}/where`} className="btn btn-primary" data-testid="where-button">{t('docs.whereButton')}</Link>
      </div>
    </article>
  );
}
