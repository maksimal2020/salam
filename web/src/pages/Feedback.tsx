import { useState } from 'react';
import { Link } from 'react-router-dom';
import { ApiError, api } from '../api';
import { ErrorBox } from '../components';
import { useI18n } from '../i18n';

export function FeedbackPage() {
  const { t, lang } = useI18n();
  const [message, setMessage] = useState('');
  const [email, setEmail] = useState('');
  const [err, setErr] = useState<ApiError | null>(null);
  const [sent, setSent] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setErr(null);
    try {
      await api('/feedback', { method: 'POST', body: { message, email: email || undefined, lang } });
      setSent(true);
      setMessage('');
      setEmail('');
    } catch (x) { setErr(x as ApiError); }
  }

  return (
    <section>
      <Link to="/data" className="back">← {t('common.back')}</Link>
      <h1>{t('feedback.title')}</h1>
      <p className="muted">{t('feedback.intro')}</p>
      {sent ? (
        <p className="notice notice-ok" data-testid="feedback-sent">{t('feedback.sent')}</p>
      ) : (
        <form className="stack" onSubmit={submit} data-testid="feedback-form">
          <label className="field">
            <span>{t('feedback.messageLabel')}</span>
            <textarea
              className="input" rows={6} required maxLength={4000}
              placeholder={t('feedback.messagePlaceholder')}
              value={message} onChange={(e) => setMessage(e.target.value)}
              data-testid="feedback-message"
            />
          </label>
          <label className="field">
            <span>{t('feedback.emailLabel')}</span>
            <input className="input" maxLength={200} value={email} onChange={(e) => setEmail(e.target.value)} data-testid="feedback-email" />
          </label>
          <ErrorBox error={err} />
          <button className="btn btn-primary" type="submit" data-testid="feedback-submit">{t('feedback.submit')}</button>
        </form>
      )}
    </section>
  );
}
