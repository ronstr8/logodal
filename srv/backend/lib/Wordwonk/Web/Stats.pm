package Wordwonk::Web::Stats;
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub leaderboard ($self) {
    my $app = $self->app;
    my $schema = $app->schema;
    
    $app->log->debug("Fetching leaderboard...");

    # Global Top 10
    my $rs = $schema->resultset('Player')->search(
        {
            lifetime_score => { '>' => 0 },
        },
        {
            join     => 'plays',
            select   => [
                'me.id',
                'me.nickname',
                'me.lifetime_score',
                { count => 'plays.id', -as => 'plays_count' }
            ],
            as       => [qw/id nickname total_score plays_count/],
            group_by => [qw/me.id me.nickname me.lifetime_score/],
            order_by => [ { -desc => 'me.lifetime_score' } ],
            limit    => 10,
        }
    );

    my @leader_rows = $rs->all;
    my @leaders = map {
        {
            name  => $_->get_column('nickname'),
            score => int($_->get_column('total_score') // 0),
            plays => int($_->get_column('plays_count') // 0),
        }
    } @leader_rows;

    # Attach last word played in a finished game for the top leader
    if (@leader_rows) {
        my $top_id = $leader_rows[0]->id;
        my $last_play = $schema->resultset('Play')->search(
            {
                'me.player_id'   => $top_id,
                'game.finished_at' => { '!=' => undef },
            },
            {
                join     => 'game',
                order_by => { -desc => 'me.created_at' },
                rows     => 1,
            }
        )->first;
        if ($last_play) {
            $leaders[0]{last_word}       = $last_play->word;
            $leaders[0]{last_word_score} = int($last_play->final_score // $last_play->score);
            $leaders[0]{last_word_at}    = $last_play->created_at->iso8601 . 'Z';
        }

        my $best_play = $schema->resultset('Play')->search(
            { player_id => $top_id },
            { order_by => { -desc => \['COALESCE(final_score, score)'] }, rows => 1 }
        )->first;
        if ($best_play) {
            $leaders[0]{best_word}  = $best_play->word;
            $leaders[0]{best_score} = int($best_play->final_score // $best_play->score);
        }
    }

    # Optional personal stats
    my $personal;
    my $player_id = $self->param('player_id');
    
    # Fallback to session player if no ID provided in params but session exists
    if (!$player_id) {
        my $session_id = $self->cookie('ww_session');
        if ($session_id) {
            my $session = $schema->resultset('Session')->find($session_id);
            $player_id = $session->player_id if $session && $session->expires_at > DateTime->now;
        }
    }

    if ($player_id) {
        my $player_stats = $schema->resultset('Player')->find(
            { id => $player_id },
            {
                join     => 'plays',
                select   => [
                    'me.nickname',
                    'me.lifetime_score',
                    { count => 'plays.id', -as => 'plays_count' }
                ],
                as       => [qw/nickname total_score plays_count/],
                group_by => [qw/me.id me.nickname me.lifetime_score/],
            }
        );
        if ($player_stats) {
            $personal = {
                name  => $player_stats->get_column('nickname'),
                score => int($player_stats->get_column('total_score') // 0),
                plays => int($player_stats->get_column('plays_count') // 0),
            };

            my $best_play = $schema->resultset('Play')->search(
                { player_id => $player_id },
                { order_by => { -desc => \['COALESCE(final_score, score)'] }, rows => 1 }
            )->first;
            if ($best_play) {
                $personal->{best_word}  = $best_play->word;
                $personal->{best_score} = int($best_play->final_score // $best_play->score);
            }
        }
    }

    $self->render(json => {
        leaders => \@leaders,
        personal => $personal
    });
}

1;

