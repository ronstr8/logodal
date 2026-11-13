use Mojo::Base -strict;
use utf8;
use Test::More;
use Test::Mojo;
use File::Temp qw(tempdir);
use Mojo::File;
use Mojo::JSON qw(encode_json);

# Brand overlays: <brand>.<lang>.json sits beside <lang>.json and overrides
# only the keys that brand words differently.

my $base_dir   = tempdir(CLEANUP => 1);
my $locale_dir = Mojo::File->new($base_dir)->child('locale')->make_path;
$ENV{SHARE_DIR} = $base_dir;

$locale_dir->child('en.json')->spew(encode_json({
    app => { played => '{{p}} played', help => 'Help', lang_en => 'English' },
}));
$locale_dir->child('es.json')->spew(encode_json({
    app => { played => '{{p}} jugó', help => 'Ayuda', lang_es => 'Español' },
}));
$locale_dir->child('wordwank.en.json')->spew(encode_json({
    app => { played => '{{p}} wanked' },
}));

my $app = Test::Mojo->new('Logodal')->app;

is $app->t('app.played', 'en', { p => 'Bo' }),              'Bo played', 'no brand -> base';
is $app->t('app.played', 'en', { p => 'Bo' }, 'logodal'),   'Bo played', 'brand without overlay -> base';
is $app->t('app.played', 'en', { p => 'Bo' }, 'wordwank'),  'Bo wanked', 'overlay key wins';
is $app->t('app.help',   'en', {},            'wordwank'),  'Help',      'key absent from overlay -> base';
is $app->t('app.played', 'es', { p => 'Bo' }, 'wordwank'),  'Bo jugó',   'no es overlay -> es base, not English overlay';

is_deeply [ sort keys %{ $app->languages } ], [ 'en', 'es' ], 'overlay files are not languages';

done_testing;
