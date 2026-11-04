import { useEffect, useRef, useState } from 'react';
import { api, qs, type City } from './api';
import { useDebounced } from './hooks';
import { useI18n } from './i18n';
import { useStore } from './store';

type Step = 'choose' | 'detecting' | 'confirm' | 'manual';

export function CityPicker({ onboarding = false }: { onboarding?: boolean }) {
  const { t } = useI18n();
  const { setCity, skipCity, closeCityPicker, city: current } = useStore();
  const [step, setStep] = useState<Step>('choose');
  const [message, setMessage] = useState<string | null>(null);
  const [candidate, setCandidate] = useState<City | null>(null);
  const [q, setQ] = useState('');
  const dq = useDebounced(q, 200);
  const [results, setResults] = useState<City[] | null>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  const done = (c: City) => { setCity({ id: c.id, name: c.name, region: c.region }); closeCityPicker(); };

  useEffect(() => {
    if (step !== 'manual') return;
    inputRef.current?.focus();
    if (!dq.trim()) { setResults(null); return; }
    let alive = true;
    api<{ cities: City[] }>(`/cities${qs({ q: dq })}`).then((r) => { if (alive) setResults(r.cities); }).catch(() => { if (alive) setResults([]); });
    return () => { alive = false; };
  }, [dq, step]);

  function manual(msg?: string) { setMessage(msg ?? null); setStep('manual'); }

  function detect() {
    setMessage(null);
    if (!('geolocation' in navigator)) return manual(t('city.unavailable'));
    setStep('detecting');
    navigator.geolocation.getCurrentPosition(
      async (pos) => {
        // The position is used for one request and then dropped; it is not saved anywhere.
        try {
          const r = await api<{ status: string; city?: City }>('/cities/locate', { method: 'POST', body: { lat: pos.coords.latitude, lon: pos.coords.longitude } });
          if (r.status === 'candidate' && r.city) { setCandidate(r.city); setStep('confirm'); }
          else manual(t(r.status === 'outside' ? 'city.outside' : 'city.notFoundNear'));
        } catch {
          manual(t('city.unavailable'));
        }
      },
      (err) => manual(t(err.code === err.PERMISSION_DENIED ? 'city.denied' : 'city.unavailable')),
      { timeout: 10000, maximumAge: 60000 },
    );
  }

  return (
    <div className="sheet-backdrop" role="dialog" aria-modal="true" aria-labelledby="city-title" data-testid="city-picker">
      <div className="sheet">
        <h2 id="city-title">{onboarding ? t('city.title') : t('city.change')}</h2>
        {onboarding && <p className="muted">{t('city.subtitle')}</p>}
        {message && <p className="notice" role="status" data-testid="city-message">{message}</p>}

        {step === 'choose' && (
          <div className="stack">
            <button className="btn btn-primary" onClick={detect} data-testid="city-detect">{t('city.detect')}</button>
            <button className="btn" onClick={() => manual()} data-testid="city-manual">{t('city.manual')}</button>
            {onboarding && <button className="btn btn-link" onClick={skipCity} data-testid="city-skip">{t('city.skip')}</button>}
            {!onboarding && <button className="btn btn-link" onClick={closeCityPicker}>{t('common.cancel')}</button>}
          </div>
        )}

        {step === 'detecting' && <p className="muted" role="status">{t('city.detecting')}</p>}

        {step === 'confirm' && candidate && (
          <div className="stack">
            <p className="big" data-testid="city-candidate">{t('city.found', { city: `${candidate.name}, ${candidate.region}` })}</p>
            <button className="btn btn-primary" onClick={() => done(candidate)} data-testid="city-confirm">{t('city.confirmYes')}</button>
            <button className="btn" onClick={() => manual()} data-testid="city-reject">{t('city.confirmNo')}</button>
          </div>
        )}

        {step === 'manual' && (
          <div className="stack">
            <input ref={inputRef} type="search" className="input" value={q} onChange={(e) => setQ(e.target.value)}
              placeholder={t('city.searchPlaceholder')} aria-label={t('city.searchPlaceholder')} data-testid="city-search" autoComplete="off" />
            {results && results.length === 0 && <p className="muted" data-testid="city-noresults">{t('city.noResults')}</p>}
            {results && results.length > 0 && (
              <ul className="list-plain" data-testid="city-results">
                {results.map((c) => (
                  <li key={c.id}>
                    <button className="row-btn" onClick={() => done(c)} data-city={c.id}>
                      <strong>{c.name}</strong><span className="muted">{c.region}</span>
                    </button>
                  </li>
                ))}
              </ul>
            )}
            <div className="row">
              <button className="btn btn-link" onClick={() => { setMessage(null); setStep('choose'); }}>{t('common.back')}</button>
              {onboarding && <button className="btn btn-link" onClick={skipCity}>{t('city.skip')}</button>}
              {!onboarding && current && <button className="btn btn-link" onClick={closeCityPicker}>{t('common.cancel')}</button>}
            </div>
          </div>
        )}
        <p className="muted small">{t('city.privacy')}</p>
      </div>
    </div>
  );
}
