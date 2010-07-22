#!/usr/bin/perl -w
use strict;
use Test::More tests => 51;
eval { require Music::Tag::MP3 };
plan( skip_all => 'Music::Tag::MP3 not installed; skipping' ) if $@;
use File::Copy;
use 5.006;

BEGIN { use_ok('Music::Tag') }

our $options = {};

# Add 13 test for each run of this
sub filetest {
    my $file        = shift;
    my $filetest    = shift;
    my $testoptions = shift;
  SKIP: {
        skip "File: $file does not exists", 7 unless ( -f $file );
        return unless ( -f $file );
        copy( $file, $filetest );
        my $tag = Music::Tag->new( $filetest, $testoptions );
        ok( $tag, 'Object created: ' . $filetest );
        die unless $tag;
        ok( $tag->get_tag, 'get_tag called: ' . $filetest );
        ok( $tag->isa('Music::Tag'), 'Correct Class: ' . $filetest );
		# Check basic set items
        is( $tag->artist, "Beethoven", 'Artist: ' . $filetest );
        is( $tag->album,  "GPL",       'Album: ' . $filetest );
        is( $tag->title,  "Elise",     'Title: ' . $filetest );
		is ($tag->sha1, '39cd05447fa9ab6d6db08f41a78ac8628874c37e', 'sha1 test');
		ok (!$tag->picture_exists, 'Picture does not Exists');

		# Now go through each method supported and test.

		my %values = ();

		foreach my $f (qw(title artist album genre sortname mb_trackid lyrics encoded_by asin
					sortname albumartist_sortname albumartist mb_artistid mb_albumid album_type 
					artist_type mip_puid mip_puid mip_fingerprint )) {
			my $val =  "test" . $f . int(rand(1000));
			ok($tag->$f($val), "Set value for $f");
			$values{$f} = $val;
		}


		# Now add a picture.
		#

		ok ($tag->picture_filename('t/beethoven.jpg'), 'add picture');

        ok( $tag->set_tag, 'set_tag: ' . $filetest );

        $tag->close();
        $tag = undef;
        my $tag2 = Music::Tag->new( $filetest, $testoptions);
        ok( $tag2, 'Object created again: ' . $filetest );
        ok( $tag2->get_tag, 'get_tag called: ' . $filetest );
		

		foreach my $f (keys %values) {
			is($tag2->$f, $values{$f}, "Read back $f");
		}

		ok ($tag2->picture_exists, 'Picture Exists');


        $tag2->close();
        unlink($filetest);
    }
}

ok( Music::Tag->LoadOptions("t/options.conf"), "Loading options file." );
filetest( "t/elise.mp3", "t/elisetest.mp3" );

