package RequestBot::BotConfig;

use strict;
use warnings;

use Config::JSON ();
use File::Basename qw(basename);
use Carp qw(croak);

=head1 NAME

RequestBot::BotConfig - Load and discover per-customer bot configuration files

=head1 DESCRIPTION

Provides helpers for discovering C<.json> config files in a customer directory
and loading them into attribute hashrefs suitable for passing to
L<RequestBot/new>.

=head1 CLASS METHODS

=head2 find_all

    my @paths = RequestBot::BotConfig->find_all('customers');

Returns a list of C<.json> file paths found in the given directory.

=cut

sub find_all {
    my ( $class, $dir ) = @_;
    croak "config directory '$dir' does not exist" unless -d $dir;
    return glob( $dir . '/*.json' );
}

=head2 load

    my $attrs = RequestBot::BotConfig->load('customers/acme.json');

Reads a customer config file and returns a hashref of constructor arguments
suitable for L<RequestBot/new>. Derived attributes (C<db_path>, C<log_path>,
C<config_path>) are added automatically based on the filename stem.

Returns C<undef> and warns if the config is missing required keys.

=cut

sub load {
    my ( $class, $config_path ) = @_;

    my $config = eval { Config::JSON->new($config_path) };
    if ($@) {
        warn "BotConfig: failed to read '$config_path': $@";
        return undef;
    }

    my $token          = $config->get('token');
    my $target_chat_id = $config->get('target_chat_id');

    unless ( defined $token && length $token ) {
        warn "BotConfig: '$config_path' is missing 'token', skipping";
        return undef;
    }
    unless ( defined $target_chat_id ) {
        warn "BotConfig: '$config_path' is missing 'target_chat_id', skipping";
        return undef;
    }

    my $name = basename($config_path);
    $name =~ s/\.json$//i;

    return {
        token          => $token,
        target_chat_id => $target_chat_id,
        config_path    => $config_path,
        db_path        => "data/$name.db",
        log_path       => "logs/$name.log",
    };
}

1;
