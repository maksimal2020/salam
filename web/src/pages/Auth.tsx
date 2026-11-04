import { useState } from 'react';
import { Link, useLocation, useNavigate } from 'react-router-dom';
import { ApiError, api, type User } from '../api';
import { ErrorBox } from '../components';
import { useI18n } from '../i18n';
import { useStore } from '../store';

export function AuthPage({ mode }: { mode: 'login' | 'register' }) {
  const { t } = useI18n();
  const { login } = useStore();
  const nav = useNavigate();
  const loc = useLocation();
  const from = (loc.state as { from?: string } | null)?.from ?? '/ads';
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [name, setName] = useState('');
  const [err, setErr] = useState<ApiError | null>(null);

  async function submit(e: React.FormEvent) {
    e.preventDefault(); setErr(null);
    try {
      const r = await api<{ token: string; user: User }>(`/auth/${mode}`, { method: 'POST', body: { email, password, displayName: name || undefined } });
      login(r.token, r.user);
      nav(r.user.role === 'moderator' ? '/mod' : from, { replace: true });
    } catch (x) { setErr(x as ApiError); }
  }
  return (
    <section>
      <h1>{mode === 'login' ? t('auth.login') : t('auth.register')}</h1>
      <form className="stack" onSubmit={submit} data-testid={`${mode}-form`}>
        {mode === 'register' && <label className="field"><span>{t('auth.name')}</span><input className="input" maxLength={60} value={name} onChange={(e) => setName(e.target.value)} data-testid="auth-name" /></label>}
        <label className="field"><span>{t('auth.email')}</span><input className="input" type="email" required autoComplete="email" value={email} onChange={(e) => setEmail(e.target.value)} data-testid="auth-email" /></label>
        <label className="field"><span>{t('auth.password')}</span><input className="input" type="password" required minLength={8} autoComplete={mode === 'login' ? 'current-password' : 'new-password'} value={password} onChange={(e) => setPassword(e.target.value)} data-testid="auth-password" /></label>
        <ErrorBox error={err} />
        <button className="btn btn-primary" type="submit" data-testid="auth-submit">{mode === 'login' ? t('auth.login') : t('auth.register')}</button>
      </form>
      <p>{mode === 'login' ? <Link to="/register" state={{ from }} data-testid="to-register">{t('auth.noAccount')}</Link> : <Link to="/login" state={{ from }}>{t('auth.haveAccount')}</Link>}</p>
    </section>
  );
}
