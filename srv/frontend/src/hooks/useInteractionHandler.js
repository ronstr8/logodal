import { useCallback, useEffect } from 'react';

export default function useInteractionHandler({
    state,
    sendMessage,
    play,
    t
}) {
    const {
        rack, setRack, rackRef,
        guess, setGuess, guessRef,
        isLocked, timeLeft,
        setBlankChoice, results,
        rackSize
    } = state;

    const returnToRack = useCallback((slotIndex) => {
        if (isLocked || timeLeft === 0) return;

        setGuess(currentGuess => {
            const targetIndex = slotIndex !== undefined ? slotIndex :
                [...currentGuess].reverse().findIndex(g => g !== null);

            const actualIndex = slotIndex !== undefined ? slotIndex :
                (targetIndex === -1 ? -1 : currentGuess.length - 1 - targetIndex);

            if (actualIndex === -1) return currentGuess;

            const played = currentGuess[actualIndex];
            if (!played) return currentGuess;

            const newGuess = [...currentGuess];
            newGuess[actualIndex] = null;
            setRack(prev => prev.map(t => t.id === played.id ? { ...t, isUsed: false } : t));
            return newGuess;
        });
    }, [isLocked, timeLeft, setGuess, setRack]);

    const playTile = useCallback((tileId, letter, slotIndex) => {
        const tile = rack.find(t => t.id === tileId);
        if (!tile) return;

        const newGuess = [...guess];
        newGuess[slotIndex] = { id: tileId, char: letter.toLowerCase(), originalLetter: '_' };
        setGuess(newGuess);
        setRack(prev => prev.map(t => t.id === tileId ? { ...t, isUsed: true } : t));
        setBlankChoice(null);
        play('placement');
    }, [rack, guess, setGuess, setRack, setBlankChoice, play]);

    const moveTileToGuess = useCallback((tile) => {
        if (isLocked || timeLeft === 0 || tile.isUsed) return;

        setGuess(currentGuess => {
            const emptyIndex = currentGuess.findIndex(g => g === null);
            if (emptyIndex === -1) return currentGuess;

            if (tile.letter === '_') {
                setBlankChoice({ slotIndex: emptyIndex, tileId: tile.id });
                return currentGuess;
            }

            const newGuess = [...currentGuess];
            newGuess[emptyIndex] = { id: tile.id, char: tile.letter, originalLetter: tile.letter };
            setRack(prev => prev.map(t => t.id === tile.id ? { ...t, isUsed: true } : t));
            play('placement');
            return newGuess;
        });
    }, [isLocked, timeLeft, setGuess, setRack, setBlankChoice, play]);

    const submitWord = useCallback(() => {
        const word = guess.map(g => g ? g.char : '').join('').trim();
        if (word.length === 0) return;

        const len = word.length;
        if (len === 6) play('placement');
        else if (len === 7) { play('placement'); setTimeout(() => play('placement'), 150); }
        else if (len >= 8) play('bigsplat');

        sendMessage('play', { word });
    }, [guess, sendMessage, play]);

    const jumbleRack = useCallback(() => {
        if (isLocked || timeLeft === 0) return;
        setRack(prev => {
            const shuffled = [...prev];
            for (let i = shuffled.length - 1; i > 0; i--) {
                const j = Math.floor(Math.random() * (i + 1));
                [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
            }
            return shuffled.map((tile, idx) => ({ ...tile, position: idx }));
        });
    }, [isLocked, timeLeft, setRack]);

    const clearGuess = useCallback(() => {
        if (isLocked || timeLeft === 0) return;
        setRack(prev => prev.map(tile => ({ ...tile, isUsed: false })));
        setGuess(Array(rackSize).fill(null));
    }, [isLocked, timeLeft, rackSize, setRack, setGuess]);

    const handleGlobalKeyDown = useCallback((e) => {
        if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA' || e.target.isContentEditable || e.target.closest('.chat-input-area')) return;
        if (isLocked || timeLeft === 0 || results) return;

        if (e.key === 'Backspace') { e.preventDefault(); returnToRack(); }
        else if (e.key === 'Enter') { e.preventDefault(); submitWord(); }
        else if (e.key.length === 1 && /[a-zA-Z]/.test(e.key)) {
            e.preventDefault();
            const char = e.key.toUpperCase();
            const currentRack = rackRef.current;
            const currentGuess = guessRef.current;

            const exactTile = currentRack.find(t => t.letter === char && !t.isUsed);
            if (exactTile) moveTileToGuess(exactTile);
            else {
                const blankTile = currentRack.find(t => t.letter === '_' && !t.isUsed);
                if (blankTile) {
                    const emptyIndex = currentGuess.findIndex(g => g === null);
                    if (emptyIndex !== -1) playTile(blankTile.id, char, emptyIndex);
                } else play('buzzer');
            }
        }
    }, [isLocked, timeLeft, results, returnToRack, submitWord, moveTileToGuess, playTile, play, rackRef, guessRef]);

    useEffect(() => {
        window.addEventListener('keydown', handleGlobalKeyDown);
        return () => window.removeEventListener('keydown', handleGlobalKeyDown);
    }, [handleGlobalKeyDown]);

    return {
        returnToRack,
        playTile,
        moveTileToGuess,
        submitWord,
        jumbleRack,
        clearGuess
    };
}
