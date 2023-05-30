package RequestBot;

use Mojo::Base 'RequestBot::SafeBrain';
use DateTime;
use URI::Encode qw|uri_encode|;

use Log::Dispatch;

use QABot::Schema;
use Try::Tiny;

=head1 NAME

RequestBot - a simple "ticketing" bot, for Telegram

=head1 DESCRIPTION

This is a Telegram bot that collects user questions/requests and forwards
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
    } else {
        return; # can this even be reached in the real world? happy to silently fail if no sender...
    }

    my $text = $update->text;
    my $reply;

    # first, the sanity checks
    if ( defined $update->forward_from ) {
        $reply = "Please don't forward messages to me, ask me yourself!";

    }
    elsif ( not defined $text ) {
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
    }

    elsif ( $text =~ m|^/privacy| ) {
        $reply =
            $self->schema->resultset('String')->find('privacy')->string_en;
        $reply .= '\n\nIf necessary, you can contact @' . 
            $self->schema->resultset('User')
                ->search_rs({privacy_contact => 1})
                ->first->tg_username
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

    # finally, looks like an actual user question! so let's process it
    else {
        $reply = $self->_forward_and_reply($update, $sender);
    }

    if ($reply) {
        $update->reply($reply);
    }

    $sender->update;

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

        if ( defined my $str = $schema->resultset('String')->find('banned_user') ) {
            return $str->string_en;
        }
        return "Gerrout, yer bard!";

    }

    my $response_type =
      $sender->seen_intro ? 'receipt_general' : 'receipt_first';

    my $msg = {
        chat_id => $self->target_chat_id,
        text    => 'Message from @'
          . $update->from->username . "\n\n"
          . $update->text,
    };

    try {
        $schema->resultset('Question')->create(
            {   sender   => $sender->id,
                text     => $update->text,
                received => DateTime->now->epoch,
            }
        );

        $self->sendMessage($msg);
        $reply
          .= $schema->resultset('String')->find($response_type)->string_en;

        $sender->seen_intro(1);
    }
    catch {
        $self->logger->error( "Crashed during forward-and-reply: $_" );
        $reply = "Something crazy happened, sorry";
    };

    return $reply;
}

=head2 _admin_command

Handles all admin commands, including database storage as well as the response
to the user. Arguments are

* C<$update> the L<Telegram::Bot::Message> object we have received
* C<$sender>, a L<QABot::Schema::Result::User> associated with the message
* C<$command> the command we're running
* C<$id> an optional ID for the command to operate on

Returns text for the bot to send back to the user.

=cut

sub _admin_command {
    my ($self, $update, $sender, $command, $id) = @_;
    my $schema = $self->schema;

    return
      "Sorry, did you need some /help? Many of my features are only for my special minions, because they give me chips."
      unless ( defined $sender and $sender->administrator );

    if ( $command eq 'unanswered' ) {

        # show unanswered questions

        my @questions = $schema->resultset('Question')->search(
            { responded => 0 },
            {   prefetch => 'sender',
                order_by => [qw| sender received |],
            },

            # if we order by sender first, we will get related questions
            # together, in theory...
            # older sender IDs are likely to have asked their questions
            # earlier so it doesn't break the "obvious" ordering too much.
        );

        return
          "Looks like everything's been answered, good work team! Let's go get some chips... well, you get some, I'll steal yours?"
          unless @questions;

        my $max_q_length = int( 1000 / scalar @questions );

        # truncate the messages to keep the message length sane

        my @reply_parts = ("Here are the unanswered questions:");

        for my $q (@questions) {
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
    elsif ( $command eq 'showquestion' ) {
        my $q = $schema->resultset('Question')->find( $id );

        return "Sorry, couldn't find question $id in my database!"
          unless defined $q;

        my $reply =
            "Question $id from @"
          . $q->sender->telegram_username
          . " received on "
          . DateTime->from_epoch( epoch => $q->received )
          ->format_cldr("d MMM, h:mm a") . "\n";

        $reply .= $q->text . "\n\n";

        $reply .= "To mark as resolved, send /answer_" . $id;

        return $reply;
    }
    elsif ( $command eq 'answer' ) {

        # mark question as resolved
        my $q = $schema->resultset('Question')->find($id);

        return "Sorry, no such question" unless defined $q;

        return try {
            $q->update( { responded => 1 } );
            return "OK, I marked question $id as resolved";
        }
        catch {
            $self->logger->error( "Failed to mark question as answered: $_" );
            return "Sorry, something went wrong trying to update the database";
        };
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

=item Julien Fiegehenn <simbabque@cpan.org>

=cut

1;
