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

use strict;
use vars qw(@ISA @EXPORT);
use Socket 1.3;
use Carp;
use IO::Socket;
use Net::Cmd;
#use IO::Handle;
use Sendpage::PagingCentral;
use Sendpage::PageQueue;
use POSIX qw(strftime);

@ISA = qw(Net::Cmd IO::Socket::INET);
@EXPORT = (@Net::Cmd::EXPORT);



# FIXME: implement a input-alarm handler that will disconnect after 1 minute
#	 of inactivity:
#		421 Timeout, Goodbye

sub HandleSNPP {
	my $sock = shift;
	my $banner = shift;
	my $pipe = shift;
	my $config = shift;
	my $log = shift;
	my $DEBUG = shift;

        my($pin,%PINS,%QPCS,$pc,$recips,$recip,@recips,$fail,$text,$caller);

	# how far are we in the process?
	my $NEED_PIN=0;
	my $NEED_TEXT=1;
	my $NEED_SEND=2;

	my $status;
			
	sub reset_inputs {
		%PINS=();
		%QPCS=();
		@recips=();
		$caller=$pin=$pc=$recips=$recip=$fail=$text=undef;

		# start off looking for a pin
		$status=$NEED_PIN;
	}

	reset_inputs();

	#$sock->debug($DEBUG);

	$log->do('debug',"Handling SNPP connection from ".$sock->peerhost)
		if ($DEBUG);

	# What is my hostname, for the banner?
	my $hostname = gethostbyaddr($sock->sockaddr, AF_INET);
	if ($hostname eq "") {
		$hostname=$sock->sockhost;
	}		

	for (;;) {
		# Figure the RFC822 time, for fun
                my $now = strftime "%a, %d %b %Y %T %z", gmtime;

		$sock->command("220 $hostname $banner $now");

		# begin the input loop
		while (1) {
			my $input=$sock->getline();
			$sock->debug_print(0,$input)
				if (${*$sock}{'net_cmd_debug'});

			# drop our trailing crlf
			$input=~s/\r?\n$//;

			# parse out our text
			my ($cmd,$args);
			$cmd=$args="";
			($cmd,$args)=split(/\s+/,$input,2);

			$cmd=~tr/a-z/A-Z/;

			# SNPP level 1 commands
			if ($cmd =~ /^QUIT/) {
				$sock->command("221 $hostname closing connection");
				return;
			}
			elsif ($cmd =~ /^PAGE/) {
				if ($status != $NEED_PIN) {
					$sock->command("503 ERROR, Pager ID Already Entered");
					next;
				}

				# collect pager ids here
				my @pins=split(/\s+/,$args);
				# validate pager ids
			        ($fail,@recips)=main::ArrayDig(@pins);
			        if ($fail == 0 && $#recips > -1) {
					$sock->command("250 Pager ID Accepted: '$args'");
        				$recips=\@recips;

				        # sort them into PC bins
				        foreach $recip (@{ $recips }) {
				                # make list of PCs
				                push(@{ $QPCS{$recip->pc()} },$recip);
				        }

					$status=$NEED_TEXT;
				}
				else {
					$sock->command("550 Error, Invalid Pager ID: '$args'");
					next;
				}

				# I don't see a need for these
				#$sock->command("421 Too Many Errors, Goodbye");
				#$sock->command("421 Gateway Service Unavailable");
				#$sock->command("554 Error, failed: $!"); 
			}
			# includes Level 2 command "data" here
			elsif ($cmd =~ /^(MESS|DATA)/) {
				if ($status == $NEED_PIN) {
					$sock->command("503 ERROR, Must use 'PAGE' first");
					next;
				}
				elsif ($status == $NEED_SEND) {
					$sock->command("503 ERROR, Message Already Entered");
					next;
				}
				
				if ($cmd =~ /^M/) {
					# SNPP v1 "MESS" collection
					$text=$args;
				}
				else {
					# SNPP v2 "DATA" collection
					$sock->command("354 Begin Input; End with <CRLF>'.'<CRLF>");

					# collect lines
					my $lines=$sock->read_until_dot;
					$text="";
					$text=join("",@$lines) if (defined($lines));
				}


				# trans crlf into lf for pagers
				$text=~s/\r\n/\n/g;

				if ($text ne "") {
					$sock->command("250 Message OK");
					$status=$NEED_SEND;
				}
				else {
					$sock->command("550 ERROR, Blank Message");
					next;
				}

				# I don't see a need for these
				#$sock->command("421 Too Many Errors, Goodbye (terminate connection)");
				#$sock->command("421 Gateway Service Unavailable (terminate connection)");
				#$sock->command("503 ERROR, Message Already Entered");
				#$sock->command("550 ERROR, Invalid Message");

				#$sock->command("554 Error, failed: $!");


			}
			elsif ($cmd =~ /^RESE/) {
				reset_inputs();
				
				$sock->command("250 RESET OK");

				# I don't see a need for these
				#$sock->command("421 Too Many Errors, Goodbye (terminate connection");
				#$sock->command("421 Gateway Service Unavailable (terminate connection)");
			}
			elsif ($cmd =~ /^SEND/) {
				my $queued=$sock->write_queued_pages($pipe,$caller,$text,$config,$log,$DEBUG,%QPCS);

				if ($queued>0) {
					$sock->command("250 $queued Queued Successfully (caller: '$caller')");
				}
				else {
					$sock->command("554 Error, queuing failed -- contact admin");
				}
				# reset ourselves
				reset_inputs();

				# I don't see a need for these
				#$sock->command("421 Too Many Errors, Goodbye (terminate connection)");
				#$sock->command("421 Gateway Service Unavailable (terminate connection)");
				#$sock->command("503 Error, Pager ID or Message Incomplete");
				#$sock->command("554 Message Failed [non-administrative reason]");
			}
			elsif ($cmd =~ /^HELP/) {
				my $line;

				foreach $line (
"Commands:",
"   PAGE [ID]    - send a page to ID",
"   MESS [text]  - attach text",
"   DATA	 - start '.'-ended text input",
"   SEND         - send the page",
"   RESE         - reset the input",
"   QUIT         - hang up",
"   HELP         - this help"
				) {
					$sock->command("214 $line");
				}
				$sock->command("250 End of Help Information");
			}

			# SNPP level 2 commands
			# 'DATA' implemented above in 'MESS'

			elsif ($cmd =~ /^CALL/) {
				if ($caller ne "") {
					$sock->command("503 ERROR, Caller ID already entered");
					next;
				}
				# who sent this page?
				$caller=$args;

				if ($caller ne "") {
					$sock->command("250 Caller ID Accepted");
				}
				else {
					$sock->command("550 Error, Invalid Caller ID: blank");
				}
			}

			# FIXME: implement hold time
			#elsif ($cmd =~ /^HOLD/) {
			#}

			# SNPP level 3 commands
			# FIXME: find out how the TAP protocol deals with 2way
			
			# Unknown commands
			else {
				$sock->command("500 Unknown command");
			}
		}
	}

	return 0;
}

sub write_queued_pages {
	my ($self,$pipe,$from,$text,$config,$log,$DEBUG,%QPCS)=@_;
	my ($pc,$recips,$queued);

	$queued=0;

	my $mask=umask(0077); # allow only user read/write
        foreach $pc (sort keys %QPCS) {
                # get our PC-list of recipients
                $recips=$QPCS{$pc};

                $log->do('debug',"opening queue for '$pc'") if ($DEBUG);
                # write a queue file with associated PINs
                my $queue=Sendpage::PageQueue->new($config,$config->get("queuedir")."/$pc");
                if (!defined($queue)) {
                        $log->do('err', "cannot find queue for PC '$pc'");
			next;
                }

                my @pages;
                @pages=();

                my $pagingcentral=Sendpage::PagingCentral->new($config,$pc);

                if (length($text) > $pagingcentral->maxchars()) {
			$log->do('debug',"Splitting due to PC '$pc' maxchar ".
				"limit: ".$pagingcentral->maxchars())
				if ($DEBUG);
                        my($newtext,$i);
                        my $maxsplits=$pagingcentral->maxsplits();
                        my $format=length($maxsplits);
                        my $availlen=$pagingcentral->maxchars()-($format * 2)-2;
                        my $chunks=POSIX::ceil(length($text)/$availlen);

                        # never send more than $maxsplits pages from one text
                        $chunks=$maxsplits if ($chunks>$maxsplits);

                        for ($i=0; $i<$chunks; $i++) {
                                $newtext=sprintf("%0${format}d/%0${format}d:",
                                                $i+1,$chunks);
                                $newtext.=substr($text,0,$availlen);
                                $text=substr($text,$availlen);

                                push(@pages,$newtext);
                        }
                        if ($text ne "") {
				$log->do('warning',"threw away %d extra chars at the end of a page with more than %d splits",length($text),$chunks);
                        }
                }
                else {
                        push(@pages,$text);
                }

                foreach $text (@pages) {
                        if (!defined($queue->addPage(Sendpage::Page->new($recips,\$text,
                                { 'when' => time,
                                  'from' => ($from ne "") ? $from :
                                        scalar(getpwuid($<))
                                 })))) {
                                $log->do('err',
                                        "cannot send this page: queue failed");
                        }
			else {
				# FIXME: implement server-side fd for new page
				#        notifications

				$queued++;
			}
                }
		print $pipe "$pc\n";
        }
	umask($mask);

	return $queued;
}

sub create {
 my $proto = shift;
 my $class = ref($proto) || $proto;
 my %arg = @_;

 my $self = $class->SUPER::new(	Listen => $arg{Listen} || 5,
				LocalAddr => $arg{Addr},
				LocalPort => $arg{Port} || "snpp(444)",
				Timeout => $arg{Timeout},
				Proto => 'tcp', 
				Reuse => 1 );

 bless ($self, $class);

 return $self;
}

1;
