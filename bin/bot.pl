#!perl

use strict;
use warnings;
use lib 'lib';

use Config::JSON ();
use RequestBot ();

my $config = Config::JSON->new('config.json');

RequestBot->new(
    map { $_ => $config->get($_) }
      qw|token target_chat_id|
)->think;
