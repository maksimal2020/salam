import { useState } from 'react';
import { api, qs, type Places } from '../api';
import { ErrorBox, InstitutionCard, Loading } from '../components';
import { useAsync } from '../hooks';
import { useI18n } from '../i18n';
import { useStore } from '../store';
import { DistrictSelect, NoPlaces } from './DocWhere';

export function WherePage() {
  const { t, lang } = useI18n();
  const { city, district, setDistrict, profile, openCityPicker } = useStore();
  const [service, setService] = useState('');
  const [mode, setMode] = useState('');
  const key = city ? `${lang}|${city.id}|${district ?? ''}|${service}|${mode}|${profile.citizenship ?? ''}` : null;
  const res = useAsync(key, () => api<Places>(`/institutions${qs({ lang, city: city?.id, district, service, mode, citizenship: profile.citizenship })}`));
  const d = res.data;
  const selected = d?.services?.find((s) => s.id === service);

  return (
    <section>
      <h1>{t('where.title')}</h1>
      <div className="row">
        <button className="chip chip-city" onClick={openCityPicker} data-testid="where-city">{city ? `${city.name}, ${city.region}` : t('city.none')}</button>
      </div>
      {!city && (
        <div className="notice" data-testid="need-city">
          <p>{t('where.noCity')}</p>
          <button className="btn btn-primary" onClick={openCityPicker}>{t('city.manual')}</button>
        </div>
      )}
      {city && (
        <>
          <label className="field">
            <span>{t('where.service')}</span>
            <select className="input" value={service} onChange={(e) => setService(e.target.value)} data-testid="service-filter">
              <option value="">{t('common.all')}</option>
              {d?.services?.map((s) => <option key={s.id} value={s.id}>{s.title}</option>)}
            </select>
          </label>
          <div className="chips" role="group" aria-label={t('where.mode')}>
            {['', 'in_person', 'online'].map((m) => (
              <button key={m} className={`chip${mode === m ? ' is-on' : ''}`} aria-pressed={mode === m} onClick={() => setMode(m)} data-mode={m}>
                {m ? t(`mode.${m}`) : t('common.all')}
              </button>
            ))}
          </div>
          {res.loading && !d && <Loading />}
          <ErrorBox error={res.error} onRetry={res.reload} />
          {d && (
            <>
              {(d.needs_district || district) && d.districts.length > 0 && <DistrictSelect districts={d.districts} value={district} onChange={setDistrict} />}
              {d.institutions.length === 0 && !(d.needs_district && !district) && <NoPlaces data={{ ...d, official_search: selected?.official_search ?? null }} />}
              <div className="stack">{d.institutions.map((i) => <InstitutionCard key={i.id} inst={i} />)}</div>
            </>
          )}
        </>
      )}
    </section>
  );
}
