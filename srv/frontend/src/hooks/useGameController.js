import { useCallback } from 'react';

export default function useGameController({
    state,
    t,
    i18n,
    play,
    startAmbience,
    fetchLeaderboard
}) {
    const {
        setRack, setTimeLeft, setTotalTime, setResults, setIsLocked,
        setGameId, setFeedback, setGuess, setLetterValue, setTileConfig,
        setPlayerNames, playerNamesRef, setSupportedLangs,
        setMessages, logSystemMessage, showChatToast, playerId, setNickname,
        setMutantLetter, setRackSize
    } = state;

    const onChatMessage = useCallback((data) => {
        const text = typeof data.payload === 'string' ? data.payload : data.payload.text;
        const senderName = typeof data.payload === 'object' ? data.payload.senderName : playerNamesRef.current[data.sender];
        const isSystem = !!(data.payload && (data.payload.isSystem || data.sender === 'SYSTEM'));
        
        let translatedText = text;
        if (typeof text === 'string' && text.includes('ai.')) {
            translatedText = t(text, { player: senderName || data.sender });
        }

        if (senderName === 'Elsegame') {
            logSystemMessage(translatedText);
            return;
        }

        if (data.payload && !data.payload.isSeparator && !data.payload.skipToast) {
            showChatToast(senderName, translatedText);
        }

        const msgObj = {
            sender: data.sender,
            senderName: senderName || data.sender,
            text: translatedText,
            isSystem: isSystem,
            isSeparator: !!(data.payload && data.payload.isSeparator),
            timestamp: new Date(data.timestamp * 1000).toLocaleTimeString()
        };

        setMessages(prev => [...prev, msgObj]);
    }, [t, logSystemMessage, showChatToast, setMessages, playerNamesRef]);

    const onChatHistory = useCallback((data) => {
        const history = data.payload.map(msg => {
            const payload = msg.payload || {};
            const isObject = typeof payload === 'object';
            return {
                sender: msg.sender,
                senderName: (isObject ? payload.senderName : null) || msg.sender,
                text: isObject ? payload.text : (typeof payload === 'string' ? payload : ''),
                isSystem: !!(isObject && (payload.isSystem || msg.sender === 'SYSTEM')),
                isSeparator: !!(isObject && payload.isSeparator),
                timestamp: new Date(msg.timestamp * 1000).toLocaleTimeString()
            };
        });
        setMessages(prev => (prev.length > history.length ? prev : history));
    }, [setMessages]);

    const onIdentity = useCallback((data) => {
        if (data.payload.id === playerId) {
            setNickname(data.payload.name);
            if (data.payload.language) i18n.changeLanguage(data.payload.language);
            if (data.payload.config) {
                setTileConfig({
                    tiles: data.payload.config.tiles || {},
                    unicorns: data.payload.config.unicorns || {}
                });
                setLetterValue(data.payload.config.tile_values || {});
                if (data.payload.config.languages) setSupportedLangs(data.payload.config.languages);
            }
        }
        setPlayerNames(prev => ({ ...prev, [data.payload.id]: data.payload.name }));
    }, [playerId, setNickname, i18n, setTileConfig, setLetterValue, setSupportedLangs, setPlayerNames]);

    const onGameStart = useCallback((data) => {
        const { uuid, rack: newRackLetters, rack_size, tile_values, time_left, tile_counts, unicorns, mutant_letter } = data.payload;
        const newRack = newRackLetters.map((letter, idx) => ({
            id: `tile-${idx}-${Date.now()}`,
            letter,
            position: idx,
            isUsed: false
        }));
        setGameId(uuid);
        setRack(newRack);
        setTimeLeft(time_left);
        setTotalTime(time_left || 30);
        setLetterValue(tile_values || {});
        setTileConfig({ tiles: tile_counts || {}, unicorns: unicorns || {} });
        setResults(null);
        const resolvedRackSize = rack_size || newRackLetters.length;
        setRackSize(resolvedRackSize);
        setGuess(Array(resolvedRackSize).fill(null));
        setIsLocked(false);
        setFeedback({ text: '', type: '' });
        setMutantLetter(mutant_letter || null);
        startAmbience();
        fetchLeaderboard();
    }, [setGameId, setRack, setTimeLeft, setTotalTime, setLetterValue, setTileConfig, setResults, setGuess, setIsLocked, setFeedback, setMutantLetter, setRackSize, startAmbience, fetchLeaderboard]);

    const onTimer = useCallback((data) => {
        if (data.payload && data.payload.time_left !== undefined) {
            setTimeLeft(Math.max(0, data.payload.time_left));
        }
    }, [setTimeLeft]);

    const onPlay = useCallback((data) => {
        if (data.sender === playerId) {
            setFeedback({ text: t('app.accepted'), type: 'success' });
            setIsLocked(true);
            setTimeout(() => setFeedback({ text: '', type: '' }), 5000);
            fetchLeaderboard();
        }
        if (data.payload.score >= 40) play('bigsplat');
    }, [playerId, setFeedback, setIsLocked, t, play, fetchLeaderboard]);

    const onPlayerJoined = useCallback((data) => {
        if (data.payload.id !== playerId) {
            logSystemMessage(t('app.player_joined', { name: data.payload.name }));
        }
    }, [playerId, logSystemMessage, t]);

    const onPlayerQuit = useCallback((data) => {
        if (data.payload.id !== playerId) {
            logSystemMessage(t('app.player_quit', { name: data.payload.name }));
        }
    }, [playerId, logSystemMessage, t]);

    const onError = useCallback((data) => {
        setFeedback({ text: data.payload, type: 'error' });
        setTimeout(() => setFeedback({ text: '', type: '' }), 5000);
    }, [setFeedback]);

    const onGameEnd = useCallback((data) => {
        const resultsData = {
            ...data.payload,
            results: data.payload.results || [],
            summary: data.payload.summary || (data.payload.results?.length > 0 ? t('results.round_over') : t('results.no_plays_round')),
        };
        if (resultsData.results.length > 0 && data.payload.definition) {
            resultsData.results[0].definition = data.payload.definition;
        }
        setResults(resultsData);
        setIsLocked(true);
        play('game_over');
        fetchLeaderboard();

        setMessages(prev => [
            ...prev,
            { sender: 'SYSTEM', text: resultsData.summary, isSystem: true, type: 'results_table', data: resultsData.results, timestamp: new Date(data.timestamp * 1000).toLocaleTimeString() },
            { isSeparator: true }
        ]);
    }, [setResults, setIsLocked, play, fetchLeaderboard, setMessages, t]);

    return {
        onChatMessage, onChatHistory, onIdentity,
        onGameStart, onTimer, onPlay,
        onPlayerJoined, onPlayerQuit, onError, onGameEnd
    };
}
