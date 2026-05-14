package Logodal::Game::Broadcaster;
use Moose;
use Mojo::JSON qw(encode_json decode_json);
use v5.36;

has app => (
    is       => 'ro',
    required => 1,
    weak_ref => 1,
);

has _subscribed_games => (
    is      => 'ro',
    default => sub { {} },
);

# Holds the Mojo::Redis instance to keep it alive (PubSub holds a weak ref to it).
has _redis => (
    is      => 'rw',
    default => undef,
);

# Returns a Mojo::Redis::PubSub object when REDIS_URL is configured and Mojo::Redis
# is installed. Returns undef otherwise — all public methods fall back to local delivery.
has _pubsub => (
    is      => 'ro',
    lazy    => 1,
    default => sub ($self) {
        my $url = $ENV{REDIS_URL} or return undef;

        my $redis = eval {
            require Mojo::Redis;
            Mojo::Redis->new($url);
        };
        if ($@ || !$redis) {
            $self->app->log->error("Broadcaster: cannot initialize Redis ($url): " . ($@ || 'unknown'));
            return undef;
        }

        $self->_redis($redis);  # Keep strong reference — PubSub holds only a weak ref
        my $ps = $redis->pubsub;

        # Every replica listens on the global broadcast channel
        $ps->listen('logodal:broadcast' => sub ($pub, $payload) {
            my $data = eval { decode_json($payload) };
            return unless $data;
            $self->_deliver_all_local($data->{msg}, $data->{exclude} // {});
        });

        $self->app->log->info("Broadcaster: Redis pub/sub active at $url");
        return $ps;
    },
);

# --- Public API ---

sub announce ($self, $msg, $recipients) {
    return unless $recipients && ref $recipients eq 'ARRAY';
    if (my $ps = $self->_pubsub) {
        for my $r (@$recipients) {
            my $pid = ref $r ? $r->id : $r;
            $self->_notify($ps, "logodal:player:$pid", encode_json({ msg => $msg }),
                sub { $self->_send_local_to_pid($pid, $msg) });
        }
    } else {
        for my $r (@$recipients) {
            my $pid = ref $r ? $r->id : $r;
            $self->_send_local_to_pid($pid, $msg);
        }
    }
}

sub announce_all_but ($self, $msg, $exclude_list = []) {
    my %exclude = map { (ref $_ ? $_->id : $_) => 1 } @$exclude_list;
    if (my $ps = $self->_pubsub) {
        $self->_notify($ps, 'logodal:broadcast', encode_json({ msg => $msg, exclude => \%exclude }),
            sub { $self->_deliver_all_local($msg, \%exclude) });
    } else {
        $self->_deliver_all_local($msg, \%exclude);
    }
}

sub announce_to_game ($self, $msg, $game_id, $exclude_list = []) {
    my %exclude = map { (ref $_ ? $_->id : $_) => 1 } @$exclude_list;
    if (my $ps = $self->_pubsub) {
        $self->_notify($ps, "logodal:game:$game_id", encode_json({ msg => $msg, exclude => \%exclude }),
            sub { $self->_deliver_game_local($game_id, $msg, \%exclude) });
    } else {
        $self->_deliver_game_local($game_id, $msg, \%exclude);
    }
}

# --- Subscription lifecycle (no-ops when Redis is not configured) ---

sub subscribe_player ($self, $pid) {
    my $ps = $self->_pubsub or return;
    $ps->listen("logodal:player:$pid" => sub ($pub, $payload) {
        my $data = eval { decode_json($payload) };
        return unless $data;
        $self->_send_local_to_pid($pid, $data->{msg});
    });
}

sub unsubscribe_player ($self, $pid) {
    my $ps = $self->_pubsub or return;
    $ps->unlisten("logodal:player:$pid");
}

sub subscribe_game ($self, $gid) {
    my $ps = $self->_pubsub or return;
    return if $self->_subscribed_games->{$gid};
    $self->_subscribed_games->{$gid} = 1;
    $ps->listen("logodal:game:$gid" => sub ($pub, $payload) {
        my $data = eval { decode_json($payload) };
        return unless $data;
        $self->_deliver_game_local($gid, $data->{msg}, $data->{exclude} // {});
    });
}

sub unsubscribe_game ($self, $gid) {
    my $ps = $self->_pubsub or return;
    return unless delete $self->_subscribed_games->{$gid};
    $ps->unlisten("logodal:game:$gid");
}

# --- Internal helpers ---

# notify returns undef when Redis is already dead, or a rejected promise when it dies mid-flight.
# Either way, run $fallback.
sub _notify ($self, $ps, $channel, $payload, $fallback) {
    my $p = eval { $ps->notify($channel, $payload) };
    if ($@ || !defined $p) {
        $fallback->();
    } else {
        $p->catch($fallback);
    }
}

# --- Local delivery helpers (used as fallback and from Redis callbacks) ---

sub _deliver_game_local ($self, $gid, $msg, $exclude) {
    my $clients = $self->app->games->{$gid}{clients} // {};
    my $type    = $msg->{type} // 'unknown';
    for my $pid (keys %$clients) {
        next if $exclude->{$pid};
        my $c = $clients->{$pid};
        if ($c && $c->tx) {
            $self->app->log->debug("Broadcaster[Game $gid]: Sending type '$type' to player $pid");
            $c->send({json => $msg});
        }
    }
}

sub _deliver_all_local ($self, $msg, $exclude) {
    for my $gid (keys %{$self->app->games}) {
        $self->_deliver_game_local($gid, $msg, $exclude);
    }
}

sub _send_local_to_pid ($self, $pid, $msg) {
    my $type = $msg->{type} // 'unknown';
    for my $gid (keys %{$self->app->games}) {
        my $c = $self->app->games->{$gid}{clients}{$pid};
        if ($c && $c->tx) {
            $self->app->log->debug("Broadcaster[Game $gid]: Sending type '$type' to player $pid");
            $c->send({json => $msg});
            return;
        }
    }
}

1;
