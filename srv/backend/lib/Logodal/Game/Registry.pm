package Logodal::Game::Registry;
use Moose;
use v5.36;
use utf8;
use UUID::Tiny qw(:std);
use DateTime;

has 'app' => ( is => 'ro', required => 1 );

my $DEFAULT_GAME_DURATION = $ENV{GAME_DURATION} || 30;
my $DEFAULT_LANG = $ENV{DEFAULT_LANG} || 'en';

sub get_or_create_game ($self, $player, $invite_gid = undef) {
    my $app = $self->app;
    my $schema = $app->schema;
    my $lang = $player->language // $DEFAULT_LANG;
    
    # 1. Search for active (started) game
    my $game_rs = $schema->resultset('Game');
    my $active_game;

    if ($invite_gid) {
        $active_game = $game_rs->find($invite_gid);
        if ($active_game && $active_game->finished_at) {
            $app->log->debug("Invited game $invite_gid already finished, falling back to active search");
            $active_game = undef;
        }
    }

    if (!$active_game) {
        $active_game = $game_rs->search(
            { 
                finished_at => undef, 
                language    => $lang,
                started_at  => { -not => undef }
            }, 
            { order_by => { -desc => 'started_at' }, rows => 1 }
        )->single;
    }

    # Check for stale games
    if ($active_game) {
        my $gid = $active_game->id;
        my $elapsed = time - $active_game->started_at->epoch;
        my $total_dur = $ENV{GAME_DURATION} || $DEFAULT_GAME_DURATION;
        
        if ($elapsed >= $total_dur) {
            $app->log->debug("Found stale game $gid, rotating...");
            # We don't call _end_game directly here to avoid circular dependency
            # Instead, we return undef to force a new game, and the controller will handle cleanup
            return { action => 'end_and_retry', game => $active_game };
        }
    }

    # 2. If no active, look for pending
    if (!$active_game) {
        $active_game = $game_rs->search(
            { 
                finished_at => undef, 
                language    => $lang,
                started_at  => undef 
            }, 
            { order_by => { -asc => 'created_at' }, rows => 1 }
        )->single;

        if ($active_game) {
            my $gid = $active_game->id;
            $app->log->debug("Starting pending $lang game $gid");
            my %updates = ( started_at => DateTime->now );
            unless ($active_game->mutant_letter) {
                my $vals = { %{ $active_game->letter_values } }; # copy — mutant may modify
                my $mutant = $self->_pick_mutant_letter($schema, $active_game->rack, $vals);
                if ($mutant) {
                    $vals->{$mutant} = 10;
                    $updates{letter_values} = $vals;
                    $updates{mutant_letter} = $mutant;
                    $app->log->info("Mutant letter for pending game $gid: $mutant");
                }
            }
            $active_game->update(\%updates);
            $self->_init_in_memory_game($gid, $active_game, $lang);
            return { action => 'start_timer', game => $active_game };
        }
        else {
            # Fallback: Create and start immediately
            $app->log->debug("No pending game found, creating emergency $lang game");
            my $rack = $app->scorer->get_random_rack($lang);
            my $vals = $app->scorer->mutable_tile_values($lang);
            my $mutant = $self->_pick_mutant_letter($schema, $rack, $vals);
            if ($mutant) {
                $vals->{$mutant} = 10;
                $app->log->info("Mutant letter for new game: $mutant");
            }

            my $gid = create_uuid_as_string(UUID_V4);
            $active_game = eval {
                $game_rs->create({
                    id            => $gid,
                    rack          => $rack,
                    letter_values => $vals,
                    language      => $lang,
                    started_at    => DateTime->now,
                    ($mutant ? (mutant_letter => $mutant) : ()),
                });
            };
            
            if ($@) {
                my $err = $@;
                if ($err =~ /unique constraint/i) {
                     return { action => 'retry' };
                }
                die $err;
            }

            $self->_init_in_memory_game($gid, $active_game, $lang);
            return { action => 'start_timer', game => $active_game };
        }
    }
    else {
        # Active game found, ensure it's in memory (Zombie Recovery)
        my $gid = $active_game->id;
        if (!$app->games->{$gid}) {
             my $elapsed = time - $active_game->started_at->epoch;
             my $total_dur = $ENV{GAME_DURATION} || $DEFAULT_GAME_DURATION;
             $self->_init_in_memory_game($gid, $active_game, $lang, $total_dur - $elapsed);
             return { action => 'start_timer', game => $active_game };
        }
        return { action => 'join', game => $active_game };
    }
}

sub _init_in_memory_game ($self, $gid, $game_record, $lang, $time_left = undef) {
    my $app = $self->app;
    require Logodal::Game::AI;

    my @all_ais = $app->schema->resultset('Player')->search({ brain => { '!=', undef } })->all;
    my @ais = map { Logodal::Game::AI->new_from_player($app, $gid, $_, $lang) } @all_ais;

    $app->games->{$gid} = {
        clients   => {},
        state     => $game_record,
        time_left => $time_left // ($ENV{GAME_DURATION} || $DEFAULT_GAME_DURATION),
        ais       => \@ais,
    };
}

sub _pick_mutant_letter ($self, $schema, $rack, $vals) {
    # Find the most recently finished game with more than one unique player
    my $last_game = $schema->resultset('Game')->search(
        { finished_at => { '!=' => undef } },
        { order_by => { -desc => 'finished_at' }, rows => 1 }
    )->first;

    return undef unless $last_game;

    my @plays = $schema->resultset('Play')->search(
        { game_id => $last_game->id },
        { order_by => { -asc => 'created_at' } }
    )->all;

    my %seen_players = map { $_->player_id => 1 } @plays;
    return undef if scalar(keys %seen_players) < 2;  # solo game doesn't count

    # Check whether every player received at least one bonus
    my %word_players;  # word => [ player_ids in order ]
    for my $p (@plays) {
        push @{ $word_players{ $p->word } }, $p->player_id;
    }

    my $rack_size = scalar(@$rack);
    my $min_bonus_len = int($rack_size / 2) + 1;
    my $quick_secs = $ENV{QUICK_BONUS_SECONDS} || 5;

    my %player_has_bonus;
    for my $p (@plays) {
        my $pid  = $p->player_id;
        my $word = $p->word;

        # Length bonus
        if (length($word) >= $min_bonus_len) {
            $player_has_bonus{$pid} = 1;
            next;
        }
        # Unique word bonus (only player with that word)
        if (scalar(@{ $word_players{$word} }) == 1) {
            $player_has_bonus{$pid} = 1;
            next;
        }
        # Duplicate bonus (first player with that word, others copied them)
        if ($word_players{$word}[0] eq $pid && scalar(@{ $word_players{$word} }) > 1) {
            $player_has_bonus{$pid} = 1;
            next;
        }
        # Quick bonus
        if ($last_game->started_at) {
            my $elapsed = $p->created_at->epoch - $last_game->started_at->epoch;
            if ($elapsed <= $quick_secs) {
                $player_has_bonus{$pid} = 1;
                next;
            }
        }
    }

    # All players must have received a bonus
    for my $pid (keys %seen_players) {
        return undef unless $player_has_bonus{$pid};
    }

    # Pick a random rack letter that isn't blank and isn't already worth 10+
    my @candidates = grep { $_ ne '_' && ($vals->{$_} // 0) < 10 } @$rack;
    return undef unless @candidates;

    return $candidates[ int(rand(@candidates)) ];
}

1;

