#!/usr/bin/perl

package Mac::iPod::GNUpod;

=head1 NAME

Mac::iPod::GNUpod - Add and remove songs from your iPod; read and write
databases in iTunes and GNUpod format

=head1 ABSTRACT

A re-implementation of the GNUpod package for manipulating an iPod. This module
provides methods for initializing your iPod, adding and removing songs, and
reading and writing databases in the iTunes and GNUpod formats. This module is
based on the GNUpod script package, written and distributed by Adrian Ulrich,
(pab at blinkenlights.ch). URL: L<http://www.gnu.org/software/gnupod/>.

=head1 SYNOPSIS

    use Mac::iPod::GNUpod;

    my $ipod = Mac::iPod::GNUpod->new(mountpoint => '/mnt/ipod';

    # Read existing databases
    $ipod->read_gnupod;
    $ipod->read_itunes;

    # Add songs
    my $id = $ipod->add_song('/home/music/The Foo Brothers - All Barred Up.mp3');

    # Get paths to songs
    my $path = $ipod->get_path($id);

    # Find the id numbers of existing songs
    my @yuck = $ipod->search(artist => 'Yoko Ono');

    # Remove songs
    $ipod->rm_song(@yuck);

    # Write databases
    $ipod->write_gnupod;
    $ipod->write_itunes;

=cut

# Remainder of POD after __END__

use warnings;
use strict;

use Mac::iPod::GNUpod::Utils;
use Mac::iPod::GNUpod::FileMagic;
use File::Copy;
use XML::Parser;
use Carp qw/carp croak/;

our $VERSION = '1.0';

# Global variables
my @flags = qw/itunes_db gnupod_db allow_dup move_files/;

sub new {
    my ($class, %opt) = @_;

    my $self = {
        mnt => '',          # Mountpoint
        itunes_db => '',    # iTunes DB
        gnupod_db => '',    # GNUpod DB
        allow_dup => 0,     # Whether duplicates are allowed
        move_files => 1,    # Whether to actually move files on add or rm
        files => [],        # List of file hrefs
        idx => {},          # Indexes of song properties (for searching)
        plorder => [],      # List of playlists in order
        pl_idx => {},       # Playlists by name
        spl_idx => {}       # Smartplaylists by name
    };

    bless $self, $class;

    if ($opt{mountpoint}) {
        $self->mountpoint($opt{mountpoint});
    }
    elsif ($opt{itunes_db} && $opt{gnupod_db}) {
        $self->itunes_db($opt{itunes_db});
        $self->gnupod_db($opt{gnupod_db});
    }
    else {
        croak "Either the mountpoint or both the itunes_db and gnupod_db options required";
    }

    return $self;
}

sub mountpoint {
    my $self = shift;
    if (@_) {
        $self->{mnt} = shift;
        $self->{itunes_db} = $self->{mnt}."/iPod_Control/iTunes/iTunesDB";
        $self->{gnupod_db} = $self->{mnt}."/iPod_Control/.gnupod/GNUtunesDB";
    }
    return $self->{mnt};
}

for my $flag (@flags) {
    no strict 'refs';
    *$flag = sub {
        my $self = shift;
        if (@_) {
            $self->{$flag} = shift;
        }
        return $self->{$flag};
    };
}

# Format a new iPod, create directory structure, prepare for GNUpod
sub init {
    my ($self, %opts) = @_;

    if (not $self->{mnt}) {
        croak "Can't init iPod without the mountpoint set";
    }

    # Folder structure
    foreach( ("Calendars", 'Contacts', 'Notes', "iPod_Control", "iPod_Control/Music",
             "iPod_Control/iTunes", 'iPod_Control/Device', "iPod_Control/.gnupod") ) {
        my $path = "$self->{mnt}/$_";
        next if -d $path;
        mkdir("$path") or croak "Could not create $path ($!)\n";
    }

    # Music folders
    for(0..19) {
        my $path = sprintf("$self->{mnt}/iPod_Control/Music/F%02d", $_);
        next if -d $path;
        mkdir("$path") or croak "Could not create $path ($!)\n";
    }

    # Limit file - why is this here?
    if($opts{france}) {
        open(LIMIT, ">$self->{mnt}/iPod_Control/Device/Limit") or croak "Failed creating limit file: $!\n";
        print LIMIT "216\n"; #Why?
        close(LIMIT);
    }
    elsif(-e "$self->{mnt}/iPod_Control/Device/Limit") {
        unlink("$opts{mount}/iPod_Control/Device/Limit");
    }

    # Convert iTunes db if allowed
    if(-e $self->{itunes_db} && !$opts{'noconvert'}) {
        $self->read_itunes;
    }

    # Make empty db otherwise
    else {
        open(ITUNES, ">", $self->{itunes_db}) or croak "Could not create $self->{itunes_db}: $!\n";
        print ITUNES "";
        close(ITUNES);
    }

    $self->write_gnupod;

    return 1;
}

# Convert iTunesDB to GNUpodDB
#
# This function almost entirely copyright (C) 2002-2003 Adrian Ulrich. Adapted
# from tunes2pod.pl in the GNUpod toolset
sub read_itunes {
    my ($self) = @_;

    require Mac::iPod::GNUpod::iTunesDBread or die;

    $self->_clear;

    Mac::iPod::GNUpod::iTunesDBread::open_itunesdb($self->{itunes_db}) 
        or croak "Could not open $self->{itunes_db}";

    #Check where the FILES and PLAYLIST part starts..
    #..and how many files are in this iTunesDB
    my $itinfo = Mac::iPod::GNUpod::iTunesDBread::get_starts();
    
    # These 2 will change while running..
    my $pos = $itinfo->{position};
    my $pdi = $itinfo->{pdi};

    #Get all files
    for my $i (0 .. ($itinfo->{songs} - 1)) {
        ($pos, my $href) = Mac::iPod::GNUpod::iTunesDBread::get_mhits($pos); #get the mhit + all child mhods
        #Seek failed.. this shouldn't happen..  
        if($pos == -1) {
            croak "FATAL: Expected to find $itinfo->{data} files, failed to get nr. $i";
        }
        $self->_addfile($href);  
    }

    #Now get each playlist
    for my $i (0 .. ($itinfo->{playlists} - 1)) {
        ($pdi, my $href) = Mac::iPod::GNUpod::iTunesDBread::get_pl($pdi); #Get an mhyp + all child mhods
        if($pdi == -1) {
            croak "FATAL: Expected to find $itinfo->{playlists} playlists, I failed to get nr. $i";
        }
        next if $href->{type}; #Don't list the MPL
        $href->{name} = "NONAME" unless($href->{name}); #Don't create an empty pl

        #SPL Data present
        if(ref($href->{splpref}) eq "HASH" && ref($href->{spldata}) eq "ARRAY") { 
            $self->_render_spl($href->{name}, $href->{splpref}, $href->{spldata}, $href->{matchrule}, $href->{content});
        }

        #Normal playlist 
        else { 
            $self->_addpl($href->{name});
            # Render iPod pls in GNUpod format
            $self->_addtopl($self->{cur_pl}, { add => { id => $_ } }) foreach @{$href->{content}};
        }
    }

    # Close the db
    Mac::iPod::GNUpod::iTunesDBread::close_itunesdb();
}

# Parse the GNUpod db (in XML)
sub read_gnupod {
    my ($self, %opts) = shift;
    unless (-r $self->{gnupod_db}) {
        croak "Can't read GNUpod database at $self->{gnupod_db}";
    }

    $self->_clear;

    # Call _eventer as a method
    my $wrapper = sub { $self->_eventer(@_) };

    my $p = new XML::Parser( Handlers => { Start => $wrapper });
    $p->parsefile($self->gnupod_db);
}

# Write the iTunes Db
#
# This code adapted from the mktunes.pl script, copyright (C) 2002-2003 Adrian
# Ulrich.
sub write_itunes {
    my $self = shift;

    require Mac::iPod::GNUpod::iTunesDBwrite or die;
 
    # Undocumented, used only for debugging
    my %opt = @_;
    $opt{name} = 'GNUpod' unless $opt{name};

    my ($curid, %data, %length, %ids);

    # Create mhits and mhods for all files
    for (@{$self->{files}}) {
        next if not $_ or not keys %$_;
        # iTunes ID and GNUpod ID are NOT necessarily the same!  So we build a
        # hash of GNUpod => iTunes ids for translating playlists
        $ids{$_->{id}} = ++$curid;

        $data{mhit} .= Mac::iPod::GNUpod::iTunesDBwrite::render_mhit($_, $curid);
    }
    $length{mhit} = length($data{mhit});

    # Create header for mhits
    $data{mhlt} = Mac::iPod::GNUpod::iTunesDBwrite::mk_mhlt({ songs => $curid });
    $length{mhlt} = length($data{mhlt});

    # Create header for the mhlt
    $data{mhsd_1} = Mac::iPod::GNUpod::iTunesDBwrite::mk_mhsd({
        size => $length{mhit} + $length{mhlt},
        type => 1
    });
    $length{mhsd_1} = length($data{mhsd_1});

    # Create the master playlist
    ($data{playlist}, $curid) = Mac::iPod::GNUpod::iTunesDBwrite::r_mpl(
        name => $opt{name},
        ids => [ 1 .. $curid ],
        type => 1,
        curid => $curid
    );

    # Create child playlists
    for my $plname (@{$self->{plorder}}) {
        my %common = ( name => $plname, type => 0, curid => $curid );
        if (my $spl = $self->get_spl($plname)) {
            (my $dat, $curid) = Mac::iPod::GNUpod::iTunesDBwrite::r_mpl(
                %common, 
                splprefs => $spl->{pref},
                spldata => $spl->{data}
            );
            $data{playlist} .= $dat;
        }
        else {
            (my $dat, $curid) = Mac::iPod::GNUpod::iTunesDBwrite::r_mpl(
                %common, 
                # Here's where we use %ids: translate the GNUpod ids given by
                # _render_pl to the iTunes ids
                ids => [ @ids{$self->_render_pl($plname)} ]
            );
            $data{playlist} .= $dat;
        }
    }
    $data{playlist} = Mac::iPod::GNUpod::iTunesDBwrite::mk_mhlp({ playlists => scalar @{$self->{plorder}} + 1  }) . $data{playlist};
    $length{playlist} = length($data{playlist});

    # Make pl headers
    $data{mhsd_2} = Mac::iPod::GNUpod::iTunesDBwrite::mk_mhsd({ size => $length{playlist}, type => 2 });
    $length{mhsd_2} = length($data{mhsd_2});

    # Calculate total file length
    my $totlength = 0;
    $totlength += $_ for values %length;

    # Make master header
    $data{mhbd} = Mac::iPod::GNUpod::iTunesDBwrite::mk_mhbd({ size => $totlength });

    # Debug me!
    if ($opt{dump}) {
        use Data::Dumper;
        open DUMP, '>', $opt{dump} or croak "Couldn't open dump file: $!";
        print DUMP Dumper(\%data);
        close DUMP;
    }

    # Write it all
    open IT, '>', $self->{itunes_db} or croak "Couldn't write iTunes DB: $!";
    binmode IT;
    for ('mhbd', 'mhsd_1', 'mhlt', 'mhit', 'mhsd_2', 'playlist') {
        no warnings 'uninitialized'; # In case one of these is empty
        print IT $data{$_};
    }
    close IT;
}

# Write the GNUpod DB XML File
sub write_gnupod {
    my($self) = @_;
    open(OUT, ">$self->{gnupod_db}") or croak "Could not write $self->{gnupod_db}: $!\n";
    binmode OUT ;
    my $oldfh = select OUT;

    print "<?xml version='1.0' standalone='yes'?>\n";
    print "<gnuPod>\n";

    # Write the files section
    print "\t<files>\n";
    for (@{$self->{files}}) {
        next if not $_ or not keys %$_;
        delete $_->{notorig}; # Don't ever write this to XML
        print "\t\t", mktag("file", $_), "\n";
    }
    print "\t</files>\n";

    #Print all playlists
    foreach (@{$self->{plorder}}) {
        my ($name, $href);
        if ($href = $self->get_spl($_)) {
            $name = "smartplaylist";
        }
        elsif ($href = $self->get_pl($_)) {
            $name = "playlist";
        }
        else {
            carp "Unknown playlist $name";
            next;
        }

        print "\t" . mktag($name, $href->{pref}, noend => 1) . "\n";
        foreach my $item (@{$href->{data}}) {
            for (keys %$item) {
                next if not keys %{$item->{$_}};
                print "\t\t", mktag($_, $item->{$_}), "\n";
            }
        }
        print "\t</$name>\n";
    }
    print "</gnuPod>\n";
    select $oldfh;
    close OUT ;
}
                
# Restore an iPod w/ corrupted dbs
sub restore {
    my ($self, %opts) = @_;
    if (not defined $self->{mnt}) {
        croak "Can't restore iPod without mountpoint set";
    }

    local $self->{move_files} = 0;
    local $self->{allow_dup} = 1;
    local $self->{restore} = 1;
    $self->_clear;
    $self->add_song(glob($self->{mnt}.'/iPod_Control/Music/*/*'));
}

# Add a song to the ipod
sub add_song {
    my ($self, @songs) = @_;
    my @newids;

    foreach (@songs) {
        # Get the magic hashref
        my $fh = Mac::iPod::GNUpod::FileMagic::wtf_is($_);
        if (not $fh) {
            carp "Skipping '$_'";
            next;
        }

        # Get the path, etc.
        ($fh->{path}, my $target) = $self->_getpath($_);

        # Check for duplicates
        unless ($self->allow_dup) {
            if (my $dup = $self->_chkdup($fh)) {
                carp "'$_' is a duplicate of song $dup, skipping";
                next;
            }
        }

        # Copy the file
        if (defined $self->{mnt} and $self->move_files) {
            unless (File::Copy::copy($_, $target)) {
                carp "Couldn't copy $_ to $target: $!, skipping";
                next;
            }
        }

        # Add this to our list of files
        push @newids, $self->_newfile($fh);
    }

    return @newids;
}

# Remove a song from the ipod
sub rm_song {
    my ($self, @songs) = @_;
    my $rmcount = 0;

    foreach my $id (@songs) {
        if (not exists $self->{files}->[$id]) {
            carp "No song with id $id";
            next;
        }

        if (defined $self->{mnt} and $self->move_files) {
            my $path = realpath($self->{mnt}, $self->{files}->[$id]->{path});
            unless (unlink $path) {
                carp "Remove failed for song $id ($path): $!";
                next;
            }
        }


        my $gone = delete $self->{files}->[$id];
        $rmcount++;

        # Get rid of index entries, dupdb
        no warnings 'uninitialized';
        delete $self->{dupdb}->{"$gone->{bitrate}/$gone->{time}/$gone->{filesize}"};
        for (keys %{$self->{idx}}) {
            my @list = @{$self->{idx}{$_}{$gone->{$_}}};
            for (my $i = 0; $i < @list; $i++) {
                if ($list[$i] eq $id) {
                    splice @list, $i, 1;
                }
            }
            if (@list) {
                $self->{idx}{$_}{$gone->{$_}} = \@list;
            }
            else {
                delete $self->{idx}{$_}{$gone->{$_}};
            }
        }
    }

    return $rmcount;
}

# Get a song by id
sub get_song {
    my ($self, @ids) = @_;
    return @{$self->{files}}[@ids];
}

# Get the real path to a song by id
sub get_path {
    my ($self, @ids) = @_;
    return unless defined $self->{mnt};
    return map { realpath($self->{mnt}, $self->{files}->[$_]->{path}) } @ids;
}

# Get all songs
sub all_songs {
    my ($self) = @_;
    return grep { defined $self->{files}->[$_] } 1 .. $#{$self->{files}};
}

# Get a pl by name
sub get_pl {
    my ($self, @names) = @_;
    return @{$self->{pl_idx}}{@names};
}

# Get an spl by name
sub get_spl {
    my ($self, @names) = @_;
    return @{$self->{spl_idx}}{@names};
}

# Get a list of ids by search terms
sub search {
    my ($self, %terms) = @_;

    # Pick opts out from terms
    my %opts;
    for ('nocase', 'nometachar', 'exact') {
        $opts{$_} = delete $terms{$_};
    }

    # Main searches
    my %count;
    my $term = 0;
    while (my ($key, $val) = each %terms) {
        for my $idxval (keys %{$self->{idx}->{$key}}) {
            if (matches($idxval, $val, %opts)) {
                $count{$_}++ for @{$self->{idx}->{$key}->{$idxval}};
            }
        }
        $term++;
    }

    # Get the list of everyone that matched
    # Sort by Artist > Album > Cdnum > Songnum > Title
    return 
        sort {
            $self->{files}->[$a]->{uniq} cmp $self->{files}->[$b]->{uniq}
        } grep { 
            $count{$_} == $term 
        } keys %count;
}

# Clear the ipod db
sub _clear {
    my $self = shift;
    $self->{files} = [];
    $self->{idx} = {};
    $self->{plorder} = [];
    $self->{pl_idx} = {};
    $self->{spl_idx} = {};
}

# Add a new file to db and list
sub _newfile {
    my ($self, $file) = @_;

    # Find the first open index slot
    my $idx = 1;
    $idx++ while defined $self->{files}->[$idx];
    $file->{id} = $idx;

    $self->_addfile($file);
}

# Add info from a file in the db
sub _addfile {
    my ($self, $file) = @_;
    no warnings 'uninitialized';

    # Check for bad path
    {
        # Get the real path
        my $rpath;
        if ($self->{mnt} && $self->move_files) {
            $rpath = realpath($self->{mnt}, $file->{path});
            
        }
        last if not $rpath;

        my $errst;
        if (not -e $rpath) {
            $errst = "File does not exist ($rpath)";
        }
        if (-d $rpath) {
            $errst = "Path is a directory ($rpath)";
        }
        if ($errst) {
            carp $errst;
            return;
        }

    }
    
    
    # Check for bad ids
    {
        my $badid;
        if ($file->{id} < 1) {
            $file->{id} = 'MISSING' if not exists $file->{id};
            carp "Bad id ($file->{id}) for file";
            $badid = 1;
        }
        elsif (defined $self->{files}->[$file->{id}]) {
            carp "Duplicate song id ($file->{id})";
            $badid = 1;
        }

        if ($badid) {
            # Attempt to rescue w/ newfile (which re-assigns id)
            if (my $r = $self->_newfile($file)) {
                carp " ...fixed";
                # Note that this song does not have its original id
                $self->{files}->[$r]->{notorig} = 1;
                return $r;
            }
            # Getting here is bad failure
            return;
        }
    }
        
    # Make duplicate index
    $self->{dupdb}->{"$file->{bitrate}/$file->{time}/$file->{filesize}"} = $file->{id};

    # Add a uniq for sorting
    $file->{uniq} = sprintf "%s|%s|%02d|%02d|%s|%s",
        $file->{artist}, $file->{album}, $file->{cdnum}, $file->{songnum}, $file->{title}, $file->{path};

    # Add to file index
    $self->{files}->[$file->{id}] = $file;

    # Make indexes, convert to utf8
    for (keys %$file) {
        # Don't index the id or uniq (redundant!)
        next if $_ eq 'id' or $_ eq 'uniq';
        push @{$self->{idx}->{$_}->{$file->{$_}}}, $file->{id};
    }

    return $file->{id};
}

# Check if two files are duplicates
sub _chkdup {
    my ($self, $fh) = @_;
    no warnings 'uninitialized';
    return $self->{dupdb}->{"$fh->{bitrate}/$fh->{time}/$fh->{filesize}"};
}

# Add a playlist
sub _addpl {
    my($self, $name, $opt) = @_;

    if($self->get_pl($name)) {
        carp "Playlist '$name' is a duplicate, not adding it";
        return;
    }
    $self->{pl_idx}->{$name}->{pref} = $opt;
    $self->{cur_pl} = $self->{pl_idx}->{$name}->{data} = [];
    push(@{$self->{plorder}}, $name);
}

# Add a smart playlist
sub _addspl {
    my($self, $name, $opt) = @_;

 
    if($self->get_spl($name)) {
        carp "Playlist '$name' is a duplicate, not adding it";
        return;
    }
    $self->{spl_idx}->{$name}->{pref} = $opt;
    $self->{cur_pl} = $self->{spl_idx}->{$name}->{data} = [];
    push(@{$self->{plorder}}, $name);
}

# Add a file to a playlist
sub _addtopl {
    my ($self, $pl, $href) = @_;
    push @$pl, $href;
}

# create a spl
sub _render_spl {
    my($self, $name, $pref, $data, $mr, $content) = @_;
    my $of = {};
    $of->{liveupdate} = $pref->{live};
    $of->{moselected} = $pref->{mos};
    $of->{matchany}   = $mr;
    $of->{limitsort} = $pref->{isort};
    $of->{limitval}  = $pref->{value};
    $of->{limititem} = $pref->{iitem};
    $of->{checkrule} = $pref->{checkrule};

    #create this playlist
    $self->_addspl($name, $of);
}

# Create a filled-out pl (replacing 'add' and 'regex' entries w/ ids)
sub _render_pl {
    my ($self, $name) = @_;
    my @list;

    for my $item (@{$self->{pl_idx}->{$name}->{data}}) {
        # Exact id numbers
        if (exists $item->{add}) {
            if (exists $item->{add}->{id}) {
                my $id = $item->{add}->{id};
                if (exists $self->{files}->[$id]) {
                    if ($self->{files}->[$id]->{notorig}) {
                        carp "Song id $id in playlist '$name' has changed id numbers, may not be intended song";
                    }
                    push @list, $id;
                }
                else {
                    carp "Error in playlist '$name': no song with id $id";
                }
            }
            else {
                push @list, $self->search(%{$item->{add}}, nometachar => 1);
            }
        }
        elsif (exists $item->{regex}) {
            push @list, $self->search(%{$item->{regex}});
        }
        elsif (exists $item->{iregex}) {
            push @list, $self->search(%{$item->{iregex}}, nocase => 1);
        }
    }

    return @list;
}

#Get all playlists
sub _getpl_names {
    my $self = shift;
    return @{$self->{plorder}};
}

# Call events (event handler for XML::Parser)
sub _eventer {
    my $self = shift;
    my($href, $el, %it) = @_;
    no warnings 'uninitialized';

    return undef unless $href->{Context}[0] eq "gnuPod";

    # Warnings for elements that should have attributes
    if ( (     $href->{Context}[1] eq 'files'
            || $href->{Context}[1] eq 'playlist' 
            || $href->{Context}[1] eq 'smartplaylist') 
            && not keys %it) {
        carp "No attributes found for <$el /> tag";
        return;
    }

    # Convert all to utf8
    for (keys %it) {
        $it{$_} = Unicode::String::utf8($it{$_})->utf8;
    }

    # <file ... /> tags
    if($href->{Context}[1] eq "files") {
        if ($el eq 'file') {
            $self->_addfile(\%it);
        }
        else {
            carp "Warning: found improper <$el> tag inside <files> tag";
        }
    } 

    # <playlist ..> tags
    elsif($href->{Context}[1] eq "" && $el eq "playlist") {
        $it{name} = "NONAME" unless $it{name};
        $self->_addpl($it{name}, \%it); #Add this playlist
    }

    # <add .. /> tags inside playlist
    elsif($href->{Context}[1] eq "playlist") {
        $self->_addtopl($self->{cur_pl}, { $el => \%it }); #call sub
    }

    # <smartplaylist ... > tags
    elsif($href->{Context}[1] eq "" && $el eq "smartplaylist") {
        $it{name} = "NONAME" unless $it{name};
        $self->_addspl($it{name}, \%it);
    }

    # <add .. /> tags inside smartplaylist
    elsif($href->{Context}[1] eq "smartplaylist") {
        if (not keys %it) {
            carp "No attributes found for <$el /> tag";
            return;
        }
        $self->_addtopl($self->{cur_pl}, { $el => \%it }); #call sub
    }
}

# Get an iPod-safe path for filename
sub _getpath {
    my($self, $filename) = @_;
    my $path;

    if (not $self->move_files) { #Don't create a new filename..
        $path = $filename;
    }
    else { #Default action.. new filename to create 
        my $name = (split(/\//, $filename))[-1];
        my $i = 0;
        $name =~ tr/a-zA-Z0-9\./_/c; 
        #Search a place for the MP3 file
        while($path = sprintf("$self->{mnt}/iPod_Control/Music/F%02d/%d_$name", int(rand(20)), $i++)) {
            last unless(-e $path);
        }
    }

    #Remove mountpoint from $path
    my $ipath = $path;
    $ipath =~ s/^$self->{mnt}(.+)/$1/;

    #Convert /'s to :'s for ipath
    $ipath =~ tr/\//:/;
    return ($ipath, $path);
}

1;

__END__

=head1 DESCRIPTION

Mac::iPod::GNUpod is a module designed to let you read the database(s) on your
iPod and add and remove songs from it using Perl. It is based on the GNUpod
script package written by Adrian Ulrich, which is available at
L<http://www.gnu.org/software/gnupod/>. You do NOT need to install the GNUpod
scripts in order to use Mac::iPod::GNUpod module.  The GNUpod scripts use a
plaintext XML database alongside the binary iTunes database used internally by
the iPod. This package is capable of reading and writing both the GNUpod
database format and the iTunes database format, and can peacefully coexist with
both. 

Currently this module ONLY works with Unix and Unix-like systems. This probably
includes Linux, FreeBSD, MacOS 10.x, and Solaris. OS-independence will come,
someday.

Note that the GNUpod database format, the original GNUpod package, and much of
the code in this module is (c) Adrian Ulrich.

This module is object oriented. A brief description of the methods needed to
perform various tasks follows:

=head2 Preparing a blank or corrupted iPod

Your iPod must be formatted and mounted for this module to see it. It can be
formatted in FAT32 (Windows) or HFS+ (Mac) format, just so long as your kernel
supports it.

If your iPod is fresh out of the box, probably nothing needs to be
done, but if its file structure has been corrupted you should initialize it
with the L<"init"> method.

If your databases have been lost or corrupted, you may use the L<"restore">
method to find and all of the songs on the iPod and rewrite fresh databases.

=head2 Reading and writing databases

You can read and write the iTunes DBs with the L<"read_itunes"> and
L<"write_itunes"> methods respectively. Conversely, the GNUpod DBs are accessed
with L<"read_gnupod"> and L<"write_gnupod">.

The advantage of the GNUpod DB is that it can be read and written many times
faster than the iTunes DB can, so your scripts will run much faster than if you
use only the iTunes format. The following scripts are functionally identical:

A:

    my $ipod = Mac::iPod::GNUpod->new(mountpoint => '/mnt/ipod');

    $ipod->read_itunes;

    # Etc ...

    $ipod->write_itunes;

B:

    my $ipod = Mac::iPod::GNUpod->new(mountpoint => '/mnt/ipod');

    $ipod->read_gnupod;

    # Etc ...

    $ipod->write_gnupod;
    $ipod->write_itunes;

However, in benchmarks B runs about twice as fast as A, because the gain of
speed reading the GNUpod DB outweighs the cost of the extra write step. (Of
course, the significance of this depends on what you do in the middle.)

=head2 Adding and removing songs

Add songs with L<"add_song">. Remove songs with L<"rm_song">.

=head2 Finding existing songs

You can search for existing songs on your iPod with the L<"search"> method. If
you want a list of all songs, use L<"all_songs">.

=head2 Working with playlists

There are currently no methods for manipulating playlists. However, the GNUpod
DB format makes it easy to create playlists by editing the DB file by hand, and
GNUpod playlists are fully supported by this module. Read more about making
playlists with GNUpod at L<http://www.gnu.org/software/gnupod/>.

=head1 METHODS

=head2 new

    my $ipod = Mac::iPod::GNUpod->new(mountpoint => '/mnt/ipod');

You create a new iPod object with new(). You must supply key-value pairs as
arguments. Most of the time you will only provide the C<mountpoint> key, which
indicates where the iPod is mounted. However, if your iPod structure is
nonstandard or you wish to test without writing to the actual iPod, you may
provide both the C<gnupod_db> and C<itunes_db> keys with values indicating the
locations of those files.

=head2 mountpoint

    my $mnt = $ipod->mountpoint;
    $ipod->mountpoint('/mnt/ipod2');

You may use this method to get the current mountpoint for the iPod. If you
provide an argument, it sets the mountpoint. When you use this method to set
the mountpoint, it automatically sets the C<itunes_db> and C<gnupod_db>,
potentially overwriting values you may have previously had there.

=head2 itunes_db

    my $itunes = $ipod->itunes_db;
    $ipod->itunes_db('/home/ipod/testdb');

Use this method to get/set the location of the iTunes DB, if it is different
from the default location on the iPod. The default location is
C<{mountpoint}/iPod_Control/iTunes/iTunesDB>.

=head2 gnupod_db

    my $gnupod = $ipod->gnupod_db;
    $ipod->gnupod_db('/home/ipod/gnupod.xml');

Use this method to get/set the location of the GNUpod DB, if it is different
from the default location. The default location is
C<{mountpoint}/iPod_Control/.gnupod/GNUtunesDB>.

=head2 allow_dup

    $ipod->allow_dup(1);

Get/set the flag stating whether duplicate songs are allowed. If this is false,
when you call C<add_song>, this module will check for duplicates in the DB and
refuse to add the song if a duplicate is found. If true, no duplicate checking
is done. Default is FALSE.

=head2 move_files

    $ipod->move_files(0);

Get/set the flag stating whether or not to actually (re)move files. If true,
when you call C<add_song> or C<rm_song>, the files will actually be copied or
deleted. If false, the songs will simply be added or removed from the database,
but the file contents of your iPod will not be changed. Default is TRUE. 

=head2 init

    $ipod->init;

Initialize a blank or empty iPod. NOTE: this method only pays attentiont to
C<mountpoint>. The only arguments to this method are optional key-value pairs
naming options. Currently the only option recognized is C<france>, which causes
a limit file to be created if true. (This method is equivalent to the
C<gnupod_INIT.pl> script, and the C<france> option is equivalent to the
C<--france> command-line option.)

=head2 restore

    $ipod->restore;

Restore an iPod with corrupted databases. This scans the files on the iPod and
rebuilds the databases with the files it finds. (This is equivalent to the
C<gnupod_addsong.pl> script with the C<--restore> option.

=head2 read_itunes

    $ipod->read_itunes;

Read an iTunes database (found at C<itunes_db>) into memory. Note that this
will forget any iTunes or GNUpod DB previously read.

=head2 write_itunes

    $ipod->write_itunes;

Write the contents of memory to the iTunes DB. You should do this at the end of
any script if you want your newly added or deleted songs to be available!

=head2 read_gnupod

    $ipod->read_gnupod;

Read the GNUpod database into memory. This also forgets any databases
previously read.

=head2 write_gnupod

    $ipod->write_gnupod;

Write the GNUpod database. If you want to use any GNUpod tools with the iPod,
you should write this db at the end of any script.

=head2 add_song

    $ipod->add_song('/home/music/The Cure - Fascination Street.mp3');

Add a song to the iPod. Takes one or more arguments, which are the filenames of
songs to be added. Currently only MP3 and WAV files are supported,
unfortunately, and trying to add a song of another type will bring up a
warning. On success, this method returns the new id number(s) of the song, on
failure returns undef.

=head2 rm_song

    $ipod->rm_song(256);

Remove a song from the iPod. Takes one or more arguments, which are the id
numbers of the songs to be removed. (You can find the id numbers of songs using
the C<search> method.) Returns the number of songs successfully removed.

=head2 get_song

    $ipod->get_song(256);

Get information about a song. Takes one or more arguments, which are the id
numbers of songs. Returns a hash reference (or a list of hash references) with
the following keys:

=over 4

=item * id

=item * artist

=item * album

=item * title

=item * songnum

=item * songs

=item * cdnum

=item * cds

=item * composer

=item * year

=item * genre

=item * fdesc

A brief description of the file type

=item * filesize

=item * bitrate

=item * time

Playing time in milliseconds

=item * srate

The frequency in hertz

=item * playcount

=item * path

The iPod-formatted path. To get a path in Unix format, use L<"get_path">.

=back

=head2 get_path

    $path = $ipod->get_path(256);

Get a Unix-formatted path. Takes a list of ids as arguments, returns a list of
paths to the songs with those ids. If C<mountpoint> isn't set, returns undef.

BUG/FEATURE: If you try to get the path of a song that was added while
C<move_files> was false, you will probably get garbage.

=head2 search

    $ipod->search(artist => 'Bob Dylan', title => 'watchtower', nocase => 1);

Search for songs on the iPod. The argument to this function is a hash of key =>
value pairs that give attributes that the returned songs will match. You may
search on any of the keys that appear in the hashref returned from C<get_song>
(listed above). You may specify multiple keys, in which case the songs returned
must match ALL of the values specified. By default, searches are regexes, which
means that searching for C<< artist => 'Cure' >> will return songs labeled
'Cure', 'The Cure', 'Cure, The', and 'Cured!' You may also use regex
metacharacters in your values, like C<< title => '[Tt]he' >>. A list of id
numbers is returned, which can be used with C<get_song> to get the complete
information about a song.

You may also alter the behavior of the search by using special optional keys.
These keys are:

=over 4

=item * exact

Only return songs that match the given terms EXACTLY. This tests using C<eq>
instead of a regular expression, and so may be much faster.

=item * nocase

Perform a case-insensitive search. This is not mutually exclusive with
C<exact>; using both of them searches for things that are identical except with
regard to case.

=item * nometachar

Ignore regular expression metacharacters in the values given.

=back

The search results are returned to you sorted by Artist > Album > Cdnum >
Songnum > Title.

=head2 all_songs

    $ipod->all_songs;

Return a list of all of the song ids on the iPod.

=head1 NOTES

The GNUpod XML file is expected to be encoded in UTF-8. Other encodings will
probably work as well (UTF-16 has been tried successfully), but Your Mileage
May Vary.

Playlists that contain <add /> elements that don't have id attributes, <regex
/> elements, or <iregex /> elements may produce songs in a different order than
the order produced by the GNUpod script mktunes.pl. This is because mktunes.pl
simply adds matching songs to the playlist in the order that it finds them,
while this module sorts them by artist, album, cdnum, tracknum, and title. What
the module does is better :).

=head1 TODO

Add methods for manipulating playlists.

Add support for more filetypes, particularly .aac files.

=head1 BUGS

Smartplaylist support is untested, so it's entirely possible that this module
will munge your smartplaylists (though it tries not to).

Turning C<move_files> on and off during the life of a script may have strange
results.

=head1 AUTHOR

Original GNUpod scripts by Adrian Ulrich <F<pab at blinkenlights.ch>>.
Adaptation for CPAN and much code rewriting by JS Bangs <F<jaspax@cpan.org>>.

=head1 VERSION

v. 1.0, Jan 09 2004.

=head1 LICENSE

The GNUpod scripts are released under the GNU Public License (GPL). This module
adaptation is released under the same terms as Perl itself (a conjunction of
the GPL and the Artistic License).

iTunes and iPod are trademarks of Apple. This module is neither written nor
supported by Apple.

=cut
