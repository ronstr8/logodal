use v5.36;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use Mojo::File;
use Mojo::JSON qw(encode_json);
use Mojo::Log;
use lib 'lib';
use Logodal::BotRoster;
use Logodal::Schema;

my $log = Mojo::Log->new(level => 'fatal');

sub roster_dir (%files) {
    my $dir = Mojo::File->new(tempdir(CLEANUP => 1));
    $dir->child("$_.json")->spew(encode_json($files{$_})) for keys %files;
    return $dir;
}
sub bot ($id, $nick, %brain) {
    return { id => "00000000-0000-4000-a000-00000000000$id", nickname => $nick,
             brain => { character_prompt => "You are $nick.", %brain } };
}

subtest 'shipped roster is valid' => sub {
    my $r = Logodal::BotRoster->load(Mojo::File->new('share/brands'));
    ok scalar @{ $r->bots } >= 2, 'has bots';
    my %brands = map { $_->{brain}{brand} => 1 } @{ $r->bots };
    ok $brands{logodal} && $brands{wordwank}, 'both brands have bots';
    like $r->voice('wordwank'), qr/Wordwank/, 'wordwank house voice';
    like $r->voice('logodal'),  qr/Logodal/,  'logodal house voice';
    is $r->voice('nope'), '', 'unknown brand has no voice';
};

subtest 'validation' => sub {
    my $dup_id = roster_dir(
        a => { brand => 'a', bots => [ bot(1, 'One') ] },
        b => { brand => 'b', bots => [ bot(1, 'Two') ] },
    );
    eval { Logodal::BotRoster->load($dup_id) };
    like $@, qr/duplicate bot id/, 'duplicate id across brands rejected';

    my $dup_nick = roster_dir(a => { brand => 'a', bots => [ bot(1, 'Same'), bot(2, 'same') ] });
    eval { Logodal::BotRoster->load($dup_nick) };
    like $@, qr/duplicate bot nickname/, 'nicknames compared case-insensitively';

    my $no_prompt = roster_dir(a => { brand => 'a', bots => [ { id => 'x', nickname => 'X', brain => { wait_seconds_base => 1 } } ] });
    eval { Logodal::BotRoster->load($no_prompt) };
    like $@, qr/character_prompt is required/, 'persona required';

    my $bad = Mojo::File->new(tempdir(CLEANUP => 1));
    $bad->child('broken.json')->spew('{ nope');
    eval { Logodal::BotRoster->load($bad) };
    like $@, qr/cannot parse/, 'malformed JSON rejected';

    is_deeply Logodal::BotRoster->load('/nonexistent/dir')->bots, [], 'missing dir -> empty roster';
};

subtest 'sync' => sub {
    my $schema = Logodal::Schema->connect('dbi:SQLite:dbname=:memory:', '', '', { quote_names => 1 });
    $schema->deploy;
    my $rs = $schema->resultset('Player');

    # A retired-to-be bot already in the DB, plus a human whose nickname collides.
    $rs->create({ id => '00000000-0000-4000-a000-000000000009', nickname => 'Oldbot',
                  brain => { character_prompt => 'old' } });
    $rs->create({ id => '11111111-1111-4111-a111-111111111111', nickname => 'Taken' });

    my $r = Logodal::BotRoster->load(roster_dir(
        wordwank => { brand => 'wordwank', voice => 'crude', bots => [ bot(3, 'Wanko', wait_seconds_base => 8) ] },
        logodal  => { brand => 'logodal',  voice => 'dry',   bots => [ bot(1, 'Icarus'), bot(2, 'Taken') ] },
    ));

    my $n = $r->sync($schema, $log);
    is $n->{added},   2, 'two bots added';
    is $n->{failed},  1, 'nickname collision logged, not fatal';
    is $n->{retired}, 1, 'unlisted bot retired';

    my $wanko = $rs->find('00000000-0000-4000-a000-000000000003');
    is $wanko->brain->{brand}, 'wordwank', 'brand stamped into brain';
    is $wanko->brain->{wait_seconds_base}, 8, 'brain fields kept';

    my $old = $rs->find('00000000-0000-4000-a000-000000000009');
    ok $old, 'retired bot row kept (play history survives)';
    ok $old->brain->{retired}, 'retired flag set';
    ok defined $old->brain, 'still recognisable as an AI (brain not null)';

    $n = $r->sync($schema, $log);
    is $n->{unchanged}, 2, 'second sync is a no-op';
    is $n->{retired},   0, 'already-retired bot not re-retired';

    # Renames and persona edits flow through.
    my $r2 = Logodal::BotRoster->load(roster_dir(
        wordwank => { brand => 'wordwank', bots => [ bot(3, 'Wankmaster', wait_seconds_base => 8) ] },
        logodal  => { brand => 'logodal',  bots => [ bot(1, 'Icarus') ] },
    ));
    is $r2->sync($schema, $log)->{updated}, 1, 'rename counted as update';
    is $rs->find('00000000-0000-4000-a000-000000000003')->nickname, 'Wankmaster', 'nickname updated';

    is_deeply Logodal::BotRoster->new->sync($schema, $log)->{retired}, 0,
        'empty roster never retires everyone';
};

done_testing;
