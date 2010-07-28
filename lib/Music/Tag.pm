package Music::Tag;
use strict;
use warnings;
our $VERSION = .40_02;

# Copyright (c) 2007,2008,2009 Edward Allen III. Some rights reserved.

#
# You may distribute under the terms of either the GNU General Public
# License or the Artistic License, as specified in the README file.
#

use Carp;
use Locale::Country;
use File::Spec;
use Encode;
use Config::Options;
use Digest::SHA1;
use Music::Tag::Generic;
use Time::Local;
use utf8;
use vars qw(%DataMethods);

sub available_plugins {
    my $self  = shift;
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

sub LoadOptions {
    my $self    = shift;
    my $optfile = shift;
    if (ref $self) {
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
    if (ref $class) {
        my $clone = {%$class};
        bless $clone, ref $class;
        return $clone;
    }
    else {
        bless $self, $class;
        $self->{_plugins} = [];
        $self->options($options);
        $self->filename($filename);
        $self->{changed} = 0;
    }

	$self->_test_modules();

    if ($plugin) {
        $self->add_plugin($plugin, $options);
        return $self;
    }
    #else {
    #    return $self->auto_plugin($options);
    #}
}

sub _test_modules {
	my $self = shift;
	my %module_map = ( 
		'ANSIColor' => 'Term::ANSIColor',
        'LevenshteinXS' => 'Text::LevenshteinXS',
        'Levenshtein' => 'Levenshtein',
		'Unaccent' => 'Text::Unaccent::PurePerl',
		'Inflect'  => 'Lingua::EN::Inflect',
    );
	while (my ($k,$v) = each %module_map) {
		if (   ($self->options->{$k})
			&& ($self->_has_module($v))) {
			$self->options->{$k} = 1;
		}
		else {
			$self->options->{$k} = 0;
		}
	}
	return;
}

sub _has_module {
    my $self    = shift;
    my $module  = shift;
    my $modfile = $module . ".pm";
    $modfile =~ s/\:\:/\//g;
    eval { require $modfile };
    if ($@) {
        $self->status(1, "Not loading $module: " . $@);
        return 0;
    }
    else {
        return 1;
    }
}

sub add_plugin {
    my $self    = shift;
    my $object  = shift;
    my $opts    = shift || {};
    my $options = $self->options->clone;
    $options->merge($opts);
    my $type = shift || 0;

    my $ref;
    if (ref $object) {
        $ref = $object;
        $ref->info($self);
        $ref->options($options);
    }
    else {
        my ($plugin, $popts) = split(":", $object);
        if ($self->available_plugins($plugin)) {
            if ($popts) {
                my @opts = split(/[;]/, $popts);
                foreach (@opts) {
                    my ($k, $v) = split("=", $_);
                    $options->options($k, $v);
                }
            }
            eval {
                unless ($plugin =~ /::/) {
                    $plugin = "Music::Tag::" . $plugin;
                }
                if ($self->_has_module($plugin)) {
                    $ref = $plugin->new($self, $options);
                }
            };
            croak "Error loading plugin ${plugin}: $@" if $@;
        }
        else {
            croak "Error loading plugin ${plugin}: Not Found";
        }
    }
    if ($ref) {
        push @{$self->{_plugins}}, $ref;
    }
    return $ref;
}

sub plugin {
    my $self   = shift;
    my $plugin = shift;
    if (defined $plugin) {
        foreach (@{$self->{_plugins}}) {
            if (ref($_) =~ /$plugin$/) {
                return $_;
            }
        }
    }
    return;
}

sub get_tag {
    my $self = shift;
    $self->_foreach_plugin(sub { $_[0]->get_tag });
    return $self;
}

sub _foreach_plugin {
    my $self     = shift;
    my $callback = shift;
    foreach my $plugin (@{$self->{_plugins}}) {
        next unless $plugin;
        if (ref $plugin) {
            &{$callback}($plugin);
        }
        else {
            $self->error("Invalid Plugin in list: '$plugin'");
        }
    }
    return $self;
}

sub set_tag {
    my $self = shift;
    $self->_foreach_plugin(sub { $_[0]->set_tag });
    return $self;
}

sub strip_tag {
    my $self = shift;
    $self->_foreach_plugin(sub { $_[0]->strip_tag });
    return $self;
}

sub close {
    my $self   = shift;
    my @params = @_;
    return $self->_foreach_plugin(
        sub {
            $_[0]->close(@params);
            $_->{info} = undef;
            $_ = undef;
        }
    );
}

sub changed {
    my $self = shift;
    my $new  = shift;
    if (defined $new) {
        $self->{changed}++;
    }
    return $self->{changed};
}

sub data {
    my $self = shift;
    my $new  = shift;
    if (defined $new) {
        $self->{data} = $new;
    }
    return $self->{data};
}

sub options {
    my $self = shift;
    unless (exists $self->{_options}) {
        $self->{_options} = Config::Options->new($self->default_options);
    }
    return $self->{_options}->options(@_);
}

sub setfileinfo {
    my $self = shift;
    if ($self->filename) {
        my @stat = stat $self->filename;
        $self->mepoch($stat[9]);
        $self->bytes($stat[7]);
        return \@stat;
    }
    return;
}

sub sha1 {
    my $self = shift;
    return unless (($self->filename) && (-e $self->filename));
    my $maxsize = 4 * 4096;
    my $in;
    open($in, '<', $self->filename) or die "Bad file: $self->filename\n";
    my @stat = stat $self->filename;
    my $sha1 = Digest::SHA1->new();
    $sha1->add(pack("V", $stat[7]));
    my $d;

    if (read($in, $d, $maxsize)) {
        $sha1->add($d);
    }
    CORE::close($in);
    return $sha1->hexdigest;
}

sub datamethods {
    my $self = shift;
    my $add  = shift;
    if ($add) {
        my $new = lc($add);
        $DataMethods{$new} = 1;
		if (!defined &{$new}) {
			$self->_make_accessor($new);
		}
    }
    return [keys %DataMethods];
}

sub used_datamethods {
    my $self = shift;
    my @ret  = ();
    foreach my $m (@{$self->datamethods}) {
        if ($m eq "picture") {
            if ($self->picture_exists) {
                push @ret, $m;
            }
        }
        else {
            if (defined $self->$m) {
                push @ret, $m;
            }
        }
    }
    return \@ret;
}

sub wav_out {
    my $self = shift;
    my $fh   = shift;
    my $out;
    $self->_foreach_plugin(
        sub {
            $out = $_->wav_out($fh);
            return $out if (defined $out);
        }
    );
    return $out;
}

# This method is far from perfect.  It can't be perfect.
# It won't mangle valid UTF-8, however.
# Just be sure to always return perl utf8 in plugins when possible.

sub _isutf8 {
    my $self = shift;
    my $in   = shift;

    # If it is a proper utf8, with tag, just return it.
    if (Encode::is_utf8($in, 1)) {
        return $in;
    }

    my $has7f = 0;
    foreach (split(//, $in)) {
        if (ord($_) >= 0x7f) {
            $has7f++;
        }
    }

    # No char >7F it is prob. valid ASCII, just return it.
    unless ($has7f) {
        utf8::upgrade($in);
        return $in;
    }

    # See if it is a valid UTF-16 encoding.
    #my $out;
    #eval {
    #    $out = decode("UTF-16", $in, 1);
    #};
    #return $out unless $@;

    # See if it is a valid UTF-16LE encoding.
    #my $out;
    #eval {
    #    $out = decode("UTF-16LE", $in, 1);
    #};
    #return $out unless $@;

    # See if it is a valid UTF-8 encoding.
    my $out;
    eval { $out = decode("UTF-8", $in, 1); };
    unless ($@) {
        utf8::upgrade($out);
        return $out;
    }

    # Finally just give up and return it.

    utf8::upgrade($in);
    return $in;
}


sub _make_accessor {
	my ($self,$m) = @_;
	no strict 'refs';
	*{__PACKAGE__ . '::' . $m} = sub {
		my ($self,$new) = @_;
		$self->_accessor($m, $new);
	 };
	 return;
}

sub _accessor {
    my ($self, $attr, $value, $default) = @_;
    unless (exists $self->{data}->{uc($attr)}) {
        $self->{data}->{uc($attr)} = undef;
    }
    if (defined $value) {
        $value = $self->_isutf8($value);
        if ($self->options('verbose')) {
            $self->status(1,
                          "Setting $attr to ",
                          (defined $value) ? $value : "UNDEFINED");
        }
        $self->{data}->{uc($attr)} = $value;
    }
    if ((defined $default) && (not defined $self->{data}->{uc($attr)})) {
        $self->{data}->{uc($attr)} = $default;
    }
    return $self->{data}->{uc($attr)};
}

sub _timeaccessor {
    my $self    = shift;
    my $attr    = shift;
    my $value   = shift;
    my $default = shift;

    if (defined $value) {
        if ($value =~ /^(\d\d\d\d)[\s\-]?  #Year
			        (\d\d)?[\s\-]?     #Month
					(\d\d)?[\s\-]?     #Day
					(\d\d)?[\s\-:]?    #Hour
					(\d\d)?[\s\-:]?    #Min
					(\d\d)?            #Sec
				   /xms
          ) {
            $value = sprintf("%04d-%02d-%02d %02d:%02d:%02d",
                             $1, $2 || 1, $3 || 1,
                             $4 || 12, $5 || 0, $6 || 0
                            );
            if (   ($1 == 0)
                || ($1 eq "0000")
                || (($1 == 1900) && ($2 == 0) && ($3 == 0))
                || (($1 == 1900) && ($2 == 1) && ($3 == 1))) {
                $self->status(0, "Invalid date set for ${attr}: ${value}");
                $value = undef;
            }
        }
        else {
            $self->status(0, "Invalid date set for ${attr}: ${value}");
            $value = undef;
        }
    }
    return $self->_accessor($attr, $value, $default);
}

sub _epochaccessor {
    my $self  = shift;
    my $attr  = shift;
    my $value = shift;
    my $set   = undef;
    if (defined($value)) {
        my @tm = gmtime($value);
        $set = sprintf("%04d-%02d-%02d %02d:%02d:%02d",
                       $tm[5] + 1900,
                       $tm[4] + 1,
                       $tm[3], $tm[2], $tm[1], $tm[0]);
    }
    my $v = $self->_timeaccessor($attr, $set);
    my $ret = undef;
    if ((defined $v)
        && ($v =~ /^(\d\d\d\d)[\s\-]?  #Year
			        (\d\d)?[\s\-]?     #Month
					(\d\d)?[\s\-]?     #Day
					(\d\d)?[\s\-:]?    #Hour
					(\d\d)?[\s\-:]?    #Min
					(\d\d)?            #Sec
				   /xms
           )
      ) {
        eval {
            $ret = Time::Local::timegm($6 || 0, $5 || 0, $4 || 12, $3 || 1,
                                       ($2 - 1) || 0, ($1 - 1900));
        };
        $self->error($@) if $@;
    }
    return $ret;
}

sub _dateaccessor {
    my $self  = shift;
    my $attr  = shift;
    my $value = shift;
    my $new   = undef;
    if (defined($value)) {
        $new = $value;
    }
    my $v = $self->_timeaccessor($attr, $new);
    my $ret = undef;
    if ((defined $v)
        && ($v =~ /^(\d\d\d\d)[\s\-]?  #Year
			        (\d\d)?[\s\-]?     #Month
					(\d\d)?[\s\-]?     #Day
					(\d\d)?[\s\-:]?    #Hour
					(\d\d)?[\s\-:]?    #Min
					(\d\d)?            #Sec
				   /xms
           )
      ) {
        $ret = sprintf("%04d-%02d-%02d", $1, $2, $3);
    }
    return $ret;
}

sub _make_time_accessor {
	my $self = shift;
	my $m = shift;
	my $t = shift || $m.'time';
	my $d = shift || $m.'date';
	my $e = shift || $m.'epoch';
	no strict 'refs';
	*{__PACKAGE__ . '::' . $t} = sub {
		my ($self,$new) = @_;
		$self->_timeaccessor(uc($m), $new);
	 };
	*{__PACKAGE__ . '::' . $d} = sub {
		my ($self,$new) = @_;
		$self->_dateaccessor(uc($m), $new);
	 };
	*{__PACKAGE__ . '::' . $e} = sub {
		my ($self,$new) = @_;
		$self->_epochaccessor(uc($m), $new);
	 };
	 return;
}

sub _ordinalaccessor {
    my $self  = shift;
    my $attr  = shift;
    my $pos   = shift;
    my $total = shift;
    my $new   = shift;

    if (defined($new)) {
        my ($t, $tt) = split("/", $new);
        my $r = "";
        if ($t) {
            $self->_accessor($pos, $t);
            $r .= $t;
        }
        if ($tt) {
            $self->_accessor($total, $tt);
            $r .= "/" . $tt;
        }
    }
    my $ret = $self->_accessor($pos);
    if ($self->_accessor($total)) {
        $ret .= "/" . $self->_accessor($total);
    }
    return $ret;
}

sub _list_accessor {
    my $self    = shift;
    my $attr    = shift;
    my $value   = shift;
    my $default = shift;
    my $d       = "";
    if ((defined $default) && (ref $default)) {
        $d = join(",", @{$default});
    }
    else {
        $d = $default;
    }
    if (defined $value) {
        my $v = "";
        if (ref $value) {
            $v = join(",", @{$value});
        }
        else {
            $v = $value;
        }
        $self->_accessor($attr, $v, $d);
    }
    my $ret = $self->_accessor($attr);
    if ($ret) { return [split(/\s*,\s*/, $ret)] }
    return undef;
}

sub albumartist {
    my $self = shift;
    my $new  = shift;
    return $self->_accessor("albumartist", $new, $self->artist());
}

sub albumartist_sortname {
    my $self = shift;
    my $new  = shift;
    return $self->_accessor("albumartist_sortname", $new, $self->sortname());
}

sub albumtags {
    my $self = shift;
    my $new  = shift;
    return $self->_list_accessor("albumtags", $new);
}

sub artisttags {
    my $self = shift;
    my $new  = shift;
    return $self->_list_accessor("artisttags", $new);
}

sub country {
    my $self = shift;
    my $new  = shift;
    if (defined($new) && country2code($new)) {
        $self->_accessor("COUNTRYCODE", country2code($new));
    }
    if ($self->countrycode) {
        return code2country($self->countrycode);
    }
    return $self->_accessor("country", $new);
}

sub discnum {
    my $self = shift;
    my $new  = shift;
    return $self->_ordinalaccessor("DISCNUM", "DISC", "TOTALDISCS", $new);
}

sub duration {
    my $self = shift;
    my $new  = shift;
    if (defined($new)) {
        $self->_accessor("DURATION", $new);
        $self->_accessor("SECS",     int($new / 1000));
    }
    if ($self->_accessor("DURATION")) {
        return $self->_accessor("DURATION");
    }
    elsif ($self->_accessor("SECS")) {
        return $self->_accessor("SECS") * 1000;
    }
}

sub ean {
    my $self = shift;
    my $new  = shift;
    if (($new) && ($new =~ /\d{13}/)) {
        return $self->_accessor("EAN", $new);
    }
    elsif ($new) {
        $self->status(0, "Not setting EAN to invalid value: $new\n");
    }
    return $self->_accessor("EAN");
}

sub filename {
    my $self = shift;
    my $new  = shift;
    if (defined($new)) {
        my $file = $new;
        if ($new) {
            $file = File::Spec->rel2abs($new);
        }
        if ($self->options('verbose')) {
            $self->status(1,
                          "Setting filename  to ",
                          (defined $file) ? $file : "UNDEFINED");
        }
        $self->_accessor("FILENAME", $file);
    }
    return $self->_accessor("FILENAME");

}

sub filedir {
    my $self = shift;
    if ($self->filename) {
        my ($vol, $path, $file) = File::Spec->splitpath($self->filename);
        return File::Spec->catpath($vol, $path, "");
    }
    return undef;
}

sub jan {
    my $self = shift;
    return $self->ean(@_);
}

sub performer {
    my $self = shift;
    my $new  = shift;
    return $self->_accessor("ARTIST", $new);
}

sub _binslurp {
    my $file = shift;
    my $in;
    open($in, '<', $file) or croak "Couldn't open $file: $!";
    my $ret;
    my $off = 0;
    while (my $r = read $in, $ret, 1024, $off) { last unless $r; $off += $r }
    CORE::close($in);
    return $ret;
}

sub picture {
    my $self = shift;
    unless (exists $self->{data}->{PICTURE}) {
        $self->{data}->{PICTURE} = {};
    }
    $self->{data}->{PICTURE} = shift if @_;

    if (   (exists $self->{data}->{PICTURE}->{filename})
        && ($self->{data}->{PICTURE}->{filename})) {
        my $root = File::Spec->rootdir();
        if ($self->filename) {
            $root = $self->filedir;
        }
        my $picfile =
          File::Spec->rel2abs($self->{data}->{PICTURE}->{filename}, $root);
        if (-f $picfile) {
            if ($self->{data}->{PICTURE}->{_Data}) {
                delete $self->{data}->{PICTURE}->{_Data};
            }
            my %ret = %{$self->{data}->{PICTURE}};    # Copy ref
            $ret{_Data} = _binslurp($picfile);
            return \%ret;
        }
    }
    elsif (   (exists $self->{data}->{PICTURE}->{_Data})
           && (length $self->{data}->{PICTURE}->{_Data})) {
        return $self->{data}->{PICTURE};
    }
    return {};
}

sub picture_filename {
    my $self = shift;
    my $new  = shift;
    if ($new) {
        unless (exists $self->{data}->{PICTURE}) {
            $self->{data}->{PICTURE} = {};
        }
        $self->{data}->{PICTURE}->{filename} = $new;
    }
    if (   (exists $self->{data}->{PICTURE})
        && ($self->{data}->{PICTURE}->{filename})) {
        return $self->{data}->{PICTURE}->{filename};
    }
    elsif (   (exists $self->{data}->{PICTURE})
           && ($self->{data}->{PICTURE}->{_Data})
           && (length($self->{data}->{PICTURE}->{_Data}))) {
        return 0;
    }
    return undef;
}

sub picture_exists {
    my $self = shift;
    if (   (exists $self->{data}->{PICTURE}->{filename})
        && ($self->{data}->{PICTURE}->{filename})) {
        my $root = File::Spec->rootdir();
        if ($self->filename) {
            $root = $self->filedir;
        }
        my $picfile =
          File::Spec->rel2abs($self->{data}->{PICTURE}->{filename}, $root);
        if (-f $picfile) {
            return 1;
        }
        else {
            $self->status(0, "Picture: ", $picfile, " does not exists");
        }
    }
    elsif (   (exists $self->{data}->{PICTURE}->{_Data})
           && (length $self->{data}->{PICTURE}->{_Data})) {
        return 1;
    }
    return 0;
}

sub tracktags {
    my $self = shift;
    my $new  = shift;
    return $self->_list_accessor("tracktags", $new);
}

sub tracknum {
    my $self = shift;
    my $new  = shift;
    return $self->_ordinalaccessor("TRACKNUM", "TRACK", "TOTALTRACKS", $new);
}

sub upc {
    my $self = shift;
    my $new  = shift;
    if (($new) && ($new =~ /\d{12}/)) {
        unless ($self->ean) {
            $self->ean('0' . $new);
        }
        $self->_accessor("UPC", $new);
    }
    elsif ($new) {
        $self->status(0, "Not setting UPC to invalid value: $new\n");
    }
    if ($self->_accessor("UPC")) {
        return $self->_accessor("UPC");
    }
    elsif ($self->ean) {
        if ($self->ean =~ /^0(\d{12})/) {
            return $1;
        }
    }
}

sub year {
    my $self = shift;
    my $new  = shift;
    if (defined($new)) {
        $self->_accessor("YEAR", $new);
    }
    if ($self->_accessor("YEAR")) {
        return $self->_accessor("YEAR");
    }
    elsif ($self->releasedate) {
        if ($self->releasetime =~ /^(\d\d\d\d)-?/) {
            return $self->_accessor("YEAR", $1);
        }
    }
    return undef;
}

sub status {
    my $self = shift;
    unless ($self->options('quiet')) {
        my $name = ref($self);
        if ($_[0] =~ /\:\:/) {
            $name = shift;
        }
        my $level = 0;
        if ($_[0] =~ /^\d+$/) {
            $level = shift;
        }
        my $verbose = $self->options('verbose') || 0;
        if ($level <= $verbose) {
            $name =~ s/^Music::Tag:://g;
            print $self->_tenprint($name, 'bold white', 12), @_, "\n";
        }
    }
    return;
}

sub _tenprint {
    my $self   = shift;
    my $text   = shift;
    my $_color = shift || "bold yellow";
    my $size   = shift || 10;
    return
        $self->_color($_color)
      . sprintf('%' . $size . 's: ', substr($text, 0, $size))
      . $self->_color('reset');
}

sub _color {
    my $self = shift;
    if ($self->options->{ANSIColor}) {
        return Term::ANSIColor::color(@_);
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
    return;
}


BEGIN {
    $Music::Tag::DefaultOptions =
      Config::Options->new(
         {verbose       => 0,
          quiet         => 0,
          ANSIColor     => 0,
          LevenshteinXS => 1,
          Levenshtein   => 1,
          Unaccent      => 1,
          Inflect       => 0,
          optionfile => ["/etc/musictag.conf", $ENV{HOME} . "/.musictag.conf"],
         }
      );
    my @datamethods =
      qw(album album_type albumartist albumartist_sortname albumid appleid 
	     artist artist_end artist_start artist_start_time artist_start_epoch 
		 artist_end_time artist_end_epoch artist_type artistid asin bitrate 
		 booklet bytes codec comment compilation composer copyright country 
		 countrycode disc discnum disctitle duration encoded_by encoder filename
		 frames framesize frequency gaplessdata genre ipod ipod_dbid ipod_location
		 ipod_trackid label lastplayedtime lastplayeddate lastplayedepoch 
		 lyrics mb_albumid mb_artistid mb_trackid mip_puid mtime mdate mepoch 
		 originalartist performer path picture playcount postgap pregap rating 
		 albumrating recorddate recordtime releasedate releasetime recordepoch 
		 releaseepoch samplecount secs songid sortname stereo tempo title 
		 totaldiscs totaltracks track tracknum url user vbr year upc ean jan
		 filetype mip_fingerprint artisttags albumtags tracktags);
    %Music::Tag::DataMethods = map { $_ => 1 } @datamethods;
    @Music::Tag::PLUGINS = ();
 
	Music::Tag->_make_time_accessor('record'); 
	Music::Tag->_make_time_accessor('release'); 
	Music::Tag->_make_time_accessor('m');
	Music::Tag->_make_time_accessor('lastplayed'); 
	Music::Tag->_make_time_accessor('artist_start','artist_start_time','artist_start','artist_start_epoch'); 
	Music::Tag->_make_time_accessor('artist_end','artist_end_time','artist_end','artist_end_epoch'); 

	foreach my $m (@datamethods) {
		if (!defined &{$m}) {
			Music::Tag->_make_accessor($m) 
		}
	}

    my $me = __PACKAGE__;
    $me =~ s/\:\:/\//g;

    foreach my $d (@INC) {
        chomp $d;
        if (-d "$d/$me/") {
            local (*F_DIR);
            opendir(*F_DIR, "$d/$me/");
            while (my $b = readdir(*F_DIR)) {
                next unless $b =~ /^(.*)\.pm$/;
                my $mod = $1;
                push @Music::Tag::PLUGINS, $mod;
            }
        }
    }
}

sub DESTROY {
	my $self = shift;
    $self->_foreach_plugin(sub { delete $_[0]->{info} });
}

1;

__END__

1;
__END__
=pod

=for changes stop

=head1 NAME

Music::Tag - Interface for collecting information about music files.

=for readme stop

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
   
    # Augment info from an online database!
   
    $info->add_plugin("MusicBrainz");
    $info->add_plugin("Amazon");

    $info->get_tag;

    print "Record Label is ", $info->label();

    # Save back to file

    $info->set_tag();
    $info->close();

=for readme continue

=head1 DESCRIPTION

Extendable module for working with Music Tags. Music::Tag Is powered by 
various plugins that collect data about a song based on whatever information
has already been discovered.  

The motivation behind this was to provide a convenient method for fixing broken
tags in music files. This developed into a universal interface to various music 
file tagging schemes and a convenient way to augment this from online databases.

Several plugin modules to find information about a music file and write it back 
into the tag are available. These modules will use available information 
(B<REQUIRED DATA VALUES> and B<USED DATA VALUES>) and set various data values 
back to the tag.

=begin readme

=head1 INSTALLATION

To install this module type the following:

   perl Makefile.PL
   make
   make test
   make install

=head2 IMPORTANT NOTE

If you have installed older versions (older than .25) PLEASE delete the 
following scripts from your bin folder: autotag, safetag, quicktag, 
musicsort, musicinfo.  

If you used any of these scripts, create a symbolic link to musictag for each.

=head2 QUICK INSTALL OF ALL PACKAGES

A bundle is available to quickly install Music::Tag with all plugins. To
install it use:

   perl -MCPAN -eshell

At the cpan shell prompt type:

   install Bundle::Music::Tag

=head1 DEPENDENCIES

This module requires these other modules and libraries:

   Encode
   File::Spec
   Locale::Country
   Digest::SHA1
   Config::Options

I strongly recommend the following to improve web searches:

   Lingua::EN::Inflect
   Text::LevenshteinXS
   Text::Unaccent::PurePerl

The following just makes things pretty:

   Term::ANSIColor

=end readme

=head1 EXECUTABLE SCRIPT

An executable script, L<musictag> is  allows quick tagging of MP3 files.  To 
learn more, use:

   musictag --help 
   musictag --longhelp

=for readme stop

=head1 METHODS

=over 4

=item B<new()>

Takes a filename, an optional hashref of options, and an optional first plugin
and returns a new Music::Tag object.  For example: 

    my $info = Music::Tag->new($filename, { quiet => 1 }, "MP3" ) ;

If no plugin is listed, then it will automatically add the appropriate file 
plugin based on the extension. It does this by using the L<Music::Tag::Auto> 
plugin. If no plugin is appropriate, it will return.  

Options are global (apply to all plugins) and default (can be overridden by 
a plugin).

Plugin specific options can be applied here, if you wish. They will be ignored
by plugins that don't know what to do with them. See the POD for each of the 
plugins for more details on options a particular plugin accepts.

B<Current global options include:>

=over 4

=item B<verbose>

Default is false. Setting this to true causes plugin to generate a lot of noise.

=item B<quiet>

Default is false. Setting this to true prevents the plugin from giving status 
messages.

=item B<autoplugin>

Option is a hash reference mapping file extensions to plugins. Technically, 
this option is for the L<Music::Tag::Auto> plugin. Default is: 

    {   mp3   => "MP3",
        m4a   => "M4A",
        m4p   => "M4A",
        mp4   => "M4A",
        m4b   => "M4A",
        '3gp' => "M4A",
        ogg   => "OGG",
        flac  => "FLAC"   }

=item B<optionfile>

Array reference of files to load options from. Default is:

    [   "/etc/musictag.conf",   
        $ENV{HOME} . "/.musictag.conf"  ]

Note that this is only used if the "load_options" method is called. 

Option file is a pure perl config file using L<Config::Options>.

=item B<ANSIColor>

Default false. Set to true to enable color status messages.

=item B<LevenshteinXS>

Default true. Set to true to use Text::LevenshteinXS to allow approximate 
matching with Amazon and MusicBrainz Plugins. Will reset to false if module 
is missing.

=item B<Levenshtein>

Default true. Same as LevenshteinXS, but with Text::Levenshtein. Will not use 
if Text::Levenshtein can be loaded. Will reset to false if module is missing.

=item B<Unaccent>

Default true. When true, allows accent-neutral matching with 
Text::Unaccent::PurePerl. Will reset to false if module is missing.

=item B<Inflect>

Default false. When true, uses Linque::EN::Inflect to perform approximate 
matches. Will reset to false if module is missing.

=back

=item B<available_plugins()>

Class method. Returns list of available plugins. For example:

    foreach (Music::Tag->available_plugins) {
        if ($_ eq "Amazon") {
            print "Amazon is available!\n";
            $info->add_plugin("Amazon", { locale => "uk" });
        }
    }

=item B<default_options()>

Class method. Returns default options as a Config::Options method.

=item B<LoadOptions()>

Load options stated in optionfile from file. Default locations are 
/etc/musictag.conf and ~/.musictag.conf.  Can be called as class method or 
object method. If called as a class method the default values for all future
Music::Tag objects are changed.  

=pod

=item B<add_plugin()>

Takes a plugin name and optional set of options and it to a the Music::Tag 
object. Returns reference to a new plugin object. For example:

    my $plugin = $info->add_plugin("MusicBrainz", 
								   { preferred_country => "UK" });

$options is a hashref that can be used to override the global options for a 
plugin.

First option can be an string such as "MP3" in which case 
Music::Tag::MP3->new($self, $options) is called, an object name such as 
"Music::Tag::Custom::MyPlugin" in which case 
Music::Tag::MP3->new($self, $options) is called or an object, which is 
added to the list.

Current plugins include L<MP3|Music::Tag::MP3>, L<OGG|Music::Tag::OGG>, 
L<FLAC|Music::Tag::FLAC>, L<M4A|Music::Tag::M4A>, L<Amazon|Music::Tag::Amazon>, 
L<File|Music::Tag::File>, L<MusicBrainz|Music::Tag::MusicBrainz>, 
L<Lyrics|Music::Tag::Lyrics> and l<LyricsFetcher|Music::Tag::LyricsFetcher>,  

Additional plugins can be created and may be available on CPAN.  
See <L:Plugin Syntax> for information.

Options can also be included in the string, as in Amazon;locale=us;trust_title=1.

=pod

=item B<plugin()>

my $plugin = $item->plugin("MP3")->strip_tag();

The plugin method takes a regular expression as a string value and returns the
first plugin whose package name matches the regular expression. Used to access 
package methods directly. Please see <L/PLUGINS> section for more details on 
standard plugin methods.

=pod

=item B<get_tag()>

get_tag applies all active plugins to the current Music::Tag object in the 
order that the plugin was added. Specifically, it runs through the list of 
plugins and performs the get_tag() method on each.  For example:

    $info->get_tag();

=pod

=item B<set_tag()>

set_tag writes info back to disk for all Music::Tag plugins, or submits info 
if appropriate. Specifically, it runs through the list of plugins and performs 
the set_tag() method on each. For example:

    $info->set_tag();

=pod

=item B<strip_tag()>

strip_tag removes info from on disc tag for all plugins. Specifically, it 
performs the strip_tag method on all plugins in the order added. For example:

    $info->strip_tag();

=pod

=item B<close()>

closes active filehandles on all plugins. Should be called before object 
destroyed or frozen. For example: 

    $info->close();

=pod

=item B<changed()>

Returns true if changed. Optional value $new sets changed set to True of $new 
is true. A "change" is any data-value additions or changes done by MusicBrainz, 
Amazon, File, or Lyrics plugins. For example:

    # Check if there is a change:
    $ischanged = $info->changed();

    # Force there to be a change
    $info->changed(1);

=item B<data()>

Returns a reference to the hash which stores all data about a track and 
optionally sets it.  This is useful if you want to freeze and recreate a track, 
or use a shared data object in a threaded environment. For example;

    use Data::Dumper;
    my $bighash = $info->data();
    print Dumper($bighash);

=pod

=item B<options()>

This method is used to access or change the options. When called with no 
options, returns a reference to the options hash. When called with one string 
option returns the value for that key. When called with one hash value, merges 
hash with current options. When called with 2 options, the first is a key and 
the second is a value and the key gets set to the value. This method is for 
global options. For example:

    # Get value for "verbose" option
    my $verbose = $info->options("verbose");

    # or...
    my $verbose = $info->options->{verbose};

    # Set value for "verbose" option
    $info->options("verbose", 0);

    # or...
    $info->options->{verbose} = 0;

=item B<setfileinfo>

Sets the mtime and bytes attributes for you from filename. 

=item B<sha1()>

Returns a sha1 digest of the filesize in little endian then the first 16K of 
the music file. Should be fairly unique. 

=pod

=item B<datamethods()>

Returns an array reference of all data methods supported.  Optionally takes a 
method which is added.  Data methods should be all lower case and not conflict 
with existing methods. Data method additions are global, and not tied to an 
object. Array reference should be considered read only. For example:


    # Print supported data methods:
    my $all_methods = Music::Tag->datamethods();
    foreach (@{$all_methods}) {
        print '$info->'. $_ . " is supported\n";
    }

    # Add is_hairband data method:
    Music::Tag->datamethods("is_hairband");

=pod

=item B<used_datamethods()>

Returns an array reference of all data methods that will not return.  For example:

    my $info = Music::Tag->new($filename);
    $info->get_tag();
    foreach (@{$info->used_datamethods}) {
        print $_ , ": ", $info->$_, "\n";
    }

=pod

=item B<wav_out($fh)>

Pipes audio data as a wav file to filehandled $fh. Returns true on success, false on failure, undefined if no plugin supports this.

=back

=head2 Data Access Methods

These methods are used to access the Music::Tag data values. Not all methods are supported by all plugins. In fact, no single plugin supports all methods (yet). Each of these is an accessor function. If you pass it a value, it will set the variable. It always returns the value of the variable.

Please note that an undefined function will return undef.  This means that in list context, it will be true even when empty.  This behavior may change, however, so don't rely on it.

=pod

=over 4

=item B<album>

The title of the release.

=item B<album_type>

The type of the release. Specifically, the MusicBrainz type (ALBUM OFFICIAL, etc.) 

=item B<albumartist>

The artist responsible for the album. Usually the same as the artist, and will return the value of artist if unset.

=item B<albumartist_sortname>

The name of the sort-name of the albumartist (e.g. Hersh, Kristin or Throwing Muses, The)

=pod

=item B<albumtags>

A array reference or comma seperated list of tags in plain text for the album.

=item B<albumrating>

The rating (value is 0 - 100) for the album (not supported by any plugins yet).

=item B<artist>

The artist responsible for the track.

=item B<artist_start>

The date the artist was born or a group was founded. Sets artist_start_time and artist_start_epoch.

=item B<artist_start_time>

The time the artist was born or a group was founded. Sets artist_start and artist_start_epoch

=item B<artist_start_epoch>

The number of seconds since the epoch when artist was born or a group was founded. Sets artist_start and artist_start_time

See release_epoch.

=item B<artist_end>

The date the artist died or a group was disbanded. Sets artist_end_time and artist_end_epoch.

=item B<artist_end_time>

The time the artist died or a group was disbanded. Sets artist_end and artist_end_epoch

=item B<artist_end_epoch>

The number of seconds since the epoch when artist died or a group was disbanded. Sets artist_end and artist_end_time

See release_epoch.

=item B<artisttags>

A array reference or comma seperated list of tags in plain text for the artist.

=item B<artist_type>

The type of artist. Usually Group or Person.

=item B<asin>

The Amazon ASIN number for this album.

=item B<bitrate>

Bitrate of file (average).

=item B<booklet>

URL to a digital booklet. Usually in PDF format. iTunes passes these out sometimes, or you could scan a booklet
and use this to store value. URL is assumed to be relative to file location.

=item B<comment>

A comment about the track.

=item B<compilation>

True if album is Various Artist, false otherwise.  Don't set to true for Best Hits.

=item B<composer>

Composer of song.

=item B<copyright>

A copyright message can be placed here.

=item B<country>

Return the country that the track was released in.

=pod

=item B<countrycode>

The two digit country code.  Sets country (and is set by country)

=item B<disc>

In a multi-volume set, the disc number.

=item B<disctitle>

In a multi-volume set, the title of a disc.

=item B<discnum>

The disc number and optionally the total number of discs, seperated by a slash. Setting it sets the disc and totaldiscs values.

=pod

=item B<duration>

The length of the track in milliseconds. Returns secs * 1000 if not set. Changes the value of secs when set.

=pod

=item B<ean>

The European Article Number on the package of product.  Must be the EAN-13 (13 digits 0-9).

=item B<encoder>

The codec used to encode the song.

=item B<filename>

The filename of the track.

=item B<filedir>

The path that music file is located in.

=pod


=item B<frequency>

The frequency of the recording (in Hz).

=item B<genre>

The genre of the song. Various music tagging schemes use this field differently.  It should be text and not a code.  As a result, some
plugins may be more restrictive in what can be written to disk,

=item B<jan>

Same as ean.

=item B<label>

The label responsible for distributing the recording.

=item B<lastplayeddate>

The date the song was last played.

=item B<lastplayedtime>

The time the song was last played.

=item B<lastplayedepoch>

The number of seconds since the epoch the time the song was last played.

See release_epoch.

=item B<lyrics>

The lyrics of the recording.

=item B<mdate>

The date the file was last modified.

=item B<mtime>

The time the file was last modified.

=item B<mepoch>

The number of seconds since the epoch the time the file was last modified.

=item B<mb_albumid>

The MusicBrainz database ID of the album or release object.

=item B<mb_artistid>

The MusicBrainz database ID for the artist.

=item B<mb_trackid>

The MusicBrainz database ID for the track.

=item B<mip_puid>

The MusicIP puid for the track.

=item B<mip_fingerprint>

The Music Magic fingerprint

=item B<performer>

The performer. This is an alias for artist.

=pod

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


Note hashref MAY be generated each call.  Do not modify and assume data-value in object will be modified!  Passing a value
will modify the data-value as expected. In other words:

    # This works:
    $info->picture( { filename => "cover.jpg" } ) ;

    # This may not:
    my $pic = $info->picture;
    $pic->{filename} = "back_cover.jpg";

=pod

=item B<picture_filename>

Returns filename used for picture data.  If no filename returns 0.  If no picture returns undef. 
If a value is passed, sets the filename. filename is path relative to the music file.

=pod

=item B<picture_exists>

Returns true if Music::Tag object has picture data (or filename), false if not. Convenience method to prevant reading the file. 
Will return false of filename listed for picture does not exist.

=pod

=item B<rating>

The rating (value is 0 - 100) for the track.

=item B<recorddate>

The date track was recorded (not release date).  See notes in releasedate for format.

=item B<recordepoch>

The recorddate in seconds since epoch.  See notes in releaseepoch for format.

=item B<recordtime>

The time and date track was recoded.  See notes in releasetime for format.

=item B<releasedate>

The release date in the form YYYY-MM-DD.  The day or month values may be left off.  Please keep this in mind if you are parsing this data.

Because of bugs in my own code, I have added 2 sanity checks.  Will not set the time and return if either of the following are true:

=over 4

=item 1) Time is set as 0000-00-00

=item 2) Time is set as 1900-00-00

=back

All times should be GMT.

=item B<releaseepoch>

The release date of an album in terms "UNIX time", or seconds since the SYSTEM 
epoch (usually Midnight, January 1, 1970 GMT). This can be negative or > 32 bits,
so please use caution before assuming this value is a valid UNIX date. This value 
will update releasedate and vice-versa.  Since this accurate to the second and 
releasedate only to the day, setting releasedate will always set this to 12:00 PM 
GMT the same day. 

Please note that this has some limitations. In 32bit Linux, the only supported
dates are Dec 1901 to Jan 2038. In windows, dates before 1970 will not work. 
Refer to the docs for Time::Local for more details.

=item B<releasetime>

Like releasedate, but adds the time.  Format should be YYYY-MM-DD HH::MM::SS.  Like releasedate, all entries but year
are optional.

All times should be GMT.

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

=item B<tracktags>

A array reference or comma seperated list of tags in plain text for the track.

=item B<tracknum>

The track number and optionally the total number of tracks, seperated by a slash. Setting it sets the track and totaltracks values (and vice-versa).

=pod

=item B<upc>

The Universal Product Code on the package of a product. Returns same value as ean without initial 0 if ean has an initial 0. If set and ean is not set, sets ean and adds initial 0.  It is possible for ean and upc to be different if ean does not have an initial 0.

=item B<url>

A url associated with the track (often a link to the details page on Amazon).

=item B<year>

The year a track was released. Defaults to year set in releasedate if not set. Does not set releasedate.

=back

=head1 Non Standard Data Access Methods

These methods are not currently used by any standard plugin.  They may be used in the future, or by other plugins (such as a SQL plugin).  Included here to standardize expansion methods.

=over 4

=item B<albumid, artistid, songid>

These three values can be used by a database plugin. They should be GUIDs like the MusicBrainz IDs. I recommend using the same value as mb_albumid, mb_artistid, and mb_trackid by default when possible.

=item B<ipod, ipod_dbid, ipod_location, ipod_trackid>

Suggested values for an iPod plugin.

=item B<pregap, postgap, gaplessdata, samplecount, appleid>

Used to store gapless data.  Some of this is supported by L<Music::Tag::MP3> as an optional value requiring a patched
L<MP3::Info>.

=item B<user>

Used for user data. Reserved. Please do not use this in any Music::Tag plugin published on CPAN.

=item B<bytes, codec, encoded_by, filetype, frames, framesize, mtime, originalartist, path, playcount, stereo, vbr>

TODO: These need to be documented

=item B<status>

Semi-internal method for printing status.

=item B<error>

Semi-internal method for printing errors.

=pod

=back

=head1 PLUGINS

See L<Music::Tag::Generic|Music::Tag::Generic> for base class for plugins.

=head1 BUGS

No method for evaluating an album as a whole, only track-by-track method.  
Several plugins do not support all data values. Has not been tested in a 
threaded environment.

=head1 SEE ALSO 

L<Music::Tag::Amazon>, L<Music::Tag::File>, L<Music::Tag::FLAC>, 
L<Music::Tag::Lyrics>, L<Music::Tag::LyricsFetcher>, L<Music::Tag::M4A>, 
L<Music::Tag::MP3>, L<Music::Tag::MusicBrainz>, L<Music::Tag::OGG>, 
L<Music::Tag::Option>, L<Term::ANSIColor>, L<Text::LevenshteinXS>, 
L<Text::Unaccent::PurePerl>, L<Lingua::EN::Inflect>

=for readme continue

=head1 SOURCE

Source is available at github: L<http://github.com/riemann42/Music-Tag|http://github.com/riemann42/Music-Tag>.

=head1 BUG TRACKING

Please use github for bug tracking: L<http://github.com/riemann42/Music-Tag/issues|http://github.com/riemann42/Music-Tag/issues>.

=head1 AUTHOR 

Edward Allen III <ealleniii _at_ cpan _dot_ org>

=head1 COPYRIGHT

Copyright (c) 2007,2008,2010 Edward Allen III. Some rights reserved.

=head1 LICENSE

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either:

a) the GNU General Public License as published by the Free
Software Foundation; either version 1, or (at your option) any
later version, or

b) the "Artistic License" which comes with Perl.

=begin readme

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See either
the GNU General Public License or the Artistic License for more details.

You should have received a copy of the Artistic License with this
Kit, in the file named "Artistic".  If not, I'll be glad to provide one.

You should also have received a copy of the GNU General Public License
along with this program in the file named "Copying". If not, write to the
Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
Boston, MA 02110-1301, USA or visit their web page on the Internet at
http://www.gnu.org/copyleft/gpl.html.

=end readme

