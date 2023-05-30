use utf8;
package RequestBot::Schema::Result::User;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

RequestBot::Schema::Result::User

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<user>

=cut

__PACKAGE__->table("user");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 telegram_id

  data_type: 'text'
  is_nullable: 1

=head2 telegram_username

  data_type: 'text'
  is_nullable: 1

=head2 banned

  data_type: 'integer'
  default_value: 0
  is_nullable: 1

=head2 admin

  data_type: 'integer'
  default_value: 0
  is_nullable: 1

=head2 privacy_contact

  data_type: 'integer'
  default_value: 0
  is_nullable: 1

=head2 seen_intro

  data_type: 'integer'
  default_value: 0
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "telegram_id",
  { data_type => "text", is_nullable => 1 },
  "telegram_username",
  { data_type => "text", is_nullable => 1 },
  "banned",
  { data_type => "integer", default_value => 0, is_nullable => 1 },
  "admin",
  { data_type => "integer", default_value => 0, is_nullable => 1 },
  "privacy_contact",
  { data_type => "integer", default_value => 0, is_nullable => 1 },
  "seen_intro",
  { data_type => "integer", default_value => 0, is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 requests

Type: has_many

Related object: L<RequestBot::Schema::Result::Request>

=cut

__PACKAGE__->has_many(
  "requests",
  "RequestBot::Schema::Result::Request",
  { "foreign.sender" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2023-05-30 14:38:43
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:yFNnsUB8Hhc4uHafjh3dXg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
