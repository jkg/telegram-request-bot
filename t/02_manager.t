use strict;
use warnings;
use Test2::V0;
use Test2::Tools::Mock qw(mock_accessors);
use File::Temp qw(tempdir tempfile);
use File::Spec ();

use lib 'lib';
use RequestBot::BotConfig ();
use RequestBot::BotManager ();

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

sub _write_config {
    my ($dir, $name, %extra) = @_;
    my $path = File::Spec->catfile($dir, "$name.json");
    open my $fh, '>', $path or die "Cannot write $path: $!";
    my $target = $extra{target_chat_id} // -100;
    my $token  = $extra{token}          // "fake-token-$name";
    print $fh qq|{"token":"$token","target_chat_id":$target}|;
    close $fh;
    return $path;
}

# ---------------------------------------------------------------------------
# BotConfig tests
# ---------------------------------------------------------------------------

subtest 'BotConfig::load' => sub {

    my $dir = tempdir( CLEANUP => 1 );

    subtest 'valid config' => sub {
        my $path = _write_config($dir, 'acme', token => 'tok123', target_chat_id => -42);
        my $attrs = RequestBot::BotConfig->load($path);

        ok defined($attrs), 'load returns a hashref for a valid config';
        is $attrs->{token},          'tok123', 'token is correct';
        is $attrs->{target_chat_id}, -42,      'target_chat_id is correct';
        is $attrs->{config_path},    $path,    'config_path is set to the file path';
        is $attrs->{db_path},        'data/acme.db',  'db_path is derived from filename';
        is $attrs->{log_path},       'logs/acme.log', 'log_path is derived from filename';
    };

    subtest 'missing token' => sub {
        my $path = File::Spec->catfile($dir, 'notoken.json');
        open my $fh, '>', $path or die $!;
        print $fh '{"target_chat_id":-1}';
        close $fh;

        my $attrs;
        my @warnings;
        {
            local $SIG{__WARN__} = sub { push @warnings, @_ };
            $attrs = RequestBot::BotConfig->load($path);
        }
        ok !defined($attrs), 'load returns undef for a config without a token';
        ok scalar(@warnings), 'a warning was emitted';
    };

    subtest 'missing target_chat_id' => sub {
        my $path = File::Spec->catfile($dir, 'nochat.json');
        open my $fh, '>', $path or die $!;
        print $fh '{"token":"sometoken"}';
        close $fh;

        my $attrs;
        my @warnings;
        {
            local $SIG{__WARN__} = sub { push @warnings, @_ };
            $attrs = RequestBot::BotConfig->load($path);
        }
        ok !defined($attrs), 'load returns undef for a config without target_chat_id';
        ok scalar(@warnings), 'a warning was emitted';
    };

    subtest 'unreadable file' => sub {
        my $attrs;
        my @warnings;
        {
            local $SIG{__WARN__} = sub { push @warnings, @_ };
            $attrs = RequestBot::BotConfig->load('/nonexistent/path/x.json');
        }
        ok !defined($attrs), 'load returns undef for a missing file';
        ok scalar(@warnings), 'a warning was emitted';
    };
};

subtest 'BotConfig::find_all' => sub {

    my $dir = tempdir( CLEANUP => 1 );
    _write_config($dir, 'alpha');
    _write_config($dir, 'beta');

    # write a non-json file that should not be returned
    open my $fh, '>', File::Spec->catfile($dir, 'ignore.txt') or die $!;
    print $fh 'not a config';
    close $fh;

    my @paths = RequestBot::BotConfig->find_all($dir);
    is scalar(@paths), 2, 'find_all returns only .json files';

    subtest 'dies on missing directory' => sub {
        ok dies { RequestBot::BotConfig->find_all('/no/such/dir') },
            'find_all dies when directory does not exist';
    };
};

# ---------------------------------------------------------------------------
# BotManager tests
# ---------------------------------------------------------------------------

subtest 'BotManager::load_bots' => sub {

    # Mock RequestBot so we don't touch DBs or the network.
    my $mock_bot = mock 'RequestBot' => (
        override => [
            new   => sub { bless { think_called => 0 }, shift },
            think => sub { $_[0]->{think_called}++ },
            init  => sub {},
        ]
    );

    my $dir = tempdir( CLEANUP => 1 );
    _write_config($dir, 'first');
    _write_config($dir, 'second');

    # Also add an invalid config to confirm it is skipped.
    my $bad_path = File::Spec->catfile($dir, 'bad.json');
    open my $fh, '>', $bad_path or die $!;
    print $fh '{"target_chat_id":-1}';   # missing token
    close $fh;

    my $manager;
    my @warnings;
    {
        local $SIG{__WARN__} = sub { push @warnings, @_ };
        $manager = RequestBot::BotManager->new;
        $manager->load_bots($dir);
    }

    is scalar( @{ $manager->bots } ), 2,
        'load_bots instantiates one bot per valid config';

    ok grep( { /skipping/ } @warnings ),
        'a warning was emitted for the invalid config';

    subtest 'dies with no valid configs' => sub {
        my $empty_dir = tempdir( CLEANUP => 1 );
        ok dies { RequestBot::BotManager->new->load_bots($empty_dir) },
            'load_bots dies when no configs are found';
    };

    subtest 'dies with no loadable configs' => sub {
        my $all_bad_dir = tempdir( CLEANUP => 1 );
        my $path = File::Spec->catfile($all_bad_dir, 'onlybad.json');
        open my $fh2, '>', $path or die $!;
        print $fh2 '{"target_chat_id":-1}';
        close $fh2;

        my @w;
        local $SIG{__WARN__} = sub { push @w, @_ };
        ok dies { RequestBot::BotManager->new->load_bots($all_bad_dir) },
            'load_bots dies when all configs are invalid';
    };
};

subtest 'BotManager::run schedules think() for each bot' => sub {

    my @think_calls;
    my $mock_bot = mock 'RequestBot' => (
        override => [
            new   => sub { bless { id => scalar @think_calls }, shift },
            think => sub { push @think_calls, $_[0] },
            init  => sub {},
        ]
    );

    # Mock Mojo::IOLoop so we don't actually start an event loop.
    my @next_ticks;
    my @recurrings;
    my $mock_loop = mock 'Mojo::IOLoop' => (
        override => [
            next_tick  => sub { push @next_ticks,  $_[1]; $_[1]->() },
            recurring  => sub { push @recurrings, $_[1] },
            is_running => sub { 1 },   # pretend loop is already running
            start      => sub {},
        ]
    );

    my $dir = tempdir( CLEANUP => 1 );
    _write_config($dir, 'botA');
    _write_config($dir, 'botB');

    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };

    my $manager = RequestBot::BotManager->new;
    $manager->load_bots($dir);
    $manager->run;

    is scalar(@next_ticks), 2,
        'run() scheduled two next_tick callbacks (one per bot)';

    is scalar(@think_calls), 2,
        'think() was called for each bot';

    is scalar(@recurrings), 1,
        'run() installed exactly one recurring health-check timer';
};

done_testing;
