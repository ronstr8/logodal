package Logodal::Web::Auth;
use Mojo::Base 'Mojolicious::Controller', -signatures;
use Crypt::URandom qw(urandom);
use DateTime;
use Mojo::Util;
use UUID::Tiny qw(:std);
use Mojo::JSON qw(encode_json decode_json);
use Authen::WebAuthn;

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

sub passkey_challenge ($self) {
    my $wa = Authen::WebAuthn->new(
        rp_id   => $self->req->url->to_abs->host,
        rp_name => "Logodal",
        origin  => $self->_wa_origin,
    );

    my $challenge = Mojo::Util::b64_encode(Crypt::URandom::urandom(32), "");
    $self->session(wa_challenge => $challenge);
    
    # Check if we have a session to determine if this is registration or login
    my $session_id = $self->cookie('ww_session');
    my $user_data = {};
    if ($session_id) {
        my $session = $self->app->schema->resultset('Session')->find($session_id);
        if ($session && $session->expires_at > DateTime->now) {
            my $player = $session->player;
            $user_data = {
                id => $player->id,
                name => $player->email || $player->nickname || "Player",
                displayName => $player->nickname || "Player",
            };
        }
    }

    $self->render(json => {
        challenge => $challenge,
        user => $user_data,
        rp => { name => "Logodal", id => $self->req->url->to_abs->host },
        pubKeyCredParams => [{ type => "public-key", alg => -7 }], # ES256
        timeout => 60000,
        attestation => "none",
    });
}

sub _wa_origin ($self) {
    my $proto = $self->req->headers->header('X-Forwarded-Proto') || ($self->req->is_secure ? 'https' : 'http');
    my $host  = $self->req->url->to_abs->host;
    return "$proto://$host";
}

sub passkey_verify ($self) {
    my $data      = $self->req->json;
    my $challenge = $self->session('wa_challenge');

    unless ($challenge) {
        return $self->render(json => { error => "No active challenge" }, status => 400);
    }

    my $wa = Authen::WebAuthn->new(
        rp_id   => $self->req->url->to_abs->host,
        rp_name => "Logodal",
        origin  => $self->_wa_origin,
    );

    # Registration flow (Attestation) — requires an active session
    if ($data->{type} eq 'registration') {
        my $schema     = $self->app->schema;
        my $session_id = $self->cookie('ww_session');

        unless ($session_id) {
            return $self->render(json => { error => "Authentication required to register passkey" }, status => 401);
        }
        my $session = $schema->resultset('Session')->find($session_id);
        unless ($session && $session->expires_at > DateTime->now) {
            return $self->render(json => { error => "Session expired" }, status => 401);
        }

        my $result = eval {
            $wa->validate_registration(
                challenge_b64          => $challenge,
                requested_uv           => "preferred",
                client_data_json_b64   => $data->{response}{clientDataJSON},
                attestation_object_b64 => $data->{response}{attestationObject},
                token_binding_id_b64   => undef,
            );
        };
        if ($@) {
            $self->app->log->warn("Passkey registration failed: $@");
            return $self->render(json => { error => "Registration verification failed" }, status => 400);
        }

        $session->player->create_related('passkeys', {
            credential_id => $result->{credential_id},
            public_key    => $result->{cred_pubkey_b64},
            sign_count    => $result->{sign_count} // 0,
        });

        $self->session(wa_challenge => undef);
        return $self->render(json => { success => 1 });
    }

    # Authentication flow (Assertion)
    else {
        my $passkey = $self->app->schema->resultset('PlayerPasskey')->find({ credential_id => $data->{id} });

        unless ($passkey) {
            return $self->render(json => { error => "Credential not found" }, status => 401);
        }

        my $result = eval {
            $wa->validate_assertion(
                challenge_b64          => $challenge,
                credential_pubkey_b64  => $passkey->public_key,
                stored_sign_count      => $passkey->sign_count,
                requested_uv           => "preferred",
                client_data_json_b64   => $data->{response}{clientDataJSON},
                authenticator_data_b64 => $data->{response}{authenticatorData},
                signature_b64          => $data->{response}{signature},
                token_binding_id_b64   => undef,
                user_handle_b64        => undef,
            );
        };
        if ($@) {
            $self->app->log->warn("Passkey assertion failed for credential " . $data->{id} . ": $@");
            return $self->render(json => { error => "Authentication verification failed" }, status => 401);
        }

        $passkey->update({ sign_count => $result->{sign_count} });
        $self->session(wa_challenge => undef);
        $self->_create_session($passkey->player);
        return $self->render(json => { success => 1 });
    }
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
        id => $player->id,
        nickname => $player->nickname,
        language => $player->language,
        has_passkey => $player->passkeys->count > 0,
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

