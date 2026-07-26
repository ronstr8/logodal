use v5.36;
use utf8;
binmode(STDOUT, ":utf8");
binmode(STDERR, ":utf8");

package main;
use Test::More;
use Test::Mojo;
use Mojo::JSON qw(encode_json decode_json);
use Mojo::UserAgent;
use Mojo::Transaction::HTTP;
use Mojo::IOLoop;
use UUID::Tiny qw(:std);
use DateTime;
use lib 'lib', 't/lib';
use TestHelper qw(get_test_mojo cleanup_test_games);

# Mock environment
$ENV{OLLAMA_URL} = 'http://mock-ollama:11434';
$ENV{OLLAMA_MODEL} = 'phi3:mini';
$ENV{GAME_DURATION} = 15;
$ENV{IDLE_CHATTER} = 1;

my $t = get_test_mojo();

sub setup_mock_ollama {
    my $mock_ua = Mojo::UserAgent->new;
    {
        no warnings 'redefine';
        *Mojo::UserAgent::post = sub ($self, $url, @args) {
            my $tx = Mojo::Transaction::HTTP->new;
            my $cb = ref $args[-1] eq 'CODE' ? pop @args : undef;
            my %args_hash = @args;
            if ($url =~ /api\/generate/) {
                my $prompt = $args_hash{json}{prompt} // '';
                
                # VERIFICATION: character persona leads the prompt; context or situation follows
                if (($prompt =~ /Game context:/ && $prompt =~ /Rack:/) || ($prompt =~ /multiplayer word game/ && $prompt =~ /Situation:/)) {
                    pass("Ollama prompt contains expected context/situation fields");
                } else {
                    fail("Ollama prompt MISSING expected context/situation fields");
                    diag("Prompt was: $prompt");
                }

                my $response = "I am a helpful character.";
                if ($prompt =~ /Yertyl/) {
                    $response = "Slow down, young WONKer. I'm thinking.";
                }
                
                $tx->res->code(200);
                $tx->res->body(encode_json({ response => $response }));
            }
            # Attach callback if present
            if ($cb) {
                Mojo::IOLoop->next_tick(sub { $cb->($self, $tx) });
            }
            return $tx;
        };
        
        # Wordd mock
        *Mojo::UserAgent::get = sub ($self, $url, $cb) {
             my $tx = Mojo::Transaction::HTTP->new;
             if ($url =~ /rand\/langs/) {
                 $tx->res->code(200);
                 $tx->res->body("TEST\nWORD");
             }
             Mojo::IOLoop->next_tick(sub { $cb->($self, $tx) });
         };
    }
    $t->app->ua($mock_ua);
}

cleanup_test_games($t);

# Seed Yertyl AI player so we have a brain to interact with
my $yertyl = $t->app->schema->resultset('Player')->create({
    id       => '00000000-0000-4000-a000-000000000001',
    nickname => 'Yertyl',
    brain    => {
        character_prompt => "You are Yertyl, a slow, thoughtful, and slightly grumpy turtle who hates being rushed. You speak in short, punchy sentences and occasionally complain about the speed of younger ’wankers’.",
        wait_seconds_base => 2,
        rnd_word_count    => 3,
        min_score_to_play => 1,
        min_score_to_win  => 40,
    }
});

# Load ResultSet class before redefining find_active_ais
require Logodal::Schema::ResultSet::Player;
# Mock find_active_ais to always return our Yertyl AI player
{
    no warnings 'redefine', 'once';
    *Logodal::Schema::ResultSet::Player::find_active_ais = sub {
        return ($yertyl);
    };
}

# Override TestHelper's mock of _request_candidates so the AI can actually fetch words
{
    no warnings 'redefine';
    *Logodal::Game::AI::_request_candidates = sub ($self, $url, $letters) {
        $self->app->ua->get($url => sub ($ua, $tx) {
            my $res = $tx->res;
            if ($res->is_success) {
                my @words = split /\n/, $res->body;
                @words = map { s/^\s+|\s+$//g; $_ = uc($_); $_ } grep { /\S/ } @words;
                $self->candidates(\@words);
            }
        });
    };
}

subtest 'LLM AI Character Dialogue with Context' => sub {
    setup_mock_ollama();

    # Seed Human player and active session
    my $human = $t->app->schema->resultset('Player')->create({
        id       => '00000000-0000-4000-b000-000000000001',
        nickname => 'Human',
    });
    my $session = $human->create_related('sessions', {
        id         => 'test-session-id',
        expires_at => DateTime->now->add(days => 1),
    });

    # Manual WebSocket setup
    my $tm = Test::Mojo->new($t->app);
    $tm->websocket_ok('/ws?lang=en' => { Cookie => 'ww_session=test-session-id' })
       ->status_is(101);

    my $ws_tx = $tm->tx;
    my @messages;
    $ws_tx->on(message => sub ($tx, $msg) {
        note("RAW WS MESSAGE: $msg");
        my $data = eval { decode_json($msg) };
        push @messages, $data if $data;
    });

    # 1. Join immediately to trigger backend work
    $tm->send_ok({json => {
        type => 'join',
        payload => { nickname => 'Human', language => 'en' }
    }});

    # 2. Capture messages
    my $ai_name;
    my $ai_spoke = 0;
    my $start = time;
    note("Monitoring game flow...");
    
    my %seen_msgs;
    while (time - $start < 30) {
        $tm->ua->ioloop->one_tick;
        
        # Log new messages
        for my $msg (@messages) {
            my $str = encode_json($msg);
            if (!$seen_msgs{$str}++) {
                note("Decoded message: $str");
            }
        }
        
        # Identify AI
        if (!$ai_name) {
            if (my ($gs) = grep { $_->{type} eq 'game_start' } @messages) {
                $ai_name = $gs->{payload}{players}->[-1];
                note("AI Persona detected: $ai_name");
            }
        }
        
        # Check for AI Chat
        if ($ai_name) {
            if (my ($chat) = grep { $_->{type} eq 'chat' && ($_->{payload}{senderName} eq $ai_name || $_->{payload}{senderName} =~ /WONKBot/) } @messages) {
                $ai_spoke = 1;
                my $text = $chat->{payload}{text};
                note("AI said: $text");
                pass("AI character generated dialogue: $text");
                last;
            }
        }
        
        select(undef, undef, undef, 0.1) unless @messages;
    }
    
    if (!$ai_spoke) {
        diag("All received messages: " . encode_json(\@messages));
    }
    ok($ai_spoke, 'AI character generated dialogue via Ollama');
    $tm->finish_ok;
};

cleanup_test_games($t);
done_testing();
