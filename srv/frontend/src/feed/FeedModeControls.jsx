import { useTranslation } from 'react-i18next';
import { FEED_MODES } from './playFeed';

const ICONS = { off: '🚫', fade: '🌫️', scroll: '📜' };

function useModeLabel() {
    const { t } = useTranslation();
    return (mode) => t(`app.feed_mode_${mode}`);
}

// Header button: each click moves to the next mode.
export function FeedModeButton({ mode, onCycle }) {
    const { t } = useTranslation();
    const label = useModeLabel();
    return (
        <button className="header-btn" onClick={onCycle} title={`${t('app.feed_label')}: ${label(mode)}`}>
            {ICONS[mode]}
        </button>
    );
}

// Sidebar control: every mode side by side.
export function FeedModePicker({ mode, onChange }) {
    const { t } = useTranslation();
    const label = useModeLabel();
    return (
        <div className="sidebar-section">
            <h3>{t('app.feed_label')}</h3>
            <div className="sidebar-lang-picker">
                {FEED_MODES.map(m => (
                    <button key={m} className={m === mode ? 'active' : ''} onClick={() => onChange(m)}>
                        {ICONS[m]} {label(m)}
                    </button>
                ))}
            </div>
        </div>
    );
}
