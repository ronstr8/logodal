// Rules for the play feed: which display mode applies, how items are
// separated, and how a backlog catches up. Pure functions, so the React
// components only animate and draw. Tuning numbers come in as `cfg`
// (see feedTuning.json).

export const FEED_MODES = ['off', 'on', 'fade', 'scroll'];

export function nextMode(mode) {
    return FEED_MODES[(FEED_MODES.indexOf(mode) + 1) % FEED_MODES.length];
}

// Scrolling text is hard on people who ask their device for less motion,
// so they start on the still, fading line. An explicit choice always wins.
export function resolveMode(saved, prefersReducedMotion) {
    if (FEED_MODES.includes(saved)) return saved;
    return prefersReducedMotion ? 'fade' : 'scroll';
}

export function separatorAfter(item) {
    return item.kind === 'end' ? ' · ' : ' … ';
}

const playersOf = (item) => (item.kind === 'summary' ? item.players : [item.player]);

// When more than `collapseAt` items are waiting, fold each run of plays into
// one summary so the feed never lags into the next round. Game-end notices
// stay put: they mark where one round's plays stop.
export function collapseBacklog(pending, collapseAt) {
    if (pending.length <= collapseAt) return pending;
    const out = [];
    for (const item of pending) {
        const last = out[out.length - 1];
        if (item.kind !== 'end' && last && last.kind !== 'end') {
            out[out.length - 1] = { id: last.id, kind: 'summary', players: [...playersOf(last), ...playersOf(item)] };
        } else {
            out.push(item);
        }
    }
    return out;
}

export function summaryNames(players, maxNames) {
    if (players.length <= maxNames) return players.join(', ');
    const shown = maxNames - 1;
    return `${players.slice(0, shown).join(', ')} +${players.length - shown}`;
}

export function scrollSpeed(backlog, cfg) {
    const factor = Math.min(cfg.maxSpeedFactor, 1 + cfg.catchUpBoostPerItem * backlog);
    return cfg.scrollPxPerSec * factor;
}

export function fadeDwell(backlog, cfg) {
    return Math.max(cfg.fadeMinDwellMs, cfg.fadeDwellMs - cfg.fadeDwellStepMs * backlog);
}

// Where a new item starts: at the right edge, or right behind the previous
// item if that one hasn't fully entered yet, so items never overlap.
export function spawnX(prev, containerWidth) {
    if (!prev) return containerWidth;
    return Math.max(containerWidth, prev.x + prev.width);
}
