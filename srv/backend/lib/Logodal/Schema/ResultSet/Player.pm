package Logodal::Schema::ResultSet::Player;
use base 'DBIx::Class::ResultSet';
use UUID::Tiny qw(:std);
use DateTime;
use Logodal::Util::NameGenerator;

sub find_or_create_from_google {
    my ($self, $user_info) = @_;
    my $schema = $self->result_source->schema;
    
    my $google_id = $user_info->{sub};
    my $email = $user_info->{email};
    my $name = $user_info->{name};

    # Start a transaction
    return $schema->txn_do(sub {
        # Check for identity first
        my $identity = $schema->resultset('PlayerIdentity')->find({
            provider => 'google',
            provider_id => $google_id,
        });

        if ($identity) {
            my $player = $identity->player;
            $player->update({ 
                last_login_at => DateTime->now,
                real_name     => $name,
            });
            return $player;
        }

        # Check for player by email if no identity (account linkage)
        my $player = $self->find({ email => $email });
        
        if (!$player) {
            # New Player
            my $gen = Logodal::Util::NameGenerator->new;
            $player = $self->create({
                id => create_uuid_as_string(UUID_V4),
                nickname => $gen->generate(4, 1, $google_id),
                real_name => $name,
                email => $email,
                last_login_at => DateTime->now,
            });
        }

        # Create identity
        $player->create_related('identities', {
            provider => 'google',
            provider_id => $google_id,
        });

        return $player;
    });
}

sub find_or_create_from_discord {
    my ($self, $user_info) = @_;
    my $schema = $self->result_source->schema;
    
    my $discord_id = $user_info->{id};
    my $email = $user_info->{email};
    my $name = $user_info->{username};

    # Start a transaction
    return $schema->txn_do(sub {
        # Check for identity first
        my $identity = $schema->resultset('PlayerIdentity')->find({
            provider => 'discord',
            provider_id => $discord_id,
        });

        if ($identity) {
            my $player = $identity->player;
            $player->update({ 
                last_login_at => DateTime->now,
                real_name     => $name,
            });
            return $player;
        }

        # Check for player by email if no identity (account linkage)
        my $player = $email ? $self->find({ email => $email }) : undef;
        
        if (!$player) {
            # New Player
            my $gen = Logodal::Util::NameGenerator->new;
            $player = $self->create({
                id => create_uuid_as_string(UUID_V4),
                nickname => $gen->generate(4, 1, $discord_id),
                real_name => $name,
                email => $email,
                last_login_at => DateTime->now,
            });
        }

        # Create identity
        $player->create_related('identities', {
            provider => 'discord',
            provider_id => $discord_id,
        });

        return $player;
    });
}

sub create_session {
    my ($player) = @_;
    my $session_token = unpack 'H*', Crypt::URandom::urandom(32);
    
    return $player->create_related('sessions', {
        id => $session_token,
        expires_at => DateTime->now->add(days => 30),
    });
}

sub find_active_ais {
    my ($self, $app) = @_;
    my $now       = DateTime->now(time_zone => 'local');
    my $now_epoch = time;
    my @participating;

    for my $ai ($self->search({ brain => { '!=', undef } })->all) {
        my $brain = $ai->brain;
        next unless $brain;
        next if $brain->{retired};   # dropped from share/brands roster

        my $on_schedule = $brain->{schedule}
            && $self->_is_on_schedule($brain->{schedule}, $now);

        # Determine join probability: 75% if on schedule, or use jump_in_probability if off-schedule
        my $prob;
        if ($on_schedule) {
            $prob = 0.75;
        } elsif ($brain->{jump_in_probability}) {
            $prob = $brain->{jump_in_probability} + 0;
        } else {
            next;
        }

        # Halflife cooldown: skip if we set a future eligible time after their last game
        if ($on_schedule && $app && $brain->{playtime_halflife_minutes}) {
            my $next_eligible = $app->ai_next_eligible->{ $ai->id } // 0;
            next if $now_epoch < $next_eligible;
        }

        push @participating, $ai if rand() < $prob;
    }

    return @participating;
}

sub _is_on_schedule {
    my ($self, $schedule, $now) = @_;
    
    my $day_map = [qw/sun mon tue wed thu fri sat sun/];
    my $day = lc $day_map->[$now->day_of_week % 7];
    my $time = sprintf("%02d:%02d", $now->hour, $now->minute);
    
    # Check 'all' or specific day
    my @rules = (@{$schedule->{all} // []}, @{$schedule->{$day} // []});
    
    for my $range (@rules) {
        my ($start, $end) = split /-/, $range;
        next unless $start && $end;
        return 1 if $time ge $start && $time le $end;
    }
    
    return 0;
}

1;

