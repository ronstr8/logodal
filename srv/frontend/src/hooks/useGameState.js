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
    const [playerBrands, setPlayerBrands] = useState({}); // player id -> brand, learned from messages
    const [supportedLangs, setSupportedLangs] = useState({ en: { name: 'English', word_count: 0 } });
    const [messages, setMessages] = useState([]);
    const [toasts, setToasts] = useState([]);
    const [mutantLetter, setMutantLetter] = useState(null);
    // Server defaults; the identity message replaces both on connect.
    const [rackSize, setRackSize] = useState(7);
    const [lengthBonusStart, setLengthBonusStart] = useState(5);
    const [lengthBonusBase, setLengthBonusBase] = useState(10);
    // Tile values without the mutant letter's 10, for the help panel.
    const [baseLetterValue, setBaseLetterValue] = useState({});

    const rackRef = useRef([]);
    const guessRef = useRef([]);
    const playerNamesRef = useRef({});
    const toastSeq = useRef(0); // Date.now() collides when two toasts land in the same ms

    useEffect(() => { rackRef.current = rack; }, [rack]);
    useEffect(() => { guessRef.current = guess; }, [guess]);
    useEffect(() => { playerNamesRef.current = playerNames; }, [playerNames]);

    const showToast = useCallback((message, isSplat = false) => {
        const id = ++toastSeq.current;
        setToasts(prev => [...prev, { id, message, isSplat }]);
        setTimeout(() => {
            setToasts(prev => prev.filter(t => t.id !== id));
        }, 2000);
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
        playerBrands, setPlayerBrands,
        supportedLangs, setSupportedLangs,
        messages, setMessages,
        toasts, setToasts, showToast,
        logSystemMessage,
        handleTimerTick,
        mutantLetter, setMutantLetter,
        rackSize, setRackSize,
        lengthBonusStart, setLengthBonusStart,
        lengthBonusBase, setLengthBonusBase,
        baseLetterValue, setBaseLetterValue
    };
}
