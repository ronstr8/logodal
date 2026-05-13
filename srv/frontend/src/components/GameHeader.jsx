import React from 'react';
import { useTranslation } from 'react-i18next';
import LogodalLogo from './LogodalLogo';

const GameHeader = ({
    nickname,
    isLogodal,
    onOpenSidebar,
    messagesVisible,
    setMessagesVisible,
    showRules,
    setShowRules,
    handleInvite,
    gameId,
    statsVisible,
    setStatsVisible,
    handleLogout,
    isMuted,
    toggleMute,
    isAmbienceEnabled,
    toggleAmbience,
    language,
    supportedLangs,
    onLanguageChange
}) => {
    const { t } = useTranslation();

    const identityLabel = isLogodal
        ? t('app.you_are_daedalus', 'You are the Daedalus')
        : nickname
            ? `${t('app.you_are', 'You are')} ${nickname}`
            : null;

    return (
        <header>
            <div className="header-left">
                <button className="mobile-menu-btn" onClick={onOpenSidebar}>☰</button>
                <LogodalLogo height={44} className="logodal-logo" />
            </div>

            <div className="header-actions desktop-only">
                {identityLabel && (
                    <div className={`user-identity${isLogodal ? ' is-logodal' : ''}`}>
                        {identityLabel}
                    </div>
                )}
                <div className="button-group">
                    <button className="header-btn wtf-btn" onClick={() => setShowRules(!showRules)} title={t('app.rules_title')}>{t('app.help_label')}</button>
                    <button className={`header-btn${messagesVisible ? ' active' : ''}`} onClick={() => setMessagesVisible(!messagesVisible)} title={t('app.messages_title', 'Messages')}>💬</button>
                    <button className="header-btn" onClick={handleInvite} title={t('app.invite_friend')} disabled={!gameId}>🔗</button>
                    <button className="header-btn" onClick={() => setStatsVisible(!statsVisible)} title={t('app.stats_button')}>🏆</button>
                    <button className="header-btn logout" onClick={handleLogout} title={t('auth.logout')}>🚪</button>
                </div>

                <div className="button-group">
                    <button className="header-btn" onClick={toggleAmbience} title={isAmbienceEnabled ? t('app.music_off') : t('app.music_on')}>{isAmbienceEnabled ? '🎵' : '🔇'}</button>
                    <button className="header-btn" onClick={toggleMute} title={isMuted ? t('app.mute_off') : t('app.mute_on')}>{isMuted ? '🔈' : '🔊'}</button>
                </div>

                <div className="button-group">
                    <select className="lang-select" value={language} onChange={(e) => onLanguageChange(e.target.value)}>
                        {Object.entries(supportedLangs).map(([code, info]) => {
                            const name = typeof info === 'object' ? info.name : info;
                            const count = typeof info === 'object' ? info.word_count : 0;
                            const displayCount = count >= 1000 ? `${Math.round(count / 1000)}k` : count;
                            return <option key={code} value={code}>{name || code.toUpperCase()} {count > 0 ? `(${displayCount})` : ''}</option>;
                        })}
                    </select>
                </div>
            </div>

            <div className="header-actions mobile-only">
                <button className="header-btn" onClick={handleInvite} title={t('app.invite_friend')} disabled={!gameId}>🔗</button>
            </div>
        </header>
    );
};

export default GameHeader;
