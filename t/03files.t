#!/usr/bin/perl

use warnings;
use strict;
use Test::More tests => 11;
use Mac::iPod::GNUpod;

my $fakepod = './t/fakepod';
my $mp3 = './t/test.mp3';

# This test adds/removes files
{
    my $ipod = Mac::iPod::GNUpod->new(mountpoint => $fakepod);

    # Add a file
    my $id;
    ok $id = $ipod->add_song($mp3), "Adding $mp3";
    # Is it actually there?
    my($path) = $ipod->get_path($id);
    ok -e $path, "$mp3 successfully moved";
    # In the db?
    is scalar($ipod->all_songs), 1, "Song added to DB";

    # Rm the file
    ok $ipod->rm_song($id), "Removing test.mp3";
    # Is it gone?
    ok((not -e $path), "Song successfully removed");
    # Not in db?
    is scalar($ipod->all_songs), 0, "Song rmed from DB";
}

# Test finding duplicates
{
    my $ipod = Mac::iPod::GNUpod->new(mountpoint => $fakepod);
    
    $ipod->add_song($mp3);
    # This should fail
    my $id1 = $ipod->add_song($mp3);
    ok((not $id1), "Add failed on duplicate");

    # Try again, turning duplicate checking off
    $ipod->allow_dup(1);
    my $id2 = $ipod->add_song($mp3);
    ok $id2, "Duplicate succeeded w/ allow_dup on";

    # Check there are two actual files on disk
    my ($path1, $path2) = $ipod->get_path($id1, $id2);
    ok((-e $path1 && -e $path2), 'Both songs exist on disk');

    # Cleanup: rm all songs
    $ipod->rm_song($ipod->all_songs);
}

# Test obedience of move_files
{
    my $ipod = Mac::iPod::GNUpod->new(mountpoint => $fakepod);

    # Don't move the file
    $ipod->move_files(0);
    my $id = $ipod->add_song($mp3);
    my $path = $ipod->get_path($id);
    ok((not -e $path), "No path for new $mp3");
    $ipod->rm_song($id); # Out of DB!
    # Is the preceding test meaningful? The return of get_path when move_files
    # is off is pure garbage.

    # Ok, now move the file
    $ipod->move_files(1);
    $id = $ipod->add_song($mp3);
    ($path) = $ipod->get_path($id);
    # Rm the song w/ move_files off
    $ipod->move_files(0);
    $ipod->rm_song($id);
    ok -e $path, "File still exists";

}

# Final cleanup
unlink glob './t/fakepod/iPod_Control/Music/*/*';
