package Mac::iPod::GNUpod::FileMagic;
#  This file is pretty much copied wholesale from the FileMagic.pm present in
#  the GNUpod toolset. The original copyright is: Copyright (C) 2002-2003
#  Adrian Ulrich <pab at blinkenlights.ch> Part of the gnupod-tools collection
#  (http://www.gnu.org/software/gnupod).
#
#  Adaptation for CPAN by JS Bangs <jaspax at glossopoesis.org>.

use warnings;
use strict; 
use Carp;
use Unicode::String; 
use MP3::Info qw(:all); 
use Mac::iPod::GNUpod::Utils;

BEGIN {
    MP3::Info::use_winamp_genres();
    MP3::Info::use_mp3_utf8(0);
    #open(NULLFH, "> /dev/null") or die "Could not open /dev/null, $!\n";
}

#Try to discover the file format (mp3 or QT (AAC) )
sub wtf_is {
    my($file) = @_;
    my $h;
    if($h = __is_mp3($file)) {
        return $h;
    }
    elsif($h = __is_pcm($file)) {
        return $h
    }
    elsif(__is_qt($file)) {
        carp "QT File (AAC) detected: $file\n";
    }
    else {
        carp "Unsupported file type: $file\n";
    }
    return undef;
}

# This will be filled out someday
sub __is_qt {
    my($file) = @_;
    return undef;
}

# Check if the file is an PCM (WAVE) File
# FIXME : There's probably some CPAN module that does this. Check around.
sub __is_pcm {
    my($file) = @_;

    open(PCM, "$file") or return;
    #Get the group id and riff type
    my ($gid, $rty);
    seek(PCM, 0, 0);
    read(PCM, $gid, 4);
    seek(PCM, 8, 0);
    read(PCM, $rty, 4);

    return undef unless($gid eq "RIFF" && $rty eq "WAVE");

    #Ok, maybe a wave file.. try to get BPS and SRATE
    my $size = -s $file;
    return undef if ($size < 32); #File to small..

    my ($bs) = undef;
    seek(PCM, 24,0);
    read(PCM, $bs, 4);
    my $srate = shx2int($bs);

    seek(PCM, 28,0); 
    read(PCM, $bs, 4);
    my $bps = shx2int($bs);

    #Check if something went wrong..
    if($bps < 1 || $srate < 1) {
    # warn "FileMagic.pm: Looks like '$file' is a crazy pcm-file: bps: *$bps* // srate: *$srate* -> skipping!!\n";
    return undef;
    }

    # FIXME
    # warn "FileMagic: debug: bps -> *$bps* / srate -> *$srate*\n";   
    my %rh = ();
    $rh{bitrate}  = $bps;
    $rh{filesize} = $size;
    $rh{srate}    = $srate;
    $rh{time}     = int(1000*$size/$bps);
    $rh{fdesc}    = "RIFF Audio File";

    # FIXME
    #No id3 tags for us.. but mmmmaybe...
    #We use getuft8 because you could use umlauts and such things :)  
    $rh{title}    = getutf8(((split(/\//, $file))[-1]) || "Unknown Title");
    $rh{album} =    getutf8(((split(/\//, $file))[-2]) || "Unknown Album");
    $rh{artist} =   getutf8(((split(/\//, $file))[-3]) || "Unknown Artist");


    return \%rh;
}

# Read mp3 tags, return undef if file is not an mp3
sub __is_mp3 {
    my($file) = @_;

    my $h = MP3::Info::get_mp3info($file);
    return undef unless $h; #No mp3

    #This is our default fallback:
    #If we didn't find a title, we'll use the
    #Filename.. why? because you are not able
    #to play the file without a filename ;)
    my $cf = ((split(/\//,$file))[-1]);

    my %rh = ();

    $rh{bitrate} = $h->{BITRATE};
    $rh{filesize} = $h->{SIZE};
    $rh{srate}    = int($h->{FREQUENCY}*1000);
    $rh{time}     = int($h->{SECS}*1000);
    $rh{fdesc}    = "MPEG $h->{VERSION} layer $h->{LAYER} file";
    $h = MP3::Info::get_mp3tag($file,1);  #Get the IDv1 tag
    my $hs = MP3::Info::get_mp3tag($file, 2, 2); #Get the IDv2 tag

    # If any of these are array refs (multiple values), take last value
    for (keys %$hs) {
        if (ref($hs->{$_}) eq 'ARRAY') {
            $hs->{$_} = $hs->{$_}->[-1];
        }
    }

    #IDv2 is stronger than IDv1..
    #Try to parse things like 01/01
    no warnings 'uninitialized';
    no warnings 'numeric';
    my @songa = pss(getutf8($hs->{TRCK} || $h->{TRACKNUM}));
    my @cda   = pss(getutf8($hs->{TPOS}));
    $rh{songs}    = int($songa[1]);
    $rh{songnum} =  int($songa[0]);
    $rh{cdnum}   =  int($cda[0]);
    $rh{cds}    =   int($cda[1]);
    $rh{year} =     getutf8($hs->{TYER} || $h->{YEAR} || 0);
    $rh{title} =    getutf8($hs->{TIT2} || $h->{TITLE} || $cf || "Untitled");
    $rh{album} =    getutf8($hs->{TALB} || $h->{ALBUM} || "Unknown Album");
    $rh{artist} =   getutf8($hs->{TPE1} || $h->{ARTIST}  || "Unknown Artist");
    $rh{genre} =    getutf8(               $h->{GENRE}   || "");
    $rh{comment} =  getutf8($hs->{COMM} || $h->{COMMENT} || "");
    $rh{composer} = getutf8($hs->{TCOM} || "");
    $rh{playcount}= int(getutf8($hs->{PCNT})) || 0;

    return \%rh;
}

# Guess format
sub pss {
    my($string) = @_;
    no warnings 'numeric';
    if(my($s,$n) = $string =~ m!(\d+)/(\d+)!) {
        return int($s), int($n);
    }
    else {
        return int($string);
    }
}

# Try to 'auto-guess' charset and return utf8.  FIXME--Surely there's something
# CPAN-wise that'll do this? This is hideous.
sub getutf8 {
    my($in) = @_;

    no warnings 'uninitialized';
    my $encoding = substr $in, 0, 1;
    if(ord($encoding) > 0 && ord($encoding) < 32) {
        carp "Unsupported ID3 encoding found: " .ord($encoding)."\n";
        return;
    }
    else { #AutoGuess (We accept invalid id3tags)
        #Remove all 00's
        $in =~ tr/\0//d;
        no warnings; # Hopefully this works better than the hack below
        #my $oldstderr = *STDERR; #Kill all utf8 warnings.. this is uuugly
        #*STDERR = "NULLFH";
        my $bfx = Unicode::String::utf8($in)->utf8;
        #*STDERR = $oldstderr;    #Restore old filehandle
        if($bfx ne $in) {
            #Input was no valid utf8, assume latin1 input
            $in =~  s/[\000-\037]//gm; #Kill stupid chars..
            $in = Unicode::String::latin1($in)->utf8
        }
        else { #Return the unicoded input
            $in = $bfx;
        }
    }
    return $in;
}

1;
