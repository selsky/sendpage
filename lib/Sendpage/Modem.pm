#
# Modem.pm extends the Device::SerialPort package, and adds a few things
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

package Sendpage::Modem;
use POSIX;
use Sendpage::KeesConf; # FIXME: make this a generic module for all
use IO::Handle;

# Hey!  Duh!  I should use the OS auto-discovery system to get the right
# serial device module here!
use Device::SerialPort;
@ISA = ("Device::SerialPort");

=head1 NAME

Sendpage::Modem.pm - extends the Device::SerialPort package

=head1 SYNOPSIS

    $modem=Sendpage::Modem->new($config,$name);
    $modem->init($baud,$parity,$data,$stop,$flow,$str);
    $modem->dial($str);
    $modem->chat($send,$resend,$expect,$timeout,$retries,$dealbreaker,
    	$ignore_carrier);
    $modem->hangup();

    $str=Sendpage::Modem->HexStr("tab:\t cr:\r");

=head1 DESCRIPTION

This is a module for use in sendpage(1).

=head1 BUGS

This needs more docs.

=cut


# globals
my $SPEED=10;	# how much to speed up the char reader

# new methods here are:
#	init		- inits modem
#	dial		- dials number (returns like "write")
#	hangup		- hangs up modem

# new vars are:
#	CONFIG		- reference to the KeesConf variable

# new modem
#	takes:
#		KeesConf, modem_name
#
sub new {
	# local vars
	my($dev,$lockprefix,$lockfile,$realdev,$debug,$pid);

	# get our args
	my $proto = shift;
	my $config = shift;
	my $name  = shift;

	$dev    = $config->get("modem:${name}\@dev");
	$lockprefix=$config->get("lockprefix");
	$debug  = $config->get("modem:${name}\@debug");

	# sanity check our config options
	if (!defined($lockprefix)) {
		$main::log->do('alert',"Modem '$name' has no lockprefix defined");
		return undef;
	}
	if (!defined($dev) || $dev eq "/dev/null") {
		$main::log->do('alert',"Modem '$name' has no device defined");
		return undef;
	}

	# We need to build the name of the lock file
	$lockfile=$lockprefix;
	
	# figure out what the REAL device name is
	if (!defined($realdev=readlink($dev))) {
		# not a symlink
		$realdev=$dev;
	}
	# now, chop the name of the dev off
	my @parts=split(m#/#,$realdev);
	$lockfile.=pop(@parts);
	# $lockfile should now be in the form "/var/lock/LCK..ttyS0"

	$main::log->do('debug', "Trying to get lockfile '$lockfile'") if ($debug);

	while (!defined(sysopen(LOCKFILE, "$lockfile",
		O_EXCL | O_CREAT | O_RDWR, 0644))) {
		if ($! == EEXIST) {
			if (defined(sysopen(LOCKFILE, "$lockfile",
				O_RDONLY))) {
				# read pid
				chomp($pid=<LOCKFILE>);
				if ($pid=~/^(\d+)$/) {
					$pid=$1;
				}
				else {
					$pid=0;
				}
				close(LOCKFILE);

				# whoa: we need to clear this
				undef $!;

				if ($pid>0) {
					kill 0, $pid;
				}
				if ($pid==0 || $! == ESRCH) {
					# pid does not exist, remove the lock
					$main::log->do('debug', "Modem '$name': stale lockfile from PID $pid removed");
					unlink("$lockfile");
					next;
				}
			}
			
			# cannot touch lockfile
			$main::log->do('warning',"Modem '$name': $dev is locked by process '$pid'");
			return undef;
		}
		else {
			$main::log->do('alert',"Modem '$name': cannot access lockfile '$lockfile': $!");
			return undef;
		}
	}
	# we have the lock file now
	print LOCKFILE $$,"\n";
	close(LOCKFILE);

	# handle inheritance?
	my $class = ref($proto) || $proto;
	my $self  = $class->SUPER::new($dev);	# this should be SerialPort
	my $ref;

	if (!defined($self)) {
		$main::log->do('crit',"Modem '$name': could not start Device::Serial port");
		unlink $lockfile;
		return undef;
	}

	# save our stateful information
	$self->{CONFIG}=$config;	# get the config info
	$self->{NAME}  =$name;		# name of the modem
	$self->{LOCKFILE} = $lockfile;	# where our lockfile is
	$self->{DEBUG} = $debug;	# debug mode?
	$self->{IGNORE_CARRIER}=$config->get("modem:${name}\@ignore-carrier",1);

	# internal buffer for 'chat'
	$self->{BUFFER} = "";

	bless($self, $class);

	# Do Device::SerialPort capability sanity checking
	if (!$self->can_ioctl()) {
		$main::log->do('crit',"Modem '$name' cannot do ioctl's.  Did you run h2ph?");
		# get rid of modem
		$self->unlock();
		undef $self;
	}

	return $self;
}

# init settings and send init string
# takes:
#	baud, parity, data, stop, flow, init str
sub init {
	my $self = shift;
	my($baud,$parity,$data,$stop,$flow,$str) = @_;
	$name="Modem '$self->{NAME}'";

	if (!defined($self->{LOCKFILE})) {
		$main::log->do('crit',"init: $name not locked");
		return undef;
	}


	$baud   = $self->{CONFIG}->get("modem:$self->{NAME}\@baud") unless ($baud);
	$parity = $self->{CONFIG}->get("modem:$self->{NAME}\@parity") unless ($parity);
	$data   = $self->{CONFIG}->get("modem:$self->{NAME}\@data") unless ($data);
	$stop   = $self->{CONFIG}->get("modem:$self->{NAME}\@stop") unless ($stop);
	$flow   = $self->{CONFIG}->get("modem:$self->{NAME}\@flow") unless ($flow);
	$str    = $self->{CONFIG}->get("modem:$self->{NAME}\@init") unless ($str);
	my $ok     = $self->{CONFIG}->get("modem:$self->{NAME}\@initok");
	my $initwait=$self->{CONFIG}->get("modem:$self->{NAME}\@initwait");
	my $initretries=$self->{CONFIG}->get("modem:$self->{NAME}\@initretries");

	# sanity check our config options
	if (!defined($baud)) {
		$main::log->do('alert', "$name has no baud rate defined!");
		return undef;
	}
	if (!defined($parity)) {
		$main::log->do('alert', "$name has no parity defined!");
		return undef;
	}
	if (!defined($data)) {
		$main::log->do('alert', "$name has no data bits defined!");
		return undef;
	}
	if (!defined($stop)) {
		$main::log->do('alert', "$name has no stop bits defined!");
		return undef;
	}
	if (!defined($flow)) {
		$main::log->do('alert', "$name has no flow control defined!");
		return undef;
	}
	if (!defined($str)) {
		$main::log->do('alert', "$name has no init string defined!");
		return undef;
	}
	
	# pass various settings through to the serial port
	# FIXME: I should probably test if these are available or successful?
	$self->alias($self->{NAME});
	$self->baudrate($baud);
	$self->parity($parity);
	$self->databits($data);
	$self->stopbits($stop);
	$self->handshake($flow);	

	# set a char timeout for modem commands
	$self->read_char_time(0);          # avg time between read char
        $self->read_const_time(1000/$SPEED);   # delay between calls

	# hang up just in case
	$main::log->do('debug', "reseting DTR ...") if ($self->{DEBUG});
	#$self->pulse_dtr_off(500);
	$self->dtr_active(F);
	select(undef,undef,undef,1.5);  # force the dtr down
	$self->dtr_active(T);

	# make sure the RTS is up
	$main::log->do('debug', "reseting RTS ...") if ($self->{DEBUG});
	$self->rts_active(T);

	# send the init string through
	return $self->chat("$str\r","$str\r",$ok,$initwait,$initretries,
		$self->{CONFIG}->get("modem:$self->{NAME}\@error"),1);
}

# FIXME: implement dial retries
sub dial {
	my $self=shift;
	my $str=shift;
	my $dialwait=shift;
	my $dialretries=shift;

	if (!defined($self->{LOCKFILE})) {
		$main::log->do('crit',"dial: Modem '$self->{NAME}' not locked");
		return undef;
	}


	my $dial = $self->{CONFIG}->get("modem:$self->{NAME}\@dial");
	$dialwait = $self->{CONFIG}->get("modem:$self->{NAME}\@dialwait")
		if (!defined($dialwait));
	$dialretries = $self->{CONFIG}->get("modem:$self->{NAME}\@dialretries")
		if (!defined($dialretries));

	if (!defined($str) || $str eq "") {
		$main::log->do('err',"Nothing to dial (no phone number passed)");
		return undef;
	}

	return $self->chat("$dial$str\r","",
		$self->{CONFIG}->get("modem:$self->{NAME}\@dialok"),
		$dialwait,1,$self->{CONFIG}->get("modem:$self->{NAME}\@no-carrier"),
		1);
}

sub safe_write {
	my ($self,$text) = @_;
	my($textlen,$written);

	if (!defined($self->{LOCKFILE})) {
		$main::log->do('crit',"safe_write: Modem '$self->{NAME}' not locked");
		return undef;
	}


	$textlen=length($text);
	do {
		$written=$self->write($text);
		if (!defined($written)) {
			$main::log->do('crit',"write totally failed");
			return undef;
		}
		elsif ($written != $textlen) {
			$main::log->do('warning',"write was incomplete!?!  retrying...");
			$text=substr($text,$written);
		}
		if ($self->{DEBUG}) {
			$main::log->do('debug',"wrote: $written ".
				$self->HexStr(substr($text,0,$written)));
		}
		$textlen-=$written;
	} while ($textlen>0);
	return 1;
}


# FIXME: more docs here, and need perhaps, and list of strings to 
#	 immediately abort on?  like "NO CARRIER", "BUSY", etc... ?
sub chat {
	my $self = shift;
        my ($send,$kicker,$expect,$timeout,$retries,$dealbreaker,
		$ignore_carrier)=@_;
        my ($avail,$got);

	if (!defined($self->{LOCKFILE})) {
		$main::log->do('crit',"chat: Modem '$self->{NAME}' not locked");
		return undef;
	}

	$ignore_carrier=$self->{IGNORE_CARRIER}
		unless (defined($ignore_carrier));
	$got=$self->{BUFFER};

	if ($self->{DEBUG}) {
		$main::log->do('debug',"\tto send: ".$self->HexStr($send));
	        $main::log->do('debug',"\twant: ".$self->HexStr($expect));
		$main::log->do('debug',"\tkicker: ".$self->HexStr($kicker));
		$main::log->do('debug',"\ttimeout: $timeout retries: $retries");
		$main::log->do('debug', "\thave: ".$self->HexStr($got));
	}

	# useful variables:
	#  $got		contains the full text of chars read
	#  $avail 	is what we JUST read


	#LOOP:
	# send initial text
	# start retry loop
	#    start timeout loop while reading chars
	#	try to read char
	#	check for sucess
	#    end loop
	#    send kicker
	# end loop


	# send initial text no matter what
	if (!defined($self->safe_write($send))) {
		$main::log->do('alert',"safe_write failed!");
	}

	# initial check for sucess
	if ($got =~ /($expect)/) {
		my $matched=$1;
		my $upto=$`.$1;
		$self->{BUFFER}=$';	# keep right of match
		$main::log->do('debug',"chat success: ".$self->HexStr($matched))
			 if ($self->{DEBUG});
		return $upto; 
	}
	if (defined($dealbreaker) && $got =~ /($dealbreaker)/) {
		my $matched=$1;
		my $upto=$`.$1;
		$self->{BUFFER}=$';	# keep right of match
		$main::log->do('debug',"chat failure: ".$self->HexStr($matched))
			 if ($self->{DEBUG});
		return undef;
	}

	# up our timeout to tenths
	$timeout*=$SPEED;

	# start retry loop
	my $tries;
	for ($tries=0; $tries<$retries; $tries++) {

		# send kicker (unless this is the first time through)
		if ($kicker ne "" && $tries>0) {
			$main::log->do('debug', "timed out, sending kicker")
				if ($self->{DEBUG});
			if (!defined($self->safe_write($kicker))) {
				$main::log->do('alert',"safe_write failed!");
			}
		}

		# start timeout loop while reading chars
		my $timeleft;
		for ($timeleft=0; $timeleft<$timeout; $timeleft++) {

			# do carrier check
			if (!defined($ignore_carrier)) { 
				my $has_carrier=$self->carrier();
				if (!$has_carrier) {
					$main::log->do('warning',
						"lost carrier during chat");
					return undef;
				}
			}

			# try to read char
			($cnt,$avail)=$self->read(1024);
			if ($cnt > 0) {
				$main::log->do('debug', "saw: ".$self->HexStr($avail))
					if ($self->{DEBUG});
				$got.=$avail;
				$main::log->do('debug', "have: ".$self->HexStr($got))
					if ($self->{DEBUG});
				
				# reset our timeout
				$timeleft=-1;
			}
			elsif ($self->{DEBUG}) {
				my $msg=sprintf("(timeout: %d/%d, retries: %d/%d)\n",
					$timeleft/10,$timeout/10,
					$tries,$retries);
				$main::log->do('debug', $msg)
					if (($timeleft % $SPEED) == 0);
			}

			# check for sucess
			if ($got =~ /($expect)/) {
				my $matched=$1;
				my $upto=$`.$1;
				$self->{BUFFER}=$';	# keep right of match
				$main::log->do('debug',
				   "chat success: ".$self->HexStr($matched))
					if ($self->{DEBUG});
				return $upto; 
			}
			if (defined($dealbreaker) && $got =~ /($dealbreaker)/) {
				my $matched=$1;
				my $upto=$`.$1;
				$self->{BUFFER}=$';	# keep right of match
				$main::log->do('debug',
				   "chat failure: ".$self->HexStr($matched))
					 if ($self->{DEBUG});
				return undef;
			}
		}
	}

	# failure
	$main::log->do('debug', "chat failed") if ($self->{DEBUG});
       	return undef;
}

# what is the state of the carrier bit?
sub carrier {
	my $self=shift;

	if (!defined($self->{LOCKFILE})) {
		$main::log->do('crit',"carrier: Modem '$self->{NAME}' not locked");
		return undef;
	}

	my $ModemStatus = $self->modemlines;
	return (($ModemStatus & $self->MS_RLSD_ON) == $self->MS_RLSD_ON);
}


# drop the carrier if it's there
sub hangup {
	$self=shift;

	if (!defined($self->{LOCKFILE})) {
		$main::log->do('crit',"hangup: Modem '$self->{NAME}' not locked");
		return undef;
	}

	if ($self->carrier()) {
		$main::log->do('debug',"hanging up Modem '$self->{NAME}'")
			if ($self->{DEBUG});
		$self->pulse_dtr_off(500);
	}

	return 1;
}

# give up everything
sub unlock {
	my $self=shift;

	if (!defined($self->{LOCKFILE})) {
		$main::log->do('crit',"unlock: Modem '$self->{NAME}' not locked");
		return undef;
	}

	$self->hangup();

	if (defined($self->{LOCKFILE})) {
		$main::log->do('debug',"unlocking Modem '$self->{NAME}'")
			if ($self->{DEBUG});
		unlink($self->{LOCKFILE});
		undef $self->{LOCKFILE};
	}
}

# what happens when we get destroyed
sub DESTROY {
	my $self = shift;

 	$main::log->do('debug',"Modem '$self->{NAME}' being destroyed") if ($self->{DEBUG});

	$self->unlock() if (defined($self->{LOCKFILE}));
}

# extra bits...
sub HexDump {
        my($self,$text)=@_;

        my $str=$self->HexStr($text);

        $main::log->do('debug', "len %d: %s",length($text),$str);
}

sub HexStr {
        my $self = shift;
        my($text)=@_;
        my(@chars,$i,$str);
        $str="";

        if (defined($text)) {
                @chars=split(//,$text);
                foreach $i (@chars) {
                        if ($i !~ /^[\040-\176]$/) {
                                $str.=sprintf("{0x%02X}",ord($i));
                        }
                        else {
                                $str.=$i;
                        }
                }
        }
        else {
                $str.="-undef-";
        }

        return $str;
}

1;

__END__

=head1 AUTHOR

Kees Cook <cook@cpoint.net>

=head1 SEE ALSO

perl(1), sendpage(1), Sendpage::KeesConf(3), Sendpage::KeesLog(3), 
Sendpage::PagingCentral(3), Sendpage::PageQueue(3), Sendpage::Page(3),
Sendpage::Recipient(3), Sendpage::Queue(3)

=head1 COPYRIGHT

Copyright 2000 Kees Cook.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

