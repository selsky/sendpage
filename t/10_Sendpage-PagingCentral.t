# -*- Mode: CPerl -*-
# Sendpage-PagingCentral.t -- unit test for Sendpage::PagingCentral
# $Id$
#
# Copyright (C)  2006  Kees Cook
# kees@outflux.net, http://outflux.net/
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
# After installation, run as: perl Sendpage-PagingCentral.t

use strict;
use warnings;

use Test::MockObject;
#use Test::More tests => 45;
use Test::More qw(no_plan);

our $mock_conf;
my $CR  = "\x0D";
my $US  = "\x1F";
my $ETX = "\x03";
my $ETB = "\x17";

BEGIN {
    my %conf_mock_methods =
    (
     get         => sub {
         shift;        # discard self

         if    ($_[0] =~ /^pc:[^@]+\@debug$/)           { return 0 }
         elsif ($_[0] =~ /^pc:[^@]+\@fields$/)          { return 2 }
         elsif ($_[0] =~ /^pc:[^@]+\@chars-per-block$/) { return 250 }
         else { return "trash" }
     },
     ifset         => sub {
         shift;        # discard self
         return "trash";
     },
     fallbackget   => sub {
         shift;        # discard self
         return "trash";
     },
    );

    our $mock_conf = new Test::MockObject;
    isa_ok( $mock_conf, 'Test::MockObject', "mock conf object" );
    $mock_conf->fake_module( 'Sendpage::KeesConf' );
    $mock_conf->fake_new( 'Sendpage::KeesConf' );
    $mock_conf->set_isa( 'Sendpage::KeesConf' );

    foreach (keys %conf_mock_methods) {
        $mock_conf->mock( $_ => $conf_mock_methods{ $_ } );
        can_ok( $mock_conf, $_ );
    }
    use_ok( 'Sendpage::KeesConf' );

    use_ok( 'Sendpage::PagingCentral' ) or die;
}

# Without an explicit modem list
my $pc = Sendpage::PagingCentral->new( $mock_conf, "testpc" );
isa_ok( $pc, 'Sendpage::PagingCentral' );

my @public_functions = qw( start_proto send disconnect deliver SendMail );
can_ok( $pc, $_ ) foreach @public_functions;
my @private_functions = qw( GenerateBlocks );
can_ok( $pc, $_ ) foreach @private_functions;

my (@blocks,$pin,$msg);

$pin = "pin";
$msg = "short message";
@blocks = $pc->GenerateBlocks( $pin, $msg );
is(scalar(@blocks),1,"Generated a single block for a short page");
is(join("",@{$blocks[0]}),"$pin$CR$msg$CR$ETX",
   "Short message block meets TAP specification");

$pin = "pin";
$msg = "long message" . "B" x 256;
@blocks = $pc->GenerateBlocks( $pin, $msg );
is(scalar(@blocks),2,"Generated two blocks for a long field split page");
TODO: {
    local $TODO = "Block splitter is 1 character below expected max";
    # max is 256 - 1 (STX) - 3 (chksum) - 1 (CR) == 251
    my $max = 256 - 1 - 3 - 1;
    is ( length( join("",@{$blocks[0]})), $max,
         "Block 0 of multi-block is $max characters" );
}
is(join("",@{$blocks[0]}),"$pin$CR".substr($msg,0,245)."$US",
   "Long message (field split) block 0 meets TAP specification");
is(join("",@{$blocks[1]}),substr($msg,245)."$CR$ETX",
   "Long message (field split) block 1 meets TAP specification");

$pin = "pin" . "A" x 245;
$msg = "long message" . "B" x 100;
@blocks = $pc->GenerateBlocks( $pin, $msg );
is(scalar(@blocks),2,"Generated two blocks for a long field edge page");
is(join("",@{$blocks[0]}),"$pin$CR$ETB",
   "Long message (field edge) block 0 meets TAP specification");
is(join("",@{$blocks[1]}),"$msg$CR$ETX",
   "Long message (field edge) block 1 meets TAP specification");

#foreach my $block (@blocks) {
#    my $str=join("",@$block);
#    $str =~ s/([[:^print:] {}|~])/sprintf("{0x%02X}",ord($1))/eg;
#    warn "$str\n";
#}

# /* vim: set filetype=perl : */ 
# /* vi:set ai ts=4 sw=4 expandtab: */
