package Logodal::Web::Auth;
use Mojo::Base 'Mojolicious::Controller', -signatures;
use Crypt::URandom qw(urandom);
use DateTime;
use Mojo::Util;
use UUID::Tiny qw(:std);
use Mojo::JSON qw(encode_json decode_json);
use Logodal::Util::NameGenerator;

# Google OIDC setup would typically happen in startup, but we can helper it
sub google_login ($self) {
    my $redirect_uri = $ENV{GOOGLE_REDIRECT_URI} || $self->url_for('google_callback')->to_abs;
    $self->app->log->debug("OAuth2 Redirect URI: $redirect_uri");

    $self->oauth2->get_token_p('google' => {
        scope => 'openid email profile',
        response_type => 'code',
        redirect_uri => $redirect_uri,
    })->then(sub ($data) {
        # This part is reached if we already have a token or just got one
        # But usually get_token_p handles the initial redirect automatically.
    })->catch(sub ($err) {
        $self->app->log->error("Google OAuth error: $err");
        $self->render(json => { error => $err }, status => 400);
    });
}

sub google_callback ($self) {
    my $redirect_uri = $ENV{GOOGLE_REDIRECT_URI} || $self->url_for('google_callback')->to_abs;

    $self->oauth2->get_token_p('google' => {
        response_type => 'code',
        redirect_uri => $redirect_uri,
    })->then(sub ($data) {
        $self->app->log->debug("Google token exchange succeeded, access_token present: " . (defined $data->{access_token} ? 'yes' : 'no'));
        my $access_token = $data->{access_token};
        # Exchange token for user info via Google UserInfo API
        return $self->ua->get_p("https://www.googleapis.com/oauth2/v3/userinfo?access_token=$access_token");
    })->then(sub ($tx) {
        my $user_info = $tx->result->json;
        if (!$user_info || $user_info->{error}) {
             die "Failed to get user info: " . ($user_info->{error} || "Unknown error");
        }

        # Find or create player using the ResultSet method
        my $player = $self->schema->resultset('Player')->find_or_create_from_google($user_info);
        
        # Create session using the Result method
        my $session = $player->create_session;
        
        # Set session cookie
        my $expires = DateTime->now->add(days => 30);
        $self->cookie(ww_session => $session->id, {
            path => '/',
            expires => $expires->epoch,
            httponly => 1,
            secure => $self->req->is_secure ? 1 : 0,
            samesite => 'Lax',
        });
        
        $self->redirect_to('/');
    })->catch(sub ($err) {
        # Log the raw callback params to help diagnose OAuth errors
        my $params = $self->req->params->to_hash;
        $self->app->log->error("Google Callback error: $err | params: code=" . ($params->{code} ? 'present' : 'missing') . " error=" . ($params->{error} // 'none'));
        $self->render(text => "Auth failed: $err", status => 500);
    });
}

sub discord_login ($self) {
    my $redirect_uri = $ENV{DISCORD_REDIRECT_URI} || $self->url_for('discord_callback')->to_abs;
    $self->app->log->debug("Discord OAuth2 Redirect URI: $redirect_uri");

    $self->oauth2->get_token_p('discord' => {
        scope => 'identify email',
        authorize_query => { response_type => 'code' },
        redirect_uri => $redirect_uri,
    })->then(sub ($data) {
        # Redirect handled by plugin
    })->catch(sub ($err) {
        $self->app->log->error("Discord OAuth error: $err");
        $self->render(json => { error => $err }, status => 400);
    });
}

sub discord_callback ($self) {
    my $redirect_uri = $ENV{DISCORD_REDIRECT_URI} || $self->url_for('discord_callback')->to_abs;

    $self->oauth2->get_token_p('discord' => {
        response_type => 'code',
        redirect_uri => $redirect_uri,
    })->then(sub ($data) {
        my $access_token = $data->{access_token};
        # Exchange token for user info via Discord Users API
        return $self->ua->get_p("https://discord.com/api/users/\@me", { Authorization => "Bearer $access_token" });
    })->then(sub ($tx) {
        my $user_info = $tx->result->json;
        if (!$user_info || $user_info->{error}) {
             die "Failed to get user info: " . ($user_info->{error} || "Unknown error");
        }

        # Find or create player using the ResultSet method
        my $player = $self->schema->resultset('Player')->find_or_create_from_discord($user_info);
        
        # Create session
        my $session = $player->create_session;
        
        # Set session cookie
        my $expires = DateTime->now->add(days => 30);
        $self->cookie(ww_session => $session->id, {
            path => '/',
            expires => $expires->epoch,
            httponly => 1,
            secure => $self->req->is_secure ? 1 : 0,
            samesite => 'Lax',
        });
        
        $self->redirect_to('/');
    })->catch(sub ($err) {
        $self->app->log->error("Discord Callback error: $err");
        $self->render(text => "Auth failed: $err", status => 500);
    });
}

sub _create_session ($self, $player) {
    my $session_id = unpack 'H*', urandom(32);
    my $expires = DateTime->now->add(days => 30);

    $self->app->schema->resultset('Session')->create({
        id => $session_id,
        player_id => $player->id,
        expires_at => $expires,
    });

    $self->cookie(ww_session => $session_id, {
        path => '/',
        expires => $expires->epoch,
        httponly => 1,
        secure => $self->req->is_secure ? 1 : 0,
        samesite => 'Lax',
    });
    
    $player->update({ last_login_at => DateTime->now });
}


sub anonymous ($self) {
    my $schema = $self->app->schema;
    my $gen    = Logodal::Util::NameGenerator->new;
    my $player = $schema->resultset('Player')->create({
        id            => create_uuid_as_string(UUID_V4),
        nickname      => $gen->generate(4, 1, time . $$),
        is_anonymous  => 1,
        last_login_at => DateTime->now,
    });

    my $expires = DateTime->now->add(days => 365);
    my $token   = unpack 'H*', Crypt::URandom::urandom(32);
    $schema->resultset('Session')->create({
        id         => $token,
        player_id  => $player->id,
        expires_at => $expires,
    });

    $self->cookie(ww_session => $token, {
        path     => '/',
        expires  => $expires->epoch,
        httponly => 1,
        secure   => $self->req->is_secure ? 1 : 0,
        samesite => 'Lax',
    });

    $self->render(json => { success => 1 });
}

sub me ($self) {
    my $session_id = $self->cookie('ww_session');
    if (!$session_id) {
        return $self->render(json => { authenticated => 0 }, status => 401);
    }

    my $session = $self->app->schema->resultset('Session')->find($session_id);
    if (!$session || $session->expires_at < DateTime->now) {
        return $self->render(json => { authenticated => 0 }, status => 401);
    }

    my $player = $session->player;
    $self->render(json => {
        authenticated => 1,
        id            => $player->id,
        nickname      => $player->nickname,
        language      => $player->language,
        is_anonymous  => $player->is_anonymous ? 1 : 0,
        has_passkey   => 0,
    });
}

sub logout ($self) {
    my $session_id = $self->cookie('ww_session');
    if ($session_id) {
        my $session = $self->app->schema->resultset('Session')->find($session_id);
        $session->delete if $session;
    }
    $self->cookie(ww_session => '', { expires => 1 });
    $self->render(json => { success => 1 });
}

1;

