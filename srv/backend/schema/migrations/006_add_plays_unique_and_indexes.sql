-- Prevent duplicate plays per player per game
ALTER TABLE plays ADD CONSTRAINT plays_game_player_unique UNIQUE (game_id, player_id);

-- Speed up the active-game-by-language query run on every player join
CREATE INDEX IF NOT EXISTS idx_games_active_lang
    ON games (language, started_at, finished_at)
    WHERE finished_at IS NULL;
