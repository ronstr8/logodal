import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
    FEED_MODES, nextMode, resolveMode, separatorAfter,
    collapseBacklog, summaryNames, scrollSpeed, fadeDwell, spawnX,
} from './playFeed.js';

const cfg = {
    scrollPxPerSec: 80, catchUpBoostPerItem: 0.5, maxSpeedFactor: 3,
    fadeDwellMs: 3000, fadeMinDwellMs: 1000, fadeDwellStepMs: 500,
    maxNames: 3,
};
const play = (id, player) => ({ id, kind: 'play', player, text: `${player} played` });
const end = (id) => ({ id, kind: 'end', text: 'Round over' });

test('modes cycle off → fade → scroll → off', () => {
    assert.deepEqual(FEED_MODES, ['off', 'fade', 'scroll']);
    assert.equal(nextMode('off'), 'fade');
    assert.equal(nextMode('scroll'), 'off');
});

test('a saved mode wins; otherwise reduced motion picks fade over scroll', () => {
    assert.equal(resolveMode('off', true), 'off');
    assert.equal(resolveMode('scroll', true), 'scroll');
    assert.equal(resolveMode(null, true), 'fade');
    assert.equal(resolveMode(null, false), 'scroll');
    assert.equal(resolveMode('bogus', false), 'scroll');
});

test('the retired pop-up mode falls back to the default', () => {
    assert.equal(resolveMode('on', false), 'scroll');
    assert.equal(resolveMode('on', true), 'fade');
});

test('plays are followed by an ellipsis, the game-end notice by a centre dot', () => {
    assert.equal(separatorAfter(play(1, 'A')), ' … ');
    assert.equal(separatorAfter(end(2)), ' · ');
});

test('a short backlog is left alone', () => {
    const pending = [play(1, 'A'), play(2, 'B')];
    assert.equal(collapseBacklog(pending, 3), pending);
});

test('a long backlog folds each run of plays into one summary, keeping game ends', () => {
    const pending = [play(1, 'A'), play(2, 'B'), play(3, 'C'), end(4), play(5, 'D')];
    assert.deepEqual(collapseBacklog(pending, 3), [
        { id: 1, kind: 'summary', players: ['A', 'B', 'C'] },
        end(4),
        play(5, 'D'),
    ]);
});

test('a summary already in the backlog absorbs the plays after it', () => {
    const pending = [{ id: 1, kind: 'summary', players: ['A', 'B'] }, play(3, 'C'), play(4, 'D'), play(5, 'E')];
    assert.deepEqual(collapseBacklog(pending, 3), [
        { id: 1, kind: 'summary', players: ['A', 'B', 'C', 'D', 'E'] },
    ]);
});

test('summary names list everyone up to the limit, then count the rest', () => {
    assert.equal(summaryNames(['A', 'B'], 3), 'A, B');
    assert.equal(summaryNames(['A', 'B', 'C'], 3), 'A, B, C');
    assert.equal(summaryNames(['A', 'B', 'C', 'D', 'E'], 3), 'A, B +3');
});

test('scrolling speeds up with the backlog, up to a cap', () => {
    assert.equal(scrollSpeed(0, cfg), 80);
    assert.equal(scrollSpeed(2, cfg), 160);
    assert.equal(scrollSpeed(50, cfg), 240);
});

test('fade dwell shortens with the backlog, down to a floor', () => {
    assert.equal(fadeDwell(0, cfg), 3000);
    assert.equal(fadeDwell(2, cfg), 2000);
    assert.equal(fadeDwell(50, cfg), 1000);
});

test('a new item enters at the right edge, or queues behind the last one', () => {
    assert.equal(spawnX(null, 600), 600);
    assert.equal(spawnX({ x: 100, width: 200 }, 600), 600);
    assert.equal(spawnX({ x: 500, width: 300 }, 600), 800);
});
