use v5.36;
use utf8;
binmode(STDOUT, ":utf8");
binmode(STDERR, ":utf8");

package main;
use Test::More;
use Test::Mojo;
use Mojo::JSON qw(decode_json);
use UUID::Tiny qw(:std);
use DateTime;
use lib 'lib', 't/lib';
use TestHelper qw(get_test_mojo cleanup_test_games);

# Minimal end-to-end smoke test of the WebSocket play path in Spanish.
#
# This drives the *real* handshake rather than seeding a Game row directly: /ws
# rejects connections without a ww_session cookie, and handle_play refuses any
# player who has not joined via game_registry. The rack is therefore
# server-generated and cannot be dictated by the test, so we play whatever we
# are dealt.
#
# Messages are collected off the transaction directly rather than via
# TestHelper::create_ws_client / wait_for_message, which block indefinitely here
# (they poll Test::Mojo's internal {messages} queue, which is only filled by
# message_ok). This mirrors the pump loop in t/integration/08-llm-ai-player.t.

my $app_t = get_test_mojo();
TestHelper::_apply_mocks();

# Pump the IO loop until $check returns true, or we run out of patience.
#
# Two subtleties, both of which cause indefinite hangs if ignored:
#   1. Test::Mojo installs its own message handler during websocket_ok, so any
#      message the server sends before we attach ours (notably `identity`, which
#      is sent the instant the socket authenticates) lands in $t->{messages}
#      instead. Drain both queues.
#   2. one_tick blocks until the reactor has something to do. Once the server
#      has gone quiet, that is forever. A recurring no-op timer guarantees the
#      loop always has work and therefore always returns.
sub pump_until ($t, $msgs, $check, $timeout = 15) {
    my $ticker = $t->ua->ioloop->recurring(0.05 => sub {});
    my $start  = time;
    my $hit;
    while (time - $start < $timeout) {
        if (my $queued = delete $t->{messages}) {
            for my $m (@$queued) {
                my $data = eval { decode_json($m->[1]) };
                push @$msgs, $data if ref $data eq 'HASH';
            }
        }
        last if $hit = $check->();
        $t->ua->ioloop->one_tick;
    }
    $t->ua->ioloop->remove($ticker);
    return $hit;
}

sub first_of ($msgs, $type) {
    return sub { (grep { ($_->{type} // '') eq $type } @$msgs)[0] };
}

subtest 'WebSocket play round-trip (es)' => sub {
    my $schema = $app_t->app->schema;

    my $player = $schema->resultset('Player')->create({
        id       => create_uuid_as_string(UUID_V4),
        nickname => 'MinimalTester',
        language => 'es',
    });
    my $session_token = create_uuid_as_string(UUID_V4);
    $player->create_related('sessions', {
        id         => $session_token,
        expires_at => DateTime->now->add(days => 1),
    });

    my $t = Test::Mojo->new($app_t->app);
    $t->websocket_ok('/ws?lang=es' => {
        'Accept-Language' => 'es',
        Cookie            => "ww_session=$session_token",
    })->status_is(101);

    my @messages;
    $t->tx->on(message => sub ($tx, $msg) {
        my $data = eval { decode_json($msg) };
        push @messages, $data if ref $data eq 'HASH';
    });

    my $identity = pump_until($t, \@messages, first_of(\@messages, 'identity'));
    ok($identity, 'Server sent identity to an authenticated socket') or return;

    $t->send_ok({ json => {
        type    => 'join',
        payload => { nickname => 'MinimalTester', language => 'es' },
    }});

    my $game = pump_until($t, \@messages, first_of(\@messages, 'game_start'));
    ok($game, 'Server sent game_start after join') or return;

    my $rack = $game->{payload}{rack};
    unless (ref $rack eq 'ARRAY' && @$rack >= 3) {
        fail('game_start carried a usable rack');
        return;
    }
    pass('game_start carried a usable rack');

    # Take three tiles straight off the rack so the real can_form_word() check in
    # _perform_play still runs for real. Wordd is mocked to accept any word that
    # does not contain "INVALID", so validation passes regardless of the draw.
    my $word = join '', @{$rack}[0 .. 2];

    $t->send_ok({ json => { type => 'play', payload => { word => $word } } });

    my $play = pump_until($t, \@messages, first_of(\@messages, 'play'));
    ok($play, "Server sent a play message for '$word'") or return;

    # The sender is the only client that gets the word echoed back; everyone else
    # receives undef so an in-flight word cannot be sniped.
    is($play->{payload}{word}, $word, 'Played word echoed back to its sender');
    ok(defined $play->{payload}{score}, 'Play carries a score');

    $t->finish_ok;
};

cleanup_test_games();
done_testing();
