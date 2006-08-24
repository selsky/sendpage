# -*- Mode: CPerl -*-
# Sendpage-Recipient.t -- unit test for Sendpage::Recipient
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
# After installation, run as `perl Sendpage-Recipient.t'

use strict;
use warnings;

use Test::MockObject;
use Test::More tests => 21;
BEGIN {
    my %conf_mock_methods =
	(
	 get		 => sub {
	     shift;		# discard
	     if ($_[0] =~ /email-cc/) { return 'zakame' }
	     elsif ($_[0] =~ /recip/) { return [ qw(foo bar baz) ] }
	     elsif ($_[0] =~ /debug/) { return 0 }
	 },
	 instance_exists => sub {
	     shift;		# discard
	     if ($_[0] =~ /pc/) { return 1 }
	 },
	);

    my $mock_conf = new Test::MockObject;
    isa_ok( $mock_conf, 'Test::MockObject', "mock conf object" );
    $mock_conf->fake_module( 'Sendpage::KeesConf' );
    $mock_conf->fake_new( 'Sendpage::KeesConf' );
    $mock_conf->set_isa( 'Sendpage::KeesConf' );

    foreach (keys %conf_mock_methods) {
	$mock_conf->mock( $_ => $conf_mock_methods{ $_ } );
	can_ok( $mock_conf, $_ );
    }
    use_ok( 'Sendpage::KeesConf' );

    use_ok( 'Sendpage::Recipient' ) or die;
}

CONSTRUCTOR: {
    my $config = Sendpage::KeesConf->new();
    isa_ok( $config, 'Sendpage::KeesConf' );

    my $db;
    my $name = "test";
    my %data =
	(
	 'email-cc' => 'zakame',
	);

    my $recip = Sendpage::Recipient->new( $config, $db, $name, \%data );
    isa_ok( $recip, 'Sendpage::Recipient' );

    my @functions = qw( alias dests data datum pin pc name );
    can_ok( $recip, $_ ) foreach @functions;

    ok( $recip->alias, "have a valid alias" );
    is_deeply( $recip->dests,
	       [ qw(foo bar baz) ],
	       "found dests" );
    is_deeply( $recip->data,
	       \%data,
	       "found data" );
    is( $recip->datum('email-cc'),
	'zakame',
	"found datum" );
    is( $recip->name,
	'test',
	"found name" );

 TODO: {
	local $TODO = "PINs and PC not yet defined";
	isnt( $recip->pin,
	    undef,
	    "found PIN" );
	isnt( $recip->pc,
	    undef,
	    "found paging central");
    }
}

# /* vim: set filetype=perl : */ 
