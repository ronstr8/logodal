import { useState, useRef, useCallback, useEffect } from 'react';

export default function useGameState(t) {
    const [rack, setRack] = useState([]);
    const [guess, setGuess] = useState(Array(8).fill(null));
    const [timeLeft, setTimeLeft] = useState(0);
    const [totalTime, setTotalTime] = useState(30);
    const [results, setResults] = useState(null);
    const [isLocked, setIsLocked] = useState(false);
    const [gameId, setGameId] = useState(null);
    const [feedback, setFeedback] = useState({ text: '', type: '' });
    const [blankChoice, setBlankChoice] = useState(null);
    const [letterValue, setLetterValue] = useState({});
    const [tileConfig, setTileConfig] = useState({ tiles: {}, unicorns: {} });
    const [playerNames, setPlayerNames] = useState({});
    const [supportedLangs, setSupportedLangs] = useState({ en: { name: 'English', word_count: 0 } });
    const [messages, setMessages] = useState([]);
    const [toasts, setToasts] = useState([]);
    const [chatToasts, setChatToasts] = useState([]);
    const [mutantLetter, setMutantLetter] = useState(null);
    const [rackSize, setRackSize] = useState(8);

    const rackRef = useRef([]);
    const guessRef = useRef([]);
    const playerNamesRef = useRef({});

    useEffect(() => { rackRef.current = rack; }, [rack]);
    useEffect(() => { guessRef.current = guess; }, [guess]);
    useEffect(() => { playerNamesRef.current = playerNames; }, [playerNames]);

    const showToast = useCallback((message, isSplat = false) => {
        const id = Date.now();
        setToasts(prev => [...prev, { id, message, isSplat }]);
        setTimeout(() => {
            setToasts(prev => prev.filter(t => t.id !== id));
        }, 2000);
    }, []);

    const showChatToast = useCallback((senderName, text) => {
        const id = Date.now();
        setChatToasts(prev => [...prev, { id, senderName, text }]);
        setTimeout(() => {
            setChatToasts(prev => prev.filter(t => t.id !== id));
        }, 3000);
    }, []);

    const logSystemMessage = useCallback((text, type = 'system', data = null) => {
        setMessages(prev => [...prev, {
            sender: 'SYSTEM',
            text,
            isSystem: true,
            type,
            data,
            timestamp: new Date().toLocaleTimeString()
        }]);
    }, []);

    const handleTimerTick = useCallback(() => {
        if (timeLeft > 0) {
            setTimeLeft(prev => Math.max(0, prev - 1));
        }
    }, [timeLeft]);

    return {
        rack, setRack, rackRef,
        guess, setGuess, guessRef,
        timeLeft, setTimeLeft,
        totalTime, setTotalTime,
        results, setResults,
        isLocked, setIsLocked,
        gameId, setGameId,
        feedback, setFeedback,
        blankChoice, setBlankChoice,
        letterValue, setLetterValue,
        tileConfig, setTileConfig,
        playerNames, setPlayerNames, playerNamesRef,
        supportedLangs, setSupportedLangs,
        messages, setMessages,
        toasts, setToasts, showToast,
        chatToasts, setChatToasts, showChatToast,
        logSystemMessage,
        handleTimerTick,
        mutantLetter, setMutantLetter,
        rackSize, setRackSize
    };
}
