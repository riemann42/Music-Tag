#!/usr/bin/perl -w
use strict;
use Test::More tests =>2;
use utf8;
eval "use Text::Unaccent::PurePerl";
plan skip_all => "Text::Unaccent::PurePerl required for testing accent changes" if $@;

BEGIN { use_ok('Music::Tag') }


my $tag = Music::Tag->new('t/fake.music',
                          { 'Unaccent' => 1 },
                          "Generic"
                         );

ok ( $tag->plugin('Generic')->simple_compare('Björk', 'Bjork'), 'Accent compare');
