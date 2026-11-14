use strict;
use warnings;
use utf8;
use Test::More;
use lib 'lib';
use Logodal::Game::Scorer;

my $scorer = Logodal::Game::Scorer->new();

sub calculate_prefix {
    my ($word, $elapsed, $quick_bonus_seconds, $rack_size) = @_;
    my @emojis;
    
    # ⚡ Quick Bonus
    push @emojis, '⚡' if $elapsed <= $quick_bonus_seconds;

    # 💯 Full Rack
    push @emojis, '💯' if length($word) >= $rack_size;

    # ✨ Extra Letters (Dynamic threshold)
    my $len_bonus = $scorer->get_length_bonus($word);
    push @emojis, '✨' if $len_bonus > 0;

    # 📅 Daily Bonus
    my $bonus_char = $scorer->get_daily_bonus_char();
    push @emojis, '📅' if index(uc($word), $bonus_char) != -1;
    
    return @emojis ? join('', @emojis) . ' ' : '';
}

subtest 'Emoji Prefix Logic' => sub {
    my $quick_bonus_seconds = 5;

    # Tuesday = 'T' is the bonus char
    is(calculate_prefix('CAT', 1, $quick_bonus_seconds, 7), '⚡📅 ', 'Quick play on standard 7 with T gets lightning + calendar');
    is(calculate_prefix('LOGODALS', 6, $quick_bonus_seconds, 8), '💯✨ ', 'Full rack (8) no T gets 100 + sparkles');
    
    # Length bonus starts at LENGTH_BONUS_START letters (default 5)
    is(calculate_prefix('WONK', 6, $quick_bonus_seconds, 8), '', '4 letters on 8 rack no T gets nothing');
    is(calculate_prefix('WONKER', 6, $quick_bonus_seconds, 8), '✨ ', '6 letters on 8 rack no T gets sparkles');
    
    is(calculate_prefix('CAT', 6, $quick_bonus_seconds, 7), '📅 ', 'Normal play on standard 7 with T gets calendar');
    is(calculate_prefix('WONKER', 1, $quick_bonus_seconds, 8), '⚡✨ ', 'Quick + 6 letters on 8 rack no T');
};

subtest 'Length bonus' => sub {
    local $ENV{LENGTH_BONUS_START};
    is($scorer->get_length_bonus('WONK'),    0,  '4 letters: no bonus');
    is($scorer->get_length_bonus('WONKS'),   10, '5 letters: +10');
    is($scorer->get_length_bonus('WONKER'),  20, '6 letters: +20');
    is($scorer->get_length_bonus('WONKERS'), 40, '7 letters: +40');
    local $ENV{LENGTH_BONUS_START} = 6;
    is($scorer->get_length_bonus('WONKS'),   0,  'start 6: 5 letters gets nothing');
    is($scorer->get_length_bonus('WONKER'),  10, 'start 6: 6 letters gets +10');
    local $ENV{LENGTH_BONUS_BASE} = 3;
    is($scorer->get_length_bonus('WONKERS'), 6,  'start 6, base 3: 7 letters gets +6');
};

done_testing();

