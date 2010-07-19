#!/usr/bin/perl
use strict;
use Music::Tag;

my @lame = ( "lame", "--preset", "extreme", "-", '[FILENAME]') 

foreach my $infile (@ARGV) {
    my $info = Music::Tag->new($infile);
    $info->get_tag();
    print "Performer is ", $info->artist, "\n";
    my $outfile = $info->filename();
    $outfile =~ s/\.[^.]*$/\.mp3/;
    if ($outfile eq $infile) {
        $outfile =~ s/\.mp3$/_1\.mp3/;
    }
    print STDERR "Writing mp3 to $outfile\n";
    my @out = ();
    foreach (@lame) {
        my $a = $_;
        $a =~ s/\[FILENAME\]/$outfile/ge;
    }
    open (OUT, "|-", @out);
    $info->wav_out(\*OUT);
    my $newinfo = Music::Tag->new($outfile);
    $newinfo->get_tag();
    foreach (@{$info->used_datamethods}) {
        next if ($newinfo->$_);
        $newinfo->$_($info->$_);
    }
    $newinfo->set_tag();
    $info->close();
    $newinfo->close();
}



