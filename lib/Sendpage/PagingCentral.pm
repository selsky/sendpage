#
# PagingCentral.pm implements the TAP protocol
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

package Sendpage::PagingCentral;
use Sendpage::Modem;
use Sendpage::KeesConf;
use Mail::Send;

=head1 NAME

PagingCental.pm - implements the TAP protocol over the Modem module

=head1 SYNOPSIS

    $pc=Sendpage::PagingCentral->new($config,$name);

    $rc=$pc->start_proto();
    $rc=$pc->send($pin,$text);
    ...
    $pc->disconnect();

    $rc=$pc->deliver($page);

    $pc->SendMail($to,$from,$cc,$subject,$body);

=head1 DESCRIPTION

This is a module for use in sendpage(1).

=head1 BUGS

Need to write more docs.

=cut


# Various return code literals
$SKIP_MSG   = 4;
$PERM_ERROR = 3;
$TEMP_ERROR = 2;
$SUCCESS    = 1;

# Timings
my @T=(undef, 2, 1, 10, 4, 8);
# Retries
my @N=(1, 3, 3, 3);
# Sequence Codes
my %SeqMajor = (	100 => "Informational Text",
		200 => "Positive Completion",
		300 => "Unused",
		400 => "Unused",
		500 => "Negative Completion",
		600 => "Unused",
		700 => "Unused",
		800 => "Unused",
		900 => "Unused"
	);
my %SeqMinor = (
		110 => "Paging Terminal TAP Specification Supported",
		111 => "Paging terminal is processing the previous input -- please wait",
		112 => "Maximum pages enter for session",
		113 => "Maximum time reached for session",
		114 => "Welcome banners",
		115 => "Exit Messages",
		211 => "Page(s) Sent Successfully",
		212 => "Long message truncated and sent",
		213 => "Message accepted - held for deferred delivery",
		214 => "Character maximum, message has been truncated and sent",
		501 => "A time-out occurred waiting for user input",
		502 => "Unexpected characters received before the start of a transaction",
		503 => "Excessive attempts to send/re-send a transaction with checksum errors",
		504 => "The message field of the TAP transaction contained characters, but message characters are not allowed for the Pager format.  Perhaps the paging receiver for the given PIN is a 'Tone Only' pager.",
		505 => "Message portion of the TAP transaction contained alphabetic characters, but alphabetics characters are not allowed for the Pager format.  Perhaps the paging receiver for the given PIN is a 'numeric' pager.",
		506 => "Excessive invalid pages received",
		507 => "Invalid Logon attempt: incorrectly formed login sequence",
		508 => "Invalid Login attempt: Service type and category given is not supported",
		509 => "Invalid Login attempt: Invalid password supplied",
		510 => "Illegal Pager ID - The pager ID contains illegal characters or is too long or short",
		511 => "Invalid Pager ID - There is no subscriber to match this ID",
		512 => "Temporarily cannot deliver to Pager ID - Try Later",
		513 => "Long message rejected for exceeding maximum character length",
		514 => "Checksum error",
		515 => "Message format error",
		516 => "Message quota temporarily exceeded",
		517 => "Character maximum, message rejected"
	);

my $CR="\x0d";
my $LF="\x0a";
my $ESC="\x1b";
my $ACK="\x06";
my $NAK="\x15";
my $STX="\x02";
my $ETX="\x03";
my $EOT="\x04";
my $RS="\x1e";
my $US="\x1f";
my $ETB="\x17";
my $SUB="\x1a";

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self  = {};

	$self->{CONFIG} = shift;
	$self->{NAME}   = shift;
	$self->{MODEMS} = shift;

	$self->{DEBUG}  = $self->{CONFIG}->get("pc:$self->{NAME}\@debug");
	$self->{ESC}    = $self->{CONFIG}->get("pc:$self->{NAME}\@esc");
	$self->{CTRL}   = $self->{CONFIG}->get("pc:$self->{NAME}\@ctrl");
	$self->{LFOK}   = $self->{CONFIG}->get("pc:$self->{NAME}\@lfok");
	$self->{FIELDS} = $self->{CONFIG}->get("pc:$self->{NAME}\@fields");
	$self->{MAXCHARS}=$self->{CONFIG}->get("pc:$self->{NAME}\@maxchars");
	$self->{MAXSPLITS}=$self->{CONFIG}->get("pc:$self->{NAME}\@maxsplits");

	$self->{LEAD}="";
	$self->{LEAD}=$CR
		if ($self->{CONFIG}->get("pc:$self->{NAME}\@stricttap"));

	bless($self,$class);
	return $self;
}

sub start_proto {
	my $self=shift;

	my(@modems, $modem, $name, $report, $ref);

	# find an available modem
	$ref=$self->{CONFIG}->get("pc:$self->{NAME}\@modems",1);
	if (!defined($ref)) {
		$ref=$self->{CONFIG}->get("modems",1);
		if (!defined($ref)) {
			@modems=@{ $self->{MODEMS} }; # use all known available
		}
	}
	else {
		@modems=@{ $ref };
	}

	# we need to make sure that we only use the modems that
	# we're allowed to use and that
	# were detected as "functioning" during startup
	my(%avail,@okay);

	# which are available?
	foreach $modem (@{ $self->{MODEMS} }) {
		$avail{$modem}=1;
	}

	undef @okay;
	foreach $modem (@modems) {
		push(@okay,$modem) if (defined($avail{$modem}));
	}

	@modems=@okay;

	my $config=$self->{CONFIG};

	# try each modem,  FIXME: should we do some sort of round-robin?
	foreach $name (@modems) {
                $modem = Sendpage::Modem->new(Name => $name,
                        Dev => $config->get("modem:${name}\@dev"),
                        Lockprefix => $config->get("lockprefix"),
                        Debug => $config->get("modem:${name}\@debug"),
                        Log => $main::log,
                        Baud => $config->get("modem:${name}\@baud"),
                        Parity => $config->get("modem:${name}\@parity"),
                        Data => $config->get("modem:${name}\@data"),
                        Stop => $config->get("modem:${name}\@stop"),
                        Flow => $config->get("modem:${name}\@flow"),
                        Init => $config->get("modem:${name}\@init"),
                        InitOK => $config->get("modem:${name}\@initok"),
                        InitWait => $config->get("modem:${name}\@initwait"),
                        InitRetry => $config->get("modem:${name}\@initretries"),
                        Error => $config->get("modem:${name}\@error"),
                        Dial => $config->get("modem:${name}\@dial"),
                        DialOK => $config->get("modem:${name}\@dialok"),
                        DialWait => $config->get("modem:${name}\@dialwait"),
                        DialRetry => $config->get("modem:${name}\@dialretries"),
                        NoCarrier => $config->get("modem:${name}\@no-carrier"),
			DTRToggleTime => $config->get("modem:${name}\@dtrtime"),
                        IgnoreCarrier => $config->get("modem:${name}\@ignore-carrier",1),
                        AreaCode => $config->get("modem:${name}\@areacode",1),
                        LongDist => $config->get("modem:${name}\@longdist"),
                        DialOut =>  $config->get("modem:${name}\@dialout")
                );

		last if (defined($modem));
	}
	# make sure we got one
	if (!defined($modem)) {
		$main::log->do('crit',"No modems available");
		return (undef,"All modems presently in use");
	}

	# Init modem
	my $result=$modem->init(
		$self->{CONFIG}->ifset("pc:$self->{NAME}\@baud"),
		$self->{CONFIG}->ifset("pc:$self->{NAME}\@parity"),
		$self->{CONFIG}->ifset("pc:$self->{NAME}\@data"),
		$self->{CONFIG}->ifset("pc:$self->{NAME}\@stop"),
		$self->{CONFIG}->ifset("pc:$self->{NAME}\@flow"));
	if (!defined($result)) {
		$main::log->do('alert',"Failed to initialize modem");
		return (undef,"Could not initialize modem");
	}

	# Dial
	$result=$modem->dial($self->{CONFIG}->get("pc:$self->{NAME}\@areacode",1),
			     $self->{CONFIG}->get("pc:$self->{NAME}\@phonenum"),
			     $self->{CONFIG}->get("pc:$self->{NAME}\@dialwait",1)
			);
	if (!defined($result)) {
		$main::log->do('crit',"Failed to dial modem");
		return (undef,"Could not dial out");
	}

	# wait for ID=
	#   timeout("\r")
	$result=$modem->chat("\r","\r","ID=",
		$self->{CONFIG}->get("pc:$self->{NAME}\@answerwait"),
		$self->{CONFIG}->get("pc:$self->{NAME}\@answerretries"));
	if (!defined($result)) {
		$main::log->do('crit',"PC did not send 'ID=' tag");
		return (undef,"Could not perform protocol startup");
	}

	# Try to log on
	#					ID=
	#    \033PG1${PASS}\r

	my $LEAD=$self->{LEAD};
	my $LOGONretries=3;	# this is protocol-defined
	my $SST="PG1";		# we only support this proto so far
	my $PASS=$self->{CONFIG}->get("pc:$self->{NAME}\@password");

	# adjust the length of the password to MAKE SURE it's 6 chars
	if (length($PASS)>6) {
		$PASS=substr($PASS,0,6);
	}
	elsif (length($PASS)<6) {
		# should I be back-filling this password?
		#$PASS=sprintf("%06s",$PASS);
	}

	# supposedly, we can get a go-head here too, so we should handle it
	my $early_go_ahead;
	undef $early_go_ahead;

	my $logged_in=0;
	while (!$logged_in && $LOGONretries) {

		$result=$modem->chat("${ESC}${SST}${PASS}\r","",
		  "(${LEAD}(${ACK}|${NAK}|${ESC}${EOT})${CR}|${ESC}\\[p${CR})",
		  $T[3],$N[0]); # the N here is not spec'd
		if (!defined($result)) {
			$main::log->do('crit',"PC timed out during logon attempt");
		}
		$modem->HexDump($result) if ($self->{DEBUG});

		#					something\rcode\r
		#   nak: retry
		#   ack: followed with go ahead
		#   eot: failure
		# show any messages
		$report=$self->ReportMsgSeq($result);

		if ($result =~ /${ESC}\[p${CR}/) {
			# got an early go ahead, skip next chat
			$main::log->do('debug',"Got early go-ahead")
				if ($self->{DEBUG});
			# FIXME: we're pattern matching on the entire string
			#	instead of feeding the "leftovers" back into
			#	the "chat" tool
			$logged_in=1;
			$early_go_ahead=1;
		}
		elsif ($result =~ /${LEAD}${ACK}${CR}/) {
			# Logon accepted
			$logged_in=1;
			$main::log->do('debug',"Logon success!")
				if ($self->{DEBUG});
		}
		elsif ($result =~ /${LEAD}${NAK}${CR}/) {
			# Logon requested again
			$LOGONretries--;
			$main::log->do('debug',"Logon needs to be retried")
				if ($self->{DEBUG});
		}
		elsif ($result =~ /${LEAD}${ESC}${EOT}${CR}/) {
			# Forced disconnected
			$main::log->do('crit',"PC requested immediate disconnect");
			return (undef,"Immediate disconnect requested: $report");
		}
	
		# make report on failure or debug
		$main::log->do($logged_in==1 ? 'debug' : 'crit',
			"proto_startup: $report")
			if ($report ne "" && ($self->{DEBUG} || $logged_in!=1));
	}
	if (!$logged_in) {
		$main::log->do('crit',"Tried to log in $LOGONretries times and failed");
		return undef;
	}

	if (!defined($early_go_ahead)) {
		# wait for them to be done announcing crap
		#					${GO_AHEAD}\r
		# n is not spec'd here
		$result=$modem->chat("","","${ESC}\\[p${CR}",$T[3],$N[0]);
		if (!defined($result)) {
			$main::log->do('crit',"PC timed out during logon speech");
			return (undef,"Protocol timed out");
		}
		$modem->HexDump($result) if ($self->{DEBUG});
		$report=$self->ReportMsgSeq($result);

		$main::log->do('debug',"go ahead: $report")
			if ($report ne "" && $self->{DEBUG});
	}

	$self->{MODEM}=$modem;
	return (1,"Proto startup success");
}

sub send {
	my $self = shift;
	my ($PIN,$text) = @_;
	my $report;

	if (!defined($self->{MODEM})) {
		($rc,$report)=$self->start_proto();
		if (!defined($rc)) {
			$main::log->do('crit',"proto startup failed (%s)",$report);
			return ($TEMP_ERROR,$report); # temp failure
		}
	}

	# now we are at step 8, and we can send pages
	my @fields=($PIN,$text);

	return $self->HandleMessage(@fields);
}

sub deliver {
	my($self,$page)=@_;
	my($rc, $report);
	my($to,$cc,$extra,$temprep,$failrep,$attempts,$maxtemp);

	$temprep=$self->{CONFIG}->get("tempfail-notify-after");
	$failrep=$self->{CONFIG}->get("fail-notify");
	$maxtemp=$self->{CONFIG}->get("max-tempfail");

	for ($page->reset(), $page->next();
	     defined($recip=$page->recip());
	     $page->next()) {
		# gather info from the page
		$attempts=$page->attempts();
		$to=$page->option('from');
		$cc=$recip->datum('email-cc');

		# attempt to send the page
		($rc,$report) = $self->send($recip->pin(),$page->text());
		my $now=time;

		# push temp error into a perm fail if needed
		if ($rc == $TEMP_ERROR && $attempts > $maxtemp) {
			$rc=$PERM_ERROR;
			$report.="\n'Too many errors ($attempts) -- giving up.'";
		}

		# gather the reported info
		$extra="";
		if (defined($report) && $report ne "") {
			$extra="Paging Central reported:\n$report";
		}

		# delay information
		if ($now < $page->option('when')) {
			$main::log->do('warning',"Weird.  Page got delivered before it was ready to be sent.");
		}
		else {
			$now-=$page->option('when');

			$extra=sprintf("Delivery delay: %d second%s.\n",
				$now,$now == 1 ? "" : "s").$extra;
		}

		if ($extra ne "") {
			$extra="---diagnostics---\n".$extra;
		}

		if ($rc == $SUCCESS) {
			# success

			$main::log->do('debug', "Page sent!") if ($self->{DEBUG});

			# remove recipient from list
			$page->drop_recip();

			# Send email notification
			if ($to ne "" || $cc ne "") {
				$self->SendMail($to,
					$self->{CONFIG}->get('page-daemon'),
					$cc,"Page delivered",
					"The following page was delivered to "
					. $recip->name() . ":\n\n"
					. $page->text() . "\n\n"
					. $extra);
			}

			$main::log->do('info',"from PC: $report")
				if ($report ne "" && $self->{DEBUG});
		}
		elsif ($rc == $TEMP_ERROR) {
			# temp failure
		
			$main::log->do('debug', "Page had temporary failure")
				if ($self->{DEBUG});

			# FIXME: send after X fails	
			# Send email notification
			if ($temprep > 0 && ($attempts % $temprep == 0) && 
		   	    ($to ne "" || $cc ne "")) {
				$self->SendMail($to,
					$self->{CONFIG}->get('page-daemon'),
					$cc,"Page temporarily failed",
					"The following page is still trying to be delivered to "
					. $recip->name() . ":\n\n"
					. $page->text() . "\n\n"
					. $extra );
			}

			$main::log->do('info',"from PC: $report")
				if ($report ne "");
		}
		elsif ($rc == $PERM_ERROR) {
			# total failure
			
			$main::log->do('debug', "Page failed!") if ($self->{DEBUG});

			# remove recipient from list
			$page->drop_recip();

			# Send email notification
			if ($failrep && ($to ne "" || $cc ne "")) {
				$self->SendMail($to,
					$self->{CONFIG}->get('page-daemon'),
					$cc,"Page NOT delivered",
					"The following page has failed to be delivered to "
					. $recip->name() . ":\n\n"
					. $page->text() . "\n\n"
					. $extra );
			}

			$main::log->do('info',"from PC: $report")
				if ($report ne "");
		}
		else {
			# truely weird
			$main::log->do('warning',"PagingCentral: weird.  Bad return code");
			$main::log->do('info',"from PC: $report")
				if ($report ne "");
		}
	}
	$page->attempts(1);
}

sub dropmodem {
	my $self = shift;

	if (!defined($self->{MODEM})) {
		# already dropped
		return 1;
	}

	# give up the modem
	$self->{MODEM}->unlock();
	undef $self->{MODEM};

	return 1;
}

sub disconnect {
	my $self = shift;
	my $report;

	if (!defined($self->{MODEM})) {
		# already disconnected
		return 1;
	}
	#neither t nor n spec'd
	my $result=$self->{MODEM}->chat("${EOT}${CR}","","${CR}",$T[1],$N[0]);
	if (!defined($result)) {
		$main::log->do('crit',"disconnect chat failed -- continuing");
		$result=1;
	}
	else {
		$self->{MODEM}->HexDump($result) if ($self->{DEBUG});
		$report=$self->ReportMsgSeq($result);

		if ($result =~ /${RS}${CR}/) {
			$main::log->do('crit', "transaction broken");
			$result=undef;
		}
		elsif ($result =~ /${ESC}${EOT}${CR}/) {
			$main::log->do('debug', "transcation complete")
				if ($self->{DEBUG});
			$result=1;
		}

		# report on failure or debug
		$main::log->do($result!=1 ? 'crit' : 'debug',
			"disconnect: $report") if ($report ne "" &&
					($self->{DEBUG} || $result!=1));
	}

	$self->dropmodem();

	$main::log->do('debug',"PagingCentral '$self->{NAME}' disconnected")
		if ($self->{DEBUG});

	return $result;
}


sub HandleMessage {
   my $self = shift;
   my(@fields)=@_;
   my($i,$field,$origfield,$fields,$sep,$result,$report);
   my $send=undef;
   my $block="";
   my $part=1;

   my $blockMAX;

   $fields=$#fields+1;  # count fields (that many more control chars)
   # allow for what was called "PET3" in old sendpage: forced extra fields
   $fields=$self->{FIELDS} if ($fields < $self->{FIELDS});
   if ($self->{DEBUG}) {
   	$main::log->do('debug', "\t\tFields to send: $fields:");
   	grep($main::log->do('debug',"\t\t\t".$_),@fields);
   }

   $result=$SUCCESS;


   # Build a message block.  Cannot exceed 250 characters.
   # (+ 3 control chars, 3 checksum chars) == 256 chars)
   $blockMAX=256 - 3 - 3;

   undef $field;
   while ((defined($field) && length($field)>0) || ($#fields>=0)) {
	if (!defined($field) || $field eq "") {
		$field=shift(@fields);
		$origfield=$field;	# save a copy for the future
	}

#	warn "origfield: '$origfield'\n";
#	warn "field:     '$field'\n";

	my($chunk,$newfield)=$self->PullNextChar($field); # pull the next char and
						   # translate and escape it if 
						   # we need to

#	warn "chunk:     '$chunk'\n";
#	warn "newfield:  '$newfield'\n";

	if (length($chunk)+length($block)<=($blockMAX-$fields)) {
		$block.=$chunk;

		# did we just exhaust a field?
		if (!defined($newfield) || $newfield eq "") {
			undef $field;	# clear it for the next field
			$block.=$CR;	# attach a CR
			$fields--;	# drop the count of fields
		}
		else {
			$field=$newfield; # drop that leading char
		}
	}
	else {
		# we are now at our maximum block size

		# if we didn't finish the field, we need to use a
		#    "US" marker to continue the field in the next block
		# if we have more blocks to send, we need to use "ETB"
		# if we're done sending, we send "ETX"
		if ($field ne $origfield) {
			# if $field is untouched, we're not in the
			#  middle of a field on this block
			$sep=(length($field)>0 || defined($fields[0])) ?
				$ETB : $ETX;
		}
		else {
			$sep = $US;
		}
		($result,$report)=$self->TransmitBlock($block,$part,$sep);
		if ($result == $SKIP_MSG) {
			return ($PERM_ERROR,$report);
		}
		elsif ($result != $SUCCESS) {
			return ($result,$report);
		}
		$part++;	# now on to the next part?
		$block="";
	}
   }
   if (defined($block)) {
	# done with everything, transmit the final block
	($result,$report)=$self->TransmitBlock($block,$part,$ETX);
   }
   if ($result == $SKIP_MSG) {
	return ($PERM_ERROR,$report);
   }
   return ($result,$report);
}

sub PullNextChar {
	my $self=shift;
	my($text)=@_;
	my($char,$left);

	$left=$text;

	# stop loops
	return ("","") if ($left eq "");

	do {	
		# yank the first char and encode it if need be
		$char=substr($left,0,1);	# yank first char
		# FIXME: more efficient test for "end of string"
		if ($char ne $left) {
			$left=substr($left,1);		# keep the rest
		}
		else {
			$left="";
		}
	} while (!$self->CharOK($char));

	# don't check empties
	return ("","") if ($char eq "");

	# drop chars to 7 bits
	if (ord($char) != (ord($char) & 0x7f)) {
		$main::log->do('warning',"hi-bit character reduced to 7 bits: '$char'");
		$char=chr(ord($char) & 0x7f);
	}
	# escape low chars if the PC supports it
	if ($self->{ESC}) {
		if (ord($char) < 0x20) {
			$char=chr(ord($char)+0x40);
			$char="${SUB}$char";
		}
	}

	return($char,$left);
}

sub CharOK {
	my $self=shift;
	my($char)=@_;

#	# for some PCs, the TAP control chars can't be used, but all	
#	# the others are trasmitable (in this case, they don't recognize
#	# the ${SUB} escape codes
#	my $not_allowed="($CR|$ESC|$STX|$ETX|$US|$ETB|$EOT)";
#
#	return undef if ($char =~ /^$not_allowed/);
#
#	return 1;

	# don't bother checking empties
	return 1 if ($char eq "");

	if (ord($char) < 0x20 && !$self->{CTRL} &&
            ($char ne $LF || !$self->{LFOK})) {
		# be more silent about dropping $LF (e.g., for numeric pagers)
		$main::log->do('warning',"Dropping bad char 0x".sprintf("%02X",ord($char))) if ($char ne $LF || $self->{DEBUG});
		return undef;
	}
	return 1;
}

sub TransmitBlock {
   my $self = shift;
   my($block,$part,$sep)=@_;
   my($result,$done,$retries,$report);

   if (!defined($self->{MODEM})) {
	$main::log->do('warning', "Yikes!  The modem object disappeared!");
        return ($TEMP_ERROR,"Lost modem object");
   }

   $block=${STX}.$block.$sep;
   $block=$block.$self->TAPCheckSum($block).$CR;

   my $LEAD=$self->{LEAD};

   $main::log->do('debug', "Block to trans: ".Sendpage::Modem->HexStr($block))
	if ($self->{DEBUG});

   undef $done;
   $retries=0;
   while (!defined($done) && $retries <= $N[2]) {

	# make sure the modem stays connected
	if (!$self->{MODEM}->ready("TransmitBlock")) {
		$self->dropmodem();
		return ($TEMP_ERROR,"Lost modem connection");
	}

	# transmit block here
	$result=$self->{MODEM}->chat($block,"",
		"${LEAD}(${ACK}|${NAK}|${RS}|${ESC}${EOT})${CR}",
		$T[3],1);
	if (!defined($result)) {
		$main::log->do('warning',"total block xmit failure--retrying");
		$retries++;
		next;	# restart block xmit
	}

	$self->{MODEM}->HexDump($result) if ($self->{DEBUG});
	# show any messages
	$report=$self->ReportMsgSeq($result);
	
	# check for answer here
	if ($result =~ /${LEAD}${ACK}${CR}/) {
		$done=$SUCCESS;
		$main::log->do('debug', "block taken!") if ($self->{DEBUG});
	}
	elsif ($result =~ /${LEAD}${NAK}${CR}/) {
		$main::log->do('debug', "retrans block") if ($self->{DEBUG});
		$retries++;
	}
	elsif ($result =~ /${LEAD}${RS}${CR}/) {
		$done=$SKIP_MSG;
		$main::log->do('debug', "skip block") if ($self->{DEBUG});
	}
	elsif ($result =~ /${LEAD}${ESC}${EOT}${CR}/) {
		$main::log->do('crit',"immediate disconnect requested!");
		$self->disconnect();
		$done=$TEMP_ERROR;
	}
   }

   # assume a temporary error unless we already know our state
   $done=$TEMP_ERROR if (!defined($done));

   return ($done,$report);	
}

# calculate the 3-char checksum for a block
sub TAPCheckSum {
	my $self=shift;
	my($data)=@_;
	my($sum,@chars,$c,@check);
	$sum=0;
	@chars=split(//,$data);
	foreach $c (@chars) {
		$sum += (ord($c) & 0x7f);  # drop hi bits (shouldn't be there)
	}
#        /* the checksum is represented as 3 ascii characters having the values
#                between 0x30 and 0x3f */
	$check[2] = chr(0x30 + ($sum & 0x0f));
	$sum >>= 4;
	$check[1] = chr(0x30 + ($sum & 0x0f));
	$sum >>= 4;
	$check[0] = chr(0x30 + ($sum & 0x0f));

	return join("",@check);
}
	

#
#   ${STX}${FIELD1}\r${FIELD2}\r${ETX}${CHECKSUM}\r
#
#  (note: pages can be broken into multiple packets, separated by "ETB")
#
#					seq\rcode\r
#   nak: retry
#   ack: got it
#   rs:  skip this one
#   eot: hang up NOW
#
#   ${EOT}\r
#					something\r
#   seq: all good
#   rs: something broken
#   eot: goodbye

sub ReportMsgSeq {
	my $self = shift;
	my($seq)=@_;
	my(@lines,$line,$msg,@msgs,$num,$text,$str);

	@lines=split(/${CR}/,$seq);
	undef @msgs;
	undef $msg;
	$str="";

	foreach $line (@lines) {
		if ($line =~ /^(\d\d\d)\D/) {
			if (defined($msg)) {
				push(@msgs,$msg);
			}
			# extract the sequence msgs number
			$line=~/^(\d\d\d)(.*)$/;
			$num=$1;
			$text=$2;
			# prepend ": " if any text exists
			$text=": $text" if ($text !~ /^\s*$/);
			# decode our message
			if (defined($SeqMinor{$num})) {
				$msg="$SeqMinor{$num}$text";
			}
			else {
				$msg="(undefined Sequence: $num)$text";
			}
	
		}
		else {
			$msg.=$line;
		}
	}
	push (@msgs,$msg) if (defined($msg));

	foreach $msg (@msgs) {
		# drop standard signalling messages
		$msg =~ s/($ESC(\[p|$EOT)*|$ACK|$NAK|$RS)//g;

		if ($msg !~ /^[\s\n\r]*$/) {
			$str.="'".Sendpage::Modem->HexStr($msg)."'\n";
		}
	}

	return $str;
}

sub maxchars {
	my($self)=@_;

	$self->{MAXCHARS};
}

sub maxsplits {
	my($self)=@_;

	$self->{MAXSPLITS};
}

sub SendMail {
	my($self,$to,$from,$cc,$subject,$body)=@_;

	my($msg,$fh);

	$msg = new Mail::Send;

	if (!defined($msg)) {
		$main::log->do('crit',"Cannot deliver email!  Mail::Send won't start");
	}
	else {
		$msg->to($to) if (defined($to) && $to ne "");
		$msg->cc($cc) if (defined($cc) && $cc ne "");
		$msg->set('From',$from);
		$msg->subject($subject);

		# use mail-agent, see if the from gets passed now
		$fh = $msg->open($self->{CONFIG}->get("mail-agent"));

		if (!defined($fh)) {
			$main::log->do('crit',"Cannot deliver email!  Mail::Send won't open");
		}
		else {
			print $fh $body || $main::log->do('crit',"Error writing email: $!");
			$fh->close || $main::log->do('crit',"Error sending email: $!");
		}
	}
}

sub DESTROY {
        my $self = shift;

        $main::log->do('debug',
			"PagingCentral '$self->{NAME}' being destroyed")
		if ($self->{DEBUG});

        $self->disconnect();
}

1;

__END__

=head1 AUTHOR

Kees Cook <cook@cpoint.net>

=head1 SEE ALSO

perl(1), sendpage(1), Sendpage::KeesConf(3), Sendpage::KeesLog(3),
Sendpage::Modem(3), Sendpage::PageQueue(3), Sendpage::Page(3),
Sendpage::Recipient(3), Sendpage::Queue(3)

=head1 COPYRIGHT

Copyright 2000 Kees Cook.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

