package Logodal::Web::Game;
use Mojo::Base 'Mojolicious::Controller', -signatures;
use v5.36;
use utf8;
use DateTime;
use Mojo::JSON qw(encode_json decode_json);
use Mojo::Util;
use UUID::Tiny qw(:std);
use Logodal::Util::NameGenerator;

my $DEFAULT_LANG = $ENV{DEFAULT_LANG} || 'en';

sub generate_procedural_name ($id) {
    return Logodal::Util::NameGenerator->new->generate(4, 1, $id);
}

sub websocket ($self) {
    $self->reseed_prng();
    $self->inactivity_timeout(3600);

    my $schema = $self->app->schema;
    my $app    = $self->app;

    # Authenticate via session cookie — reject unauthenticated connections
    my $session_id = $self->cookie('ww_session');
    unless ($session_id) {
        $self->send({json => { type => 'error', payload => { code => 'unauthenticated', message => 'No session' } }});
        return $self->finish(4401, 'Unauthenticated');
    }

    my $session = $schema->resultset('Session')->find($session_id);
    unless ($session && $session->expires_at > DateTime->now) {
        $self->send({json => { type => 'error', payload => { code => 'session_expired', message => 'Session expired' } }});
        return $self->finish(4401, 'Session expired');
    }

    my $player = $session->player;
    my $lang   = $self->param('lang') || $self->req->headers->header('Accept-Language') || 'en';

    # Send identity immediately
    $self->send({json => {
        type    => 'identity',
        payload => { 
            id       => $player->id, 
            name     => $player->nickname,
            language => $player->language,
            config   => {
                tiles       => $app->scorer->tile_counts($player->language // $DEFAULT_LANG),
                unicorns    => $app->scorer->unicorns($player->language // $DEFAULT_LANG),
                tile_values => $app->scorer->generate_tile_values($player->language // $DEFAULT_LANG),
                languages   => $app->languages,
            }
        }
    }});

    # 2. Connection Tracking
    my $client_id = "$self"; # Unique stringified controller
    my $player_id = $player->id;
    $app->log->debug("Player $player_id connected via $client_id");

    $self->on(message => sub ($c, $msg) {
        my $bytes = utf8::is_utf8($msg) ? Mojo::Util::encode('UTF-8', $msg) : $msg;
        my $data = eval { decode_json($bytes) };
        if ($@) {
            $c->app->log->error("Invalid JSON from $player_id: $@");
            return;
        }

        my $type    = $data->{type}    // '';
        my $payload = $data->{payload} // {};

        if ($type eq 'join') {
            $c->app->game_manager->join_player($c, $player, $payload);
        }
        elsif ($type eq 'chat') {
            $c->app->game_manager->handle_chat($c, $player, $payload);
        }
        elsif ($type eq 'play') {
            $c->app->game_manager->handle_play($c, $player, $payload);
        }
        elsif ($type eq 'set_language') {
            $c->app->game_manager->handle_set_language($c, $player, $payload);
        }
    });

    $self->on(finish => sub ($c, $code, $reason) {
        $c->app->game_manager->handle_disconnect($player->id);
    });
}

1;

