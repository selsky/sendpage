package Sendpage::Modem;

# Modem.pm extends the Device::SerialPort package, and adds a few things
#
# $Id$
#
# Copyright (C) 2000-2004 Kees Cook
# kees@outflux.net, http://outflux.net/
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
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
# <URL:http://www.gnu.org/copyleft/gpl.html>

use strict;
use warnings;

use POSIX;
use IO::Handle;
use Sendpage::KeesLog;

# FIXME: Hey!  Duh!  I should use the OS auto-discovery system to get the
# right serial device module here!
use Device::SerialPort;
our @ISA = ("Device::SerialPort");

=head1 NAME

Sendpage::Modem - extends the Device::SerialPort package

=head1 SYNOPSIS

 $modem = Sendpage::Modem->new($params);
 $modem->init($baud, $parity, $data, $stop, $flow, $str);
 $modem->ready($functionname);
 $modem->dial($areacode, $phonenumber, $timeout);
 $modem->chat($send, $resend, $expect, $timeout,
              $retries, $dealbreaker, $carrier);
 $modem->hangup();

 $str = Sendpage::Modem->HexStr("tab:\t cr:\r");

=head1 DESCRIPTION

This module is used by L<sendpage> as an interface for working with
modem devices by extending the L<Device::SerialPort> module.

=head1 BUGS

This needs more docs.

=cut


# globals
my $SPEED = 10;	# arbitrary: how much to speed up the char reader timeout

# new methods here are:
#	init		- inits modem
#	dial		- dials number (returns like "write")
#	hangup		- hangs up modem

=pod

The currently-implemented methods are:

=over 4

=item new LIST

Instantiates a new Modem.

Accepts modem parameters.

=cut

# new modem
#	takes:
#		modem parameters
#
sub new
{
    # local vars
    my ($lockfile, $realdev, $pid);

    # get our args
    my $proto = shift;
    my %arg   = @_;

    my $name  = $arg{Name};

    my $dev	   = $arg{Dev};
    my $lockprefix = $arg{Lockprefix};
    my $debug      = $arg{Debug};
    my $log	   = $arg{Log} || new Sendpage::KeesLog(Syslog => 0);

    # sanity check our config options
    unless (defined $lockprefix) {
	$log->do('alert',"Modem '$name' has no lockprefix defined");
	undef $log;
	return undef;
    }
    unless (defined($dev) || $dev ne "/dev/null") {
	$log->do('alert',"Modem '$name' has no device defined");
	undef $log;
	return undef;
    }

    # We need to build the name of the lock file
    $lockfile = $lockprefix;

    # FIXME: I need clarification on this: should we discover the
    # true name of the device or not?
    ## figure out what the REAL device name is
    #if (!defined($realdev=readlink($dev))) {
    #	# not a symlink
    $realdev = $dev;
    #}

    # now, chop the name of the dev off
    my @parts  = split m#/#, $realdev;
    $lockfile .= pop @parts;
    # $lockfile should now be in the form "/var/lock/LCK..ttyS0"

    $log->do('debug', "Locking with '$lockfile' ...") if $debug;

    # FIXME: I still don't feel that this is a Perlish thing to do,
    # but it works; I'll have to dig more in PerlMonks, or in the
    # Cookbook...
    #
    # Kees told me that the following implements a UUCP-style locking
    # mechanism, but I suppose I could add Perl's flock() here for added
    # strength.
    until (sysopen(LOCKFILE, "$lockfile", O_EXCL | O_CREAT | O_RDWR)) {
	if ($! == EEXIST) {
	    # Our lockfile previously existed
	    if (sysopen(LOCKFILE, "$lockfile", O_RDONLY)) {
		# read PID
		local $_ = <LOCKFILE> || "";
		close LOCKFILE;
		$pid = (/^\s*(\d+)/) ? $1 : -1;
		undef $!;	# whoa: we need to clear this
		if ($pid > 0) {
		    # Someone used the device recently
		    kill 0, $pid; # check if $pid is alive
		    if ($! == ESRCH) {
			# $pid is deceased (or zombiefied)
			$log->do('debug',
				 "Modem '$name': stale lockfile from PID $pid removed");
			unlink($lockfile), next;
		    }
		} elsif ($pid < 0) {
		    # We shouldn't really go here, unless something
		    # nasty is up...
		    $log->do('warning',
			     "Modem '$name': malformated lockfile being removed");
		    unlink($lockfile), next;
		}
		# allow PID '0' from the "lockfile"
		# program to exist indefinitely.
	    }

	    # cannot touch lockfile
	    $log->do('warning',
		     "Modem '$name': '$dev' is locked by process '$pid'");
	    undef $log;
	    return undef;
	} else {
	    $log->do('alert',
		     "Modem '$name': cannot access lockfile '$lockfile': %s",$!);
	    undef $log;
	    return undef;
	}
    }

    # we have the lock file now
    print LOCKFILE sprintf("%10d\n", $$);
    close LOCKFILE;

    # handle inheritance?
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new($dev); # this should be SerialPort
    my $ref;				  # Hmmm, unused?

    unless (defined $self) {
	$log->do('crit',
		 "Modem '$name': could not start Device::Serial port: %s",
		 $!);
	unlink $lockfile;
	undef $log;
	return undef;
    }

    # save our stateful information
    $self->{MYNAME}   = $name;		# name of the modem
    $self->{LOCKFILE} = $lockfile;	# where our lockfile is
    $self->{DEBUG}    = $debug;		# debug mode?
    $self->{INITDONE} = 0;		# we have not run "init"

    # internal buffer for 'chat'
    $self->{BUFFER} = "";

    bless $self, $class;

    # Do Device::SerialPort capability sanity checking
    unless ($self->can_ioctl()) {
	$log->do('crit',
		 "Modem '$name' cannot do ioctl's.  Did 'configure' run correctly when you built sendpage?");
	# get rid of modem
	$self->unlock();
	undef $log;
	undef $self;
    }

    # grab config settings
    foreach my $index ( qw(Baud Parity StrictParity Data Stop Flow Init InitOK
			   InitWait InitRetry Error Dial DialOK DialWait
			   DialRetry NoCarrier CarrierDetect DTRToggleTime
			   AreaCode LongDist DialOut) ) {
	if (defined($arg{$index})) {
	    $self->{$index} = $arg{$index};
	    $log->do('debug',
		     "Modem '$name' setting '$index': '". $self->{$index} . "'")
		if $self->{DEBUG};
	}
    }

    $self->{LOG} = $log;	# get the log object
    return $self;
}

=item init LIST

Initialize a Sendpage::Device with given settings and sends the init
string.

Accepts baud rate, parity, data bits, stop bits, flow control flag,
init string, and parity strictness (for Win32 systems.)

Emits whatever the result of a C<chat> call (inherited from
L<Device::SerialPort>,) C<undef> otherwise.

=cut

# init settings and send init string
# takes:
#	baud, parity, data, stop, flow, init str
sub init
{
    my $self = shift;
    my($baud, $parity, $data, $stop, $flow, $str, $strict_parity) = @_;
    my $name = "Modem '$self->{MYNAME}'";

    unless (defined $self->{LOCKFILE}) {
	$self->{LOG}->do('crit',"init: $name not locked");
	return undef;
    }

    $baud	   ||= $self->{Baud};
    $parity	   ||= $self->{Parity};
    $data	   ||= $self->{Data};
    $stop	   ||= $self->{Stop};
    $flow	   ||= $self->{Flow};
    $str	   ||= $self->{Init};
    $strict_parity ||= $self->{StrictParity};

    my $ok	    = $self->{InitOK};
    my $initwait    = $self->{InitWait};
    my $initretries = $self->{InitRetry};

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
    $self->alias($self->{MYNAME});

    my $baud_set = $self->baudrate($baud);
    $self->{LOG}->do('debug', "baud requested: '$baud' baud set: '$baud_set'")
	if $self->{DEBUG};
    if ($baud ne $baud_set) {
	$self->{LOG}->do('alert', "$name failed to set baud rate!");
	return undef;
    }

    my $parity_set = $self->parity($parity);
    $self->{LOG}->do('debug',
		     "parity requested: '$parity' parity set: '$parity_set'")
	if $self->{DEBUG};
    if ($parity ne $parity_set) {
	$self->{LOG}->do('alert', "$name failed to set parity!");
	return undef;
    }

    # Make sure we're backward compatible with Win32
    if ($self->can("stty_inpck") && $self->can("stty_istrip")) {
	if ($strict_parity) {
	    $self->stty_inpck(1);
	    $self->stty_istrip(1);
	} else {
	    $self->stty_inpck(0);
	    $self->stty_istrip(0);
	}
    }

    my $data_set = $self->databits($data);
    $self->{LOG}->do('debug',
		     "databits requested: '$data' databits set: '$data_set'")
	if $self->{DEBUG};
    if ($data ne $data_set) {
	$self->{LOG}->do('alert', "$name failed to set databits!");
	return undef;
    }

    my $stop_set = $self->stopbits($stop);
    $self->{LOG}->do('debug',
		     "stopbits requested: '$stop' stopbits set: '$stop_set'")
	if $self->{DEBUG};
    if ($stop ne $stop_set) {
	$self->{LOG}->do('alert', "$name failed to set stopbits!");
	return undef;
    }

    my $flow_set = $self->handshake($flow);
    $self->{LOG}->do('debug', "flow requested: '$flow' flow set: '$flow_set'")
	if $self->{DEBUG};
    if ($flow ne $flow_set) {
	$self->{LOG}->do('alert', "$name failed to set flow control!");
	return undef;
    }

    # set a char timeout for modem commands
    $self->read_char_time(0);		 # avg time between read char
    $self->read_const_time(1000/$SPEED); # delay between calls

    if ($self->{DTRToggleTime} != 0) {
	# hang up just in case
	$self->{LOG}->do('debug', "reseting DTR ...")
	    if $self->{DEBUG};
	# force the dtr down
	$self->dtr_active(0);
	select(undef, undef, undef, $self->{DTRToggleTime});
	$self->dtr_active(1);
    } else {
	$self->{LOG}->do('debug', "skipping DTR toggle ...")
	    if $self->{DEBUG};
    }

    # make sure the RTS is up
    $self->{LOG}->do('debug', "forcing RTS ...") if $self->{DEBUG};
    $self->rts_active('T');

    my $result = undef;
    # allow for blank inits (direct attaches)
    if ($str eq "") {
	$self->{LOG}->do('debug', "skipping init string ...")
	    if $self->{DEBUG};
	$result = 1;
    } else {
	# send the init string through
	$self->{INITDONE} = 1;	# frame this to let chat work
	$result = $self->chat("$str\r", "$str\r", $ok, $initwait,
			      $initretries, $self->{Error}, "off");
	$self->{INITDONE} = 0;	# disable again
    }
    if (defined $result) {
	$self->{INITDONE} = 1;
    }
    return $result;
}

=item ready FUNCNAME

Checks is a Sendpage::Device is locked and initialized properly.

Accepts the name of a function to be used after C<check>ing.

Emits 1 if ok, C<undef> otherwise.

=cut

sub ready
{
    my $self = shift;
    my $func = shift;

    unless (defined $self->{LOCKFILE}) {
	$self->{LOG}->do('crit', "$func: Modem '$self->{MYNAME}' not locked");
	return undef;
    }
    unless ($self->{INITDONE}) {
	$self->{LOG}->do('crit',
			 "$func: Modem '$self->{MYNAME}' not initialized");
	return undef;
    }
    return 1;
}

=item dial LIST

Dial a number.

Accepts the I<area code> number, the I<number> to be dialed, I<waiting
time> (in seconds) between dials, and the number of I<dial retries>
before giving up.

Emits C<undef> if unsuccessful, or the result of the succeeding C<chat>
call.

=cut

# FIXME: implement dial retries
sub dial
{
    my ($self, $dial_areacode, $dial_num, $dialwait, $dialretries) = @_;

    return undef unless $self->ready("dial");

    my $modem_dial     = $self->{Dial};
    my $modem_areacode = $self->{AreaCode};
    my $modem_longdist = $self->{LongDist};
    my $modem_dialout  = $self->{DialOut};

    $dialwait    ||= $self->{DialWait};
    $dialretries ||= $self->{DialRetry};

    # allow for blank dial strs (direct attaches)
    if ($modem_dial eq "") {
	$self->{LOG}->do('debug', "skipping dial ...")
	    if $self->{DEBUG};
	return 1;
    }

    unless (defined($dial_num) || $dial_num ne "") {
	$self->{LOG}->do('err', "Nothing to dial (no phone number)");
	return undef;
    }

    my $actual_num = "";
    my $report     = "";

    if (defined($dial_areacode) && defined($modem_areacode)) {
	if ($dial_areacode != $modem_areacode) {
	    $actual_num  = $modem_longdist . $dial_areacode;
	    $report      = "LongDist: '$modem_longdist' ";
	    $report     .= "PCAreaCode: '$dial_areacode' ";
	} else {
	    $report      = "(Not LongDist) ";
	}
    } else {
	# add the area code anyway
	$actual_num = $dial_areacode;
	if (defined($dial_areacode)) {
	    $report  = "(No Modem AreaCode) ";
	    $report .= "PCAreaCode: '$dial_areacode' "
	}
    }
    # we always need to end the dialing with the phone number...
    $actual_num .= $dial_num;
    $report     .= "Num: '$dial_num'";

    if ($modem_dialout ne "") {
	$report = "DialOut: '$modem_dialout' " . $report;
    }

    $self->{LOG}->do('debug', "Calling with %s", $report) if $self->{DEBUG};

    return $self->chat($modem_dial . $modem_dialout . $actual_num . "\r",
		       "", $self->{DialOK}, $dialwait, 1,
		       $self->{NoCarrier}, "off");
}

=item safe_write STRING

Write a message text.

Accepts a message string.

Emits 1 if successful, C<undef> otherwise.

=cut

sub safe_write
{
    my ($self, $text) = @_;
    my ($textlen, $written);

    unless (defined $self->{LOCKFILE}) {
	$self->{LOG}->do('crit',
			 "safe_write: Modem '$self->{MYNAME}' not locked");
	return undef;
    }


    $textlen = length($text);
    do {
	$written = $self->write($text);
	if (!defined($written)) {
	    $self->{LOG}->do('crit', "write totally failed");
	    return undef;
	} elsif ($written != $textlen) {
	    $self->{LOG}->do('warning',"write was incomplete!?!  retrying...");
	    $text = substr($text, $written);
	}
	if ($self->{DEBUG}) {
	    $self->{LOG}->do('debug',"wrote: %d %s",
			     $written,
			     $self->HexStr(substr($text, 0, $written)));
	}
	$textlen -= $written;
    } while ($textlen > 0);
    return 1;
}

=item chat LIST

Examine a stream and interact like C<expect> to find and respond to
strings using regular expressions.

Accepts FIXME

Emits FIXME

=cut

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
#	carrier:should the carrier detect signal on the modem
#		be ignored during this chat, or use DSR? ("on","off", "dsr")
sub chat {
    my $self = shift;
    my ($send, $kicker, $expect, $timeout, $retries, $dealbreaker, $carrier) = @_;
    my ($got);

    return undef unless $self->ready("chat");

    $carrier = $self->{CarrierDetect} unless defined $carrier;
    $got     = $self->{BUFFER};

    if ($self->{DEBUG}) {
	$self->{LOG}->do('debug', "\tto send: %s", $self->HexStr($send));
	$self->{LOG}->do('debug', "\twant: %s", $self->HexStr($expect));
	$self->{LOG}->do('debug', "\tkicker: %s", $self->HexStr($kicker));
	$self->{LOG}->do('debug', "\ttimeout: $timeout retries: $retries");
	$self->{LOG}->do('debug', "\thave: %s", $self->HexStr($got));
    }

    # useful variables:
    #  $got		contains the full text of chars read


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
    $self->{LOG}->do('alert', "safe_write failed!")
	if ($send ne "" && !defined($self->safe_write($send)));

    if ($expect eq "") {
	$self->{LOG}->do('debug',
			 "chat defaulted to success: no 'expect' regexp");
	return "";
    }

    # initial check for sucess
    # FIXME: Hmm, using $` and $' is expensive...
    if ($got =~ /($expect)/) {
	my $matched	= $1;
	my $upto	= $` . $1;
	$self->{BUFFER} = $';	# keep right of match
	$self->{LOG}->do('debug', "chat success: %s", $self->HexStr($matched))
	    if $self->{DEBUG};
	return $upto; 
    }
    if (defined($dealbreaker) && $got =~ /($dealbreaker)/) {
	my $matched	= $1;
	my $upto	= $` . $1;
	$self->{BUFFER} = $';	# keep right of match
	$self->{LOG}->do('debug', "chat failure: %s", $self->HexStr($matched))
	    if $self->{DEBUG};
	return undef;
    }

    # up our timeout to tenths
    $timeout *= $SPEED;

    # start retry loop
    my $tries;
    for ($tries = 0; $tries < $retries; $tries++) {

	# send kicker (unless this is the first time through)
	if ($kicker ne "" && $tries > 0) {
	    $self->{LOG}->do('debug', "timed out, sending kicker")
		if $self->{DEBUG};
	    $self->{LOG}->do('alert', "safe_write failed!")
		unless defined $self->safe_write($kicker);
	}

	# start timeout loop while reading chars
	my $timeleft;
	for ($timeleft = 0; $timeleft < $timeout; $timeleft++) {

	    # do carrier check
	    my $has_carrier = $self->carrier($carrier);
	    if (!$has_carrier) {
		$self->{LOG}->do('warning',
				 "lost carrier during chat");
		# modem no longer valid
		$self->{INITDONE} = 0;
		return undef;
	    }

	    # try to read char
	    my ($cnt, $avail) = $self->read(255);
	    if ($cnt > 0) {
		$self->{LOG}->do('debug', "$cnt seen: %s",
				 $self->HexStr($avail))
		    if $self->{DEBUG};
		$got .= $avail;
		$self->{LOG}->do('debug', "have: %s", $self->HexStr($got))
		    if $self->{DEBUG};
	    } elsif ($self->{DEBUG}) {
		my $msg = sprintf("(timeout: %d/%d, retries: %d/%d)",
				  $timeleft / $SPEED, $timeout / $SPEED,
				  $tries, $retries);
		$self->{LOG}->do('debug', "%s", $msg)
		    if (($timeleft % $SPEED) == 0);
	    }

	    # check for sucess
	    if ($got =~ /($expect)/) {
		my $matched	= $1;
		my $upto	= $` . $1;
		$self->{BUFFER} = $'; # keep right of match
		$self->{LOG}->do('debug',
				 "chat success: %s", $self->HexStr($matched))
		    if $self->{DEBUG};
		return $upto;
	    }
	    if (defined($dealbreaker) && $got =~ /($dealbreaker)/) {
		my $matched	= $1;
		my $upto	= $` . $1;
		$self->{BUFFER} = $'; # keep right of match
		$self->{LOG}->do('debug',
				 "chat failure: %s", $self->HexStr($matched))
		    if $self->{DEBUG};
		return undef;
	    }
	}
    }

    # failure
    $self->{LOG}->do('debug', "chat failed") if $self->{DEBUG};
    return undef;
}

=item carrier STRING

Check for the state of the carrier bit.

Accepts a I<string> specifying the type of carrier bit check.  If C<on>
is given, checks for MS_RLSD_ON; if C<dsr>, checks for MS_DSR_ON.  If
C<off> no checking is done; the number 1 is emitted.

FIXME: Better docs here

=cut

# what is the state of the carrier bit?
sub carrier
{
    my $self = shift;
    my $way  = shift;		# "on", "off", or "dsr"

    unless (defined $self->{LOCKFILE}) {
	$self->{LOG}->do('crit',
			 "carrier: Modem '$self->{MYNAME}' not locked");
	return undef;
    }

    return 1 if ($way =~ /off/i);

    if ($way =~ /on/i) {
	my $ModemStatus = $self->modemlines;
	return (($ModemStatus & $self->MS_RLSD_ON) == $self->MS_RLSD_ON);
    }
    if ($way =~ /dsr/i) {
	my $ModemStatus = $self->modemlines;
	return (($ModemStatus & $self->MS_DSR_ON) == $self->MS_DSR_ON);
    }
    $self->{LOG}->do('crit',
		     "carrier: Modem '$self->{MYNAME}' unknown carrier check '$way'");
    return undef;
}

=item hangup

Drops the carrier connected to the Sendpage::Device.

Emits 1 if successful, C<undef> otherwise.

=cut

# drop the carrier if it's there
sub hangup
{
    my $self = shift;

    unless (defined $self->{LOCKFILE}) {
	$self->{LOG}->do('crit', "hangup: Modem '$self->{MYNAME}' not locked");
	return undef;
    }

    if ($self->{CarrierDetect}!~/off/i
	&& $self->carrier($self->{CarrierDetect})) {
	$self->{LOG}->do('debug',
			 "toggling DTR to hang up Modem '$self->{MYNAME}'")
	    if $self->{DEBUG};
	$self->pulse_dtr_off(500);
    }

    return 1;
}

=item unlock()

Unlock a modem.

Emits C<undef> only if the modem is not locked.

=cut

# give up everything
sub unlock
{
    my $self = shift;

    unless (defined $self->{LOCKFILE}) {
	$self->{LOG}->do('crit', "unlock: Modem '$self->{MYNAME}' not locked");
	return undef;
    }

    $self->hangup();

    if (defined($self->{LOCKFILE})) {
	$self->{LOG}->do('debug', "unlocking Modem '$self->{MYNAME}'")
	    if $self->{DEBUG};
	unlink($self->{LOCKFILE});
	undef $self->{LOCKFILE};
    }
}

=item DESTROY()

Cleanup code, implicitly executed.

=cut

# what happens when we get destroyed
sub DESTROY
{
    my $self = shift;

    # since I call "close", a weird double-destroy happens, need these
    # for final logging
    #my $log=$self->{LOG};
    #my $name=$self->{MYNAME};
    #my $debug=$selft->{DEBUG};

    $self->{LOG}->do('debug', "Modem Object '$self->{MYNAME}' being destroyed")
	if $self->{DEBUG};

    $self->unlock() if defined $self->{LOCKFILE};

    # call parent destructor
    $self->SUPER::DESTROY;

    $self->{LOG}->do('debug', "Modem Object '$self->{MYNAME}' destroyed")
	if $self->{DEBUG};
}

=for developers: Add new functions here.

=back

=cut

# extra bits...
sub HexDump
{
    my ($self, $text) = @_;

    my $str = $self->HexStr($text);

    $self->{LOG}->do('debug', "len %d: %s", length($text), $str);
}

sub HexStr
{
    my $self  = shift;
    my $text  = shift;
    my ($str, @chars);

    if (defined($text)) {
	@chars = split // => $text;
	for my $i (@chars) {
	    if ($i !~ /^[\040-\176]$/) {
		$str .= sprintf("{0x%02X}", ord($i));
	    } else {
		$str .= $i;
	    }
	}
    } else {
	$str .= "-undef-";
    }

    return $str;
}

1;				# This is a module

__END__

=head1 AUTHOR

Kees Cook <kees@outflux.net>

=head1 BUGS

This needs more docs; DEFINITELY!

=head1 SEE ALSO

Man pages: L<perl>, L<sendpage>.

Module documentation: L<Sendpage::KeesConf>, L<Sendpage::KeesLog>,
L<Sendpage::PagingCentral>, L<Sendpage::PageQueue>, L<Sendpage::Page>,
L<Sendpage::Recipient>, L<Sendpage::Queue>

=head1 COPYRIGHT

Copyright 2000-2003 Kees Cook.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
