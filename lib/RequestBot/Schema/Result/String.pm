use utf8;
package RequestBot::Schema::Result::String;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

RequestBot::Schema::Result::String

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<string>

=cut

__PACKAGE__->table("string");

=head1 ACCESSORS

=head2 identifier

  data_type: 'text'
  is_nullable: 0

=head2 string_en

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "identifier",
  { data_type => "text", is_nullable => 0 },
  "string_en",
  { data_type => "text", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</identifier>

=back

=cut

__PACKAGE__->set_primary_key("identifier");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2023-05-30 14:38:43
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:wx1yask+6vT2hFHve/Q75w


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
