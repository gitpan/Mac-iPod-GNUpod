#!/usr/bin/perl

# This file tests reading and writing the GNUpod DB

use warnings;
use strict;
use Test::More tests => 6;
use Mac::iPod::GNUpod;

# Read and write normal file
{
    my $ipod = Mac::iPod::GNUpod->new(gnupod_db => './t/test.xml', itunes_db => '/dev/null');

    ok $ipod->read_gnupod, "Read GNUpod";

    # Write to a different file
    $ipod->gnupod_db('./t/test2.xml');
    ok $ipod->write_gnupod, "Write GNUpod";

    # Reread, check sameness
    my $ipod2 = Mac::iPod::GNUpod->new(gnupod_db => './t/test2.xml', itunes_db => '/dev/null');
    $ipod2->read_gnupod;
    is_deeply $ipod, $ipod2, "Read/write results in same structure";

    # Cleanup
    unlink './t/test2.xml';
}

# Read the crazy file
{
    my $ipod = Mac::iPod::GNUpod->new(gnupod_db => './t/crazy.xml', itunes_db => '/dev/null');

    ok $ipod->read_gnupod, "Read crazy GNUpod";

    # Write, reread
    $ipod->gnupod_db('./t/crazy2.xml');
    $ipod->write_gnupod;
    my $ipod2 = Mac::iPod::GNUpod->new(gnupod_db => './t/crazy2.xml', itunes_db => '/dev/null');
    $ipod2->read_gnupod;

    # is_deeply can't succeed (diff order of items), so we'll check manually
    is_deeply $ipod->{files}, $ipod2->{files}, "All files OK";
    is_deeply $ipod->{pl_idx}, $ipod2->{pl_idx}, "All pls OK";

    # Cleanup
    unlink './t/crazy2.xml';
}
