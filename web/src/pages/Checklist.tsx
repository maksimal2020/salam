import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { api, type DocBrief, type Source } from '../api';
import { ErrorBox, Loading, Necessity, Stamp } from '../components';
import { useAsync } from '../hooks';
import { useI18n } from '../i18n';
import { useStore, type Profile } from '../store';

interface Result {
  items: DocBrief[];
  clarify: ({ type: 'missing'; field: string } | { type: 'other_country' } | { type: 'depends_on_citizenship'; docId: string; title: string })[];
  where_to_check: Source[];
  includes_demo: boolean;
}

export function ChecklistPage() {
  const { t, lang } = useI18n();
  const { meta, profile, setProfile, city, marks, toggleMark, openCityPicker } = useStore();
  const [draft, setDraft] = useState<Profile>(profile);
  const complete = !!(profile.citizenship && profile.purpose && profile.stage);
  const [editing, setEditing] = useState(!complete);
  useEffect(() => { setDraft(profile); }, [profile]);

  const key = complete && !editing ? `${lang}|${JSON.stringify(profile)}` : null;
  const res = useAsync(key, () => api<Result>('/checklist', { method: 'POST', body: { ...profile, lang } }));
  const r = res.data;
  const done = r ? r.items.filter((i) => marks[i.id]).length : 0;
  const ref = meta?.reference;

  function submit(e: React.FormEvent) {
    e.preventDefault();
    setProfile(draft);
    setEditing(!(draft.citizenship && draft.purpose && draft.stage));
  }

  return (
    <section>
      <Link to="/docs" className="back">← {t('common.back')}</Link>
      <h1>{t('list.title')}</h1>

      {editing && (
        <form className="stack" onSubmit={submit} data-testid="list-form">
          <p className="muted">{t('list.intro')}</p>
          <label className="field">
            <span>{t('list.citizenship')}</span>
            <select className="input" value={draft.citizenship ?? ''} onChange={(e) => setDraft({ ...draft, citizenship: e.target.value || undefined })} data-testid="citizenship-select">
              <option value="">{t('list.chooseCitizenship')}</option>
              {meta?.citizenships.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
            </select>
          </label>
          <fieldset className="field">
            <legend>{t('list.purpose')}</legend>
            {ref?.purposes.map((p) => (
              <label key={p} className="choice"><input type="radio" name="purpose" checked={draft.purpose === p} onChange={() => setDraft({ ...draft, purpose: p })} data-purpose={p} /> {t(`purpose.${p}`)}</label>
            ))}
          </fieldset>
          <fieldset className="field">
            <legend>{t('list.stage')}</legend>
            {ref?.stages.map((s) => (
              <label key={s} className="choice"><input type="radio" name="stage" checked={draft.stage === s} onChange={() => setDraft({ ...draft, stage: s })} data-stage={s} /> {t(`list.stage.${s === 'before' ? 'before' : 'in_russia'}`)}</label>
            ))}
          </fieldset>
          <div className="field">
            <span>{t('list.city')}</span>
            <button type="button" className="chip chip-city" onClick={openCityPicker}>{city ? `${city.name}, ${city.region}` : t('list.noCityYet')}</button>
          </div>
          <fieldset className="field">
            <legend>{t('list.status')}</legend>
            {ref?.flags.map((f) => (
              <label key={f} className="choice">
                <input type="checkbox" checked={!!draft.flags[f]} onChange={(e) => setDraft({ ...draft, flags: { ...draft.flags, [f]: e.target.checked } })} data-flag={f} /> {t(`flag.${f}`)}
              </label>
            ))}
          </fieldset>
          <button className="btn btn-primary" type="submit" data-testid="list-build">{t('list.build')}</button>
        </form>
      )}

      {!editing && (
        <>
          <div className="row">
            <button className="btn btn-small" onClick={() => setEditing(true)} data-testid="list-edit">{t('list.edit')}</button>
            <button className="btn btn-small btn-link" onClick={() => { const empty = { flags: {} }; setProfile(empty); setDraft(empty); setEditing(true); }}>{t('list.reset')}</button>
          </div>
          {res.loading && !r && <Loading />}
          <ErrorBox error={res.error} onRetry={res.reload} />
          {r && (
            <>
              {r.includes_demo && <p className="notice notice-demo">{t('list.demoBanner')}</p>}
              {r.items.length > 0 && (
                <>
                  <p className="progress-label" data-testid="progress">{t('list.progress', { done, total: r.items.length })}</p>
                  <div className="progress" aria-hidden="true"><div style={{ width: `${(done / r.items.length) * 100}%` }} /></div>
                </>
              )}
              {r.items.length === 0 && r.clarify.length === 0 && <p className="empty">{t('list.empty')}</p>}
              <ol className="steps" data-testid="list-items">
                {r.items.map((i) => (
                  <li key={i.id} className={`card card-official step${marks[i.id] ? ' is-done' : ''}`} data-id={i.id}>
                    <label className="step-check">
                      <input type="checkbox" checked={!!marks[i.id]} onChange={() => toggleMark(i.id)} aria-label={t('list.markDone')} />
                    </label>
                    <div className="step-body">
                      <Link to={`/docs/${i.id}`}><strong>{i.title}</strong></Link>
                      <div className="badges"><Necessity value={i.necessity} /><Stamp status={i.status} /></div>
                      <p className="small">{i.summary}</p>
                      <Link className="btn btn-small" to={`/docs/${i.id}/where`}>{t('list.showWhere')}</Link>
                    </div>
                  </li>
                ))}
              </ol>
              {r.clarify.length > 0 && (
                <div className="notice" data-testid="clarify">
                  <h2>{t('list.clarify')}</h2>
                  <p className="muted">{t('list.clarifyHint')}</p>
                  <ul>
                    {r.clarify.map((c, n) => (
                      <li key={n}>
                        {c.type === 'missing' && t(c.field === 'citizenship' ? 'list.citizenship' : c.field === 'purpose' ? 'list.purpose' : 'list.stage')}
                        {c.type === 'other_country' && t('list.otherCountry')}
                        {c.type === 'depends_on_citizenship' && c.title}
                      </li>
                    ))}
                  </ul>
                  <ul>{r.where_to_check.map((s) => <li key={s.url}><a href={s.url} target="_blank" rel="noreferrer noopener">{s.title}</a></li>)}</ul>
                </div>
              )}
            </>
          )}
        </>
      )}
    </section>
  );
}
