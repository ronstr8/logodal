package Logodal::Game::AI;
use Mojo::Base -base, -signatures;
use utf8;
use Mojo::Util;
use UUID::Tiny qw(:std);
use Logodal::Util::NameGenerator;
use Mojo::JSON qw(encode_json decode_json);
use Mojo::UserAgent;

has 'app';
has 'game_id';
has 'player_id' => sub { create_uuid_as_string(UUID_V4) };
has 'nickname'  => sub { Logodal::Util::NameGenerator->new->generate(4, 1) };
has 'language'  => 'en';

# AI Config
has 'wait_seconds_base' => 5;
has 'max_seconds'       => 0;   # 0 = no cap; caps the latest possible play time
has 'rnd_word_count'    => 5;
has 'min_score_to_play' => 2;
has 'min_score_to_win'  => 30;
has 'min_word_length'   => 0;   # 0 = no minimum
has 'character_prompt';
has 'playtime_halflife_minutes' => 0;

# Instance state
has 'ua'              => sub { Mojo::UserAgent->new->request_timeout(20) }; # bounded, reused across calls
has 'rack'            => sub { '' }; # Current letters in hand
has 'candidates'      => sub { [] };
has 'play_time'       => 0;
has 'played'          => 0;
has 'thinking_times'  => sub { [] };
has 'last_score'      => 0;
has 'reacted_beaten'  => 0;

sub new_from_player ($class, $app, $game_id, $player, $language = undef) {
    my $brain = $player->brain // {};
    my $lang  = $language // $player->language // 'en';

    my $self = $class->new(
        app               => $app,
        game_id           => $game_id,
        language          => $lang,
        nickname          => $player->nickname,
        player_id         => $player->id,
        character_prompt          => $brain->{character_prompt},
        playtime_halflife_minutes => $brain->{playtime_halflife_minutes} // 0,
        wait_seconds_base         => $brain->{wait_seconds_base} // 8,
        max_seconds       => $brain->{max_seconds} // 0,
        rnd_word_count    => $brain->{rnd_word_count} // 5,
        min_score_to_play => $brain->{min_score_to_play} // 2,
        min_score_to_win  => $brain->{min_score_to_win} // 30,
        min_word_length   => $brain->{min_word_length} // 0,
    );
    $self->_init_schedule();
    return $self;
}

sub _init_schedule ($self) {
    my $total_dur = $ENV{GAME_DURATION} || 30;
    
    # Random play time between base and cap (or full duration if no cap)
    my $cap   = ($self->max_seconds && $self->max_seconds < $total_dur) ? $self->max_seconds : $total_dur;
    my $range = $cap - $self->wait_seconds_base;
    $range = 1 if $range < 1;
    $self->play_time($self->wait_seconds_base + int(rand($range)));
    
    # 1-2 thinking chats
    my $chats = 1 + int(rand(2));
    my @thinking;
    for (1 .. $chats) {
        push @thinking, 2 + int(rand($self->play_time - 2)) if $self->play_time > 3;
    }
    $self->thinking_times([ sort { $a <=> $b } @thinking ]);
}

sub fetch_candidates ($self, $rack_str) {
    $self->rack($rack_str);
    my $lang = $self->language;
    my $count = $self->rnd_word_count;
    my $wordd_base = $ENV{WORDD_URL} || "http://wordd:2345/";
    
    my $letters = $rack_str;
    $letters =~ s/_/?/g; # wordd uses ? for wildcards

    my $url = "${wordd_base}rand/langs/$lang/word?letters=$letters&count=$count";
    $url .= "&min_length=" . $self->min_word_length if $self->min_word_length > 0;
    
    $self->_request_candidates($url, $letters);
}

sub _request_candidates ($self, $url, $letters) {
    $self->app->ua->get($url => sub ($ua, $tx) {
        my $res = $tx->res;
        if ($res->is_success) {
            my $body = $res->body;
            my @words = split /\n/, $body;
            # Ensure they are uppercase and trimmed
            @words = map { uc(Mojo::Util::trim($_)) } grep { /\S/ } @words;
            $self->candidates(\@words);
            $self->app->log->debug("AI " . $self->nickname . " fetched " . scalar(@words) . " candidates for letters '$letters'");
        } else {
            my $err = $tx->error;
            $self->app->log->error("AI " . $self->nickname . " failed to fetch words for '$letters': " . ($err->{message} // 'Unknown error'));
        }
    });
}

sub tick ($self, $seconds_elapsed) {
    return if $self->played;

    # Time to play?
    if ($seconds_elapsed >= $self->play_time) {
        $self->play_best_word();
        return;
    }

    # Time to think? "Thinking" is pure filler — only when idle chatter is enabled.
    if (@{$self->thinking_times} && $seconds_elapsed >= $self->thinking_times->[0]) {
        shift @{$self->thinking_times};
        $self->generate_speech('thinking') if $self->_idle_chatter_on;
    }
}

# IDLE_CHATTER gates all canned/filler AI talk. Default OFF: AIs speak only when
# the LLM produces a line, and stay silent otherwise.
sub _idle_chatter_on ($self) {
    my $v = $ENV{IDLE_CHATTER};
    return 0 unless defined $v;
    return ($v eq '1' || lc($v) eq 'true') ? 1 : 0;
}

sub generate_speech ($self, $event_type, $args = {}) {
    my $ollama_url = $ENV{OLLAMA_URL};
    $self->app->log->debug("AI " . $self->nickname . " generating speech for event $event_type (Ollama: " . ($ollama_url // 'OFF') . ")");
    unless ($ollama_url) {
        $self->_canned_fallback($event_type, $args);
        return;
    }

    my $persona = $self->character_prompt // "You are a competitive word game player.";
    my $lang    = $self->language;
    my $rules   = $self->app->t('app.rules_summary', $lang);
    my $rack    = $self->rack;

    my $event_desc = "";
    if ($event_type eq 'thinking') {
        $event_desc = "You are thinking about your next word. Your rack is: $rack.";
    } elsif ($event_type eq 'beaten') {
        $event_desc = "Your last play was beaten by '" . ($args->{player} // 'someone') . "'.";
    } elsif ($event_type eq 'played') {
        $event_desc = "You just played '" . ($args->{word} // 'a word') . "' for " . ($args->{score} // 0) . " points.";
    }

    my $history  = $self->app->games->{ $self->game_id }{chat_history} // [];
    my $chat_ctx = $self->_format_chat_context($history);

    my $full_prompt = "$persona\n\n"
                    . "Game context: $rules | Language: $lang | Rack: $rack\n\n"
                    . $chat_ctx
                    . "Situation: $event_desc\n\n"
                    . "Say something brief (15 words max). No quotes.";

    my $gid = $self->game_id;
    $self->_ollama_say($full_prompt,
        sub ($speech) {
            return unless length $speech;
            return unless $self->app->games->{$gid}; # game may have ended while we waited
            $self->_broadcast_chat($speech);
        },
        sub {
            $self->app->log->error("Ollama speech generation failed ($event_type)");
            $self->_canned_fallback($event_type, $args);
        },
    );
}

# Emit a canned (pre-translated) line — but only when IDLE_CHATTER is on.
# With it off, the AI simply stays silent rather than spewing filler.
sub _canned_fallback ($self, $event_type, $args) {
    return unless $self->_idle_chatter_on;
    my $key = "ai.$event_type";
    $key = "ai.reaction_beaten" if $event_type eq 'beaten';
    $self->chat($key, $args);
}

# Format the last N chat messages for prompt context. N = OLLAMA_CHAT_CONTEXT_DEPTH.
sub _format_chat_context ($self, $history) {
    my $depth = $ENV{OLLAMA_CHAT_CONTEXT_DEPTH} // 0;
    return '' unless $depth > 0 && $history && @$history;
    my @recent = @$history;
    @recent = @recent[ -$depth .. -1 ] if @recent > $depth;
    my @lines = map {
        ($_->{payload}{senderName} // $_->{sender} // '?') . ': ' . ($_->{payload}{text} // '')
    } @recent;
    return @lines ? "Recent game chat:\n" . join("\n", @lines) . "\n\n" : '';
}

# Single point for talking to Ollama. Reuses a bounded per-AI UA so slow/hung
# requests can't pile up. Calls $on_say->($text) on success, $on_err->() on failure.
sub _ollama_say ($self, $prompt, $on_say, $on_err = undef) {
    my $ollama_url = $ENV{OLLAMA_URL} or return;
    $self->ua->post($ollama_url . "/api/generate" => json => {
        model  => $ENV{OLLAMA_MODEL} // 'llama3.1:8b',
        prompt => $prompt,
        stream => \0,
        # Cap generation: a chat line is ~15 words; this bounds rambling and latency.
        options => { num_predict => $ENV{OLLAMA_NUM_PREDICT} // 60 },
    } => sub ($ua, $tx) {
        my $res = $tx->res;
        if ($res->is_success) {
            my $speech = $self->_sanitize_speech($res->json->{response});
            $on_say->($speech);
        } else {
            my $err_msg = $tx->error ? $tx->error->{message} : "Status " . ($res->code // 'unknown');
            $self->app->log->error("Ollama request failed: $err_msg");
            $on_err->() if $on_err;
        }
    });
}

# Defensive clamp on whatever the model returns. Weak models (e.g. tinyllama)
# ignore "keep it short" and continue/echo the prompt, so we never trust the raw
# output: take the first line only, drop a leading "Name:" label and wrapping
# quotes, and hard-cap the word count. Bounds the worst case to a short line.
sub _sanitize_speech ($self, $raw) {
    return '' unless defined $raw && length $raw;
    my ($line) = grep { /\S/ } split /\r?\n/, $raw;  # first non-empty line
    return '' unless defined $line;
    $line =~ s/^\s+|\s+$//g;
    my $nick = $self->nickname // '';
    $line =~ s/^\Q$nick\E\s*:\s*//i if length $nick;          # drop self-name prefix
    $line =~ s/^["'\x{201c}\x{201d}]+|["'\x{201c}\x{201d}]+$//g; # wrapping quotes
    my $cap   = $ENV{AI_SPEECH_MAX_WORDS} // 25;
    my @words = split /\s+/, $line;
    if (@words > $cap) {
        $line = join(' ', @words[0 .. $cap - 1]);
        $line =~ s/[,;:\s]+$//;
        $line .= '...';
    }
    return $line;
}

sub _broadcast_chat ($self, $text) {
    my $msg = {
        type    => 'chat',
        sender  => $self->player_id,
        payload => {
            text       => $text,
            senderName => $self->nickname,
        }
    };
    $self->app->broadcast_to_game($msg, $self->game_id);
}

sub play_best_word ($self) {
    my $words = $self->candidates;
    return unless @$words;

    my $game_data = $self->app->games->{$self->game_id};
    return unless $game_data;
    my $game_record = $game_data->{state};

    # Calculate scores for all candidates
    my @scored;
    my %seen_words;
    for my $w (@$words) {
        next if $seen_words{$w}++;
        push @scored, { word => $w, score => $self->app->scorer->calculate_score($w, $game_record->letter_values) };
    }

    # Sort DESC
    @scored = sort { $b->{score} <=> $a->{score} } @scored;
    @scored = grep { length($_->{word}) >= $self->min_word_length } @scored if $self->min_word_length;

    my $chosen;
    # Filter by min score for "good" plays
    my @filtered = grep { $_->{score} >= $self->min_score_to_play } @scored;

    if (@filtered) {
        if ($filtered[0]{score} >= $self->min_score_to_win) {
            $chosen = $filtered[0];
            $self->app->log->debug("AI " . $self->nickname . " chose high-score word: " . $chosen->{word} . " (" . $chosen->{score} . ")");
        } else {
            # Random pick among valid-enough candidates
            $chosen = $filtered[int(rand(@filtered))];
            $self->app->log->debug("AI " . $self->nickname . " chose random word: " . $chosen->{word} . " (" . $chosen->{score} . ")");
        }
    } elsif (@scored) {
        # FALLBACK: Just pick any valid word if no words meet the AI's "pride" threshold
        # This prevents the AI from just skipping multiple rounds
        $chosen = $scored[0];
        $self->app->log->debug("AI " . $self->nickname . " using fallback play: " . $chosen->{word} . " (" . $chosen->{score} . ")");
    }

    if ($chosen) {
        $self->played(1);
        $self->last_score($chosen->{score});
        $self->_execute_play($chosen->{word}, $chosen->{score}, $game_record);
        $self->generate_speech('played', { word => $chosen->{word}, score => $chosen->{score} });
    } else {
        $self->app->log->debug("AI " . $self->nickname . " found NO valid plays this round (candidates: " . scalar(@$words) . ")");
    }
}

sub _execute_play ($self, $word, $score, $game_record) {
    my $app = $self->app;
    
    # Persist the play (AI players don't save ranking, but their round play is recorded)
    $app->schema->resultset('Play')->create({
        game_id   => $game_record->id,
        player_id => $self->player_id,
        word      => $word,
        score     => $score,
    });

    $app->log->debug("AI " . $self->nickname . " played: $word ($score pts)");

    # Broadcast
    # Broadcast using the app's broadcaster (safer than manual loop)
    my $timestamp = time;
    my $msg = {
        type      => 'play',
        sender    => $self->player_id,
        timestamp => $timestamp,
        payload   => {
            playerName => $self->nickname,
            word       => undef,
            score      => $score,
            msg        => $self->nickname . " played a word for $score pts!",
        }
    };
    $app->broadcaster->announce_to_game($msg, $self->game_id);

    # Calculate achievement emojis
    my $actual_rack_size = (ref($game_record->rack) eq 'ARRAY' ? scalar(@{$game_record->rack}) : 0);
    my $len_bonus = $app->scorer->get_length_bonus($word, $actual_rack_size);
    my $emoji_prefix = $app->game_manager->_get_achievement_emojis($game_record, $word, $len_bonus);

    # Global Chat Broadcast
    my $chat_msg = $app->t('app.played_word', $self->language, { 
        player     => $self->nickname, 
        tile_count => length($word), 
        raw_points => $score 
    });
    $app->broadcast_to_game({
        type    => 'chat',
        sender  => 'SYSTEM',
        payload => {
            text       => $emoji_prefix . $chat_msg,
            senderName => $self->nickname,
        },
        timestamp => $timestamp,
    }, $self->game_id);

    # Premature Climax check
    $app->game_manager->_check_premature_climax($self->game_id);
}

# --- Background social commentary (LLM-only; never canned) ---
# Generate one short, in-character social line and deliver it. Chat context is
# pulled from Redis (cross-replica) via the broadcaster, not the local array.
sub social_say ($self, $gid, $kind, $ctx) {
    my $app  = $self->app;
    my $lang = $self->language;
    my $persona = $self->character_prompt // "You are a friendly but competitive word-game player.";

    my $situation;
    if ($kind eq 'greet') {
        $situation = "A player called '" . ($ctx->{name} // 'someone') . "' just joined the game. Greet them in one short, welcoming line.";
    } elsif ($kind eq 'compliment') {
        $situation = "'" . ($ctx->{name} // 'A player') . "' just played '" . ($ctx->{word} // '') . "' for " . ($ctx->{score} // 0) . " points. React with a brief, genuine compliment.";
    } elsif ($kind eq 'congrat') {
        $situation = "The game just ended. '" . ($ctx->{name} // 'someone') . "' won with '" . ($ctx->{word} // '') . "' (" . ($ctx->{score} // 0) . " pts). Congratulate them in one short line.";
    } else {
        return;
    }

    my $local = $app->games->{$gid}{chat_history} // [];
    $app->broadcaster->get_chat_history($gid, $local, sub ($history) {
        my $prompt = "$persona\n\n"
                   . "You are chatting in a multiplayer word game (language: $lang). Keep it casual and human.\n\n"
                   . $self->_format_chat_context($history)
                   . "Situation: $situation\n\n"
                   . "Reply with ONE short line (12 words max). No quotes.";
        $self->_ollama_say($prompt, sub ($speech) {
            return unless length $speech;
            $self->_deliver_social($gid, $kind, $ctx, $speech);
        });
    });
}

sub _deliver_social ($self, $gid, $kind, $ctx, $text) {
    my $app = $self->app;
    my $msg = {
        type    => 'chat',
        sender  => $self->player_id,
        payload => { text => $text, senderName => $self->nickname },
    };
    if ($kind eq 'congrat') {
        # The game is already torn down by now; reach the players on their
        # personal channels (subscriptions survive game end).
        my $pids = $ctx->{recipient_pids} // [];
        $app->broadcaster->announce($msg, $pids) if @$pids;
    } else {
        return unless $app->games->{$gid}; # game still live
        $app->broadcast_to_game($msg, $gid);
    }
}

sub chat ($self, $key, $args = {}) {
    my $lang = $self->language;
    my $text = $self->app->t($key, $lang, $args);

    $self->_broadcast_chat($text);
}

sub check_reaction ($self, $player_name, $player_score) {
    return if $self->reacted_beaten;
    return unless $self->last_score > 0;

    if ($player_score > $self->last_score) {
        $self->reacted_beaten(1);
        $self->generate_speech('beaten', { player => $player_name });
    }
}

1;

