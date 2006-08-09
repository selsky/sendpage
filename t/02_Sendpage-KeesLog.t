# -*- Mode: CPerl -*-
# Sendpage-KeesLog.t -- unit test for Sendpage::KeesLog
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
# After installation, run as `perl Sendpage-KeesLog.t'

use strict;
use warnings;

use Test::More tests => 15;
BEGIN { use_ok( 'Sendpage::KeesLog' ) or die }

CONSTRUCTOR: {
    my $log = Sendpage::KeesLog->new();
    isa_ok( $log, 'Sendpage::KeesLog' );

    my @functions = qw( reconfig off on do DESTROY );
    can_ok( $log, $_ ) foreach @functions;
}

CONSTRUCTOR_WITH_ARGS: {
    # Note: giving `Opts' below hushes some warnings produced from Sys::Syslog
    my $log = new Sendpage::KeesLog Syslog => 1, Opts => 'pid nodelay nowait';
    isa_ok( $log, 'Sendpage::KeesLog' );

    # basic testing; assumes syslog is up
    is( $log->on,
	1,
	"log on" );
    ok( $log->do('debug', "testing Sendpage::KeesLog::do()"),
	"do() to syslog" );
    is( $log->off,
	undef,
	"log off" );

    # make a tempfile for stderr redirection
    require File::Temp;
    my $tfh = new File::Temp UNLINK => 1;
    isa_ok( $tfh, 'File::Temp', $tfh );
    my $fname = $tfh->filename;

    # save away our stderr to the tempfile for later testing
    local *SAVEERR;
    open SAVEERR, ">&STDERR";
    open STDERR,  "> $fname" or die "Can't redirect stderr";
    select STDERR; $| = 1;

    $log->reconfig(Syslog => 0);
    $log->do('info', "testing Sendpage::KeesLog::do()");

    close STDERR;
    open  STDERR, ">&SAVEERR";

    like( <$tfh>,
	  qr/testing/,
	  "logging to stderr (redirected to tempfile)" );
    close $tfh;

    # cleanup
    is( unlink($fname),
	1,
	"Remove $fname" );
    ok( !-e $fname, "$fname gone" );
}
