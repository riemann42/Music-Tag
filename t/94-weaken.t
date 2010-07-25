#!/usr/bin/perl -w
use strict;

use Test::More tests => 2;
use Test::Weaken qw(leaks);
use 5.006;

BEGIN { use_ok('Music::Tag') }

my $test = sub {
	my $tag = Music::Tag->new(
		undef,
		{artist    => "Sarah Slean",
		 album     => "Orphan Music",
		 title     => "Mary",
		 quiet	   => 1,
		},
		"Option"
							 );

	$tag->get_tag;
	$tag->set_tag;
	$tag->close;
	return $tag;
};

ok(! leaks($test), 'No Memory Leaks for Option Tag');
