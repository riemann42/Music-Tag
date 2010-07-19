#!/usr/bin/perl -w
use strict;

use Test::More tests => 21;
use 5.006;

BEGIN { use_ok('Music::Tag') }

my $tag = Music::Tag->new( undef,  { artist => "Sarah Slean",
								     album => "Orphan Music",
									 title => "Mary",
									 ANSIColor => 0,
									 quiet => 1,
									 locale => "ca" } , "Option" );

ok( $tag, 'Object created');
ok( $tag->get_tag, 'get_tag called' );
is ( $tag->artist , 'Sarah Slean', 'artist');
is ( $tag->album , 'Orphan Music', 'album');
is ( $tag->albumartist, 'Sarah Slean', 'albumartist');
$tag->albumtags('Canada,Female,Bible Reference');
is ( $tag->albumtags->[2], 'Bible Reference', 'albumtags');
$tag->artisttags(['Canada','Female']);
is ( $tag->artisttags->[1], 'Female', 'artisttags');
ok($tag->countrycode('CA'), 'Set Country Code');
is ( $tag->countrycode, 'CA', 'Get Country Code');
ok ( length($tag->country) > 4, 'country from code');
ok ($tag->discnum('2/3'), 'Set discnum');
is ($tag->disc, 2, 'Get discnum');
is ($tag->totaldiscs, 3, 'Get totaldiscs');
ok ($tag->track(4), 'Set track');
ok ($tag->totaltracks(40), 'Set total tracks');
is ($tag->tracknum, '4/40', 'Get tracknum');

ok ($tag->ean('0825646392322'), 'Set ean');
is ($tag->upc, '825646392322', 'Get upc');

ok ($tag->releasetime('2006-10-31 1:01:02'), 'Set releasetime');
is ($tag->releasedate,'2006-10-31', 'releasedate');

