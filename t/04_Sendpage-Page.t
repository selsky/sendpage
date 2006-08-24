# -*- Mode: CPerl -*-
# Sendpage-Page.t -- unit test for Sendpage::Page
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
# After installation, run as `perl Sendpage-Page.t'

use strict;
use warnings;

use Test::MockObject;
use Test::More tests => 45;
BEGIN {
    # testing data to be returned by the mock objects
    my %recipient =
	(
	 name  => sub { "John Doe" },
	 data  => sub { { from => "Tester" } },
	 datum => sub { "Tester" },
	);

    # create our MockObject template
    my $mock = Test::MockObject->new();
    isa_ok( $mock, 'Test::MockObject', 'mock Sendpage::Recipient' );
    $mock->fake_module( 'Sendpage::Recipient' );
    $mock->fake_new( 'Sendpage::Recipient' );
    $mock->set_isa( 'Sendpage::Recipient' );

    # create methods
    foreach (keys %recipient) {
	$mock->mock( $_ => $recipient{ $_ } );
	ok( $mock->can( $_ ), qq( mock recipient template can $_() ) );
    }

    use_ok( 'Sendpage::Recipient' );
    use_ok( 'Sendpage::Page' ) or die;
}

# make our 3 Stooges, erm, Recipients
our ($larry, $curly, $moe);
for my $stooge ( qw(larry curly moe) ) {
    no strict 'refs';		# access symbol table
    $$stooge = Sendpage::Recipient->new;
    isa_ok( $$stooge,
	    'Sendpage::Recipient',
	    "mock Sendpage::Recipient '$stooge'" );

    can_ok( $$stooge, $_ ) foreach qw( name data datum );
    $$stooge->name($stooge);
}

# Page template
my %p =
    (
     recipients	=> [ $larry, $curly, $moe ],
     text	=> "Some text to page here",
     options	=> { when => time },
    );

my $page = Sendpage::Page->new( \@{ $p{recipients} },
				\$p{text},
				\%{ $p{options} },
			      );
isa_ok( $page, 'Sendpage::Page' );

my @functions = qw( text reset next recip has_recips drop_recip
		    deliverable option attempts dump );
can_ok( $page, $_ ) foreach @functions;

# can we read the page's text?
is( $page->text,
    $p{text},
    qq(text("$p{text}")) );

# can we deliver it?
is( $page->deliverable,
    1,
    qq(page deliverable()) );

# can we reset the recipient list iterator?
is( $page->reset,
    -1,
    qq(reset() recipient list pointer) );

# can we get the next in the recipient list?
is( $page->next,
    0,
    qq(next() at start of recipient list) );

# Is the current recipient at head?
is( $page->recip,
    $p{recipients}[0],
    qq(recip() is at head) );

if ($page->deliverable) {
    for (my $i = 0, $page->reset, $page->next;
	 my $r = $page->recip;
	 $i++, $page->next) {
	isnt( $r,
	      undef,
	      qq(recip() in loop) );
	is( $page->text,
	    $p{text},
	    qq(text() for each recipient) );
	cmp_ok( $page->drop_recip,
		'>=',
		0,
		qq(drop_recip() current recip @{[ $r->name ]} $i) );
    }
    is( $page->attempts(1),
	1,
	qq(first attempt()) );
}

# anyone left to deliver?
is( $page->has_recips,
    '',
    qq(no more recips()) );

# /* vim: set filetype=perl : */ 
# /* vi:set ai ts=4 sw=4 expandtab: */
