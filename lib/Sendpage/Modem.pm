#
# Modem.pm extends the Device::SerialPort package, and adds a few things
#
# $Id$
#
# Copyright (C) 2000,2001 Kees Cook
# cook@cpoint.net, http://outflux.net/
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
use IO::Handle;
use Sendpage::KeesLog;

# Hey!  Duh!  I should use the OS auto-discovery system to get the right
# serial device module here!
use Device::SerialPort;
@ISA = ("Device::SerialPort");

=head1 NAME

Sendpage::Modem.pm - extends the Device::SerialPort package

=head1 SYNOPSIS

    $modem=Sendpage::Modem->new($params);
    $modem->init($baud,$parity,$data,$stop,$flow,$str);
    $modem->ready($functionname);
    $modem->dial($areacode,$phonenumber,$timeout);
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

# new modem
#	takes:
#		KeesLog, modem_name
#
sub new {
	# local vars
	my($lockfile,$realdev,$pid);

	# get our args
	my $proto = shift;
	my %arg  = @_;

	my $name  = $arg{Name};

	my $dev    = $arg{Dev};
	my $lockprefix=$arg{Lockprefix};
	my $debug  = $arg{Debug};
	my $log    = $arg{Log};
	if (!defined($log)) {
		$log = new Sendpage::KeesLog(Syslog => 0);
	}

	# sanity check our config options
	if (!defined($lockprefix)) {
		$log->do('alert',"Modem '$name' has no lockprefix defined");
		undef $log;
		return undef;
	}
	if (!defined($dev) || $dev eq "/dev/null") {
		$log->do('alert',"Modem '$name' has no device defined");
		undef $log;
		return undef;
	}

	# We need to build the name of the lock file
	$lockfile=$lockprefix;
	
	# FIXME: I need clarification on this: should we discover the
	# true name of the device or not?
	## figure out what the REAL device name is
	#if (!defined($realdev=readlink($dev))) {
	#	# not a symlink
		$realdev=$dev;
	#}

	# now, chop the name of the dev off
	my @parts=split(m#/#,$realdev);
	$lockfile.=pop(@parts);
	# $lockfile should now be in the form "/var/lock/LCK..ttyS0"

	$log->do('debug', "Locking with '$lockfile' ...") if ($debug);

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
					$log->do('debug', "Modem '$name': stale lockfile from PID $pid removed");
					unlink("$lockfile");
					next;
				}
			}
			
			# cannot touch lockfile
			$log->do('warning',"Modem '$name': '$dev' is locked by process '$pid'");
			undef $log;
			return undef;
		}
		else {
			$log->do('alert',"Modem '$name': cannot access lockfile '$lockfile': $!");
			undef $log;
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
		$log->do('crit',"Modem '$name': could not start Device::Serial port");
		unlink $lockfile;
		undef $log;
		return undef;
	}

	# save our stateful information
	$self->{NAME}  =$name;		# name of the modem
	$self->{LOCKFILE} = $lockfile;	# where our lockfile is
	$self->{DEBUG} = $debug;	# debug mode?
	$self->{INITDONE} = 0;		# we have not run "init"

	# internal buffer for 'chat'
	$self->{BUFFER} = "";

	bless($self, $class);

	# Do Device::SerialPort capability sanity checking
	if (!$self->can_ioctl()) {
		$log->do('crit',"Modem '$name' cannot do ioctl's.  Did you run h2ph?");
		# get rid of modem
		$self->unlock();
		undef $log;
		undef $self;
	}

	# grab config settings
	my $index;
	foreach $index (qw(Baud Parity Data Stop Flow Init InitOK InitWait InitRetry Error Dial DialOK DialWait DialRetry NoCarrier IgnoreCarrier DTRToggleTime AreaCode LongDist DialOut)) {
		if (defined($arg{$index})) {
			$self->{$index} = $arg{$index};
			$log->do('debug',"Modem '$name' setting '$index': '".
				$self->{$index}."'")
					if ($self->{DEBUG});
		}
	}

	$self->{LOG} = $log;		# get the log object
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
		$self->{LOG}->do('crit',"init: $name not locked");
		return undef;
	}


	$baud   = $self->{Baud} unless ($baud);
	$parity = $self->{Parity} unless ($parity);
	$data   = $self->{Data} unless ($data);
	$stop   = $self->{Stop} unless ($stop);
	$flow   = $self->{Flow} unless ($flow);
	$str    = $self->{Init} unless ($str);
	my $ok     = $self->{InitOK};
	my $initwait=$self->{InitWait};
	my $initretries=$self->{InitRetry};

	# sanity check our config options
	if (!defined($baud)) {
		$self->{LOG}->do('alert', "$name has no baud rate defined!");
		return undef;
	}
	if (!defined($parity)) {
		$self->{LOG}->do('alert', "$name has no parity defined!");
		return undef;
	}
	if (!defined($data)) {
		$self->{LOG}->do('alert', "$name has no data bits defined!");
		return undef;
	}
	if (!defined($stop)) {
		$self->{LOG}->do('alert', "$name has no stop bits defined!");
		return undef;
	}
	if (!defined($flow)) {
		$self->{LOG}->do('alert', "$name has no flow control defined!");
		return undef;
	}
#	if (!defined($str)) {
#		$self->{LOG}->do('alert', "$name has no init string defined!");
#		return undef;
#	}
	
	# pass various settings through to the serial port
	$self->alias($self->{NAME});

	my $baud_set=$self->baudrate($baud);
	$self->{LOG}->do('debug', "baud requested: '$baud' baud set: '$baud_set'")
		if ($self->{DEBUG});
	if ($baud ne $baud_set) {
		$self->{LOG}->do('alert', "$name failed to set baud rate!");
		return undef;
	}

	my $parity_set=$self->parity($parity);
	$self->{LOG}->do('debug', "parity requested: '$parity' parity set: '$parity_set'")
		if ($self->{DEBUG});
	if ($parity ne $parity_set) {
		$self->{LOG}->do('alert', "$name failed to set parity!");
		return undef;
	}

	my $data_set=$self->databits($data);
	$self->{LOG}->do('debug', "databits requested: '$data' databits set: '$data_set'")
		if ($self->{DEBUG});
	if ($data ne $data_set) {
		$self->{LOG}->do('alert', "$name failed to set databits!");
		return undef;
	}

	my $stop_set=$self->stopbits($stop);
	$self->{LOG}->do('debug', "stopbits requested: '$stop' stopbits set: '$stop_set'")
		if ($self->{DEBUG});
	if ($stop ne $stop_set) {
		$self->{LOG}->do('alert', "$name failed to set stopbits!");
		return undef;
	}

	my $flow_set=$self->handshake($flow);	
	$self->{LOG}->do('debug', "flow requested: '$flow' flow set: '$flow_set'")
		if ($self->{DEBUG});
	if ($flow ne $flow_set) {
		$self->{LOG}->do('alert', "$name failed to set flow control!");
		return undef;
	}

	# set a char timeout for modem commands
	$self->read_char_time(0);          # avg time between read char
        $self->read_const_time(1000/$SPEED);   # delay between calls

	if ($self->{DTRToggleTime} != 0) {
		# hang up just in case
		$self->{LOG}->do('debug', "reseting DTR ...")
			if ($self->{DEBUG});
		# force the dtr down
		$self->dtr_active(0);
		select(undef,undef,undef,$self->{DTRToggleTime});
		$self->dtr_active(1);
	}
	else {
		$self->{LOG}->do('debug',"skipping DTR toggle ...")
			if ($self->{DEBUG});
	}

	# make sure the RTS is up
	$self->{LOG}->do('debug', "forcing RTS ...") if ($self->{DEBUG});
	$self->rts_active(T);

	my $result = undef;
	# allow for blank inits (direct attaches)
	if ($str eq "") {
		$self->{LOG}->do('debug',"skipping init string ...")
			if ($self->{DEBUG});
		$result=1;
	}
	else {
		# send the init string through
		$self->{INITDONE}=1; # frame this to let chat work
		$result=$self->chat("$str\r","$str\r",$ok,$initwait,
			$initretries, $self->{Error},1);
		$self->{INITDONE}=0; # disable again
	}
	if (defined($result)) {
		$self->{INITDONE}=1;
	}
	return $result;
}

sub ready {
	my $self=shift;
	my $func=shift;

	if (!defined($self->{LOCKFILE})) {
		$self->{LOG}->do('crit',"$func: Modem '$self->{NAME}' not locked");
		return undef;
	}
	if (!$self->{INITDONE}) {
		$self->{LOG}->do('crit',"$func: Modem '$self->{NAME}' not initialized");
		return undef;
	}
	return 1;
}

# FIXME: implement dial retries
sub dial {
	my $self=shift;
	my $dial_areacode=shift;
	my $dial_num=shift;
	my $dialwait=shift;
	my $dialretries=shift;

	return undef unless $self->ready("dial");

	my $modem_dial = $self->{Dial};
	my $modem_areacode = $self->{AreaCode};
	my $modem_longdist = $self->{LongDist};
	my $modem_dialout = $self->{DialOut};

	$dialwait = $self->{DialWait} if (!defined($dialwait));
	$dialretries = $self->{DialRetry} if (!defined($dialretries));

	# allow for blank dial strs (direct attaches)
	if ($modem_dial eq "") {
		$self->{LOG}->do('debug',"skipping dial ...")
			if ($self->{DEBUG});
		return 1;
	}

	if (!defined($dial_num) || $dial_num eq "") {
		$self->{LOG}->do('err',"Nothing to dial (no phone number)");
		return undef;
	}

	my $actual_num="";
	my $report="";

	if (defined($dial_areacode) && defined($modem_areacode)) {
		if ($dial_areacode != $modem_areacode) {
			$actual_num=$modem_longdist.$dial_areacode;
			$report="LongDist: '$modem_longdist' ";
			$report.="PCAreaCode: '$dial_areacode' ";
		}
		else {
			$report="(Not LongDist) ";
		}
	}
	else {
		# add the area code anyway
		$actual_num=$dial_areacode;
		if (defined($dial_areacode)) {
			$report="(No Modem AreaCode) ";
			$reprot.="PCAreaCode: '$dial_areacode' "
		}
	}
	# we always need to end the dialing with the phone number...
	$actual_num.=$dial_num;
	$report.="Num: '$dial_num'";

	if ($modem_dialout ne "") {
		$report="DialOut: '$modem_dialout' ".$report;
	}

	$self->{LOG}->do('debug',"Calling with $report") if ($self->{DEBUG});

	return $self->chat($modem_dial.$modem_dialout.$actual_num."\r","",
				$self->{DialOK},$dialwait,1,
				$self->{NoCarrier},1);
}

sub safe_write {
	my ($self,$text) = @_;
	my($textlen,$written);

	if (!defined($self->{LOCKFILE})) {
		$self->{LOG}->do('crit',"safe_write: Modem '$self->{NAME}' not locked");
		return undef;
	}


	$textlen=length($text);
	do {
		$written=$self->write($text);
		if (!defined($written)) {
			$self->{LOG}->do('crit',"write totally failed");
			return undef;
		}
		elsif ($written != $textlen) {
			$self->{LOG}->do('warning',"write was incomplete!?!  retrying...");
			$text=substr($text,$written);
		}
		if ($self->{DEBUG}) {
			$self->{LOG}->do('debug',"wrote: $written ".
				$self->HexStr(substr($text,0,$written)));
		}
		$textlen-=$written;
	} while ($textlen>0);
	return 1;
}


# FIXME: more docs here
# This function examines a stream and interacts like "expect" to find and
# respond to strings, using regular expressions.
# Args:
#	send:	what to immediately send now
#	kicker:	what to send after a timeout waiting for the expected text
#	expect:	what to look for (perl regexp)
#	timeout:time in seconds to wait for the "expect"ed text
#	retries:how many times to send the kicker and restart the timeout
#	dealbreaker:a regexp that indicates total failure (NO CARRIER, etc)
#	ignore_carrier:should the carrier detect signal on the modem
#			be ignored during this chat?
sub chat {
	my $self = shift;
        my ($send,$kicker,$expect,$timeout,$retries,$dealbreaker,
		$ignore_carrier)=@_;
        my ($avail,$got);

	return undef unless $self->ready("chat");

	$ignore_carrier=$self->{IgnoreCarrier}
		if (!defined($ignore_carrier));
	$got=$self->{BUFFER};

	if ($self->{DEBUG}) {
		$self->{LOG}->do('debug',"\tto send: ".$self->HexStr($send));
	        $self->{LOG}->do('debug',"\twant: ".$self->HexStr($expect));
		$self->{LOG}->do('debug',"\tkicker: ".$self->HexStr($kicker));
		$self->{LOG}->do('debug',"\ttimeout: $timeout retries: $retries");
		$self->{LOG}->do('debug', "\thave: ".$self->HexStr($got));
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
	if ($send ne "" && !defined($self->safe_write($send))) {
		$self->{LOG}->do('alert',"safe_write failed!");
	}

	if ($expect eq "") {
		$self->{LOG}->do('debug',"chat defaulted to success: no 'expect' regexp");
		return "";
	}

	# initial check for sucess
	if ($got =~ /($expect)/) {
		my $matched=$1;
		my $upto=$`.$1;
		$self->{BUFFER}=$';	# keep right of match
		$self->{LOG}->do('debug',"chat success: ".$self->HexStr($matched))
			 if ($self->{DEBUG});
		return $upto; 
	}
	if (defined($dealbreaker) && $got =~ /($dealbreaker)/) {
		my $matched=$1;
		my $upto=$`.$1;
		$self->{BUFFER}=$';	# keep right of match
		$self->{LOG}->do('debug',"chat failure: ".$self->HexStr($matched))
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
			$self->{LOG}->do('debug', "timed out, sending kicker")
				if ($self->{DEBUG});
			if (!defined($self->safe_write($kicker))) {
				$self->{LOG}->do('alert',"safe_write failed!");
			}
		}

		# start timeout loop while reading chars
		my $timeleft;
		for ($timeleft=0; $timeleft<$timeout; $timeleft++) {

			# do carrier check
			if (!defined($ignore_carrier)) { 
				my $has_carrier=$self->carrier();
				if (!$has_carrier) {
					$self->{LOG}->do('warning',
						"lost carrier during chat");
					# modem no longer valid
					$self->{INITDONE}=0;
					return undef;
				}
			}

			# try to read char
			($cnt,$avail)=$self->read(255);
			if ($cnt > 0) {
				$self->{LOG}->do('debug', "$cnt seen: ".$self->HexStr($avail))
					if ($self->{DEBUG});
				$got.=$avail;
				$self->{LOG}->do('debug', "have: ".$self->HexStr($got))
					if ($self->{DEBUG});
				
				# reset our timeout
				$timeleft=-1;
			}
			elsif ($self->{DEBUG}) {
				my $msg=sprintf("(timeout: %d/%d, retries: %d/%d)",
					$timeleft/$SPEED,$timeout/$SPEED,
					$tries,$retries);
				$self->{LOG}->do('debug', $msg)
					if (($timeleft % $SPEED) == 0);
			}

			# check for sucess
			if ($got =~ /($expect)/) {
				my $matched=$1;
				my $upto=$`.$1;
				$self->{BUFFER}=$';	# keep right of match
				$self->{LOG}->do('debug',
				   "chat success: ".$self->HexStr($matched))
					if ($self->{DEBUG});
				return $upto; 
			}
			if (defined($dealbreaker) && $got =~ /($dealbreaker)/) {
				my $matched=$1;
				my $upto=$`.$1;
				$self->{BUFFER}=$';	# keep right of match
				$self->{LOG}->do('debug',
				   "chat failure: ".$self->HexStr($matched))
					 if ($self->{DEBUG});
				return undef;
			}
		}
	}

	# failure
	$self->{LOG}->do('debug', "chat failed") if ($self->{DEBUG});
       	return undef;
}

# what is the state of the carrier bit?
sub carrier {
	my $self=shift;

	if (!defined($self->{LOCKFILE})) {
		$self->{LOG}->do('crit',"carrier: Modem '$self->{NAME}' not locked");
		return undef;
	}

	my $ModemStatus = $self->modemlines;
	return (($ModemStatus & $self->MS_RLSD_ON) == $self->MS_RLSD_ON);
}


# drop the carrier if it's there
sub hangup {
	$self=shift;

	if (!defined($self->{LOCKFILE})) {
		$self->{LOG}->do('crit',"hangup: Modem '$self->{NAME}' not locked");
		return undef;
	}

	if (!$self->{IgnoreCarrier} && $self->carrier()) {
		$self->{LOG}->do('debug',"hanging up Modem '$self->{NAME}'")
			if ($self->{DEBUG});
		$self->pulse_dtr_off(500);
	}

	return 1;
}

# give up everything
sub unlock {
	my $self=shift;

	if (!defined($self->{LOCKFILE})) {
		$self->{LOG}->do('crit',"unlock: Modem '$self->{NAME}' not locked");
		return undef;
	}

	$self->hangup();

	if (defined($self->{LOCKFILE})) {
		$self->{LOG}->do('debug',"unlocking Modem '$self->{NAME}'")
			if ($self->{DEBUG});
		unlink($self->{LOCKFILE});
		undef $self->{LOCKFILE};
	}
}

# what happens when we get destroyed
sub DESTROY {
	my $self = shift;

 	$self->{LOG}->do('debug',"Modem Object '$self->{NAME}' being destroyed") if ($self->{DEBUG});

	$self->unlock() if (defined($self->{LOCKFILE}));

	# Very weird: don't Perl objects destroy parents?
	$self->close();
}

# extra bits...
sub HexDump {
        my($self,$text)=@_;

        my $str=$self->HexStr($text);

        $self->{LOG}->do('debug', "len %d: %s",length($text),$str);
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

