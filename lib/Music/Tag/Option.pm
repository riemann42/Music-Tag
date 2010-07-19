package Music::Tag::Option;
our $VERSION = 0.27;

# Copyright (c) 2006 Edward Allen III. Some rights reserved.
#
## This program is free software; you can redistribute it and/or
## modify it under the terms of the Artistic License, distributed
## with Perl.

=pod

=head1 NAME

Music::Tag::Option - Plugin module for Music::Tag to set tags via tag optons 

=head1 SYNOPSIS

	use Music::Tag

	my $filename = "/var/lib/music/artist/album/track.flac";

	my $info = Music::Tag->new($filename, { quiet => 1 }, "ogg");

	$info->add_plugin(option, { artist => "Sarah Slean" });

	$info->get_info();
	   
	print "Artist is ", $info->artist;

	#Outputs "Artist is Sarah Slean"

=head1 DESCRIPTION

Music::Tag::Option is a plugin to set tags via the plugin option mechanisim.

=head1 REQUIRED VALUES

None.

=head1 SET VALUES

=over 4

=item Any value you would like can be set this way.

=cut

use strict;
our @ISA = qw(Music::Tag::Generic);

sub set_tag {
    my $self = shift;
    my $okmethods = { map { lc($_) => 1 } @{ $self->info->datamethods } };
    while ( my ( $k, $v ) = each %{ $self->options } ) {
        if ( ( defined $v ) and ( $okmethods->{ lc($k) } ) ) {
            my $method = uc($k);
            $self->info->$method($v);
            $self->tagchange($method);
        }
    }
}

sub get_tag { set_tag(@_); }

=back

=head1 OPTIONS

Any tag accepted by L<Music::Tag>.

=head1 METHODS

=over

=item default_options

Returns the default options for the plugin.  

=item set_tag

Sets the info in the Music::Tag file to info from options.

=item get_tag

Same as set_tag.

=back

=head1 BUGS

No known additional bugs provided by this Module.

=head1 SEE ALSO

L<Music::Tag>, L<Music::Tag::Amazon>, L<Music::Tag::File>, L<Music::Tag::FLAC>, L<Music::Tag::Lyrics>,
L<Music::Tag::M4A>, L<Music::Tag::MP3>, L<Music::Tag::MusicBrainz>, L<Music::Tag::OGG>

=head1 AUTHOR 

Edward Allen III <ealleniii _at_ cpan _dot_ org>

=head1 LICENSE

This program is free software; you can redistribute it and/or
modify it under the terms of the Artistic License, distributed
with Perl.

=head1 COPYRIGHT

Copyright (c) 2007 Edward Allen III. Some rights reserved.




=cut

1;
