package Music::Tag;
our $VERSION = 0.30;

# Copyright (c) 2007,2008 Edward Allen III. Some rights reserved.
#
## This program is free software; you can redistribute it and/or
## modify it under the terms of the Artistic License, distributed
## with Perl.
#

=pod

=head1 NAME

Music::Tag - Module for collecting information about music files.

=head1 SYNOPSIS

    use Music::Tag;

    my $info = Music::Tag->new($filename);
   
    # Read basic info

    $info->get_tag();
   
    print "Performer is ", $info->artist();
    print "Album is ", $info->album();
    print "Release Date is ", $info->releasedate();

    # Change info
   
    $info->artist('Throwing Muses');
    $info->album('University');
   
    # Augment info from online database!
   
    $info->add_plugin("MusicBrainz");
    $info->add_plugin("Amazon");

    $info->get_tag;

    print "Record Label is ", $info->label();

    # Save back to file

    $info->set_tag();
    $info->close();

=head1 AUTHOR

Edward Allen, ealleniii _at_ cpan _dot_ org

=head1 DESCRIPTION

The motiviation behind this was to provide a convenient method for fixing broken tags.

This module is a wrapper module, which calls various plugin modules to find information about a music file and write it back into the tag. 

=cut

use strict qw(vars);
use Carp;
use Locale::Country;
use File::Spec;
use Encode;
use Config::Options;
use Digest::SHA1;

#use CPAN;
use utf8;

use vars qw($AUTOLOAD %DataMethods);

=pod

=head1 METHODS

=over 4

=item B<new()>

my $info = Music::Tag->new($filename, [ $options ], [ "PLUGIN" ] ) ;

Takes a filename, a hashref of options, and an optonal first plugin and returns a new Music::Tag object. 

If no plugin is listed, then it will automatically add the appropriate file plugin based
on the extension. If it can't do that, it will return undef. If you are the kind of person who
uses ID3v2 and ID3v1 tags for everything, then use "MP3" as an option here to prevent it from
trying to use iTunes tags for you .m4a files.
 
Options are global (apply to all plugins) and default (can be overridden by a plugin).

Plugin specific options can be applied here, if you wish. They will be ignored by
plugins that don't know what to do with them. See the POD for each plugins for more
details on options a particular plugin accepts.

Current global options include:

=over 4

=item B<verbose>

Default is false. Setting this to true causes plugin to generate a lot of noise.

=item B<quiet>

Default is false. Setting this to true causes prevents the plugin from giving status messages.

=item B<autoplugin>

Option is a hash reference maping file extensions to plugins. Technically, this option is for
the "Music::Tag::Auto" plugin. Default is: 

    {   mp3	  => "MP3",
        m4a   => "M4A",
        m4p   => "M4A",
        mp4   => "M4A",
        m4b   => "M4A",
        '3gp' => "M4A",
        ogg   => "OGG",
        flac  => "FLAC"   }

=item B<optionfile>

Array reference of files to load options from.

=item B<ANSIColor>

Set to true to enable _color status messages.

=item B<LevenshteinXS>

Set to true to use Text::LevenshteinXS to allow approximate matching with Amazon and MusicBrainz Plugins.

=item B<Levenshtein>

Same as LevenshteinXS, but with Text::Levenshtein.

=item B<TimeLocal>

Attempt to use Time::Local to support unix release date tags.

=item B<Unaccent>

Set to true to allow accent-neutral matching with Text::Unaccent.

=item B<Inflect>

When true, uses Linque::EN::Inflect to perform approximate matches. Default false. Will reset to
false if module is missing.

=item B<Stem>

When true, uses Linqua::Stem to perform approximate matches. Default false. Will reset to
false if module is missing.

=item B<TimeLocal>

When true, uses Time::Local to perform date calculations.  Defaults true.  Will reset to
false if module is missing.

=back

=cut

BEGIN {
    $Music::Tag::DefaultOptions =
      Config::Options->new(
                          { verbose       => 0,
                            quiet         => 0,
                            ANSIColor     => 0,
                            LevenshteinXS => 1,
                            Levenshtein   => 1,
                            TimeLocal     => 1,
                            Unaccent      => 1,
                            Inflect       => 0,
                            Stem          => 0,
                            StemLocale    => "en-us",
                            optionfile => [ "/etc/musictag.conf", $ENV{HOME} . "/.musictag.conf" ],
                          }
      );
    my @datamethods =
      qw(albkey album album_type albumartist albumartist_sortname albumid appleid artist artist_end artist_start artist_type artistid artkey asin bitrate booklet bytes codec comment compilation composer copyright country countrycode disc discnum disctitle duration encoded_by encoder filename frames framesize frequency gaplessdata genre ipod ipod_dbid ipod_location ipod_trackid label lastplayed lyrics mb_albumid mb_artistid mb_trackid mip_puid mtime originalartist path picture playcount postgap pregap rating recorddate recordtime releasedate releasetime samplecount secs songid songkey sortname stereo tempo title totaldiscs totaltracks track tracknum url user vbr year);
    %Music::Tag::DataMethods = map { $_ => 1 } @datamethods;
	%Music::Tag::AUTOPLUGINS = ();
    @Music::Tag::PLUGINS = ();
    my $myname = __PACKAGE__;
    my $me     = $myname;
    $me =~ s/\:\:/\//g;
    foreach my $d (@INC) {
        chomp $d;
        if ( -d "$d/$me/" ) {
            local (*F_DIR);
            opendir( *F_DIR, "$d/$me/" );
            while ( my $b = readdir(*F_DIR) ) {
                next unless $b =~ /^(.*)\.pm$/;
				my $mod = $1;
                push @Music::Tag::PLUGINS, $mod;
            }
        }
    }
}

=item B<available_plugins()>

Returns list of available plugins.

=cut

sub available_plugins {
	my $self = shift;
	my $check = shift;
	if ($check) {
		foreach (@Music::Tag::PLUGINS) {
			if ($check eq $_) {
				return 1;
			}
		}
		return 0;
	}
	return @Music::Tag::PLUGINS;
}
		
sub default_options {
    my $self = shift;
    return $Music::Tag::DefaultOptions;
}

=item B<LoadOptions()>

Load options stated in optionfile from file.  Default locations are /etc/musictag.conf and ~/.musictag.conf.
Can be called as class method or object method.

=cut

sub LoadOptions {
    my $self    = shift;
    my $optfile = shift;
    if ( ref $self ) {
        return $self->options->fromfile_perl($optfile);
    }
    elsif ($self) {
        return $Music::Tag::DefaultOptions->fromfile_perl($optfile);
    }
}

sub new {
    my $class    = shift;
    my $filename = shift;
    my $options  = shift || {};
    my $plugin   = shift || "Auto";
    my $data     = shift || {};
    my $self     = {};
    $self->{data} = $data;
    if ( ref $class ) {
        my $clone = {%$class};
        bless $clone, ref $class;
        return $clone;
    }
    else {
        bless $self, $class;
        $self->{_plugins} = [];
        $self->options($options);
        $self->filename($filename);
    }

    if ( ( $self->options->{ANSIColor} ) && ( $self->_has_module("Term::ANSIColor") ) ) {
        $self->options->{ANSIColor} = 1;
    }
    else {
        $self->options->{ANSIColor} = 0;
    }

    if ( ( $self->options->{LevenshteinXS} ) && ( $self->_has_module("Text::LevenshteinXS") ) ) {
        $self->options->{LevenshteinXS} = 1;
    }
    elsif ( ( $self->options->{Levenshtein} ) && ( $self->_has_module("Levenshtein") ) ) {
        $self->options->{Levenshtein} = 1;
    }
    else {
        $self->options->{LevenshteinXS} = 0;
        $self->options->{Levenshtein}   = 0;
    }
    if ( ( $self->options->{Unaccent} ) && ( not $self->_has_module("Text::Unaccent") ) ) {
        $self->options->{Unaccent} = 0;
    }
    if ( ( $self->options->{Inflect} ) && (  not $self->_has_module("Lingua::EN::Inflect") ) ) {
        $self->options->{Inflect} = 0;
    }
    if ( ( $self->options->{Stem} ) && (  not $self->_has_module("Lingua::Stem") ) ) {
        $self->options->{Stem} = 0;
    }
    if ( ( $self->options->{TimeLocal} ) && (  not $self->_has_module("Time::Local") ) ) {
        $self->options->{TimeLocal} = 0;
    }

    if ($plugin) {
        $self->add_plugin( $plugin, $options );
        return $self;
    }
    #else {
    #    return $self->auto_plugin($options);
    #}
}

sub _has_module {
    my $self   = shift;
    my $module = shift;

    #if (CPAN->has_inst($module)) {
    my $modfile = $module . ".pm";
    $modfile =~ s/\:\:/\//g;
    eval {require $modfile };
    if ($@) {
        $self->error("Not loading $module: ". $@);
        return 0;
    }
    else {
        return 1;
    }
}

=pod

=item B<add_plugin()>

my $plugin = $info->add_plugin("PLUGIN", $options)

Takes a plugin name and optional set of options and it to a the Music::Tag object. Returns reference to a new plugin object.

$options is a hashref that can be used to override the global options for a plugin.

Current plugins include L<MP3|Music::Tag::MP3>, L<OGG|Music::Tag::OGG>, L<FLAC|Music::Tag::FLAC>, L<M4A|Music::Tag::M4A>, L<Amazon|Music::Tag::Amazon>, L<File|Music::Tag::File>, and L<MusicBrainz|Music::Tag::MusicBrainz>. Additional plugins can be created. See <L:Plugin Syntax> for information.

First option can be an string such as "MP3" in which case Music::Tag::MP3->new($self, $options) is called,an object name such as "Music::Tag::Custom::MyPlugin" in which case Music::Tag::MP3->new($self, $options) is called. It can also be an object.

Options can also be included in the string, as in Amazon;locale=us;trust_title=1.

=cut

sub add_plugin {
    my $self    = shift;
    my $object  = shift;
    my $opts    = shift || {};
    my $options = $self->options->clone;
    $options->merge($opts);
    my $type = shift || 0;

    my $ref;
    if ( ref $object ) {
        $ref = $object;
        $ref->info($self);
        $ref->options($options);
    }
    else {
        my ( $plugin, $popts ) = split( ":", $object );
		if ($self->available_plugins($plugin)) {
			if ($popts) {
				my @opts = split( /[;]/, $popts );
				foreach (@opts) {
					my ( $k, $v ) = split( "=", $_ );
					$options->options( $k, $v );
				}
			}
			eval {
				unless ( $plugin =~ /::/ ) {
					$plugin = "Music::Tag::" . $plugin;
				}
				if($self->_has_module($plugin)) {
					$ref = $plugin->new( $self, $options );
				}
			};
			croak "Error loading plugin ${plugin}: $@" if $@;
		}
		else {
			croak "Error loading plugin ${plugin}: Not Found";
		}
    }
    if ($ref) {
        push @{ $self->{_plugins} }, $ref;
    }
    return $ref;
}

=pod

=item B<plugin()>

my $plugin = $item->plugin("MP3")->strip_tag();

The plugin method takes a regular expression as a string value and returns the first plugin whose package name matches the regular expression. Used to access package methods directly. Please see <L/PLUGINS> section for more details on standard plugin methods.

=cut

sub plugin {
    my $self   = shift;
    my $plugin = shift;
    if ( defined $plugin ) {
        foreach ( @{ $self->{_plugins} } ) {
            if ( ref($_) =~ /$plugin$/ ) {
                return $_;
            }
        }
    }
    else {
        return $self->{_plugins};
    }
}

=pod

=item B<get_tag()>

$info->get_tag();

get_tag applies all active plugins to the current tag object in the order that the plugin was added. Specifically, it runs through the list of plugins and performs the get_tag() method on each. 

=cut

sub get_tag {
    my $self = shift;
    foreach ( @{ $self->{_plugins} } ) {
        if ( ref $_ ) {
            $_->get_tag();
        }
        else {
            $self->error("Invalid Plugin in list: $_");
        }
    }
    return $self;
}

=pod

=item B<set_tag()>

$info->set_tag();

set_tag writes info back to disk for all tags, or submits info if appropriate. Specifically, it runs through the list of plugins and performs the set_tag() method on each.

=cut

sub set_tag {
    my $self = shift;
    foreach ( @{ $self->{_plugins} } ) {
        if ( ref $_ ) {
            $_->set_tag();
        }
        else {
            $self->error("Invalid Plugin in list!");
        }
    }
    return $self;
}

=pod

=item B<strip_tag()>

$info->strip_tag();

strip_tag removes info from on disc tag for all plugins. Specifically, it performs the strip_tag methd on all plugins in the order added.

=cut

sub strip_tag {
    my $self = shift;
    foreach ( @{ $self->{_plugins} } ) {
        if ( ref $_ ) {
            $_->strip_tag();
        }
        else {
            $self->error("Invalid Plugin in list!");
        }
    }
    return $self;
}

=pod

=item B<close()>

$info->close();

closes active filehandles on all plugins. Should be called before object destroyed or frozen.

=cut

sub close {
    my $self = shift;
    foreach ( @{ $self->{_plugins} } ) {
        if ( ref $_ ) {
            $_->close(@_);
            $_->{info} = undef;
            $_ = undef;
        }
        else {
            $self->error("Invalid Plugin in list!");
        }
    }
    $self = undef;
}

=pod

=item B<changed()>

$ischanged = $info->changed($new);

Returns true if changed. Optional value $new sets changed set to True of $new is true. A "change" is any tag additions done by MusicBrainz, Amazon, or File plugins.

=cut

sub changed {
    my $self = shift;
    my $new  = shift;
    if ( defined $new ) {
        $self->{changed}++;
    }
    return $self->{changed};
}

=item B<data()>

Returns a reference to the hash which stores all data about a track and optionally sets it.  This is useful if you
want to freeze and recreate a track, or use a shared data object in a threaded environment.

=cut

sub data {
    my $self = shift;
    my $new  = shift;
    if ( defined $new ) {
        $self->{data} = $new;
    }
    return $self->{data};
}

=pod

=item B<options()>

my $verbose = $info->options("verbose");
my $verbose = $info->options->{verbose};
$info->options("verbose", 0);
$info->options->{verbose} = 0;

This method is used to access or change the options. When called with no options, returns a reference to the options hash. When called with one string option returns the value for that key. When called with one hash value, merges hash with current options. When called with 2 options, the first is a key and the second is a value and the ket gets set to the value. This method is for global options.

=cut

sub options {
    my $self = shift;
    unless ( exists $self->{_options} ) {
        $self->{_options} = Config::Options->new( $self->default_options );
    }
    return $self->{_options}->options(@_);
}

=item B<setfileinfo>

Sets the myime and bytes attributes for you from filename.

=cut

sub setfileinfo {
    my $self = shift;
    if ( $self->filename ) {
        my @stat = stat $self->filename;
        $self->mtime( $stat[9] );
        $self->bytes( $stat[7] );
    }
}

=item B<sha1()>

Returns a sha1 digest of the first 16K of the music file.  

=cut

sub sha1 {
    my $self = shift;
    return unless ( ( $self->filename ) && ( -e $self->filename ) );
    my $maxsize = 4 * 4096;
    open( IN, $self->filename ) or die "Bad file: $self->filename\n";
    my @stat = stat $self->filename;
    my $sha1 = Digest::SHA1->new();
    $sha1->add( pack( "V", $stat[7] ) );
    my $d;

    if ( read( IN, $d, $maxsize ) ) {
        $sha1->add($d);
    }
    CORE::close(IN);
    return $sha1->hexdigest;
}

=pod

=item B<datamethods()>

Returns an array reference of all data methods supported.  Optionally takes a method which is added.  Data methods should be all lower case and not conflict with existing methods. Datamethod additions are global, and not tied to an object. Array reference should be considered read only.  

=cut

sub datamethods {
    my $self = shift;
    my $new  = shift;
    if ($new) {

        #TODO Add sanity check here to prevent overwriting default methods.
        $DataMethods{$new} = 1;
    }
    return [ keys %DataMethods ];
}

=pod

=back

=head2 Data Access Methods

These methods are used to access the tag info. Not all methods are supported by all plugins. In fact, no single plugin supports all methods (yet). Each of these is an accessort function. If you pass it a value, it will set the variable. It always returns the value of the variable. It can return undef.

=cut

# This method is far from perfect.  It can't be perfect.
# It won't mangle valid UTF-8, however.
# Just be sure to always return perl utf8 in plugins when possible.

sub _isutf8 {
    my $self = shift;
    my $in   = shift;

    # If it is a proper utf8, with tag, just return it.
    if ( Encode::is_utf8( $in, 1 ) ) {
        return $in;
    }

    my $has7f = 0;
    foreach ( split( //, $in ) ) {
        if ( ord($_) >= 0x7f ) {
            $has7f++;
        }
    }

    # No char >7F it is prob. valid ASCII, just return it.
    unless ($has7f) {
        return $in;
    }

    # See if it is a valid UTF-16 encoding.
    #my $out;
    #eval {
    #	$out = decode("UTF-16", $in, 1);
    #};
    #return $out unless $@;

    # See if it is a valid UTF-16LE encoding.
    #my $out;
    #eval {
    #	$out = decode("UTF-16LE", $in, 1);
    #};
    #return $out unless $@;

    # See if it is a valid UTF-8 encoding.
    my $out;
    eval { $out = decode( "UTF-8", $in, 1 ); };
    return $out unless $@;

    # Finally just give up and return it.

    return $in;
}

sub _accessor {
    my $self    = shift;
    my $attr    = shift;
    my $value   = shift;
    my $default = shift;
    unless ( exists $self->{data}->{ uc($attr) } ) {
        $self->{data}->{ uc($attr) } = undef;
    }
    if ( defined $value ) {
        $value = $self->_isutf8($value);
        if ( $self->options('verbose') ) {
            $self->status( "VERBOSE:  Setting $attr to ",
                           ( defined $value ) ? $value : "UNDEFINED" );
        }
        $self->{data}->{ uc($attr) } = $value;
    }
    if ( ( defined $default ) && ( not defined $self->{data}->{ uc($attr) } ) ) {
        $self->{data}->{ uc($attr) } = $default;
    }
    return $self->{data}->{ uc($attr) };
}

sub _timeaccessor {
    my $self    = shift;
    my $attr    = shift;
    my $value   = shift;
    my $default = shift;

    if ( defined $value ) {
        if ( $value =~
             /^(\d\d\d\d)[ \-]?(\d\d)?[ \-]?(\d\d)?[ \-]?(\d\d)?[ \-:]?(\d\d)?[ \-:]?(\d\d)?/ ) {
            $value = sprintf( "%04d-%02d-%02d %02d:%02d:%02d",
                              $1, $2 || 1, $3 || 1, $4 || 12, $5 || 0, $6 || 0 );
            if (    ( $1 == 0 )
                 || ( $1 eq "0000" )
                 || ( ( $1 == 1900 ) && ( $2 == 0 ) && ( $3 == 0 ) )
                 || ( ( $1 == 1900 ) && ( $2 == 1 ) && ( $3 == 1 ) ) ) {
                $self->status("Invalid date set for ${attr}: ${value}");
                $value = undef;
            }
        }
        else {
            $self->status("Invalid date set for ${attr}: ${value}");
            $value = undef;
        }
    }
    $self->_accessor( $attr, $value, $default );
}

sub _epochaccessor {
    my $self  = shift;
    my $attr  = shift;
    my $value = shift;
    my $set   = undef;
    return undef unless ( $self->options('TimeLocal') );
    if ( defined($value) ) {
        my @tm = gmtime($value);
        $set = sprintf( "%04d-%02d-%02d %02d:%02d:%02d",
                        $tm[5] + 1900,
                        $tm[4] + 1,
                        $tm[3], $tm[2], $tm[1], $tm[0] );
    }
    my $v = $self->_timeaccessor( $attr, $set );
    my $ret = undef;
    if ( ( defined $v )
        && (
            $v =~ /^(\d\d\d\d)[ \-]?(\d\d)?[ \-]?(\d\d)?[ \-]?(\d\d)?[ \-:]?(\d\d)?[ \-:]?(\d\d)?/ )
      ) {
        eval { $ret = Time::Local::gmtime( $6 || 0, $5 || 0, $4 || 12, $3 || 1, $2 || 0, $1 ); };
        $self->error($@) if $@;
    }
    return $ret;
}

sub _dateaccessor {
    my $self  = shift;
    my $attr  = shift;
    my $value = shift;
    my $set   = undef;
    return undef unless ( $self->options('TimeLocal') );
    if ( defined($value) ) {
        $set = $value;
    }
    my $v = $self->_timeaccessor( $attr, $set );
    my $ret = undef;
    if ( ( defined $v )
        && (
            $v =~ /^(\d\d\d\d)[ \-]?(\d\d)?[ \-]?(\d\d)?[ \-]?(\d\d)?[ \-:]?(\d\d)?[ \-:]?(\d\d)?/ )
      ) {
        return sprintf( "%04d-%02d-%02d", $1, $2, $3 );
    }
    else {
        return undef;
    }
}

sub _ordinalaccessor {
    my $self  = shift;
    my $attr  = shift;
    my $pos   = shift;
    my $total = shift;
    my $new   = shift;

    if ( defined($new) ) {
        my ( $t, $tt ) = split( "/", $new );
        my $r = "";
        if ($t) {
            $self->_accessor( $pos, $t );
            $r .= $t;
        }
        if ($tt) {
            $self->_accessor( $total, $t );
            $r .= "/" . $tt;
        }
    }
    my $ret = $self->_accessor($pos);
    if ( $self->_accessor($total) ) {
        $ret .= "/" . $self->_accessor($total);
    }
    return $ret;
}

=pod

=over 4

=item B<album>

The title of the release.

=item B<album_type>

The type of the release. Specifically, the MusicBrainz type (ALBUM OFFICIAL, etc.) 

=item B<albumartist>

The artist responsible for the album. Usually the same as the artist, and will return the value of artist if unset.

=cut

sub albumartist {
    my $self = shift;
    my $new  = shift;
    return $self->_accessor( "albumartist", $new, $self->artist() );
}

=item B<albumartist_sortname>

The name of the sort-name of the albumartist (e.g. Hersh, Kristin or Throwing Muses, The)

=cut

sub albumartist_sortname {
    my $self = shift;
    my $new  = shift;
    return $self->_accessor( "albumartist_sortname", $new, $self->sortname() );
}

=pod

=item B<artist>

The artist responsible for the track.

=item B<artist_type>

The type of artist. Usually Group or Person.

=item B<asin>

The Amazon ASIN number for this album.

=item B<bitrate>

Enconding bitrate.

=item B<booklet>

URL to a digital booklet. Usually in PDF format. iTunes passes these out sometimes, or you could scan a booklet
and use this to store value. URL is assumed to be realtive to file location.

=item B<comment>

A comment about the track.

=item B<compilation>

True if album is Various Artist, false otherwise.  Don't set to true for Best Hits.

=item B<composer>

Composer of song.

=item B<copyright>

A copyright message can be placed here.

=cut

=item B<country>

Return the country that the track was released in.

=cut


sub country {
    my $self = shift;
    my $new  = shift;
    if ( defined($new) ) {
        $self->_accessor( "COUNTRYCODE", country2code($new) );
    }
    if ( $self->countrycode ) {
        return code2country( $self->countrycode );
    }
    return undef;
}

=pod

=item B<disc>

In a multi-volume set, the disc number.

=item B<disctitle>

In a multi-volume set, the title of a disc.

=item B<discnum>

The disc number and optionally the total number of discs, seperated by a slash. Setting it sets the disc and totaldiscs values (and vice-versa).

=cut

sub discnum {
    my $self = shift;
    my $new  = shift;
    $self->_ordinalaccessor( "DISCNUM", "DISC", "TOTALDISCS", $new );
}

=pod

=item B<duration>

The length of the track in milliseconds. Returns secs * 1000 if not set. Changes the value of secs when set.

=cut

sub duration {
    my $self = shift;
    my $new  = shift;
    if ( defined($new) ) {
        $self->_accessor( "DURATION", $new );
        $self->_accessor( "SECS",     int( $new / 1000 ) );
    }
    if ( $self->_accessor("DURATION") ) {
        return $self->_accessor("DURATION");
    }
    elsif ( $self->_accessor("SECS") ) {
        return $self->_accessor("SECS") * 1000;
    }
}

=pod

=item B<encoder>

The codec used to encode the song.

=item B<filename>

The filename of the track.

=cut

sub filename {
    my $self = shift;
    my $new  = shift;
    if ( defined($new) ) {
        my $file = $new;
        if ($new) {
            $file = File::Spec->rel2abs($new);
        }
        if ( $self->options('verbose') ) {
            $self->status( "VERBOSE:  Setting filename  to ",
                           ( defined $file ) ? $file : "UNDEFINED" );
        }
        $self->_accessor( "FILENAME", $file );
    }
    return $self->_accessor("FILENAME");

}

=item B<filedir>

The path that music file is located in.

=cut

sub filedir {
    my $self = shift;
    if ( $self->filename ) {
        my ( $vol, $path, $file ) = File::Spec->splitpath( $self->filename );
        return File::Spec->catpath( $vol, $path, "" );
    }
    return undef;
}

=pod


=item B<frequency>

The frequency of the recording (in Hz).

=item B<genre>

The genre of the song. Various tags use this field differently, so it may be lost.

=item B<label>

The label responsible for distributing the recording.

=item B<lyrics>

The lyrics of the recording.

=item B<mb_albumid>

The MusicBrainz database ID of the album or release object.

=item B<mb_artistid>

The MusicBrainz database ID for the artist.

=item B<mb_trackid>

The MusicBrainz database ID for the track.

=item B<mip_puid>

The MusicIP puid for the track.

=item B<picture>

A hashref that contains the following:

     {
       "MIME type"     => The MIME Type of the picture encoding
       "Picture Type"  => What the picture is off.  Usually set to 'Cover (front)'
       "Description"   => A short description of the picture
       "_Data"         => The binary data for the picture.
       "filename"      => A filename for the picture.  Data overrides "_Data" and will
                          be returned as _Data if queried.  Filename is calculated as relative
                          to the path of the music file as stated in "filename" or root if no
                          filename for music file available.
    }


Note hashref MAY be generated each call.  Do not modify and assume tag will be modified!

=cut

sub _binslurp {
    my $file = shift;
    local *IN;
    open( IN, $file ) or croak "Couldn't open $file: $!";
    my $ret;
    my $off = 0;
    while ( my $r = read IN, $ret, 1024, $off ) { last unless $r; $off += $r }
    return $ret;
}

sub picture {
    my $self = shift;
    unless ( exists $self->{data}->{PICTURE} ) {
        $self->{data}->{PICTURE} = {};
    }
    $self->{data}->{PICTURE} = shift if @_;

    if (    ( exists $self->{data}->{PICTURE}->{filename} )
         && ( $self->{data}->{PICTURE}->{filename} ) ) {
        my $root = File::Spec->rootdir();
        if ( $self->filename ) {
            $root = $self->filedir;
        }
        my $picfile = File::Spec->rel2abs( $self->{data}->{PICTURE}->{filename}, $root );
        if ( -f $picfile ) {
            if ( $self->{data}->{PICTURE}->{_Data} ) {
                delete $self->{data}->{PICTURE}->{_Data};
            }
            my %ret = %{ $self->{data}->{PICTURE} };    # Copy ref
            $ret{_Data} = _binslurp($picfile);
            return \%ret;
        }
    }
    elsif (    ( exists $self->{data}->{PICTURE}->{_Data} )
            && ( length $self->{data}->{PICTURE}->{_Data} ) ) {
        return $self->{data}->{PICTURE};
    }
    else {
        return undef;
    }
}

=pod

=item B<picture_filename>

Returns filename used for picture data.  If no filename returns 0.  If no picture returns undef.

=cut

sub picture_filename {
    my $self = shift;
    if ( ( exists $self->{data}->{PICTURE} ) && ( $self->{data}->{PICTURE}->{filename} ) ) {
        return $self->{data}->{PICTURE}->{filename};
    }
    elsif (    ( exists $self->{data}->{PICTURE} )
            && ( $self->{data}->{PICTURE}->{_Data} )
            && ( length( $self->{data}->{PICTURE}->{_Data} ) ) ) {
        return 0;
    }
    else {
        return undef;
    }
}

=pod

=item B<picture_exists>

Returns true if tag has picture data (or filename), false if not.  Convenience method to prevant reading the file. 
Will return false of filename listed for picture does not exist.

=cut

sub picture_exists {
    my $self = shift;
    if (    ( exists $self->{data}->{PICTURE}->{filename} )
         && ( $self->{data}->{PICTURE}->{filename} ) ) {
        my $root = File::Spec->rootdir();
        if ( $self->filename ) {
            $root = $self->filedir;
        }
        my $picfile = File::Spec->rel2abs( $self->{data}->{PICTURE}->{filename}, $root );
        if ( -f $picfile ) {
            return 1;
        }
        else {
            $self->status( "Picture: ", $picfile, " does not exists" );
        }
    }
    elsif (    ( exists $self->{data}->{PICTURE}->{_Data} )
            && ( length $self->{data}->{PICTURE}->{_Data} ) ) {
        return 1;
    }
    else {
        return undef;
    }
}

=pod

=item B<rating>

The rating (value is 0 - 100) for the track.

=item B<recorddate>

The date track was recorded (not release date).  See notes in releasedate for format.

=item B<recordepoch>

The recorddate in seconds since epoch.  See notes in releaseepoch for format.

=item B<recordtime>

The time and date track was recoded.  See notes in releasetime for format.

=cut

sub recorddate {
    my $self = shift;
    $self->_dateaccessor( "RECORDTIME", @_ );
}

sub recordepoch {
    my $self = shift;
    $self->_epochaccessor( "RECORDTIME", @_ );
}

sub recordtime {
    my $self = shift;
    $self->_timeaccessor( "RECORDTIME", @_ );
}

=pod


=item B<releasedate>

The release date in the form YYYY-MM-DD.  The day or month values may be left off.  Please keep this in mind if you are parsing this data.

Because of bugs in my own code, I have added 2 sanity checks.  Will not set the time and return undef if either of the following are true:

    1) Time is set as 0000-00-00

    2) Time is set as 1900-00-00

All times should be GMT.

=cut

sub releasedate {
    my $self = shift;
    $self->_dateaccessor( "RELEASETIME", @_ );
}

=pod

=item B<releaseepoch>

The release date of an album in terms "unix time", or seconds since the SYSTEM epoch (usually Midnight, January 1, 1970 GMT). This can be negative or > 32 bits, so please use caution before assuming this value is a valid unix date.  Using this requires the L<Time::Local> module, so install it if you have not.  Returns undef if Time::Local is not installed.  This value will update releasedate and vice versa.  Since this accurate to the second and releasedate only to the day, setting releasedate will always set this to 12:00 PM GMT the same day.  Returns undef if Time::Local is not installed. 

=cut

sub releaseepoch {
    my $self = shift;
    $self->_epochaccessor( "RELEASETIME", @_ );
}

=pod

=item B<releasetime>

Like releasedate, but adds the time.  Format should be YYYY-MM-DD HH::MM::SS.  Like releasedate, all entries are year
are optional.

All times should be GMT.

=cut

sub releasetime {
    my $self = shift;
    $self->_timeaccessor( "RELEASETIME", @_ );
}

=pod

=item B<secs>

The number of seconds in the recording.

=item B<sortname>

The name of the sort-name of the artist (e.g. Hersh, Kristin or Throwing Muses, The)

=item B<tempo>

The tempo of the track

=item B<title>

The name of the song.

=item B<totaldiscs>

The total number of discs, if a multi volume set.

=item B<totaltracks>

The total number of tracks on the album.

=item B<track>

The track number

=item B<tracknum>

The track number and optionally the total number of tracks, seperated by a slash. Setting it sets the track and totaltracks values (and vice-versa).

=cut

sub tracknum {
    my $self = shift;
    my $new  = shift;
    $self->_ordinalaccessor( "TRACKNUM", "TRACK", "TOTALTRACKS", $new );
}

=pod

=item B<url>

A url associated with the track (often the buy link for Amazon).

=item B<year>

The year a track was released.  Defaults to year set in releasedate if not set.  Does not set releasedate.

=cut

sub year {
    my $self = shift;
    my $new  = shift;
    if ( defined($new) ) {
        $self->_accessor( "YEAR", $new );
    }
    if ( $self->_accessor("YEAR") ) {
        return $self->_accessor("YEAR");
    }
    elsif ( $self->releasedate ) {
        if ( $self->releasetime =~ /^(\d\d\d\d)-?/ ) {
            return $self->_accessor( "YEAR", $1 );
        }
    }
    return undef;
}

=back

=head1 Non Standard Data Access Methods

These methods are not currently used by any standard plugin.  They may be used in the future, or by other plugins (such as a SQL plugin).  Included here to standardize expanstion methods.

=over 4

=item B<albumid, artistid, songid>

These three values can be used by a database plugin. I recommend using the same value as mb_albumid, mb_artistid, and mb_trackid by default when possible.

=item B<ipod, ipod_dbid, ipod_location, ipod_trackid>

Values for an iPod plugin.  (This does not exists yet.  It may someday.  Ok it does.  I may PUBLISH it someday.).

=item B<pregap, postgap, gaplessdata, samplecount>

Used to store gapless data in.

=item B<user>

Used for user data.

=back


=cut

sub status {
    my $self = shift;
    unless ( $self->options('quiet') ) {
        my $name = ref($self);
        $name =~ s/^Music:://g;
        print $self->_tenprint( $name, 'bold white' ), @_, "\n";
    }
}

sub _tenprint {
    my $self  = shift;
    my $text  = shift;
    my $_color = shift || "bold yellow";
    my $size  = shift || 10;
    return $self->_color($_color)
      . sprintf( '%' . $size . 's: ', substr( $text, 0, $size ) )
      . $self->_color('reset');
}

sub _color {
    my $self = shift;
    if ( $self->options->{ANSIColor} ) {
        return Term::ANSIColor::_color(@_);
    }
    else {
        return "";
    }
}

sub error {
    my $self = shift;
   # unless ( $self->options('quiet') ) {
        carp(ref($self), " ", @_);
   # }
}

sub AUTOLOAD {
    my $self = shift;
    my $attr = $AUTOLOAD;
    $attr =~ s/.*:://;
    my $new = shift;
    if ( $DataMethods{ lc($attr) } ) {
        return $self->_accessor( $attr, $new );
    }
    else {
        croak "Music::Tag:  Invalid method: $attr called";
    }
}

sub DESTROY {
}

1;

package Music::Tag::Generic;
use Encode;
use strict;
use vars qw($AUTOLOAD);
use Carp;

=pod

=head1 PLUGINS

All plugins should set @ISA to include Music::Tag::Generic and contain one or more of the following methods:

=over 4

=item B<new()>

Set in template. If you override, it should take as options a reference to a Music::Tag object and an href of options. 

=cut

sub new {
    my $class   = shift;
    my $parent  = shift;
    my $options = shift || {};
    my $self    = {};
    bless $self, $class;
    $self->info($parent);
    $self->options($options);
    return $self;
}

=pod

=item B<info()>

Should return a reference to the associated Music::Tag object. If passed an object, should set the associated Music::Tag object to it.

=cut

sub info {
    my $self = shift;
    my $val  = shift;
    if ( defined $val && ref $val ) {
        $self->{info} = $val;
    }
    return $self->{info};
}

=item B<get_tag()>

Populates the data in the Music::Tag object.

=cut

sub get_tag {
}

=item B<set_tag()>

Optional method to save info back to tag.

=cut

sub set_tag {
}

=pod

=item B<strip_tag>

Optional method to remove a tag.

=cut

sub strip_tag {
}

=item B<close>

Optional method to close open file handles.

=cut

sub close {
}

=item B<tagchange>

Inhereted method that can be called to announce a tag change from what is read on file. Used by secondary plugins like Amazon, MusicBrainz, and File.

=cut

sub tagchange {
    my $self = shift;
    my $tag  = lc(shift);
    my $to   = shift || $self->info->$tag || "";
    $self->status( $self->info->_tenprint( $tag, 'bold blue', 15 ) . '"' . $to . '"' );
    $self->info->changed(1);
}

=item B<simplify>

A usfull method for simplifying artist names and titles. Takes a string, and returns a sting with no whitespace.  Also removes accents (if Text::Unaccent is available) and converts numbers like 1,2,3 as words to one, two, three.  Removes a,the

=cut

sub simplify {
    my $self = shift;
    my $text = shift;
    chomp $text;

    # Text::Unaccent wants a char set, this enforces that...
    if ( $self->options->{Unaccent} ) {
        $text = Text::Unaccent::unac_string( "UTF-8", encode( "utf8", $text, Encode::FB_DEFAULT ) );
    }

    $text = lc($text);

    $text =~ s/\[[^\]]+\]//g;
    $text =~ s/[\s_]/ /g;

    if ( $self->options->{Stem} ) {
        $text = join( " ", @{ Lingua::Stem::stem( split( /\s/, $text ) ) } );
    }

    if ( length($text) > 5 ) {
        $text =~ s/\bthe\s//g;
        $text =~ s/\ba\s//g;
        $text =~ s/\ban\s//g;
        $text =~ s/\band\s//g;
        $text =~ s/\ble\s//g;
        $text =~ s/\bles\s//g;
        $text =~ s/\bla\s//g;
        $text =~ s/\bde\s//g;
    }
    if ( $self->options->{Inflect} ) {
        $text =~ s/(\.?\d+\,?\d*\.?\d*)/Lingua::EN::Inflect::NUMWORDS($1)/eg;
    }
    else {
        $text =~ s/\b10\s/ten /g;
        $text =~ s/\b9\s/nine /g;
        $text =~ s/\b8\s/eight /g;
        $text =~ s/\b7\s/seven /g;
        $text =~ s/\b6\s/six /g;
        $text =~ s/\b5\s/five /g;
        $text =~ s/\b4\s/four /g;
        $text =~ s/\b3\s/three /g;
        $text =~ s/\b2\s/two /g;
        $text =~ s/\b1\s/one /g;
    }

    $text =~ s/\sii\b/two/g;
    $text =~ s/\siii\b/three/g;
    $text =~ s/\siv\b/four/g;
    $text =~ s/\sv\b/five/g;
    $text =~ s/\svi\b/six/g;
    $text =~ s/\svii\b/seven/g;
    $text =~ s/\sviii\b/eight/g;

    $text =~ s/[^a-z0-9]//g;
    return $text;
}

# similar_percent is a precent, so should be open set (0..1)
sub simple_compare {
    my $self            = shift;
    my $a               = shift;
    my $b               = shift;
    my $similar_percent = shift;
    my $crop_percent    = shift;

    my $sa = $self->simplify($a);
    my $sb = $self->simplify($b);
    if ( $sa eq $sb ) {
        return 1;
    }

    return unless ( $similar_percent || $crop_percent );

    my $la  = length($sa);
    my $lb  = length($sb);
    my $max = ( $la < $lb ) ? $lb : $la;
    my $min = ( $la < $lb ) ? $la : $lb;

    return unless ( $min and $max );

    my $dist = undef;
    if ( $self->options->{LevenshteinXS} ) {
        $dist = Text::LevenshteinXS::distance( $sa, $sb );
    }
    elsif ( $self->options->{Levenshtein} ) {
        $dist = Text::Levenshtein::distance( $sa, $sb );
    }
    unless ($crop_percent) {
        $crop_percent = $similar_percent * ( 2 / 3 );
    }

    if ( ( defined $dist ) && ( ( ( $min - $dist ) / $min ) >= $similar_percent ) ) {
        return -1;
    }

    if ( $min < 10 ) {
        return 0;
    }
    if ( ( ( ( 2 * $min ) - $max ) / $min ) <= $crop_percent ) {
        return 0;
    }
    if ( substr( $sa, 0, $min ) eq substr( $sb, 0, $min ) ) {
        return -1;
    }
    return 0;
}

=item B<status>

Inhereted method to print a pretty status message.

=cut

sub status {
    my $self = shift;
    unless ( $self->info->options('quiet') ) {
        my $name = ref($self);
        $name =~ s/^Music::Tag:://g;
        print $self->info->_tenprint( $name, 'bold white', 12 ), @_, "\n";
    }
}

=item B<error>

Inhereted method to print an error message.

=cut

sub error {
    my $self = shift;
    carp(ref($self), " ", @_);
}

sub changed {
    my $self = shift;
    my $new  = shift;
    if ( defined $new ) {
        $self->{changed}++;
    }
    return $self->{changed};
}

=item B<options>

Returns a hashref of options (or sets options, just like Music::Tag method).

=cut

sub options {
    my $self = shift;
    unless ( exists $self->{_options} ) {
        $self->{_options} = Config::Options->new( $self->default_options );
    }
    return $self->{_options}->options(@_);
}

=pod

=item B<default_options>

method should return default options

=cut

sub default_options { {} }

sub DESTROY {
    my $self = shift;

    # Wow.  Took me a while to find this memory leak.
    if ( exists $self->{info} ) {
        delete $self->{info};
    }
}

1;

=pod

=back

=head1 BUGS

No method for analysing album as a whole, only track-by-track method.  Several plugins
do not support all tags.  Has not been tested in a threaded environment.

=head1 SEE ALSO INCLUDED

L<Music::Tag::Amazon>, L<Music::Tag::File>, L<Music::Tag::FLAC>, L<Music::Tag::Lyrics>,
L<Music::Tag::M4A>, L<Music::Tag::MP3>, L<Music::Tag::MusicBrainz>, L<Music::Tag::OGG>, L<Music::Tag::Option>

=head1 SEE ALSO

L<Term::ANSIColor>, L<Text::LevenshteinXS>, L<Text::Unaccent>, L<Lingua::EN::Inflect>, L<Lingua::Stem>

=head1 AUTHOR 

Edward Allen III <ealleniii _at_ cpan _dot_ org>

=head1 LICENSE

This program is free software; you can redistribute it and/or
modify it under the terms of the Artistic License, distributed
with Perl.

=head1 COPYRIGHT

Copyright (c) 2007,2008 Edward Allen III. Some rights reserved.



=cut

