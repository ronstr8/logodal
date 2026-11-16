// Client-side copy of the scoring rules the UI needs to preview. The server
// (Logodal::Game::Scorer) stays the authority; keep these in step with it.

// Mirrors Scorer::get_length_bonus: `base` points for a word of `start`
// letters, doubling for every letter after.
export function lengthBonus(length, start, base) {
    const extra = length - start;
    return extra < 0 ? 0 : base * 2 ** extra;
}
