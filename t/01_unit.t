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
            administrator => 0
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

    subtest 'forwards are not supported' => sub {
        my $msg = _new_msg( forward_from => 'someone else' );

        $bot->_dispatch($msg);
        like $msg->_reply, qr/don't forward/, 'Bot does not like forward';
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
    $mock_bot->override(
        sendMessage => sub {
            ++$sent;
        }
    );

    my $bot = _new_bot();

    subtest 'banned user' => sub {
        my $msg = _new_msg(
            text => q{some text},
        );

        $sent = 0;
        my $q_count = ResultSet('Question')->count;

        my $reply = $bot->_forward_and_reply( $msg, ResultSet('User')->find(4) );
        like $reply, qr/Sorry Dave/, 'Bot dislikes the banned user';
        is $sent, 0, "...and doesn't relay their message";
        is ResultSet('Question')->count, $q_count, "...nor store it in the DB";

    };

    subtest 'database updates' => sub {
        my $msg = _new_msg(
            from => Telegram::Bot::Object::User->new(
                id => 23,
                username => 'Bob'
            ),
            text => q{question we want to actually store},
        );

        my $user = ResultSet('User')->find(2);

        $sent = 0;
        my $reply = $bot->_forward_and_reply( $msg, $user );
        like $reply, qr/thanks again/, 'Bot replied appropriately to a normal message';

        ok my $q = ResultSet('Question')->find(
            {text => 'question we want to actually store'}
        ) => 'the question made it into the db';

        is $q->sender->id, 2, 'Attributed the question to the right user';

        is $sent, 1, '...and sent the question to the target chat';
    };

    $mock_bot->reset('sendMessage'); # put it back how we found it

};

subtest 'admin-only commands' => sub {

    my $bot = _new_bot();
    my $admin_user = _user_from_tgid( 34 );
    my $db_admin_user = ResultSet('User')->find(3);

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

    subtest 'basic question management' => sub {

        ResultSet('Question')->update({ responded => 1 });

        my $q = ResultSet('Question')->create({
            sender => 1,
            text => q{This is a story, all about how},
            received => 1679700000,
            responded => 0
        });

        my $qid1 = $q->id;

        $q = ResultSet('Question')->create({
            sender => 2,
            text => q{My life got flipped, turned upside down},
            received => 1679703600,
            responded => 0
        });

        my $qid2 = $q->id;

        my $msg = _new_msg(
            text => '/unanswered',
            from => $admin_user
        );

        my $reply = $bot->_admin_command( $msg, $db_admin_user, 'unanswered' );

        my $expected = <<EOF;
Here are the unanswered questions:

Message # $qid1 from \@alice, at 24 Mar, 11:20 PM
This is a story, all about how

Message # $qid2 from \@bob, at 25 Mar, 12:20 AM
My life got flipped, turned upside down
EOF

        is "$reply\n", $expected, 'Correctly lists two whole questions';
        # heredoc has to terminate with newline, real response does not.

        $msg = _new_msg(
            text => "/showquestion_$qid1",
            from => $admin_user
        );

        $reply = $bot->_admin_command( $msg, $db_admin_user, 'showquestion', $qid1 );

        $expected = <<EOF;
Question $qid1 from \@alice received on 24 Mar, 11:20 PM
This is a story, all about how

To mark as resolved, send /answer_$qid1
EOF

        is "$reply\n", $expected, 'Correctly prints the specified question';

        $msg = _new_msg(
            text => "/answer_$qid1",
            from => $admin_user
        );

        $reply = $bot->_admin_command( $msg, $db_admin_user, 'answer', $qid1 );

        is ResultSet('Question')->find($qid1)->responded, 1,
            q{question gets marked as resolved};

        like $reply, qr/marked question \d+ as resolved/,
            q{...and the admin-user is correctly informed};

    };

    subtest 'nothing to answer' => sub {

        # all questions are answered
        $bot->schema->resultset('Question')->update({responded => 1 });

        my $msg = _new_msg(
            text => '/unanswered',
            from => $admin_user
        );

        like $bot->_admin_command( $msg, $db_admin_user, 'unanswered' )
            => qr/good work team/, 'Bot is happy when everything is answered';

        $bot->schema->resultset('Question')->delete;

        like $bot->_admin_command( $msg, $db_admin_user, 'unanswered' )
            => qr/good work team/, '.. and when nothing was ever asked';

        $msg = _new_msg(
            text => '/showquestion_10000',
            from => $admin_user
        );

        like $bot->_admin_command( $msg, $db_admin_user, 'showquestion', 10_000 )
            => qr/couldn't find question/, '... and copes with invalid question ids';

        $msg = _new_msg(
            text => '/answer_100',
            from => $admin_user
        );

        like $bot->_admin_command( $msg, $db_admin_user, 'answer', 100 )
            => qr/no such question/, '... including when trying to answer them';

    };

    subtest 'unknown admin command' => sub {

        my $msg = _new_msg(
            text => '/notarealcommand',
            from => $admin_user
        );

        like $bot->_admin_command( $msg, $db_admin_user, 'notarealcommand' ), qr{didn't catch that},
            q{Offer the user some help when we don't recognise the command};

    };

    subtest 'emoji bug in question recall' => sub {

        my $bot = _new_bot();


        my $q = ResultSet('Question')->create({
            sender => 1,
            text => q{💙🐸🍟🕌},
            received => time(),
            responded => 0
        });

        my $msg = _new_msg(
            text => '/showquestion_' . $q->id,
            from => $admin_user
        );

        my $reply = $bot->_admin_command($msg, $db_admin_user, 'showquestion', $q->id);

        like $reply, qr{💙🐸🍟🕌}, "Bot correctly displays emoji in questions";

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