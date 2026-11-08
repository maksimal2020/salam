import { NavLink, Navigate, Route, Routes, Link, useLocation } from 'react-router-dom';
import { useState } from 'react';
import { LANGS, useI18n } from './i18n';
import { useStore } from './store';
import { CityPicker } from './CityPicker';
import { Icon, BrandMark, TileCode, TileArrow } from './components';
import { DocsPage } from './pages/Docs';
import { DocPage } from './pages/Doc';
import { DocWherePage } from './pages/DocWhere';
import { ChecklistPage } from './pages/Checklist';
import { WherePage } from './pages/Where';
import { TipsPage } from './pages/Tips';
import { AdsPage } from './pages/Ads';
import { AdPage } from './pages/Ad';
import { AdFormPage } from './pages/AdForm';
import { MyAdsPage } from './pages/MyAds';
import { AuthPage } from './pages/Auth';
import { ModPage } from './pages/Mod';
import { DataPage } from './pages/Data';
import { FeedbackPage } from './pages/Feedback';

/** One color per language tile: five colors from the app's logo. Orange and yellow tiles use dark text. */
const TILE_COLORS: { bg: string; fg: string; dark: boolean }[] = [
  { bg: '#3A5BFF', fg: '#fff', dark: false },
  { bg: '#7C4DFF', fg: '#fff', dark: false },
  { bg: '#FF8A3D', fg: '#1B1B2B', dark: true },
  { bg: '#E8397A', fg: '#fff', dark: false },
  { bg: '#FFC93C', fg: '#1B1B2B', dark: true },
];

/** First screen: language names are written in the languages themselves. */
function LanguageScreen() {
  const { setLang } = useI18n();
  return (
    <main className="onboarding lang-screen" data-testid="language-screen">
      <BrandMark />
      <h1 className="brand-big">Salam!</h1>
      <p className="muted"><Icon name="globe" /> Тил · Забон · Language · Til</p>
      <div className="lang-tiles">
        {LANGS.map((l, i) => {
          const c = TILE_COLORS[i % TILE_COLORS.length];
          return (
            <button
              key={l.code}
              className="lang-tile"
              style={{ background: c.bg, color: c.fg }}
              lang={l.code}
              onClick={() => setLang(l.code)}
              data-lang={l.code}
            >
              <TileCode code={l.code} fg={c.fg} dark={c.dark} />
              {l.native}
              <TileArrow />
            </button>
          );
        })}
      </div>
    </main>
  );
}

function LanguageMenu({ onClose }: { onClose: () => void }) {
  const { lang, setLang, t } = useI18n();
  return (
    <div className="sheet-backdrop" role="dialog" aria-modal="true" aria-label={t('lang.title')} onClick={onClose}>
      <div className="sheet" onClick={(e) => e.stopPropagation()}>
        <h2>{t('lang.title')}</h2>
        <div className="stack">
          {LANGS.map((l) => (
            <button key={l.code} className={`btn btn-lang${l.code === lang ? ' is-current' : ''}`} lang={l.code} aria-pressed={l.code === lang}
              onClick={() => { setLang(l.code); onClose(); }} data-lang={l.code}>{l.native}</button>
          ))}
        </div>
        <button className="btn btn-link" onClick={onClose}>{t('common.close')}</button>
      </div>
    </div>
  );
}

function Header() {
  const { t, lang, offline } = useI18n();
  const { city, openCityPicker, user } = useStore();
  const [langOpen, setLangOpen] = useState(false);
  return (
    <>
      <header className="topbar">
        <Link to="/docs" className="brand">{t('app.name')}</Link>
        <div className="topbar-actions">
          <button className="chip chip-city" onClick={openCityPicker} data-testid="city-chip" aria-label={t('city.change')}>
            <Icon name="pin" />
            <span>{city ? `${city.name}, ${city.region}` : t('city.none')}</span>
          </button>
          <button className="chip" onClick={() => setLangOpen(true)} data-testid="lang-chip" aria-label={t('lang.title')}>
            <Icon name="globe" /><span>{lang.toUpperCase()}</span>
          </button>
          <Link className="chip" to={user ? '/ads/mine' : '/login'} aria-label={t('auth.account')} data-testid="account-chip"><Icon name="user" /></Link>
        </div>
      </header>
      {offline && <p className="offline-bar" role="status">{t('offline.notice')}</p>}
      {langOpen && <LanguageMenu onClose={() => setLangOpen(false)} />}
    </>
  );
}

export function App() {
  const { chosen, ready, t } = useI18n();
  const { cityAsked, cityPickerOpen } = useStore();
  const loc = useLocation();

  if (!chosen) return <LanguageScreen />;
  if (!ready) return <p className="muted pad" role="status">…</p>;
  const needCity = !cityAsked;

  return (
    <div className="app">
      <Header />
      <main className="content" key={loc.pathname.split('/')[1]}>
        <Routes>
          <Route path="/" element={<Navigate to="/docs" replace />} />
          <Route path="/docs" element={<DocsPage />} />
          <Route path="/docs/:id" element={<DocPage />} />
          <Route path="/docs/:id/where" element={<DocWherePage />} />
          <Route path="/list" element={<ChecklistPage />} />
          <Route path="/where" element={<WherePage />} />
          <Route path="/tips" element={<TipsPage />} />
          <Route path="/ads" element={<AdsPage />} />
          <Route path="/ads/new" element={<AdFormPage />} />
          <Route path="/ads/mine" element={<MyAdsPage />} />
          <Route path="/ads/:id" element={<AdPage />} />
          <Route path="/ads/:id/edit" element={<AdFormPage />} />
          <Route path="/login" element={<AuthPage mode="login" />} />
          <Route path="/register" element={<AuthPage mode="register" />} />
          <Route path="/mod" element={<ModPage />} />
          <Route path="/data" element={<DataPage />} />
          <Route path="/feedback" element={<FeedbackPage />} />
          <Route path="*" element={<p className="muted">{t('error.notFound')}</p>} />
        </Routes>
        <footer className="foot"><Link to="/data">{t('nav.more')}</Link> · <Link to="/feedback" data-testid="footer-feedback">{t('feedback.title')}</Link></footer>
      </main>
      <nav className="tabbar" aria-label="main">
        {([['docs', '/docs'], ['where', '/where'], ['tips', '/tips'], ['ads', '/ads']] as const).map(([k, to]) => (
          <NavLink key={k} to={to} className={({ isActive }) => `tab${isActive ? ' is-active' : ''}`} data-testid={`tab-${k}`}>
            <Icon name={k} /><span>{t(`nav.${k}`)}</span>
          </NavLink>
        ))}
      </nav>
      {(needCity || cityPickerOpen) && <CityPicker onboarding={needCity} />}
    </div>
  );
}
