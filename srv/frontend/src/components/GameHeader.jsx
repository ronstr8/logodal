import React from 'react';
import { useTranslation } from 'react-i18next';

const GameHeader = ({
    nickname,
    isWordwonk,
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

    const identityLabel = isWordwonk
        ? t('app.you_are_wordwonk', 'You are the Wordwonk')
        : nickname
            ? `${t('app.you_are', 'You are')} ${nickname}`
            : null;

    return (
        <header>
            <div className="header-left">
                <button className="mobile-menu-btn" onClick={onOpenSidebar}>☰</button>
                <h1 style={{ whiteSpace: 'nowrap' }}>Wordwonk</h1>
            </div>

            <div className="header-toggles desktop-only">
                <button className={`panel-toggle ${messagesVisible ? 'active' : ''}`} onClick={() => setMessagesVisible(!messagesVisible)}>
                    {t('app.messages_title', 'Messages')}
                </button>
            </div>

            <div className="header-actions desktop-only">
                {identityLabel && (
                    <div className={`user-identity${isWordwonk ? ' is-wordwonk' : ''}`}>
                        {identityLabel}
                    </div>
                )}
                <div className="button-group">
                    <button className="header-btn wtf-btn" onClick={() => setShowRules(!showRules)} title={t('app.rules_title')}>{t('app.help_label')}</button>
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
