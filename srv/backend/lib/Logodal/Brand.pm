package Logodal::Brand;
use Mojo::Base -base, -signatures;
use Mojo::JSON qw(decode_json);

# Maps request hostnames to brands ("skins") and back.
#
# One deployment serves several brands (logodal.com, wordwank.com, ...) from a
# single database and player pool. The brand only affects presentation: theme,
# copy, and which domain we link back to. Configured from the environment:
#   BRAND_HOSTS   JSON object {"logodal.com":"logodal","wordwank.com":"wordwank"}
#   DEFAULT_BRAND brand for unknown hosts (default "logodal")

has hosts   => sub { {} };       # host => brand
has default => 'logodal';

sub from_env ($class) {
    my $hosts = {};
    if (my $json = $ENV{BRAND_HOSTS}) {
        $hosts = eval { decode_json($json) } // {};
        warn "Logodal::Brand: ignoring malformed BRAND_HOSTS: $@" if $@;
    }
    return $class->new(
        hosts   => { map { lc($_) => $hosts->{$_} } keys %$hosts },
        default => $ENV{DEFAULT_BRAND} || 'logodal',
    );
}

# Every brand we know about, including the default.
sub known ($self) {
    my %seen = ($self->default => 1);
    $seen{$_} = 1 for values %{ $self->hosts };
    return [ sort keys %seen ];
}

# Resolve a Host header value to a brand. Exact host match first (ignoring port
# and a leading "www."), then any known brand appearing as a whole DNS label,
# so dev hosts like wordwank.localhost or wordwank.kind.local just work.
sub for_host ($self, $host) {
    return $self->default unless defined $host && length $host;
    $host = lc $host;
    $host =~ s/:\d+$//;
    $host =~ s/^www\.//;

    my $hosts = $self->hosts;
    return $hosts->{$host} if exists $hosts->{$host};

    my %labels = map { $_ => 1 } split /\./, $host;
    for my $brand (@{ $self->known }) {
        return $brand if $labels{$brand};
    }
    return $self->default;
}

# Canonical public URL for a brand, or undef if it has no configured host.
sub url_for ($self, $brand) {
    my $hosts = $self->hosts;
    my ($host) = sort grep { $hosts->{$_} eq $brand } keys %$hosts;
    return $host ? "https://$host" : undef;
}

1;
