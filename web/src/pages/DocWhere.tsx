import { Link, useParams } from 'react-router-dom';
import { api, qs, type Places } from '../api';
import { Empty, ErrorBox, InstitutionCard, Loading, SourceList } from '../components';
import { useAsync } from '../hooks';
import { useI18n } from '../i18n';
import { useStore } from '../store';

export function DistrictSelect({ districts, value, onChange }: { districts: { id: string; name: string }[]; value: string | null; onChange: (v: string | null) => void }) {
  const { t } = useI18n();
  return (
    <div className="notice" data-testid="district-prompt">
      <label>
        <strong>{t('city.districtTitle')}</strong>
        <span className="muted block">{t('city.districtHint')}</span>
        <select className="input" value={value ?? ''} onChange={(e) => onChange(e.target.value || null)} data-testid="district-select">
          <option value="">{t('city.districtAny')}</option>
          {districts.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
        </select>
      </label>
    </div>
  );
}

export function NoPlaces({ data }: { data: Places }) {
  const { t } = useI18n();
  return (
    <div className="stack" data-testid="no-places">
      <Empty>{t('where.none', { city: data.city?.name ?? '' })}</Empty>
      {data.official_search
        ? <a className="btn" href={data.official_search.url} target="_blank" rel="noreferrer noopener" data-testid="official-search">{t('where.officialSearch')}: {data.official_search.title}</a>
        : <p className="muted" data-testid="no-official-search">{t('where.noOfficialSearch')}</p>}
      {data.sources && data.sources.length > 0 && <SourceList sources={data.sources} checkedAt={null} />}
    </div>
  );
}

export function DocWherePage() {
  const { id = '' } = useParams();
  const { t, lang } = useI18n();
  const { city, district, setDistrict, profile, openCityPicker } = useStore();
  const key = `${id}|${lang}|${city?.id ?? ''}|${district ?? ''}|${profile.citizenship ?? ''}`;
  const res = useAsync(key, () => api<Places>(`/documents/${id}/places${qs({ lang, city: city?.id, district, citizenship: profile.citizenship })}`));
  const d = res.data;

  return (
    <section>
      <Link to={`/docs/${id}`} className="back">← {t('common.back')}</Link>
      <h1>{t('docs.whereButton')}</h1>
      {d?.document && <p className="muted" data-testid="where-doc">{t('where.forDocument', { doc: d.document.title })}</p>}
      <div className="row">
        <button className="chip chip-city" onClick={openCityPicker} data-testid="where-city">{city ? `${city.name}, ${city.region}` : t('city.none')}</button>
      </div>

      {!city && (
        <div className="notice" data-testid="need-city">
          <p>{t('city.needed')}</p>
          <button className="btn btn-primary" onClick={openCityPicker}>{t('city.manual')}</button>
        </div>
      )}
      {city && res.loading && !d && <Loading />}
      <ErrorBox error={res.error} onRetry={res.reload} />

      {city && d && d.where_kind !== 'institutions' && (
        <div className="notice" data-testid="no-institution">
          <p>{t('where.noInstitution')}</p>
          {d.where_note && <p className="muted">{d.where_note}</p>}
        </div>
      )}

      {city && d && d.where_kind === 'institutions' && (
        <>
          {(d.needs_district || district) && d.districts.length > 0 && <DistrictSelect districts={d.districts} value={district} onChange={setDistrict} />}
          {d.institutions.length === 0 && !(d.needs_district && !district) && <NoPlaces data={d} />}
          {d.institutions.length === 0 && d.needs_district && !district && <p className="muted">{t('where.none', { city: city.name })}</p>}
          <div className="stack">{d.institutions.map((i) => <InstitutionCard key={i.id} inst={i} />)}</div>
        </>
      )}
    </section>
  );
}
