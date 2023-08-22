use strict;
use warnings;
use Test2::V0 -target => 'RequestBot';
use Test2::Tools::Mock qw/mock_accessors/;
use Test::DBIx::Class {
    schema_class => 'RequestBot::Schema',
    connect_info => [ 'dbi:SQLite:dbname=:memory:', '', '', {sqlite_unicode => 1} ],
};
use Telegram::Bot::Object::Chat ();
use Telegram::Bot::Object::User ();

my $mock_bot = mock 'RequestBot' => (
    track    => 1,
    override => [
        think => sub {return},
        init  => sub {return},
    ]
);

my $mock_msg = mock 'Telegram::Bot::Object::Message' => (
    track    => 1,
    add      => [ mock_accessors('_reply') ],
    override => [ reply => sub { $_[0]->_reply( $_[1] ) }, ],
);

# Install database fixtures. Note that we use much shorter text strings
# than the actual application so testing is easier.
fixtures_ok 'strings';
fixtures_ok 'user';

subtest 'meta' => sub {
    isa_ok $CLASS->new, 'RequestBot', 'Telegram::Bot::Brain';
};

subtest 'dispatching' => sub {

    # Override the _forward_and_reply and _admin_command subs, so we don't
    # accidentally talk to the internet, and because we will test these later.

    my ( $forwarded, $admin_commands );
    $mock_bot->override(
        _forward_and_reply => sub {
            ++$forwarded;
        },
        _admin_command => sub {
            ++$admin_commands;
        }
    );

    my $bot = _new_bot();

    subtest 'text is required for private chat' => sub {
        my $msg = _new_msg(
            text => undef,
            chat => _new_private_chat( id => 5 )
        );

        $bot->_dispatch($msg);
        like $msg->_reply, qr/I can only deal in words/, 'Bot needs text';
    };

    subtest 'first time user' => sub {

        my $expected_user_id = ResultSet('User')->count + 1;

        my $msg = _new_msg(
            from => Telegram::Bot::Object::User->new(
                id => 666,
                username => 'Charlie'
            ),
            chat => _new_private_chat( id => 5150 ),
            text => q{some text},
        );

        $bot->_dispatch( $msg );

        my $user = ResultSet('User')->find($expected_user_id);

        is_fields $user, {
            telegram_id => 666,
            telegram_username => 'Charlie',
            banned => 0,
            admin => 0,
            privacy_contact => 0,
            seen_intro => 0,
        }, 'created a reasonable looking record for a new user';

    };

    subtest 'do nothing if you do not understand the message' => sub {
        my $msg = _new_msg(
            text => undef,
            chat => _new_group_chat( id => -23 )
        );

        $forwarded = 0;

        $bot->_dispatch($msg);
        is $msg->_reply, undef,
            'Bot does not respond to messages it does not understand';
        is $forwarded, 0, '... and we did not try to forward';
    };

    subtest 'forwards are only supported if the forwarder is admin' => sub {
        
        $forwarded = 0;
        my $msg = _new_msg( 
            forward_from => 'someone else',
            chat => _new_private_chat(),
            text => 'just some text, you know'
        );

        $bot->_dispatch($msg);
        like $msg->_reply, qr/don't forward/, 'Bot does not like forward from just anybody';
        is $forwarded, 0, 'And does not call _forward_and_reply';

        $msg->{user} = _user_from_tgid( 34 ); # forwarder
        $msg->{forward_from} = _user_from_tgid( 12 ); # originator

        $bot->_dispatch($msg);

        is $msg->_reply, '1', 'Bot treats the message as non-forwarded messages from originator';

    };

    subtest 'command: /whereami' => sub {
        my $msg = _new_msg(
            chat => _new_group_chat( id => -5 ),
            text => q{/whereami}
        );

        $bot->_dispatch($msg);
        like $msg->_reply, qr/This is -5/, 'Bot responds with chat id';
    };

    for my $command (qw/ help start /) {
        subtest qq{command: /$command} => sub {
            my $msg = _new_msg( text => qq{/$command} );

            $bot->_dispatch($msg);
            is $msg->_reply, 'hello world', 'Bot responds welcome message';
        };
    }

    subtest 'admin-only /commands' => sub {

        is $admin_commands, undef, 'No unexpected admin commands yet';

        # don't actually need to test every command here, but arbitrary
        # /commands should all get passed through here...
        my $msg = _new_msg( text => '/hlaghlagh' );
        $bot->_dispatch($msg);

        is $admin_commands, 1, '... and an arbitrary /command is treated as one';

    };


    subtest 'final dispatch checks' => sub {

        my $msg_group = _new_msg(
            chat => _new_group_chat( id => -4 ),
            text => q{does not matter}
        );

        my $msg_priv = _new_msg(
            chat => _new_private_chat( id => 4 ),
            text => q{still not important}
        );

        $forwarded = 0;
        $bot->_dispatch($msg_group);
        is $msg_group->_reply, undef,   'Bot does not respond to messages in groups';
        is $forwarded, 0, '... and we did not try to forward';

        $bot->_dispatch($msg_priv);
        is $msg_priv->_reply, '1', 'Bot does respond to messages in private';
        is $forwarded, 1, '... and we did try to forward';

    };

    $mock_bot->reset('_admin_command');
    $mock_bot->reset('_forward_and_reply');

};

subtest 'testing forward_and_reply' => sub {

    # let's override sendMessage so that we don't actually try and talk to
    # Telegram, but we can go a little deeper into _forward_and_reply
    my $sent = 0;
    my $sent_text = '';
    $mock_bot->override(
        sendMessage => sub {
            ++$sent;
            my $bot = shift;
            my $msg = shift;
            if ( defined $msg ) {
                $sent_text = $msg->{text};
            }
        }
    );

    my $bot = _new_bot();

    subtest 'banned user' => sub {
        my $msg = _new_msg(
            text => q{some text},
        );

        $sent = 0;
        my $q_count = ResultSet('Request')->count;

        my $reply = $bot->_forward_and_reply( $msg, ResultSet('User')->find(4) );
        like $reply, qr/Sorry Dave/, 'Bot dislikes the banned user';
        is $sent, 0, "...and doesn't relay their message";
        is ResultSet('Request')->count, $q_count, "...nor store it in the DB";

    };

    subtest 'database updates' => sub {
        my $msg = _new_msg(
            from => Telegram::Bot::Object::User->new(
                id => 23,
                username => 'Bob'
            ),
            text => q{request we want to actually store},
        );

        my $user = ResultSet('User')->find(2);

        $sent = 0;
        my $reply = $bot->_forward_and_reply( $msg, $user );
        like $reply, qr/thanks again/, 'Bot replied appropriately to a normal message';

        my $q = ResultSet('Request')->find(
            {text => 'request we want to actually store'}
        );
        ok $q->id => 'the request made it into the db';

        my $qid = $q->id;
        like $reply, qr/ID is $qid/, '...and the user was told the ID';

        my $close_command = '/close_' . $q->id;

        is $q->sender->id, 2, 'Attributed the request to the right user';

        is $sent, 1, '...and sent the request to the target chat';

        like $sent_text, qr/$close_command/, "...and the target chat gets the correct resolution command";
    };

    subtest 'forwarded message by admin' => sub {
        my $msg = _new_msg( 
            from => _user_from_tgid( 34 ), # admin
            forward_from => _user_from_tgid( 12 ), # originator
            text => q{some text we sent to the wrong person},
        );

        my $user = ResultSet('User')->find(1);

        $sent = 0;

        my $reply = $bot->_forward_and_reply( $msg, $user );
        like $reply, qr /thanks again/, 'Bot replies to the forwarded message correctly, in this one weird case';

        is $sent, 1, '...and the message was passed on';

        $sent = 0;
    };

    $mock_bot->reset('sendMessage'); # put it back how we found it

};

subtest 'admin-only commands' => sub {

    my $bot = _new_bot();
    my $admin_user = _user_from_tgid( 34 );
    my $db_admin_user = ResultSet('User')->find(3);

    my $sent_text;
    my $sent = 0;
    $mock_bot->override(
        sendMessage => sub {
            ++$sent;
            my $bot = shift;
            my $msg = shift;
            if ( defined $msg ) {
                $sent_text = $msg->{text};
            }
        }
    );

    subtest 'non-admin user' => sub {
        my $msg = _new_msg(
            from => _user_from_tgid( 999 ),
            chat => _new_private_chat( id => 999 ),
            text => 'from an unknown user'
        );

        my $user = ResultSet('User')->find_or_create({
            telegram_id => 999,
            telegram_username => 'Hal'
        });

        my $reply = $bot->_admin_command($msg, $user);
        like $reply, qr{special minions}, 'Politely refuse the unknown user';

        $msg = _new_msg(
            from => _user_from_tgid( 12 ),
            chat => _new_private_chat( id => 12 ),
            text => 'from an known, non-admin user'
        );

        $user = ResultSet('User')->find(1);

        $reply = $bot->_admin_command($msg, $user);
        like $reply, qr{special minions}, '... and refuse the non-admin user';

    };

    subtest 'basic request management' => sub {

        ResultSet('Request')->update({ responded => 1 });

        my $q = ResultSet('Request')->create({
            sender => 1,
            text => q{This is a story, all about how},
            received => 1679700000,
            responded => 0
        });

        my $qid1 = $q->id;

        $q = ResultSet('Request')->create({
            sender => 2,
            text => q{My life got flipped, turned upside down},
            received => 1679703600,
            responded => 0
        });

        my $qid2 = $q->id;

        my $msg = _new_msg(
            text => '/open',
            from => $admin_user
        );

        my $reply = $bot->_admin_command( $msg, $db_admin_user, 'open' );

        my $expected = <<EOF;
Here are the unresolved requests:

Message # $qid1 from \@alice, at 24 Mar, 11:20 PM
This is a story, all about how

Message # $qid2 from \@bob, at 25 Mar, 12:20 AM
My life got flipped, turned upside down
EOF

        is "$reply\n", $expected, 'Correctly lists two whole requests';
        # heredoc has to terminate with newline, real response does not.

        $msg = _new_msg(
            text => "/showrequest_$qid1",
            from => $admin_user
        );

        $reply = $bot->_admin_command( $msg, $db_admin_user, 'showrequest', $qid1 );

        $expected = <<EOF;
Request $qid1 from \@alice received on 24 Mar, 11:20 PM
This is a story, all about how

To mark as resolved, send /close_$qid1
EOF

        is "$reply\n", $expected, 'Correctly prints the specified request';

        $msg = _new_msg(
            text => "/close_$qid1",
            from => $admin_user
        );

        $sent_text = ''; # make sure this is empty beforehand
        $sent = 0; # and this

        $reply = $bot->_admin_command( $msg, $db_admin_user, 'close', $qid1 );

        is ResultSet('Request')->find($qid1)->responded, 1,
            q{request gets marked as resolved};

        like $reply, qr/marked request $qid1 as resolved/,
            q{...and the admin-user is correctly informed};

        like $sent_text, qr/ID $qid1/,
            q{...and the requestor is correctly informed too!};

    };

    subtest 'nothing to answer' => sub {

        # all requests are answered
        ResultSet('Request')->update({responded => 1 });

        my $msg = _new_msg(
            text => '/open',
            from => $admin_user
        );

        like $bot->_admin_command( $msg, $db_admin_user, 'open' )
            => qr/good work team/, 'Bot is happy when everything is answered';

        $bot->schema->resultset('Request')->delete;

        like $bot->_admin_command( $msg, $db_admin_user, 'open' )
            => qr/good work team/, '.. and when nothing was ever asked';

        $msg = _new_msg(
            text => '/showrequest_10000',
            from => $admin_user
        );

        like $bot->_admin_command( $msg, $db_admin_user, 'showrequest', 10_000 )
            => qr/couldn't find request/, '... and copes with invalid request ids';

        $msg = _new_msg(
            text => '/close_100',
            from => $admin_user
        );

        like $bot->_admin_command( $msg, $db_admin_user, 'close', 100 )
            => qr/no such request/, '... including when trying to resolve them';

    };

    subtest 'user management' => sub {

        my $msg = _new_msg(
            from => $admin_user
        );

        my %list_tests = (
            users => '@alice - /promote_1 - /banhammer_1',
            admins => '@bob - /demote_2',
            banned => '@moriarty - /unban_4',
        );

        for ( keys %list_tests ) {
            my $expectation = $list_tests{$_};
            like $bot->_admin_command( $msg, $db_admin_user, $_ )
                => qr/$expectation/s, "/$_ command behaves as expected";
        }

        $mock_bot->override( sendMessage => sub {} );
        # TODO: test that we call this, rather than just disabling it

        like $bot->_admin_command( $msg, $db_admin_user, promote => 1 ),
            => qr/is an admin/, "Promotion responds correctly";
        is ResultSet('User')->find(1)->admin, 1, "And that user was promoted";

        $mock_bot->reset( 'sendMessage' );

        like $bot->_admin_command( $msg, $db_admin_user, banhammer => 1 ),
            => qr/too powerful/i, "Banning an admin fails";
        is ResultSet('User')->find(1)->banned, 0, "And user was not banned";

        like $bot->_admin_command( $msg, $db_admin_user, unban => 4 ),
            => qr/moriarty is now unbanned/i, "Unban responds correctly";
        is ResultSet('User')->find(4)->banned, 0, "And the user was unbanned";

        like $bot->_admin_command( $msg, $db_admin_user, banhammer => 4 ),
            => qr/moriarty can't send me requests/i, "Banning responds correctly";
        is ResultSet('User')->find(4)->banned, 1, "And the user was banned";

    };

    subtest 'changing target_chat_id' => sub {

        my $sent = 0;
        $mock_bot->override(
            sendMessage => sub {
                $sent++;
            }
        );

        my $config_change_count = 0;
        my $mock_config = mock 'Config::JSON' => (
            track => 1,
            override => [
                set => sub { ++$config_change_count }
            ]
        );

        my $msg = _new_msg(
            from => $admin_user,
            chat => _new_group_chat( id => 234 ),
        );

        like $bot->_admin_command( $msg, $db_admin_user, 'liveherenow' )
            => qr/communicate here/, "Bot responds appropriately to target chat reset";

        is $bot->target_chat_id, 234, "And it correctly updates the target chat";
        is $sent, 1, "And it sends the old-chat notifications";
        is $config_change_count, 1, "And it wrote to the config file";
        
    };

    subtest 'unknown admin command' => sub {

        my $msg = _new_msg(
            text => '/notarealcommand',
            from => $admin_user
        );

        like $bot->_admin_command( $msg, $db_admin_user, 'notarealcommand' ), qr{didn't catch that},
            q{Offer the user some help when we don't recognise the command};

    };

    subtest 'emoji bug in request recall' => sub {

        my $bot = _new_bot();


        my $q = ResultSet('Request')->create({
            sender => 1,
            text => q{💙🐸🍟🕌},
            received => time(),
            responded => 0
        });

        my $msg = _new_msg(
            text => '/showrequest_' . $q->id,
            from => $admin_user
        );

        my $reply = $bot->_admin_command($msg, $db_admin_user, 'showrequest', $q->id);

        like $reply, qr{💙🐸🍟🕌}, "Bot correctly displays emoji in requests";

    };

};



sub _new_bot {
    return $CLASS->new(
        token          => 'token',
        target_chat_id => 123,
        schema         => Schema(),
    );
}

sub _new_msg {
    my %args = @_;
    unless ( defined $args{from} ) {
        $args{from} = _user_from_tgid();
    }
    return Telegram::Bot::Object::Message->new(%args);
}

sub _new_private_chat {
    return Telegram::Bot::Object::Chat->new( type => 'private', @_ );
}

sub _new_group_chat {
    return Telegram::Bot::Object::Chat->new( type => 'group', @_ );
}

sub _user_from_tgid {
    my $telegram_id = shift // -1;
    return Telegram::Bot::Object::User->new( id => $telegram_id );
}


done_testing;