use strict;
use warnings;
use lib 'lib';
use Logodal;
use Test::More;

warn "Attempting to create Logodal app...\n";
my $app = Logodal->new;
warn "App created.\n";

warn "Attempting to call startup...\n";
$app->startup;
warn "Startup finished.\n";

ok(1, "Got here");
done_testing();

