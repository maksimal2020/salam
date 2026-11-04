import { api } from '../api';
import { ErrorBox, Loading } from '../components';
import { useAsync } from '../hooks';
import { useI18n } from '../i18n';

interface Coverage {
  scenarios: { group: string; purpose: string; stage: string; lostDocument: boolean; total: number; verified: number; demo: number; clarify: number; state: 'verified' | 'partial' | 'demo' | 'missing' }[];
  cities: { id: string; name: string; region: string }[];
  documents: { id: string; verified: boolean; whereKind: string; cells: Record<string, 'verified' | 'demo' | 'district' | 'missing'> }[];
  otherCities: number;
}

export function DataPage() {
  const { t, tk } = useI18n();
  const res = useAsync('coverage', () => api<Coverage>('/coverage'));
  const titles = useAsync('doc-titles', () => api<{ documents: { id: string; title: string }[] }>('/documents'));
  const name = (id: string) => titles.data?.documents.find((d) => d.id === id)?.title ?? id;
  const c = res.data;
  const stateLabel = (s: string) => (s === 'verified' ? t('data.verified') : s === 'partial' ? t('data.partial') : s === 'demo' ? t('data.demo') : t('data.missing'));
  return (
    <section>
      <h1>{t('data.title')}</h1>
      <p className="muted">{t('data.intro')}</p>
      {res.loading && !c && <Loading />}
      <ErrorBox error={res.error} onRetry={res.reload} />
      {c && (
        <>
          <h2>{t('data.scenarios')}</h2>
          <div className="table-wrap">
            <table data-testid="coverage-scenarios">
              <thead><tr><th>{t('list.citizenship')}</th><th>{t('list.purpose')}</th><th>{t('list.stage')}</th><th>#</th><th>{t('data.verified')}</th><th /></tr></thead>
              <tbody>
                {c.scenarios.map((s, i) => (
                  <tr key={i}>
                    <td>{tk('group', s.group)}</td>
                    <td>{tk('purpose', s.purpose)}{s.lostDocument ? ` · ${tk('flag', 'lost_document')}` : ''}</td>
                    <td>{t(`list.stage.${s.stage === 'before' ? 'before' : 'in_russia'}`)}</td>
                    <td>{s.total}</td>
                    <td>{s.verified}/{s.total}</td>
                    <td><span className={`cell cell-${s.state}`}>{stateLabel(s.state)}</span></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <h2>{t('data.cities')}</h2>
          <div className="table-wrap">
            <table data-testid="coverage-cities">
              <thead><tr><th>{t('nav.docs')}</th>{c.cities.map((x) => <th key={x.id}>{x.name}</th>)}</tr></thead>
              <tbody>
                {c.documents.map((d) => (
                  <tr key={d.id}>
                    <td>{name(d.id)}</td>
                    {c.cities.map((x) => <td key={x.id}>{d.whereKind !== 'institutions' ? <span className="muted">n/a</span> : <span className={`cell cell-${d.cells[x.id]}`}>{d.cells[x.id] === 'verified' ? t('data.verified') : d.cells[x.id] === 'demo' ? t('data.demo') : d.cells[x.id] === 'district' ? t('city.districtTitle') : '—'}</span>}</td>)}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="muted small">{t('data.missing')}: {c.otherCities}</p>
        </>
      )}
    </section>
  );
}
