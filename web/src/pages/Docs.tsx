import { useState } from 'react';
import { Link } from 'react-router-dom';
import { api, qs, type DocBrief } from '../api';
import { Empty, ErrorBox, Loading, Necessity, Stamp } from '../components';
import { useAsync, useDebounced } from '../hooks';
import { useI18n } from '../i18n';
import { useStore } from '../store';

export function DocsPage() {
  const { t, lang } = useI18n();
  const { meta, marks } = useStore();
  const [q, setQ] = useState('');
  const [situation, setSituation] = useState('');
  const dq = useDebounced(q, 200);
  const docs = useAsync(`${lang}|${dq}|${situation}`, () => api<{ documents: DocBrief[] }>(`/documents${qs({ lang, q: dq, situation })}`));
  const done = Object.values(marks).filter(Boolean).length;

  return (
    <section>
      <h1>{t('docs.title')}</h1>
      <Link to="/list" className="card card-cta" data-testid="my-list-link">
        <strong>{t('docs.myList')}</strong>
        <span className="muted">{done > 0 ? t('list.progress', { done, total: Object.keys(marks).length }) : t('docs.myListHint')}</span>
      </Link>
      <input type="search" className="input" value={q} onChange={(e) => setQ(e.target.value)} placeholder={t('docs.search')} aria-label={t('docs.search')} data-testid="docs-search" />
      <div className="chips" role="group">
        <button className={`chip${situation === '' ? ' is-on' : ''}`} onClick={() => setSituation('')} aria-pressed={situation === ''}>{t('common.all')}</button>
        {meta?.situations.map((s) => (
          <button key={s.id} className={`chip${situation === s.id ? ' is-on' : ''}`} onClick={() => setSituation(s.id)} aria-pressed={situation === s.id} data-situation={s.id}>{s.name}</button>
        ))}
      </div>
      {docs.loading && !docs.data && <Loading />}
      <ErrorBox error={docs.error} onRetry={docs.reload} />
      {docs.data && docs.data.documents.length === 0 && <Empty>{t('common.empty')}</Empty>}
      <div className="stack">
        {docs.data?.documents.map((d) => (
          <Link key={d.id} to={`/docs/${d.id}`} className="card card-official card-link" data-testid="doc-card" data-id={d.id}>
            <div className="card-head">
              <h3>{d.title}</h3>
              <div className="badges"><Necessity value={d.necessity} /><Stamp status={d.status} /></div>
            </div>
            <p>{d.summary}</p>
          </Link>
        ))}
      </div>
    </section>
  );
}
