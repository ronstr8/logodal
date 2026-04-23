import { useTranslation } from 'react-i18next'
import { useState, useEffect } from 'react'
import './PlayerStats.css'

function timeAgo(isoStr) {
    if (!isoStr) return null;
    const diffMs = Date.now() - new Date(isoStr).getTime();
    const s = Math.floor(diffMs / 1000);
    if (s < 60) return `${s}s`;
    const m = Math.floor(s / 60);
    if (m < 60) return `${m}m`;
    const h = Math.floor(m / 60);
    if (h < 24) return `${h}h`;
    const d = Math.floor(h / 24);
    return `${d}d`;
}

function useTimeAgo(isoStr) {
    const [label, setLabel] = useState(() => timeAgo(isoStr));
    useEffect(() => {
        if (!isoStr) return;
        setLabel(timeAgo(isoStr));
        const diffMs = Date.now() - new Date(isoStr).getTime();
        const interval = diffMs < 60_000 ? 1000 : diffMs < 3_600_000 ? 30_000 : 60_000;
        const id = setInterval(() => setLabel(timeAgo(isoStr)), interval);
        return () => clearInterval(id);
    }, [isoStr]);
    return label;
}

const WordwonkBanner = ({ leader }) => {
    const { t } = useTranslation();
    const ago = useTimeAgo(leader.last_word_at);

    return (
        <div className="wordwonk-banner">
            <div className="wordwonk-intro">{t('stats.the_wordwonk_is')}</div>
            <div className="wordwonk-name">{leader.name}</div>
            {leader.last_word && (
                <div className="wordwonk-last-word">
                    <span className="wordwonk-word">{leader.last_word}</span>
                    <span className="wordwonk-ago">({leader.last_word_score}pts{ago ? `, ${ago} ago` : ''})</span>
                </div>
            )}
        </div>
    );
};

const PlayerStats = ({ data }) => {
    const { t } = useTranslation();
    if (!data) return <div className="loading-stats">{t('stats.loading')}</div>;

    const { leaders = [], personal } = data;
    const wordwonk = leaders[0];

    return (
        <div className="stats-container">
            {wordwonk && <WordwonkBanner leader={wordwonk} />}

            {personal && (
                <div className="personal-stats-section">
                    <h3>{t('stats.your_performance')}</h3>
                    <div className="personal-stats-grid">
                        <div className="stat-card">
                            <span className="stat-value">{personal.score}</span>
                            <span className="stat-label">{t('stats.total_points')}</span>
                        </div>
                        <div className="stat-card">
                            <span className="stat-value">{personal.plays}</span>
                            <span className="stat-label">{t('stats.words_played')}</span>
                        </div>
                        {personal.best_word && (
                            <div className="stat-card stat-card-best">
                                <span className="stat-value stat-value-word">{personal.best_word} <span className="stat-value-score">({personal.best_score})</span></span>
                                <span className="stat-label">{t('stats.best_play')}</span>
                            </div>
                        )}
                    </div>
                </div>
            )}

            <div className="leaderboard-section">
                <h3>{t('stats.global_top_10')}</h3>
                <div className="leaderboard-list">
                    {leaders.map((p, i) => (
                        <div key={i} className="leader-entry">
                            <span className="leader-rank">#{i + 1}</span>
                            <span className="leader-name">{p.name}</span>
                            <span className="leader-score">{p.score}</span>
                        </div>
                    ))}
                    {leaders.length === 0 && <div className="empty-msg">{t('app.no_legends')}</div>}
                </div>
            </div>
        </div>
    )
}

export default PlayerStats
