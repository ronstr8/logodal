import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import LogodalLogo from './LogodalLogo';
import './Login.css';

const Login = ({ onLoginSuccess }) => {
    const { t } = useTranslation();
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState(null);
    const [lastMethod, setLastMethod] = useState(localStorage.getItem('logodal_last_login'));

    const handleGoogleLogin = () => {
        window.location.href = '/auth/google';
    };

    const handleDiscordLogin = () => {
        window.location.href = '/auth/discord';
    };

    const handleAnonymousLogin = async () => {
        setLoading(true);
        setError(null);
        try {
            const resp = await fetch('/auth/anonymous', { method: 'POST' });
            if (resp.ok) {
                localStorage.setItem('logodal_last_login', 'anonymous');
                onLoginSuccess();
            } else {
                setError(t('auth.anonymous_failed', 'Could not start anonymous session'));
            }
        } catch (err) {
            setError(err.message);
        } finally {
            setLoading(false);
        }
    };

    return (
        <div className="login-overlay">
            <div className="login-card">
                <LogodalLogo height={68} style={{ margin: '0 auto 0.75rem' }} />
                <p className="login-subtitle">{t('auth.welcome_back')}</p>

                {lastMethod && (
                    <div className="last-login-hint">
                        {t('auth.last_used')}: <strong>{lastMethod}</strong>
                    </div>
                )}

                <div className="auth-buttons">
                    <button className="auth-btn google" onClick={handleGoogleLogin} disabled={loading}>
                        <img src="/icons/google.svg" alt="" />
                        {t('auth.continue_with_google')}
                    </button>

                    <button className="auth-btn discord" onClick={handleDiscordLogin} disabled={loading}>
                        <span className="icon">🎮</span>
                        {t('auth.continue_with_discord', 'Continue with Discord')}
                    </button>

                    <button className="auth-btn anonymous" onClick={handleAnonymousLogin} disabled={loading}>
                        <span className="icon">👤</span>
                        {t('auth.play_anonymously', 'Play Anonymously')}
                    </button>
                </div>

                {error && <div className="auth-error">{error}</div>}

                <div className="auth-footer">
                    <p>{t('auth.privacy_hint')}</p>
                </div>
            </div>
        </div>
    );
};

export default Login;
