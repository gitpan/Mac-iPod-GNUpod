#!/usr/bin/perl

# Test script for general tasks

use Test::More tests => 24;

# Use
BEGIN {
    use_ok 'Mac::iPod::GNUpod';
}

my $fakepod = './t/fakepod';
mkdir $fakepod;

# Constructor, style 1
{
    my $ipod = Mac::iPod::GNUpod->new(mountpoint => $fakepod);
    ok $ipod, 'Init giving mountpoint';

    ok(($ipod->mountpoint eq $fakepod), 'Location of mountpoint');
    ok(($ipod->itunes_db eq $ipod->mountpoint . '/iPod_Control/iTunes/iTunesDB'), 'Location of iTunesDB');
    ok(($ipod->gnupod_db eq $ipod->mountpoint . '/iPod_Control/.gnupod/GNUtunesDB'), 'Location of GNUpodDB');
}

# Constructor, style 2
{
    my $ipod = Mac::iPod::GNUpod->new(
        itunes_db => "$fakepod/iPod_Control/iTunes/iTunesDB",
        gnupod_db => "$fakepod/iPod_Control/.gnupod/GNUtunesDB"
    );
    ok $ipod, 'Init giving iTunes and GNUpod';

    ok((not $ipod->mountpoint), 'Mountpoint unset');
    ok(($ipod->itunes_db eq "$fakepod/iPod_Control/iTunes/iTunesDB"), "Location of iTunesDB");
    ok(($ipod->gnupod_db eq "$fakepod/iPod_Control/.gnupod/GNUtunesDB"), "Location of GNUpodDB");
}

# Test flags and other get/sets
{
    my $ipod = Mac::iPod::GNUpod->new(mountpoint => $fakepod);

    # Test defaults
    my %expect = (
        mountpoint => $fakepod,
        itunes_db  => "$fakepod/iPod_Control/iTunes/iTunesDB",
        gnupod_db  => "$fakepod/iPod_Control/.gnupod/GNUtunesDB",
        allow_dup  => 0,
        move_files => 1
    );

    for (keys %expect) {
        ok(($ipod->$_ eq $expect{$_}), "Got correct default for $_");

        $ipod->$_('foo');
        ok(($ipod->$_ eq 'foo'), "Set $_");
    }
}

# Test init()
{
    my $ipod = Mac::iPod::GNUpod->new(mountpoint => $fakepod);

    # Nuke that mofo
    system 'rm -rf ./t/fakepod/*';

    ok $ipod->init, 'Init successful';

    # Check directories
    my $prob;
    for ('Calendars', 'Contacts', 'Notes', 'iPod_Control', 'iPod_Control/Device', 'iPod_Control/Music', 'iPod_Control/iTunes', 'iPod_Control/.gnupod') {
        $prob = $_ unless -e "$fakepod/$_";
        last if $prob;
    }
    ok((not $prob), "Directory structure check (problem with " . ($prob || 'none') . ')');

    # Check music directories
    undef $prob;
    for (0 .. 19) {
        $prob = $_ unless -e "$fakepod/iPod_Control/Music/F" . sprintf('%02d', $_);
        last if $prob;
    }
    ok((not $prob), "Music directory check (problem with " . ($prob || 'none') . ')');

    # Check db files
    ok((-e $ipod->gnupod_db), 'GNUpodDB exists');
    ok((-e $ipod->itunes_db), 'iTunesDB exists');
}

# Test restore()
# Actually not, since I can't think of any lightweight way to do it for now.

