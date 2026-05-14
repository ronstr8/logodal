import { useEffect, useRef, useState } from 'react'
import { useTranslation, Trans } from 'react-i18next'
import './Panel.css'

const MessageList = ({ messages }) => {
    const { t } = useTranslation();
    const scrollRef = useRef(null);
    const isAtBottom = useRef(true);
    const [hasUnread, setHasUnread] = useState(false);

    const scrollToBottom = (force = false) => {
        if (scrollRef.current && (force || isAtBottom.current)) {
            scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
        }
    };

    const handleScroll = () => {
        if (!scrollRef.current) return;
        const { scrollTop, scrollHeight, clientHeight } = scrollRef.current;
        const atBottom = scrollHeight - scrollTop - clientHeight < 50;
        isAtBottom.current = atBottom;
        if (atBottom) setHasUnread(false);
    };

    // Scroll to bottom on initial mount
    useEffect(() => {
        scrollToBottom(true);
    }, []);

    // On new messages: scroll if at bottom, otherwise mark dirty
    useEffect(() => {
        if (isAtBottom.current) {
            requestAnimationFrame(() => scrollToBottom());
        } else {
            setHasUnread(true);
        }
    }, [messages]);

    const jumpToBottom = () => {
        isAtBottom.current = true;
        setHasUnread(false);
        scrollToBottom(true);
    };

    const getSystemIcon = (msg) => {
        if (msg.type === 'results' || msg.type === 'results_table') return '🏆';
        const text = msg.text || '';
        if (text.includes('start playing')) return '🏁';
        if (text.includes('played a word')) return '📝';
        if (text.includes('won with') || text.includes('won the round')) return '🏆';
        return '🤖';
    };

    const renderResultsTable = (results) => {
        if (!results || results.length === 0) return null;
        return (
            <table className="results-table">
                <tbody>
                    {results.map((r, idx) => (
                        <tr key={idx}>
                            <td className="col-player">{r.nickname || r.player || 'Anonymous'}</td>
                            <td className="col-word">{r.word || '???'}</td>
                            <td className={`col-score ${r.is_dupe ? 'is-dupe' : ''}`}>
                                {r.is_dupe ? '🦜' : r.score}
                            </td>
                        </tr>
                    ))}
                </tbody>
            </table>
        );
    };

    return (
        <div className="messages-container">
            <div
                className="panel-content chat-history"
                ref={scrollRef}
                onScroll={handleScroll}
            >
                {(messages || []).map((msg, i) => {
                    if (msg.isSeparator) {
                        return <div key={i} className="chat-separator"><hr /></div>;
                    }
                    const isSystem = msg.isSystem || msg.sender === 'SYSTEM';
                    const icon = isSystem ? getSystemIcon(msg) : null;

                    return (
                        <div key={i} className={`chat-msg ${isSystem ? 'system-msg' : ''}`}>
                            {isSystem ? (
                                <>
                                    <span className="chat-icon">{icon} </span>
                                    <div className="system-content">
                                        <span className="chat-text" style={{ whiteSpace: 'pre-wrap' }}>{msg.text}</span>
                                        {msg.type === 'results_table' && renderResultsTable(msg.data)}
                                    </div>
                                </>
                            ) : (
                                <Trans
                                    t={t}
                                    i18nKey="app.chat_format"
                                    values={{ player: msg.senderName || msg.sender, text: msg.text }}
                                    components={{ v: <span className="chat-sender" /> }}
                                />
                            )}
                        </div>
                    );
                })}
            </div>
            {hasUnread && (
                <button className="unread-badge" onClick={jumpToBottom}>
                    ↓ new messages
                </button>
            )}
        </div>
    );
};

export default MessageList;
