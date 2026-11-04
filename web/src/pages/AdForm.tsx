import { useEffect, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { ApiError, api, type Listing } from '../api';
import { ErrorBox, Loading } from '../components';
import { useAsync } from '../hooks';
import { LANGS, useI18n } from '../i18n';
import { useStore } from '../store';
import { CATEGORIES } from './Ads';

export function AdFormPage() {
  const { id } = useParams();
  const { t, tk, lang } = useI18n();
  const { user, city, openCityPicker } = useStore();
  const nav = useNavigate();
  const existing = useAsync(id ? `ad|${id}` : null, () => api<Listing>(`/listings/${id}`));

  const [category, setCategory] = useState('housing');
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [adLang, setAdLang] = useState<string>(lang);
  const [cityId, setCityId] = useState(city?.id ?? '');
  const [price, setPrice] = useState('');
  const [days, setDays] = useState(14);
  const [employer, setEmployer] = useState('');
  const [pay, setPay] = useState('');
  const [schedule, setSchedule] = useState('');
  const [terms, setTerms] = useState('');
  const [err, setErr] = useState<ApiError | null>(null);
  const [saved, setSaved] = useState<string | null>(null);

  useEffect(() => { if (!id && city) setCityId(city.id); }, [city, id]);
  useEffect(() => {
    const a = existing.data;
    if (!a) return;
    setCategory(a.category); setTitle(a.title); setBody(a.body); setAdLang(a.lang); setCityId(a.city.id); setPrice(a.price ?? '');
    setDays(a.duration_days); setEmployer(a.extra.employer ?? ''); setPay(a.extra.pay ?? ''); setSchedule(a.extra.schedule ?? ''); setTerms(a.extra.terms ?? '');
  }, [existing.data]);

  if (!user) return <p className="notice"><Link to="/login" state={{ from: '/ads/new' }} data-testid="login-required">{t('ads.loginToAct')}</Link></p>;
  if (id && existing.loading) return <Loading />;

  async function submit(e: React.FormEvent) {
    e.preventDefault(); setErr(null); setSaved(null);
    const payload = {
      category, title, body, lang: adLang, city_id: cityId, price: price || null, duration_days: days,
      extra: category === 'work' ? { employer, pay, schedule: schedule || null, terms: terms || null } : undefined,
    };
    try {
      const r = await api<{ id: number; status: string }>(id ? `/listings/${id}` : '/listings', { method: id ? 'PATCH' : 'POST', body: payload });
      setSaved(r.status);
      nav(`/ads/${r.id}`);
    } catch (x) { setErr(x as ApiError); }
  }

  return (
    <section>
      <Link to="/ads" className="back">← {t('common.back')}</Link>
      <h1>{id ? t('ads.edit') : t('ads.new')}</h1>
      <p className="notice">{t('ads.safety')}</p>
      <form className="stack" onSubmit={submit} data-testid="ad-form">
        <label className="field"><span>{t('ads.field.category')}</span>
          <select className="input" value={category} onChange={(e) => setCategory(e.target.value)} data-testid="ad-category">
            {CATEGORIES.map((c) => <option key={c} value={c}>{tk('ads.cat', c)}</option>)}
          </select>
        </label>
        <label className="field"><span>{t('ads.field.title')}</span><input className="input" required minLength={5} maxLength={120} value={title} onChange={(e) => setTitle(e.target.value)} data-testid="ad-title-input" /></label>
        {category === 'work' && (
          <>
            <label className="field"><span>{t('ads.field.employer')}</span><input className="input" required maxLength={200} value={employer} onChange={(e) => setEmployer(e.target.value)} data-testid="ad-employer" /></label>
            <label className="field"><span>{t('ads.field.pay')}</span><input className="input" required maxLength={200} value={pay} onChange={(e) => setPay(e.target.value)} data-testid="ad-pay" /></label>
            <label className="field"><span>{t('ads.field.schedule')}</span><input className="input" maxLength={200} value={schedule} onChange={(e) => setSchedule(e.target.value)} data-testid="ad-schedule" /></label>
            <label className="field"><span>{t('ads.field.terms')}</span><input className="input" maxLength={200} value={terms} onChange={(e) => setTerms(e.target.value)} data-testid="ad-terms" /></label>
          </>
        )}
        <label className="field"><span>{t('ads.field.body')}</span><textarea className="input" rows={6} required minLength={10} maxLength={4000} value={body} onChange={(e) => setBody(e.target.value)} data-testid="ad-body" /></label>
        {category !== 'work' && category !== 'free' && (
          <label className="field"><span>{t('ads.field.price')}</span><input className="input" maxLength={80} value={price} onChange={(e) => setPrice(e.target.value)} data-testid="ad-price" /></label>
        )}
        <div className="field"><span>{t('ads.field.city')}</span>
          <button type="button" className="chip chip-city" onClick={openCityPicker} data-testid="ad-city">{city && city.id === cityId ? `${city.name}, ${city.region}` : cityId || t('city.none')}</button>
        </div>
        <label className="field"><span>{t('ads.lang')}</span>
          <select className="input" value={adLang} onChange={(e) => setAdLang(e.target.value)} data-testid="ad-lang-select">
            {LANGS.map((l) => <option key={l.code} value={l.code}>{l.native}</option>)}
          </select>
        </label>
        <label className="field"><span>{t('ads.field.duration')}</span>
          <select className="input" value={days} onChange={(e) => setDays(Number(e.target.value))} data-testid="ad-days">
            {[7, 14, 30].map((d) => <option key={d} value={d}>{t('ads.days', { n: d })}</option>)}
          </select>
        </label>
        <ErrorBox error={err} />
        {saved && <p className="notice notice-ok">{t('ads.saved')}</p>}
        <button className="btn btn-primary" type="submit" disabled={!cityId} data-testid="ad-submit">{id ? t('common.save') : t('ads.new')}</button>
      </form>
    </section>
  );
}
