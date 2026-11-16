import { useState, useRef, useEffect, useCallback } from 'react';
import { useTranslation } from 'react-i18next';
import { useFeedSubscription } from './usePlayFeed';
import { collapseBacklog, summaryNames, separatorAfter, scrollSpeed, fadeDwell, spawnX } from './playFeed';
import tuning from './feedTuning.json';
import './PlayFeed.css';

function useItemText() {
    const { t } = useTranslation();
    return useCallback((item) => (item.kind === 'summary'
        ? t('app.feed_played_many', { names: summaryNames(item.players, tuning.maxNames) })
        : item.text), [t]);
}

// Shows the play feed in the viewer's chosen mode. 'on' is the classic
// slide-out pop-ups; 'fade' and 'scroll' are a one-line strip at the top
// that sits in the page flow, so it can never cover the rack.
export default function PlayFeed({ mode, items }) {
    if (mode === 'on') return <FeedPopups items={items} />;
    if (mode === 'fade') return <FeedStrip><FadeLine items={items} /></FeedStrip>;
    if (mode === 'scroll') return <FeedStrip><ScrollLine items={items} /></FeedStrip>;
    return null;
}

function FeedStrip({ children }) {
    return <div className="feed-strip" role="log">{children}</div>;
}

function FeedPopups({ items }) {
    const text = useItemText();
    const [shown, setShown] = useState([]);
    useFeedSubscription(items, (fresh) => {
        setShown(prev => [...prev, ...fresh]);
        const ids = new Set(fresh.map(i => i.id));
        setTimeout(() => setShown(prev => prev.filter(i => !ids.has(i.id))), tuning.popupMs);
    });
    return (
        <div className="chat-toast-container">
            {shown.map(item => <div key={item.id} className="chat-toast"><div className="chat-toast-text">{text(item)}</div></div>)}
        </div>
    );
}

// One still line that crossfades to the next item, dwelling less the more
// are waiting, and clears itself once the feed goes quiet.
function FadeLine({ items }) {
    const text = useItemText();
    const [queue, setQueue] = useState([]);
    const [current, setCurrent] = useState(null);
    const shownAt = useRef(0);
    useFeedSubscription(items, (fresh) => setQueue(q => collapseBacklog([...q, ...fresh], tuning.collapseAt)));

    useEffect(() => {
        const showNext = () => {
            shownAt.current = Date.now();
            setCurrent(queue[0]);
            setQueue(q => q.slice(1));
        };
        if (!current) { if (queue.length) showNext(); return; }
        const wait = queue.length ? fadeDwell(queue.length, tuning) : tuning.fadeLingerMs;
        const timer = setTimeout(() => (queue.length ? showNext() : setCurrent(null)),
            Math.max(0, wait - (Date.now() - shownAt.current)));
        return () => clearTimeout(timer);
    }, [current, queue]);

    return current && <span key={current.id} className="feed-fade-item">{text(current)}</span>;
}

// A continuous ticker. Positions live in refs and are written straight to
// the DOM each frame, so React only re-renders when items enter or leave.
function ScrollLine({ items }) {
    const text = useItemText();
    const boxRef = useRef(null);
    const [shown, setShown] = useState([]);
    const shownRef = useRef(shown);
    shownRef.current = shown;
    const pos = useRef(new Map()); // id -> { el, x, width }
    const paused = useRef(false);
    const lastPointer = useRef('mouse');

    useFeedSubscription(items, (fresh) => setShown(prev => {
        const width = boxRef.current?.clientWidth ?? 0;
        const firstWaiting = prev.findIndex(i => !((pos.current.get(i.id)?.x ?? Infinity) < width));
        const entered = firstWaiting < 0 ? prev : prev.slice(0, firstWaiting);
        const pending = collapseBacklog([...prev.slice(entered.length), ...fresh], tuning.collapseAt);
        // Waiting items are re-placed in order next frame, since a summary changes their widths.
        pending.forEach(i => { const p = pos.current.get(i.id); if (p) p.x = undefined; });
        return [...entered, ...pending];
    }));

    useScrollLoop(boxRef, shownRef, pos, paused, setShown);

    const register = (id) => (el) => {
        if (!el) return;
        const p = pos.current.get(id) ?? {};
        pos.current.set(id, { ...p, el });
    };

    return (
        <div className="feed-scroll" ref={boxRef}
            onPointerDown={(e) => { lastPointer.current = e.pointerType; }}
            onPointerEnter={(e) => { if (e.pointerType === 'mouse') paused.current = true; }}
            onPointerLeave={(e) => { if (e.pointerType === 'mouse') paused.current = false; }}
            onClick={() => { if (lastPointer.current !== 'mouse') paused.current = !paused.current; }}>
            {shown.map(item => (
                <span key={item.id} ref={register(item.id)} className="feed-scroll-item">
                    {text(item)}<span className="feed-sep">{separatorAfter(item)}</span>
                </span>
            ))}
        </div>
    );
}

function useScrollLoop(boxRef, shownRef, pos, paused, setShown) {
    useEffect(() => {
        let raf;
        let last = performance.now();
        const step = (now) => {
            const dt = Math.min(0.1, (now - last) / 1000); // a hidden tab shouldn't jump on return
            last = now;
            const gone = advance(shownRef.current, pos.current, boxRef.current?.clientWidth ?? 0, paused.current ? 0 : dt);
            if (gone.length) {
                gone.forEach(id => pos.current.delete(id));
                setShown(prev => prev.filter(i => !gone.includes(i.id)));
            }
            raf = requestAnimationFrame(step);
        };
        raf = requestAnimationFrame(step);
        return () => cancelAnimationFrame(raf);
    }, [boxRef, shownRef, pos, paused, setShown]);
}

// One frame: place new items, move everything left, report what scrolled off.
function advance(list, pos, width, dt) {
    let prev = null;
    let backlog = 0;
    const placed = [];
    for (const item of list) {
        const p = pos.get(item.id);
        if (!p?.el) break; // not mounted yet; later items wait behind it
        p.width = p.el.offsetWidth;
        if (p.x === undefined) p.x = spawnX(prev, width);
        if (p.x >= width) backlog++;
        placed.push([item.id, p]);
        prev = p;
    }
    const dx = scrollSpeed(backlog, tuning) * dt;
    const gone = [];
    for (const [id, p] of placed) {
        p.x -= dx;
        p.el.style.transform = `translateX(${p.x}px)`;
        if (p.x + p.width < 0) gone.push(id);
    }
    return gone;
}
