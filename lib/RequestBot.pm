package RequestBot;

use Mojo::Base 'RequestBot::SafeBrain';
use DateTime;
use URI::Encode qw|uri_encode|;

use Config::JSON;

use Log::Dispatch;

use RequestBot::Schema;
use Try::Tiny;

=head1 NAME

RequestBot - a simple "ticketing" bot, for Telegram

=head1 DESCRIPTION

This is a Telegram bot that collects user requests and forwards
them into a designated group chat, where its administrative users can track
them, process them and then respond to the requestor when appropriate.

=head1 ATTRIBUTES

=cut

has 'schema';
has 'token';
has 'target_chat_id';
has 'logger';

=head1 METHODS

=head2 init

Called by L<Telegram::Bot::Brain> to initialise the bot.

=cut

sub init {
    my $self = shift;

    if ( !$self->schema ) {
        $self->schema( RequestBot::Schema->connect(
        	'dbi:SQLite:requestbot.db', '', '', { sqlite_unicode => 1 })
        ) or die "Couldn't open database file, sorry.";
    }

    if ( !$self->logger ) {

        try {

            my $logger = Log::Dispatch->new(
                outputs => [
                    [
                        FileRotate =>
                            min_level   => 'info',
                            filename    => 'logs/squawk.log',
                            TZ          => 'UTC',
                            DatePattern => 'yyyy-MM-dd',
                            min_level   => 'info',
                            newline     => 1,
                            mode        => 'append',
                    ],
                    [
                        Screen =>
                            min_level   => 'error',
                            newline     => 1,
                    ],
                ]
            );

            $self->logger( $logger );

        } catch {
            die "Couldn't initialise logging service: $_";
        };

    }

    $self->add_listener( \&_dispatch );
}

=head1 INTERNAL METHODS

=head2 _dispatch

The listener that handles all of the messages. Takes a L<Telegram::Bot::Message>
object and is called every time a message is polled. Updates the message with
a response, but does not return anything.

=cut

sub _dispatch {
    my $self   = shift;
    my $update = shift;

    my $sender;

    if ( defined $update->from ) {
        $sender = $self->schema->resultset('User')->find_or_create( telegram_id => $update->from->id );
        $sender->telegram_username( $update->from->username );
        $sender->update;
    } else {
        return; # can this even be reached in the real world? happy to silently fail if no sender...
    }

    my $text = $update->text;
    my $reply;

    # first, the sanity checks
    if ( not defined $text ) {
        if ( $update->chat->type eq 'private' ) {
            # private chat, respond to tell them we didn't understand
            $reply = "Sorry, I can only deal in words, not attachments";
        }
        else {
            # in a group, quietly ignore anything we don't understand
            return;
        }
    }

    # then the /commands
    elsif ( $text eq '/whereami' ) {
        $reply = "Are you lost? This is " . $update->chat->id;
    }

    elsif ( $text =~ m|^/start| or $text =~ m|^/help| ) {
        $reply =
          $self->schema->resultset('String')->find('help')->string_en;

        if ( $sender->admin ) {
            $reply .= "\n\n" . $self->schema->resultset('String')->find('admin_help')->string_en;
        }
    }

    elsif ( $text =~ m|^/privacy| ) {
        $reply =
            $self->schema->resultset('String')->find('privacy')->string_en;
        $reply .= "\n\nIf necessary, you can contact \@" .
            $self->schema->resultset('User')
                ->search_rs({privacy_contact => 1})
                ->first->telegram_username
            . " to access your data, or to have it updated/removed";
    }

    elsif ( $text =~ m{
        ^
        /([a-z]+)        # /command
        (?:_(\d+))?      # optional _123
    }ix ) {
        $reply = $self->_admin_command($update, $sender, $1, $2);
    }

    # for everything else, check that we're not in a group environment
    elsif ( $update->chat->type ne 'private' ) {
        return;
    }

    elsif ( defined $update->forward_from ) {
        $reply = "Please don't forward messages to me, ask me yourself!";

    }

    # finally, looks like an actual user request! so let's process it
    else {
        $reply = $self->_forward_and_reply($update, $sender);
    }

    if ($reply) {
        $update->reply($reply);
    }

}

=head2 _forward_and_reply

Forwards a message to the group in our C<target_chat_id> and sends a response
to the user.

=cut

sub _forward_and_reply {
    my $self   = shift;
    my $update = shift;
    my $sender = shift;

    my $schema = $self->schema;
    my $reply  = '';

    if ( $sender->banned ) {
        return $self->schema->resultset('String')->find('banned')->string_en;
    }

    my $response_type =
      $sender->seen_intro ? 'receipt_general' : 'receipt_first';

    try {
        my $rq = $schema->resultset('Request')->create(
            {   sender   => $sender->id,
                text     => $update->text,
                received => DateTime->now->epoch,
            }
        );

        my $msg = {
            chat_id => $self->target_chat_id,
            text    => 'Message from @'
                . $update->from->username . "\n\n"
                . $update->text . "\n\n"
                . "Resolve using: /close_" . $rq->id
        };

        $self->sendMessage($msg);
        $reply
          .= $schema->resultset('String')->find($response_type)->string_en;

        $sender->seen_intro(1);
    } catch {
        $self->logger->error( "Crashed during forward-and-reply: $_" );
        $reply = "Something crazy happened, sorry";
    };

    $sender->update;
    return $reply;
}

=head2 _admin_command

Handles all admin commands, including database storage as well as the response
to the user. Arguments are

* C<$update> the L<Telegram::Bot::Message> object we have received
* C<$sender>, a L<RequestBot::Schema::Result::User> associated with the message
* C<$command> the command we're running
* C<$id> an optional ID for the command to operate on

Returns text for the bot to send back to the user.

=cut

sub _admin_command {
    my ($self, $update, $sender, $command, $id) = @_;
    my $schema = $self->schema;

    return
      "Sorry, did you need some /help? Many of my features are only for my special minions, because they give me chips."
      unless ( defined $sender and $sender->admin );

    if ( $command eq 'open' ) {

        # show unanswered requests

        my @requests = $schema->resultset('Request')->search(
            { responded => 0 },
            {   prefetch => 'sender',
                order_by => [qw| received |],
            },

            # if we order by sender first, we will get related requests
            # together, in theory...
            # older sender IDs are likely to have sent their first requests
            # earlier so it doesn't break the "obvious" ordering too much.
        );

        return
          "Looks like everything's been answered, good work team! Let's go get some chips... well, you get some, I'll steal yours?"
          unless @requests;

        my $max_q_length = int( 1000 / scalar @requests );

        # truncate the messages to keep the message length sane

        my @reply_parts = ("Here are the unresolved requests:");

        for my $q (@requests) {
            my $sender_display = '@' . $q->sender->telegram_username;
            my $date_display   = DateTime->from_epoch( epoch => $q->received )
              ->format_cldr("d MMM, h:mm a");

            my $id_display = $q->id;

            my $content_display =
                ( length( $q->text ) > $max_q_length )
              ? ( substr $q->text, 0, $max_q_length ) . "..."
              : $q->text;

            push @reply_parts,
              "Message # $id_display from $sender_display, at $date_display\n$content_display";
        }

        return join "\n\n", @reply_parts;
    }
    elsif ( $command eq 'showrequest' ) {
        my $q = $schema->resultset('Request')->find( $id );

        return "Sorry, couldn't find request $id in my database!"
          unless defined $q;

        my $reply =
            "Request $id from @"
          . $q->sender->telegram_username
          . " received on "
          . DateTime->from_epoch( epoch => $q->received )
          ->format_cldr("d MMM, h:mm a") . "\n";

        $reply .= $q->text . "\n\n";

        $reply .= "To mark as resolved, send /close_" . $id;

        return $reply;
    }
    elsif ( $command eq 'close' ) {

        # mark request as resolved
        my $q = $schema->resultset('Request')->find($id);

        return "Sorry, no such request" unless defined $q;

        return try {
            $q->update( { responded => 1 } );
            return "OK, I marked request $id as resolved";
        }
        catch {
            $self->logger->error( "Failed to mark request as closed: $_" );
            return "Sorry, something went wrong trying to update the database";
        };
    }
    elsif ( $command eq 'users' ) {

        my @user_blocks;

        my $rs = $schema->resultset('User')->search({ admin => 0, banned => 0 });

        return "no non-admin, non-banned users found" unless $rs->count;

        while ( my $user = $rs->next ) {
            my $userid = $user->id;
            my $tg_display = '@' . $user->telegram_username;

            push @user_blocks, "$tg_display - /promote_$userid - /banhammer_$userid";
        }

        return "KNOWN USERS\n\n" . join("\n", @user_blocks) . "\n\nSee also: /admins, /banned";

    }
    elsif ( $command eq 'banned' ) {

        my @user_blocks;
        my $rs = $schema->resultset('User')->search({ banned => 1 });

        return "no banned users found" unless $rs->count;

        while ( my $user = $rs->next ) {
            my $userid = $user->id;
            my $tg_display = '@' . $user->telegram_username;

            push @user_blocks, "$tg_display - /unban_$userid";
        }

        return "BANNED USERS\n\n" . join "\n", @user_blocks;

    }
    elsif ( $command eq 'admins' ) {

        my @user_blocks;
        my $rs = $schema->resultset('User')->search({admin => 1 });

        return "no admin users found, but then, uh, how did you do that?" unless $rs->count;

        while ( my $user = $rs->next ) {
            my $userid = $user->id;
            my $tg_display = '@' . $user->telegram_username;

            push @user_blocks, "$tg_display - /demote_$userid";
        }

        return "CURRENT ADMINS\n\n" . join "\n", @user_blocks;

    }
    elsif ( $command eq 'promote' ) {

        my $user = $schema->resultset('User')->find( $id );
        return "no user with id $id found, sorry"
            unless defined $user;

        $user->admin(1);
        $user->update;

        my $msg = {
            chat_id => $self->target_chat_id,
            text    => "ADMIN PROMOTION!\n\n\@"
                . $user->telegram_username . " has been promoted by \@"
                . $update->from->username 
                . "\n\nCheck the /admins list to see current admins"
        };

        $self->sendMessage($msg);

        return 'OK, @' . $user->telegram_username . " is an admin, now";

    }
    elsif ( $command eq 'demote' ) {

        return "this command is not yet implemented, please get someone to manually update the database";

    }
    elsif ( $command eq 'banhammer' ) {

        my $user = $schema->resultset('User')->find( $id );
        return "no user with id $id found, sorry"
            unless defined $user;
        
        return "sorry, that user is too powerful to simple ban"
            if $user->privacy_contact or $user->admin;

        $user->banned(1);
        $user->update;

        return 'OK, @' . $user->telegram_username . " can't send me requests any more";

    }
    elsif ( $command eq 'unban' ) {

        my $user = $schema->resultset('User')->find( $id );
        return "no user with id $id found, sorry"
            unless defined $user;
        
        $user->banned(0);
        $user->update;

        return 'OK, @' . $user->telegram_username . " is now unbanned";

    }
    elsif ( $command eq 'liveherenow' ) {

        return "Sorry, that only works in groups"
            if $update->chat->type eq 'private';

        if ( $self->target_chat_id ) {
            $self->sendMessage({
                chat_id => $self->target_chat_id,
                text => 'User @' . $sender->telegram_username . " has told me to communicate in a different chat, now"
            });
        }

        my $reply;
        try {

            my $config = Config::JSON->new( 'config.json' );
            $config->set( target_chat_id => $update->chat->id );

            $self->target_chat_id( $update->chat->id );

            $reply = "OK, I will communicate here, from now on!";

        } catch {

            $reply = "I couldn't update my config file, sorry";

        };

        return $reply;

    }
    else {
        return "Sorry, I didn't catch that, do you need /help?";

    }
}

=head1 SEE ALSO

L<Telegram::Bot>

=head1 AUTHOR

=over

=item James Green <jkg@earth.li>

=cut

1;
