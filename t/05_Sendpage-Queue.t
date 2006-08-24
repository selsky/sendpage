# -*- Mode: CPerl -*-
# Sendpage-Queue.t -- unit test for Sendpage::Queue
# $Id$
#
# Copyright (C)  2006  Zak B. Elep
# zakame@spunge.org, http://zakame.spunge.org
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License,
# or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA
#
# After installation, run as `perl Sendpage-Queue.t'

use strict;
use warnings;

use Test::More tests => 55;
BEGIN { use_ok( 'Sendpage::Queue' ) or die }

CONSTRUCTOR: {
    # make the tempdir
    use File::Temp qw/ tempfile tempdir /;
    my $dir   = tempdir( CLEANUP => 1 );

    # populate tempdir with files
    my @tempfiles;
    (undef, $tempfiles[ $_ ]) = tempfile( "qXXXX", UNLINK => 1, DIR => $dir )
	foreach 0 .. 10;

    my $queue = new Sendpage::Queue $dir;
    isa_ok( $queue, 'Sendpage::Queue' );

    my @functions = qw( file ready getReadyFile fileToss fileDone
			getNewFile doneNewFile lockFile unlockFile
			lockQueue unlockQueue createUniqueName );
    can_ok( $queue, $_ ) foreach @functions;

    # is the queue ready?
    cmp_ok( $queue->ready, '==', $#tempfiles,
	    qq(queue is ready) );

    # test the queue in action
    my $i = 0;
    my %seen;
    while ($queue->ready) {
	my $fname = $queue->file;
	my $fh    = $queue->getReadyFile;

	my $test;
	unless (defined $seen{$fname}) {
	    $test = qq(read file() $tempfiles[$i]);
	} else {
	    $test = qq(reread file $tempfiles[$i]);
	}

	$seen{$fname}++;
	like( $tempfiles[$i],
	      qr/$fname/,
	      $test );

	my $string = <$fh>;
	if (defined($string) and $string =~ /test/) {
	    ok( $queue->fileToss,
		qq(tossed $tempfiles[$i]) );
	    $i++;
	} else {
	    print $fh "this is a test";
	    ok( $queue->fileDone,
		qq(testing $tempfiles[$i]) );
	}
    }
}

# /* vim: set filetype=perl : */ 
