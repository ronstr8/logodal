package Logodal::BotRoster;
use Mojo::Base -base, -signatures;
use Mojo::File;
use Mojo::JSON qw(decode_json);
use JSON::PP ();

# Per-brand bot definitions, loaded from share/brands/<brand>.json:
#
#   { "brand": "wordwank",
#     "voice": "House voice prepended to every bot prompt of this brand",
#     "bots":  [ { "id": "<uuid>", "nickname": "Wanko", "brain": { ... } } ] }
#
# `brain` is exactly the players.brain JSONB the game already uses
# (character_prompt, schedule, wait_seconds_base, ...). The sync stamps
# brain.brand so a bot speaks in its own brand's voice to every player.
#
# Files are the source of truth: `sync` upserts them into players on deploy
# (bin/migrate.pl). Bots missing from the files are retired (brain.retired),
# never deleted, so their play history survives.

has brands => sub { {} };   # brand => { voice => ..., bots => [...] }

sub default_dir ($class) {
    my $share = $ENV{SHARE_DIR} || Mojo::File->new(__FILE__)->dirname->dirname->dirname->child('share');
    return Mojo::File->new($share)->child('brands');
}

# Load and validate every <brand>.json in $dir. Dies with a clear message on a
# malformed file, duplicate id/nickname, or missing required field.
sub load ($class, $dir = undef) {
    $dir = Mojo::File->new($dir // $class->default_dir);
    my (%brands, %ids, %nicks);
    return $class->new(brands => {}) unless -d $dir;

    for my $file (sort { "$a" cmp "$b" } $dir->list->grep(qr/\.json$/)->each) {
        my $data = eval { decode_json($file->slurp) }
            or die "BotRoster: cannot parse $file: " . ($@ || 'not a JSON object') . "\n";
        my $brand = $data->{brand} // ($file->basename =~ s/\.json$//r);
        die "BotRoster: $file has brand '$brand', expected lowercase letters\n"
            unless $brand =~ /^[a-z]+$/;

        my @bots;
        for my $bot (@{ $data->{bots} // [] }) {
            my $label = "$file bot " . ($bot->{nickname} // $bot->{id} // '?');
            for my $f (qw(id nickname brain)) {
                die "BotRoster: $label is missing '$f'\n" unless $bot->{$f};
            }
            die "BotRoster: $label brain.character_prompt is required\n"
                unless $bot->{brain}{character_prompt};
            die "BotRoster: duplicate bot id $bot->{id} ($label)\n"            if $ids{ $bot->{id} }++;
            die "BotRoster: duplicate bot nickname $bot->{nickname} ($label)\n" if $nicks{ lc $bot->{nickname} }++;

            push @bots, {
                id       => $bot->{id},
                nickname => $bot->{nickname},
                brain    => { %{ $bot->{brain} }, brand => $brand },
            };
        }
        $brands{$brand} = { voice => $data->{voice} // '', bots => \@bots };
    }
    return $class->new(brands => \%brands);
}

sub bots ($self) {
    return [ map { @{ $self->brands->{$_}{bots} } } sort keys %{ $self->brands } ];
}

sub voice ($self, $brand) {
    my $b = $self->brands->{ $brand // '' } or return '';
    return $b->{voice} // '';
}

# Upsert every bot into players and retire bots no longer listed. Never dies on
# a single bad row (e.g. a nickname taken by a human): logs and continues, so a
# roster typo can't block a deploy. Returns { added, updated, unchanged,
# retired, failed } counts.
sub sync ($self, $schema, $log) {
    my %n = map { $_ => 0 } qw(added updated unchanged retired failed);
    my $bots = $self->bots;
    unless (@$bots) {
        # No files found: don't treat that as "retire everyone".
        $log->warn('BotRoster: no bots defined; skipping sync');
        return \%n;
    }

    my $rs = $schema->resultset('Player');
    my %listed;
    for my $bot (@$bots) {
        $listed{ $bot->{id} } = 1;
        my $ok = eval {
            my $row = $rs->find($bot->{id});
            if (!$row) {
                $rs->create({ id => $bot->{id}, nickname => $bot->{nickname}, brain => $bot->{brain} });
                $log->info("BotRoster: added $bot->{nickname} ($bot->{brain}{brand})");
                $n{added}++;
            }
            elsif ($row->nickname eq $bot->{nickname} && _same($row->brain, $bot->{brain})) {
                $n{unchanged}++;
            }
            else {
                my $was = $row->nickname;
                $row->update({ nickname => $bot->{nickname}, brain => $bot->{brain} });
                $log->info("BotRoster: updated $bot->{nickname}" . ($was ne $bot->{nickname} ? " (was $was)" : ''));
                $n{updated}++;
            }
            1;
        };
        unless ($ok) {
            $log->error("BotRoster: failed to sync $bot->{nickname}: $@");
            $n{failed}++;
        }
    }

    for my $row ($rs->search({ brain => { '!=' => undef } })->all) {
        next if $listed{ $row->id };
        my $brain = $row->brain // {};
        next if $brain->{retired};
        $row->update({ brain => { %$brain, retired => \1 } });
        $log->info('BotRoster: retired ' . $row->nickname . ' (no longer in roster)');
        $n{retired}++;
    }

    $log->info(sprintf 'BotRoster: %d added, %d updated, %d unchanged, %d retired, %d failed',
        @n{qw(added updated unchanged retired failed)});
    return \%n;
}

# Canonical (sorted-key) JSON comparison so key order doesn't count as a change.
my $CANON = JSON::PP->new->canonical->allow_nonref;
sub _same ($x, $y) {
    return $CANON->encode($x // {}) eq $CANON->encode($y // {});
}

1;
