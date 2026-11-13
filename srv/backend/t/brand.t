use v5.36;
use Test::More;
use lib 'lib';
use Logodal::Brand;

my $b = Logodal::Brand->new(
    hosts   => { 'logodal.com' => 'logodal', 'wordwank.com' => 'wordwank' },
    default => 'logodal',
);

is_deeply $b->known, ['logodal', 'wordwank'], 'known brands include default and mapped';

is $b->for_host('wordwank.com'),        'wordwank', 'exact host';
is $b->for_host('WordWank.COM'),        'wordwank', 'case-insensitive';
is $b->for_host('www.wordwank.com'),    'wordwank', 'leading www stripped';
is $b->for_host('wordwank.com:8443'),   'wordwank', 'port stripped';
is $b->for_host('logodal.com'),         'logodal',  'other brand';
is $b->for_host('wordwank.localhost'),  'wordwank', 'dev host by label';
is $b->for_host('localhost:3000'),      'logodal',  'unknown host -> default';
is $b->for_host('notwordwank.com'),     'logodal',  'substring is not a label match';
is $b->for_host(undef),                 'logodal',  'missing host -> default';

is $b->url_for('wordwank'), 'https://wordwank.com', 'url_for mapped brand';
is $b->url_for('nope'),     undef,                  'url_for unknown brand';

{
    local $ENV{BRAND_HOSTS}   = '{"Logodal.com":"logodal","wordwank.com":"wordwank"}';
    local $ENV{DEFAULT_BRAND} = 'wordwank';
    my $e = Logodal::Brand->from_env;
    is $e->for_host('logodal.com'), 'logodal',  'from_env lowercases hosts';
    is $e->for_host('example.org'), 'wordwank', 'from_env default';
}
{
    local $ENV{BRAND_HOSTS} = 'not json';
    local $SIG{__WARN__} = sub {};
    my $e = Logodal::Brand->from_env;
    is $e->for_host('wordwank.com'), 'logodal', 'malformed map falls back to default';
}

done_testing;
