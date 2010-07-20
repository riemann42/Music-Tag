#!/usr/bin/perl -w
use strict;

use Test::More tests => 13;
use 5.006;

BEGIN { use_ok('Music::Tag') }

ok(Music::Tag::available_plugins('Options'), 'available_plugins');
is(Music::Tag::default_options->{'TimeLocal'}, 1, 'default_options');
ok( Music::Tag->LoadOptions("t/options.conf"), "Loading options file.\n" );


my $tag = Music::Tag->new(undef, {}, 'Option');

ok( $tag, 'Object created');
ok ($tag->options->{'quiet'} == 1, "options");

ok( $tag, 'Object created');

cmp_ok( $tag->changed, '==', 0);

ok ($tag->add_plugin("Option", { album => "Orphan Music",
								 title => "Mary",
								 ANSIColor => 0,
								 quiet => 1,
								 locale => "ca" } , "Option" ), "add_plugin");


ok( $tag->get_tag, 'get_tag called' );

is (ref($tag->plugin("Option")), 'Music::Tag::Option', "plugin");

ok (ref $tag->data, 'Tag Data');

my %used = ( map { lc($_) => 1 } @{$tag->used_datamethods} );

ok ($used{title}, "used_datamethods");

