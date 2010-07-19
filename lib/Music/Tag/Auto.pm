package Music::Tag::Auto;
our $VERSION = 0.01;

# Copyright (c) 2006 Edward Allen III. Some rights reserved.
#
## This program is free software; you can redistribute it and/or
## modify it under the terms of the Artistic License, distributed
## with Perl.

=pod

=head1 NAME

Music::Tag::Auto - Plugin module for Music::Tag to load other plugins by file extension.

=head1 SYNOPSIS

	use Music::Tag

	my $filename = "/var/lib/music/artist/album/track.flac";

	my $info = Music::Tag->new($filename, { quiet => 1 }, "Auto");

	$info->get_info();
	print "Artist is ", $info->artist;


=head1 DESCRIPTION

Music::Tag::Auto is loaded automatically in Music::Tag .3 and newer to load other plugins.

=head1 REQUIRED VALUES

None.

=head1 SET VALUES

None.

=cut

use strict;
use warnings;
our @ISA = qw(Music::Tag::Generic);

sub default_options {
	{
		autoplugin => {
			mp3	=> "MP3",
			m4a => "M4A",
			m4p => "M4A",
			mp4 => "M4A",
			m4b => "M4A",
			'3gp' => "M4A",
			ogg => "OGG",
			flac => "FLAC"
		}
	}
}

sub new {
    my $class   = shift;
    my $parent  = shift;
    my $options = shift || {};
    my $self    = {};
    bless $self, $class;
    $self->info($parent);
    $self->options($options);
    my $plugin   = "";

    if ( $self->info->filename =~ /\.([^\.]*)$/ ) {
		if (exists $self->options->{autoplugin}->{lc($1)}) {
		   $plugin = $self->options->{autoplugin}->{lc($1)}; 
		}
    }
	if (($plugin) && ($self->info->available_plugins($plugin))) {
		unless ( $plugin =~ /::/ ) {
			$plugin = "Music::Tag::" . $plugin;
		}
		$self->status(1, "Auto loading plugin: $plugin");
		if($self->info->_has_module($plugin)) {
			return $plugin->new( $self->info, $self->options );
		}
    }
    else {
        $self->error("Sorry, I can't find a plugin for ", $self->info->filename);
        return undef;
    }
}

=head1 OPTIONS

=over 4

=item B<autoplugin>

Option is a hash reference.  Reference maps file extensions to plugins. Default is: 

    {   mp3	  => "MP3",
        m4a   => "M4A",
        m4p   => "M4A",
        mp4   => "M4A",
        m4b   => "M4A",
        '3gp' => "M4A",
        ogg   => "OGG",
        flac  => "FLAC"   }

=back

=head1 METHODS

=over

=item new($parent, $options)

Returns a Music::Tag object based on file extension, if available.  Otherwise returns undef. 

=item default_options

Returns the default options for the plugin.  

=item set_tag

Not defined for this plugin.

=item get_tag

Not defined for this plugin.

=back

=head1 BUGS

No known additional bugs provided by this Module.

=head1 SEE ALSO

L<Music::Tag>, L<Music::Tag::FLAC>, L<Music::Tag::Lyrics>, L<Music::Tag::M4A>, L<Music::Tag::MP3>, L<Music::Tag::OGG>

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
