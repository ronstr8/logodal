import { test } from 'node:test';
import assert from 'node:assert/strict';
import { lengthBonus } from './scoring.js';

// Mirrors Scorer::get_length_bonus: base at `start` letters, doubling per letter after.
test('no length bonus below the starting length', () => {
    assert.equal(lengthBonus(4, 5, 10), 0);
    assert.equal(lengthBonus(0, 5, 10), 0);
});

test('the base bonus at the starting length, doubling for each letter after', () => {
    assert.equal(lengthBonus(5, 5, 10), 10);
    assert.equal(lengthBonus(6, 5, 10), 20);
    assert.equal(lengthBonus(7, 5, 10), 40);
});

test('follows a different start and base', () => {
    assert.equal(lengthBonus(5, 6, 5), 0);
    assert.equal(lengthBonus(6, 6, 5), 5);
    assert.equal(lengthBonus(8, 6, 5), 20);
});
