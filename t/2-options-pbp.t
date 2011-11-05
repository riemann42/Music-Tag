#!/usr/bin/perl -w
use strict;

use Test::More tests => 171;
use 5.006;

BEGIN { use_ok('Music::Tag', pbp => 1) }

my $tag = Music::Tag->new(
    undef,
    {artist    => "Sarah Slean",
     album     => "Orphan Music",
     title     => "Mary",
     comment   => undef,            # Should be ignored for now.
     ANSIColor => 0,
     quiet     => 1,
     locale    => "ca"
    },
    "Option"
                         );

ok($tag,          'Object created');
ok($tag->get_tag, 'get_tag called');

cmp_ok($tag->get_artist,      'eq', 'Sarah Slean',  'artist');
cmp_ok($tag->get_album,       'eq', 'Orphan Music', 'album');
cmp_ok($tag->get_albumartist, 'eq', 'Sarah Slean',  'albumartist');

ok(!defined $tag->get_comment, 'comment should be undefined');

ok($tag->set_encoded_by('Sarah'), 'Set encoded_by');
cmp_ok($tag->get_encoded_by, 'eq', 'Sarah', 'Get encoded_by');
$tag->set_albumtags('Canada,Female,Bible Reference');
cmp_ok($tag->get_albumtags->[2], 'eq', 'Bible Reference', 'albumtags');
$tag->set_artisttags(['Canada', 'Female']);
cmp_ok($tag->get_artisttags->[1], 'eq', 'Female', 'artisttags');

ok($tag->set_countrycode('CA'), 'Set Country Code');
cmp_ok($tag->get_countrycode, 'eq', 'CA', 'Get Country Code');
ok(length($tag->get_country) > 4, 'country from code');

ok($tag->set_discnum('2/3'), 'Set discnum');
cmp_ok($tag->get_disc,       '==', 2, 'Get discnum');
cmp_ok($tag->get_totaldiscs, '==', 3, 'Get totaldiscs');

ok($tag->set_track(4),        'Set track');
ok($tag->set_totaltracks(40), 'Set total tracks');
cmp_ok($tag->get_tracknum, 'eq', '4/40', 'Get tracknum');

ok($tag->set_ean('0825646392322'), 'Set ean');
cmp_ok($tag->get_upc, 'eq', '825646392322', 'Get upc');

ok($tag->set_releasetime('2006-10-31 1:01:02'), 'Set releasetime');
cmp_ok($tag->get_releasedate, 'eq', '2006-10-31', 'releasedate');

ok($tag->datamethods('testit'), 'add custom method');
ok($tag->set_testit('blue'),        'write to custom method');
cmp_ok($tag->get_testit, 'eq', 'blue', 'read custom method');

foreach my $meth (
    qw(album album_type albumartist albumartist_sortname albumid appleid artist artist_type artistid asin bitrate booklet codec comment compilation composer copyright disctitle encoded_by encoder genre ipod ipod_dbid ipod_location ipod_trackid label lyrics mb_albumid mb_artistid mb_trackid mip_puid originalartist path sortname  title  url user filetype mip_fingerprint)
  ) {
    my $val = "test" . $meth . int(rand(1000));
    my ($wmeth,$rmeth) = ('set_'.$meth, 'get_'. $meth);
    ok($tag->$wmeth($val), 'auto write to ' . $meth);
    cmp_ok($tag->$rmeth, 'eq', $val, 'auto read from ' . $meth);
}

foreach my $meth (
    qw( bytes disc duration frames framesize frequency gaplessdata playcount postgap pregap rating albumrating  samplecount secs stereo tempo totaldiscs totaltracks )
  ) {
    my $val = int(rand(10))+1;
    my ($wmeth,$rmeth) = ('set_'.$meth, 'get_'. $meth);
    ok($tag->$wmeth($val), 'auto write to ' . $meth);
    cmp_ok($tag->$rmeth, '==', $val, 'auto read from ' . $meth);
}

my %values = ();

foreach my $meth (
	 qw(artist_end_epoch artist_start_epoch lastplayedepoch mepoch recordepoch releaseepoch)) {
	 my $val = int(rand(1_800_000_000));
	 $values{$meth} = $val;
     my ($wmeth,$rmeth) = ('set_'.$meth, 'get_'. $meth);
	 ok($tag->$wmeth($val), 'auto write to '. $meth);
	 cmp_ok($tag->$rmeth, '==', $val, 'auto read from' . $meth);
}

foreach my $meth (
	 qw(artist_end_date artist_start_date lastplayeddate mdate recorddate releasedate)) {
	 my $me = $meth;
	 my $md = $meth;
	 $me =~ s/date/epoch/;
	 $md =~ s/_date//;
     $md = 'get_' .  $md;
	 my @tm = gmtime($values{$me});
	 cmp_ok($tag->$md, 'eq', sprintf('%04d-%02d-%02d', $tm[5]+1900, $tm[4]+1, $tm[3]), 'auto read from '. $md);
}

foreach my $meth (
	 qw(artist_end_time artist_start_time lastplayedtime mtime recordtime releasetime)) {
	 my $me = $meth;
	 $me =~ s/time/epoch/;
	 my @tm = gmtime($values{$me});
     my $rmeth = 'get_'.$meth;
	 cmp_ok($tag->$rmeth, 'eq', sprintf('%04d-%02d-%02d %02d:%02d:%02d', $tm[5]+1900, $tm[4]+1, $tm[3], $tm[2], $tm[1], $tm[0]), 'auto read from '. $meth);
}

foreach my $meth (qw(recorddate releasedate)) {
    my ($wmeth,$rmeth) = ('set_'.$meth, 'get_'. $meth);
    ok($tag->$wmeth('2009-07-12'), 'auto write to ' . $meth);
    cmp_ok($tag->$rmeth, 'eq', '2009-07-12', 'auto read from' . $meth);
}

ok(!$tag->setfileinfo, 'setfileinfo should fail');
ok(!$tag->get_sha1,        'sha1 should fail');

