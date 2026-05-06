package RequestBot::BotManager;

use Mojo::Base -base;
use Mojo::IOLoop ();

use RequestBot ();
use RequestBot::BotConfig ();

=head1 NAME

RequestBot::BotManager - Run multiple RequestBot instances in a single process

=head1 DESCRIPTION

Loads per-customer config files from a directory, instantiates one
L<RequestBot> per customer, and drives them all through a single shared
L<Mojo::IOLoop> event loop.

=head1 HOW IT WORKS

L<Telegram::Bot::Brain/think> calls C<Mojo::IOLoop-E<gt>start> only when the
loop is not already running. By scheduling each C<$bot-E<gt>think> inside a
C<Mojo::IOLoop-E<gt>next_tick> callback, all bots register their recurring
C<getUpdates> handlers into the shared loop. C<Mojo::IOLoop-E<gt>start> is
then called once and drives every bot concurrently.

=head1 ATTRIBUTES

=head2 bots

An arrayref of loaded L<RequestBot> instances.

=head2 health_check_interval

How often (in seconds) the manager checks for silent bots. Default: 300.

=head2 health_check_timeout

How many seconds of silence before a bot is considered unhealthy. Default: 900.

=cut

has 'bots'                  => sub { [] };
has 'health_check_interval' => 300;
has 'health_check_timeout'  => 900;

=head1 METHODS

=head2 load_bots

    $manager->load_bots('customers');

Discovers all C<*.json> files in the given directory and instantiates one
L<RequestBot> per valid config. Invalid or unreadable configs are skipped with
a warning. Dies if no bots were successfully loaded.

=cut

sub load_bots {
    my ( $self, $config_dir ) = @_;

    my @paths = RequestBot::BotConfig->find_all($config_dir);

    unless (@paths) {
        die "BotManager: no config files found in '$config_dir'\n";
    }

    my @bots;
    for my $path (@paths) {
        my $attrs = RequestBot::BotConfig->load($path);
        unless ($attrs) {
            warn "BotManager: skipping '$path' due to config errors\n";
            next;
        }

        my $bot = RequestBot->new(%$attrs);
        push @bots, $bot;
        warn "BotManager: loaded bot for '$attrs->{config_path}'\n";
    }

    die "BotManager: no bots were successfully loaded\n" unless @bots;

    $self->bots(\@bots);
    return $self;
}

=head2 run

    $manager->run;

Starts all loaded bots and enters the event loop. Blocks until the loop is
stopped (e.g. via SIGTERM or SIGINT).

=cut

sub run {
    my $self = shift;

    $self->_install_signal_handlers;
    $self->_install_health_check;

    for my $bot ( @{ $self->bots } ) {
        Mojo::IOLoop->next_tick( sub { $bot->think } );
    }

    Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
}

# ---- private ----------------------------------------------------------------

sub _install_signal_handlers {
    my $self = shift;

    $SIG{INT}  = sub { warn "BotManager: caught SIGINT, stopping\n";  Mojo::IOLoop->stop };
    $SIG{TERM} = sub { warn "BotManager: caught SIGTERM, stopping\n"; Mojo::IOLoop->stop };
}

sub _install_health_check {
    my $self = shift;

    my $interval = $self->health_check_interval;
    my $timeout  = $self->health_check_timeout;

    Mojo::IOLoop->recurring(
        $interval => sub {
            my $now = time();
            for my $bot ( @{ $self->bots } ) {
                my $last = $bot->last_update_time;
                next unless $last;    # bot hasn't received any updates yet
                my $silent_for = $now - $last;
                if ( $silent_for > $timeout ) {
                    warn sprintf(
                        "BotManager: bot '%s' has been silent for %d seconds\n",
                        $bot->config_path,
                        $silent_for,
                    );
                }
            }
        }
    );
}

1;
