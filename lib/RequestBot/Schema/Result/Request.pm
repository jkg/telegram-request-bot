use utf8;
package RequestBot::Schema::Result::Request;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

RequestBot::Schema::Result::Request

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<request>

=cut

__PACKAGE__->table("request");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 sender

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

=head2 text

  data_type: 'text'
  is_nullable: 1

=head2 received

  data_type: 'integer'
  is_nullable: 0

=head2 responded

  data_type: 'integer'
  default_value: 0
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "sender",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
  "text",
  { data_type => "text", is_nullable => 1 },
  "received",
  { data_type => "integer", is_nullable => 0 },
  "responded",
  { data_type => "integer", default_value => 0, is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 sender

Type: belongs_to

Related object: L<RequestBot::Schema::Result::User>

=cut

__PACKAGE__->belongs_to(
  "sender",
  "RequestBot::Schema::Result::User",
  { id => "sender" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2023-05-30 14:38:43
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:WQhAa4a1fL7o1TfniboH7Q


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
