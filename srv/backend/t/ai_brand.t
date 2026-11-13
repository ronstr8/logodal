use v5.36;
use utf8;
use Test::More;
use Test::Mojo;
use File::Temp qw(tempdir);
use Mojo::File;
use Mojo::JSON qw(encode_json);
use lib 'lib';
use Logodal::BotRoster;
use Logodal::Game::AI;

# Bots carry their own brand: the brand's house voice leads their LLM persona,
# and their canned lines come from that brand's locale overlay.

my $share = Mojo::File->new(tempdir(CLEANUP => 1));
my $loc   = $share->child('locale')->make_path;
$loc->child('en.json')->spew(encode_json({ ai => { played => ['{{word}}. Not bad.'] } }));
$loc->child('wordwank.en.json')->spew(encode_json({ ai => { played => ['{{word}}! Wanked it.'] } }));
$ENV{SHARE_DIR} = "$share";

my $app = Test::Mojo->new('Logodal')->app;
$app->bot_roster(Logodal::BotRoster->new(brands => {
    wordwank => { voice => 'CRUDE HOUSE VOICE', bots => [] },
}));

my @said;
no warnings 'redefine';
local *Logodal::Game::AI::_broadcast_chat = sub ($self, $text) { push @said, $text };

my $ww = Logodal::Game::AI->new(app => $app, game_id => 'g', brand => 'wordwank', character_prompt => 'You are Wanko.');
is $ww->_persona('fallback'), "CRUDE HOUSE VOICE\n\nYou are Wanko.", 'voice leads persona';

my $ld = Logodal::Game::AI->new(app => $app, game_id => 'g', brand => 'logodal', character_prompt => 'You are Icarus.');
is $ld->_persona('fallback'), 'You are Icarus.', 'brand without voice -> bare persona';

my $anon = Logodal::Game::AI->new(app => $app, game_id => 'g', brand => 'wordwank');
is $anon->_persona('fallback'), "CRUDE HOUSE VOICE\n\nfallback", 'default persona still gets voice';

$ww->chat('ai.played', { word => 'KNOB' });
$ld->chat('ai.played', { word => 'LYRE' });
is_deeply \@said, ['KNOB! Wanked it.', 'LYRE. Not bad.'], 'canned lines use the bot brand';

done_testing;
