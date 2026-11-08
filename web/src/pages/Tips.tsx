import { useState } from 'react';
import { api, qs } from '../api';
import { Empty, ErrorBox, Loading } from '../components';
import { useAsync, useDebounced } from '../hooks';
import { useI18n } from '../i18n';
import { useStore } from '../store';

interface Tip { id: string; topic: string; updated_at: string; title: string; body: string; city: { id: string; name: string; region: string } | null }
const TOPICS = ['housing', 'groceries', 'clothes', 'secondhand', 'transport', 'mobile', 'sim', 'banking', 'jobsearch', 'scams', 'legal'];

export function TipsPage() {
  const { t, tk, lang, fmtDate } = useI18n();
  const { city, openCityPicker } = useStore();
  const [q, setQ] = useState('');
  const [topic, setTopic] = useState('');
  const [local, setLocal] = useState(false);
  const dq = useDebounced(q, 200);
  const res = useAsync(`${lang}|${city?.id ?? ''}|${dq}|${topic}|${local}`, () => api<{ tips: Tip[] }>(`/tips${qs({ lang, city: city?.id, q: dq, topic, local: local && !!city && '1' })}`));

  return (
    <section>
      <h1>{t('tips.title')}</h1>
      <div className="row">
        <button className="chip chip-city" onClick={openCityPicker} data-testid="tips-city">{city ? `${city.name}, ${city.region}` : t('city.none')}</button>
        <label className="choice"><input type="checkbox" checked={local} disabled={!city} onChange={(e) => setLocal(e.target.checked)} data-testid="tips-local" /> {t('tips.thisCity')}</label>
      </div>
      <input type="search" className="input" value={q} onChange={(e) => setQ(e.target.value)} placeholder={t('tips.search')} aria-label={t('tips.search')} data-testid="tips-search" />
      <div className="chips" role="group">
        <button className={`chip${topic === '' ? ' is-on' : ''}`} aria-pressed={topic === ''} onClick={() => setTopic('')}>{t('tips.allTopics')}</button>
        {TOPICS.map((x) => <button key={x} className={`chip${topic === x ? ' is-on' : ''}`} aria-pressed={topic === x} onClick={() => setTopic(x)}>{tk('topic', x)}</button>)}
      </div>
      {res.loading && !res.data && <Loading />}
      <ErrorBox error={res.error} onRetry={res.reload} />
      {res.data && res.data.tips.length === 0 && <Empty>{t('tips.empty')}</Empty>}
      <div className="stack">
        {res.data?.tips.map((tip) => (
          <article key={tip.id} className="card card-editorial" data-testid="tip" data-id={tip.id}>
            <div className="badges">
              <span className="tag tag-editorial">{t('badge.editorial')}</span>
              <span className="tag">{tk('topic', tip.topic)}</span>
              <span className="tag">{tip.city ? t('tips.cityOnly', { city: `${tip.city.name}, ${tip.city.region}` }) : t('tips.general')}</span>
            </div>
            <h3>{tip.title}</h3>
            <p>{tip.body}</p>
            <p className="muted small">{t('common.updated', { date: fmtDate(tip.updated_at) })}</p>
          </article>
        ))}
      </div>
    </section>
  );
}
