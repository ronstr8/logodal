import { useState, useCallback, useRef, useEffect } from 'react';
import { resolveMode, nextMode } from './playFeed';
import tuning from './feedTuning.json';

const STORAGE_KEY = 'logodal_feed_mode';

function readSavedMode() {
    try { return localStorage.getItem(STORAGE_KEY); } catch { return null; }
}

function prefersReducedMotion() {
    return typeof window !== 'undefined' && !!window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
}

// The play feed: an append-only list of plays and game-end notices, plus
// the viewer's chosen display mode. Display components subscribe to new
// items with useFeedSubscription; this hook never decides how they look.
export default function usePlayFeed() {
    const [mode, setModeState] = useState(() => resolveMode(readSavedMode(), prefersReducedMotion()));
    const [items, setItems] = useState([]);
    const nextId = useRef(1);

    const setMode = useCallback((m) => {
        setModeState(m);
        try { localStorage.setItem(STORAGE_KEY, m); } catch { /* private window: just don't remember */ }
    }, []);

    const cycleMode = useCallback(() => setMode(nextMode(mode)), [mode, setMode]);

    const push = useCallback((item) => {
        const withId = { ...item, id: nextId.current++ };
        setItems(prev => [...prev, withId].slice(-tuning.historyLimit));
    }, []);

    return { mode, setMode, cycleMode, items, push };
}

// Calls onNew with the items that arrived since the last render, ignoring
// anything already in the feed when the subscriber mounted, so switching
// modes doesn't replay old plays.
export function useFeedSubscription(items, onNew) {
    const lastSeen = useRef(items.length ? items[items.length - 1].id : 0);
    const onNewRef = useRef(onNew);
    onNewRef.current = onNew;
    useEffect(() => {
        const fresh = items.filter(i => i.id > lastSeen.current);
        if (!fresh.length) return;
        lastSeen.current = fresh[fresh.length - 1].id;
        onNewRef.current(fresh);
    }, [items]);
}
