#!/usr/bin/perl

package Mac::iPod::GNUpod::Utils;

# This file is based on code from FooBar.pm and XMLhelper.pm in the GNUpod
# toolset. The original code is (C) 2002-2003 Adrian Ulrich <pab at
# blinkenlights.ch>.
#
# Much rewriting and adaptation by JS Bangs <jaspax at glossopoesis.org>, (C)
# 2003-2004.

use Exporter;
use Unicode::String;
@ISA = qw/Exporter/;
@EXPORT = qw/shx2int xescaped realpath mkhash mktag matches/;

use strict;
use warnings;

# Reformat shx numbers
sub shx2int {
    my($shx) = @_;
    my $buff = '';
    foreach(split(//,$shx)) {
        $buff = sprintf("%02X",ord($_)).$buff;
    }
    return hex($buff);
}

# Escape strings for XML
sub xescaped {
    my $txt = shift;
    for ($txt) {
        s/&/&amp;/g;
        s/"/&quot;/g;
        s/</&lt;/g;
        s/>/&gt;/g;
        #s/'/&apos;/g;
    }

    return $txt;
}

# Convert an ipod path to Unix
sub realpath {
    my($mountp, $ipath) = @_;
    no warnings 'uninitialized';
    $ipath =~ tr/:/\//;
    return "$mountp/$ipath";
}

# Create a hash
sub mkhash {
    my($base, @content) = @_;
    my $href = ();
    for(my $i=0;$i<int(@content);$i+=2) {
        $href->{$base}->{$content[$i]} = Unicode::String::utf8($content[$i+1])->utf8;
    }
    return $href;
}

# Create an XML tag 
sub mktag {
    my($elm, $attr, %opt) = @_;
    my $r = '<' . xescaped($elm) . ' ';
    foreach (sort keys %$attr) {
        $r .= xescaped($_). "=\"" . xescaped($attr->{$_}) . "\" ";
    }
    if ($opt{noend}) {
        $r .= ">";
    }
    else {
        $r .= " />";
    }

    return $r;
    #return Unicode::String::utf8($r)->utf8;
}

# Find if two things match, w/ opts
sub matches {
    my ($left, $right, %opts) = @_;
    no warnings 'uninitialized';
    if ($opts{nocase}) {
        $left = lc $left;
        $right = lc $right;
    }
    if ($opts{nometachar}) {
        $right = quotemeta $right;
    }

    if ($opts{exact}) {
        return $left eq $right;
    }
    else {
        return $left =~ /$right/;
    }
}

1;
