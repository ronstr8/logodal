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
            my $vals = { %{ $active_game->letter_values } }; # copy — mutant may modify
            my $mutant = $self->_pick_mutant_letter($active_game->rack, $vals);
            if ($mutant) {
                $vals->{$mutant} = 10;
                $updates{letter_values} = $vals;
                $updates{mutant_letter} = $mutant;
                $app->log->info("Mutant letter for pending game $gid: $mutant");
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
            my $mutant = $self->_pick_mutant_letter($rack, $vals);
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
        # Active game found, ensure it's in memory
        my $gid = $active_game->id;
        if (!$app->games->{$gid}) {
            my $elapsed   = time - $active_game->started_at->epoch;
            my $total_dur = $ENV{GAME_DURATION} || $DEFAULT_GAME_DURATION;
            # Passive init: timer and AIs run on the replica that started the game.
            # Timer ticks arrive via Redis pub/sub. On pod restart the stale-game check
            # above handles rotation — no timer restart needed here.
            $self->_init_passive_game($gid, $active_game, $total_dur - $elapsed);
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

# Passive init for replicas that are not the game owner: clients dict only, no AIs, no timer.
# time_left is still tracked locally so join payloads are accurate.
sub _init_passive_game ($self, $gid, $game_record, $time_left) {
    $self->app->games->{$gid} = {
        clients   => {},
        state     => $game_record,
        time_left => $time_left,
        ais       => [],
    };
}

sub _pick_mutant_letter ($self, $rack, $vals) {
    my @candidates = grep { $_ ne '_' && ($vals->{$_} // 0) < 10 } @$rack;
    return undef unless @candidates;
    return $candidates[ int(rand(@candidates)) ];
}

1;

