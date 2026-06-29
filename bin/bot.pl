#!perl

use strict;
use warnings;
use lib 'lib';

use Getopt::Long qw(GetOptions);

use RequestBot::BotManager ();
<<<<<<< HEAD

# Legacy single-bot mode: perl bin/bot.pl config.json
# Multi-bot mode:         perl bin/bot.pl [--config-dir customers]

my $config_dir = 'customers';

GetOptions( 'config-dir=s' => \$config_dir );

# Allow a bare positional argument as a legacy single-config path.
# In that case we wrap it in a temporary customers dir by loading it directly.
if ( @ARGV && !-d $ARGV[0] ) {
    require Config::JSON;
    require RequestBot;
    my $config = Config::JSON->new( $ARGV[0] );
    RequestBot->new(
        map { $_ => $config->get($_) }
          qw|token target_chat_id sheet_id|
    )->think;
    exit 0;
}

$config_dir = $ARGV[0] if @ARGV && -d $ARGV[0];

my $manager = RequestBot::BotManager->new;
$manager->load_bots($config_dir);
$manager->run;

=======

# Legacy single-bot mode: perl bin/bot.pl config.json
# Multi-bot mode:         perl bin/bot.pl [--config-dir customers]

my $config_dir = 'customers';

GetOptions( 'config-dir=s' => \$config_dir );

# Allow a bare positional argument as a legacy single-config path.
# In that case we wrap it in a temporary customers dir by loading it directly.
if ( @ARGV && !-d $ARGV[0] ) {
    require Config::JSON;
    require RequestBot;
    my $config = Config::JSON->new( $ARGV[0] );
    RequestBot->new(
        map { $_ => $config->get($_) }
          qw|token target_chat_id|
    )->think;
    exit 0;
}

$config_dir = $ARGV[0] if @ARGV && -d $ARGV[0];

my $manager = RequestBot::BotManager->new;
$manager->load_bots($config_dir);
$manager->run;
>>>>>>> d5ec9b0241d5b33a97cc58e4656b8f88bd625d31
