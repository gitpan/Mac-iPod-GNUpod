#!/usr/bin/perl

# This file tests reading and writing the iTunesDB

use warnings;
use strict;
use Test::More tests => 8;
use Mac::iPod::GNUpod;

my $test = './t/test.itunes';
my $comp = './t/comp.itunes';

# Read and write iTunes
{
    my $ipod = Mac::iPod::GNUpod->new(gnupod_db => './t/test.xml', itunes_db => $test);

    # Read GNUpod, write iTunes, and compare to prepared iTunes
    $ipod->read_gnupod;

    # The 'name' option is undocumented and only used in test scripts.
    # mktunes.pl writes the current GNUpod ver. into the iTunesDB, and we have
    # to match this in order to make the files match.
    ok $ipod->write_itunes(name => 'GNUpod 0.93-1'), "Write iTunes";

    # Make another object reading the DB and check for identical
    my $ipod2 = Mac::iPod::GNUpod->new(gnupod_db => './t/test.xml', itunes_db => $test);
    ok $ipod2->read_itunes, "Read iTunes";

    # is_deeply won't succeed--several differences
    # Check things individually
    is_deeply $ipod->{files}, $ipod2->{files}, "Read iTunes gives same files";
    is_deeply $ipod->{plorder}, $ipod2->{plorder}, "Read iTunes gives same pls";
    my (@list1, @list2);
    for (sort keys %{$ipod->{pl_idx}}) {
        push @list1, $ipod->_render_pl($_);
    }
    for (sort keys %{$ipod2->{pl_idx}}) {
        push @list2, $ipod2->_render_pl($_);
    }
    is_deeply \@list1, \@list2, "Same rendered playlist items";

}

# Compare test iTunes to one prepared w/ mktunes.pl
{
    my $testpod = Mac::iPod::GNUpod->new(gnupod_db => '/dev/null', itunes_db => $test);
    my $comppod = Mac::iPod::GNUpod->new(gnupod_db => '/dev/null', itunes_db => $comp);

    $testpod->read_itunes;
    $comppod->read_itunes;

    # Different order for pl items--so check manually
    is_deeply $testpod->{files}, $comppod->{files}, "Same file items";
    is_deeply $testpod->{plorder}, $comppod->{plorder}, "Same pl order";
    my (%testpls, %comppls);
    for (sort keys %{$testpod->{pl_idx}}) {
        $testpls{$_} = { map { $_ => undef } $testpod->_render_pl($_) };
    }
    for (sort keys %{$comppod->{pl_idx}}) {
        $comppls{$_} = { map { $_ => undef } $comppod->_render_pl($_) };
    }

    is_deeply \%testpls, \%comppls, "Same playlist items (unsorted)";
}

# Final cleanup
unlink $test;
    
