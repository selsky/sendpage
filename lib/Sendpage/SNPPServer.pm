#!/usr/bin/perl
# implements the snppserver portions of sendpage
# (large parts shamelessly stolen from Net::DummyInetd)
#
# $Id$
#
# Copyright (C) 2000 Cornelius Cook
# cook@cpoint.net, http://collective.cpoint.net/
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
# http://www.gnu.org/copyleft/gpl.html
package Sendpage::SNPPServer;

require 5.002;

use IO::Handle;
use IO::Socket;
use strict;
use Carp;
use Sendpage::Page;


sub _process {
 my $listen = shift;
 my $vec = '';
 my $r;

 vec($vec,fileno($listen),1) = 1;

 while(select($r=$vec,undef,undef,undef)) {
   my $sock = $listen->accept;
   my $pid;

   if($pid = fork()) {
     sleep 1;
     close($sock);
   }
   elsif(defined $pid) {
#     my $x =  IO::Handle->new_from_fd($sock,"r");
#     open(STDIN,"<&=".fileno($x)) || die "$! $@";
#     close($x);
#
#     my $y = IO::Handle->new_from_fd($sock,"w");
#     open(STDOUT,">&=".fileno($y)) || die "$! $@";
#     close($y);
#
#     close($sock);
#     exec(@cmd) || carp "$! $@";

      HandleSNPP($sock);
   }
   else {
     close($sock);
     carp $!;
   }
  }
 exit -1;
}

sub new {
 my $self = shift;
 my $type = ref($self) || $self;

 my $listen = IO::Socket::INET->new(Listen => 5, Proto => 'tcp', 
				    Reuse => 1, @_);
 my $pid;

 return bless [ $listen->sockport, $pid ]
        if($pid = fork());

 _process($listen,@_);
}

sub port {
 my $self = shift;
 $self->[0];
}

sub DESTROY {
 my $self = shift;
 kill 9, $self->[1];
}

1;

