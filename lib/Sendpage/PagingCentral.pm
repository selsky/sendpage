package Sendpage::PagingCentral;

# PagingCentral.pm implements the TAP protocol
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
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
# http://www.gnu.org/copyleft/gpl.html

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

    $pc->SendMail($to,$from,$cc,$errorsto,$subject,$body);

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
my %SeqMajor = (    100 => "Informational Text",
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
my $TRN="\x2f";
my $OP="\x4f";
my $RE="\x52";

sub new
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = { };

    $self->{CONFIG} = shift;
    $self->{NAME}   = shift;
    $self->{MODEMS} = shift;

    # load config information
    $self->{DEBUG}  = $self->{CONFIG}->get("pc:$self->{NAME}\@debug");

    # TAP protocol/block handling options
    $self->{Proto}         = $self->{CONFIG}->get("pc:$self->{NAME}\@proto");
    $self->{AnswerWait}    = $self->{CONFIG}->get("pc:$self->{NAME}\@answerwait");
    $self->{AnswerRetries} = $self->{CONFIG}->get("pc:$self->{NAME}\@answerretries");
    $self->{CharsPerBlock} = $self->{CONFIG}->get("pc:$self->{NAME}\@chars-per-block");
    $self->{MAXCHARS}      = $self->{CONFIG}->get("pc:$self->{NAME}\@maxchars");
    $self->{FIELDS}        = $self->{CONFIG}->get("pc:$self->{NAME}\@fields");
    $self->{MAXSPLITS}     = $self->{CONFIG}->get("pc:$self->{NAME}\@maxsplits");
    $self->{MaxPages}      = $self->{CONFIG}->get("pc:$self->{NAME}\@maxpages");
    $self->{MaxBlocks}     = $self->{CONFIG}->get("pc:$self->{NAME}\@maxblocks");

    # TAP character translation options
    $self->{ESC}    = $self->{CONFIG}->get("pc:$self->{NAME}\@esc");
    $self->{CTRL}   = $self->{CONFIG}->get("pc:$self->{NAME}\@ctrl");
    $self->{LFOK}   = $self->{CONFIG}->get("pc:$self->{NAME}\@lfok");

    # Serial characteristics
    $self->{Baud}         = $self->{CONFIG}->ifset("pc:$self->{NAME}\@baud");
    $self->{Parity}       = $self->{CONFIG}->ifset("pc:$self->{NAME}\@parity");
    $self->{StrictParity} = $self->{CONFIG}->ifset("pc:$self->{NAME}\@strict-parity");
    $self->{Data}         = $self->{CONFIG}->ifset("pc:$self->{NAME}\@data");
    $self->{Stop}         = $self->{CONFIG}->ifset("pc:$self->{NAME}\@stop");
    $self->{Flow}         = $self->{CONFIG}->ifset("pc:$self->{NAME}\@flow");

    # Modem control options
    $self->{AreaCode}    = $self->{CONFIG}->get("pc:$self->{NAME}\@areacode",1);
    $self->{PhoneNum}    = $self->{CONFIG}->get("pc:$self->{NAME}\@phonenum");
    $self->{DialWait}    = $self->{CONFIG}->get("pc:$self->{NAME}\@dialwait",1);
    $self->{DialRetries} = $self->{CONFIG}->get("pc:$self->{NAME}\@dialretries");

    # Email control settings
    $self->{CConErr}     = $self->{CONFIG}->fallbackget("pc:$self->{NAME}\@cc-on-error");
    $self->{CCSimple}    = $self->{CONFIG}->fallbackget("pc:$self->{NAME}\@cc-simple");
    $self->{NotifyAfter} = $self->{CONFIG}->fallbackget("pc:$self->{NAME}\@tempfail-notify-after");
    $self->{FailNotify}  = $self->{CONFIG}->fallbackget("pc:$self->{NAME}\@fail-notify");
    $self->{MaxTempFail} = $self->{CONFIG}->fallbackget("pc:$self->{NAME}\@max-tempfail");
    $self->{MaxAge}      = $self->{CONFIG}->fallbackget("pc:$self->{NAME}\@max-age");

    # Completion commands
    $self->{CompletionCmd} = $self->{CONFIG}->fallbackget("pc:$self->{NAME}\@completion-cmd",1);

    $self->{LEAD} = "";
    $self->{LEAD} = $CR
	if ($self->{CONFIG}->get("pc:$self->{NAME}\@stricttap"));

    # get the daemon info, allowing for fall-back
    $self->{PageDaemon} = $self->{CONFIG}->fallbackget("pc:$self->{NAME}\@page-daemon");

    return bless $self => $class;
}

# Clear work-tracking counters
sub clear_counters
{
    my $self = shift;

    # clear counters
    $self->{PagesProcessed}  = 0;
    $self->{BlocksProcessed} = 0;
}

# Get a modem, init, dial, and authenticate to TAP
sub start_proto
{
    my $self = shift;

    my (@modems, $modem, $name, $result, $report, $ref);

    # find an available modem
    $ref = $self->{CONFIG}->fallbackget("pc:$self->{NAME}\@modems", 1);
    if (!defined($ref)) {
	@modems = @{ $self->{MODEMS} }; # use all known available
    } else {
	@modems = @{ $ref };
    }

    # we need to make sure that we only use the modems that
    # we're allowed to use and that
    # were detected as "functioning" during startup
    my (%avail, @okay);

    # which are available?
    $avail{$_} = 1 foreach (@{ $self->{MODEMS} });

    foreach $modem (@modems) {
	push(@okay,$modem) if (defined($avail{$modem}));
    }

    @modems = @okay;

    my $config = $self->{CONFIG};

    # try each modem,  FIXME: should we do some sort of round-robin?
    foreach $name (@modems) {
	$modem = Sendpage::Modem->new(Name => $name,
				      Dev => $config->get("modem:${name}\@dev"),
				      Lockprefix => $config->get("lockprefix"),
				      Debug => $config->get("modem:${name}\@debug"),
				      Log => $main::log,
				      Baud => $config->get("modem:${name}\@baud"),
				      Parity => $config->get("modem:${name}\@parity"),
				      StrictParity => $config->get("modem:${name}\@strict-parity"),
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
				      CarrierDetect => $config->get("modem:${name}\@carrier-detect",1),
				      AreaCode => $config->get("modem:${name}\@areacode",1),
				      LongDist => $config->get("modem:${name}\@longdist"),
				      DialOut =>  $config->get("modem:${name}\@dialout")
				     );

	# Did we get it?
	next unless defined $modem;

	# Init modem
	$result = $modem->init(Baud => $self->{Baud},
			       Parity => $self->{Parity},
			       Data => $self->{Data},
			       Stop => $self->{Stop},
			       Flow => $self->{Flow},
			       StrictParity => $self->{StrictParity},
			       # modem init string undefined; use default
			      );
	unless (defined $result) {
	    $main::log->do('alert',
			   "PC '%s' Failed to initialize modem '%s'",
			   $self->{NAME}, $name);
	    undef $modem;
	    next;
	}

	# Dial
	$result = $modem->dial(AreaCode => $self->{AreaCode},
			       PhoneNum => $self->{PhoneNum},
			       DialWait =>$self->{DialWait},
			      );
	unless (defined $result) {
	    $main::log->do('crit',
			   "Failed to dial PC '%s' from modem '%s'",
			   $self->{NAME},$name);
	    undef $modem;
	    next;
	}

	# reserved, init'd, and dialed the modem
	last;
    }

    # make sure we got one
    unless (defined $modem) {
	$main::log->do('crit', "No PC connections available");
	return (undef,"No PC connections available");
    }

    # Clear counters
    $self->clear_counters();

    my $SST = $self->{Proto};	# Get proto type

    # Starting implementation of UCP
    # ------------------------------
    # I did a few new routines to handle UCP:
    # - HandleUCPMessage
    # - AssambleUCPMessage
    # - CalcUCPChecksum
    # - CreateUCPMessage
    # - CreateUCPHeader
    # - TranmistUCPMessage
    # And I modified the following routines:
    # - send
    # - disconnect
    # - and this one (start_proto)
    # UCP doesn't need to loggon. So we just skip that for UCP
    if ($SST =~ /^TAP|PG[13]$/) { # Proto is TAP (PG1 or PG3)
	# wait for ID=
	#   timeout("\r")
	$result = $modem->chat("\r", "\r", "ID=", $self->{AnswerWait},
			       $self->{AnswerRetries});
	unless (defined $result) {
	    $main::log->do('crit', "PC did not send 'ID=' tag");
	    return (undef, "Could not perform protocol startup");
	}

	# Try to log on
	#                    ID=
	#    \033PG1${PASS}\r

	my $LEAD = $self->{LEAD};
	my $LOGONretries = 3;	# this is protocol-defined
	# my $SST=$self->{CONFIG}->get("pc:$self->{NAME}\@proto"); # PG1, etc
	my $PASS = $self->{CONFIG}->get("pc:$self->{NAME}\@password");

	# adjust the length of the password to MAKE SURE it's 6 chars
	if (length($PASS) > 6) {
	    $PASS = substr $PASS, 0, 6;
	} elsif (length($PASS) < 6) {
	    # should I be back-filling this password?
	    #$PASS=sprintf("%06s",$PASS);
	}
	# supposedly, we can get a go-head here too, so we should handle it
	my $early_go_ahead;

	my $logged_in = 0;
	while (!$logged_in && $LOGONretries) {

	    $result = $modem->chat("${ESC}${SST}${PASS}\r", "",
				   "(${LEAD}(${ACK}|${NAK}|${ESC}${EOT})${CR}|${ESC}\\[p${CR})",
				   $T[3], $N[0]); # the N here is not spec'd
	    unless (defined $result) {
		$main::log->do('crit', "PC timed out during logon handshake");
		return (undef, "Paging Central timed out during logon handshake");
	    }
	    $modem->HexDump($result) if $self->{DEBUG};

	    #                    something\rcode\r
	    #   nak: retry
	    #   ack: followed with go ahead
	    #   eot: failure
	    # show any messages
	    $report = $self->ReportMsgSeq($result);

	    if ($result =~ /${ESC}\[p${CR}/) {
		# got an early go ahead, skip next chat
		$main::log->do('debug', "Got early go-ahead")
		    if $self->{DEBUG};
		# FIXME: we're pattern matching on the entire string
		#    instead of feeding the "leftovers" back into
		#    the "chat" tool
		$logged_in     = 1;
		$early_go_ahead= 1;
	    } elsif ($result =~ /${LEAD}${ACK}${CR}/) {
		# Logon accepted
		$logged_in = 1;
		$main::log->do('debug', "Logon success!")
		    if $self->{DEBUG};
	    } elsif ($result =~ /${LEAD}${NAK}${CR}/) {
		# Logon requested again
		$LOGONretries--;
		$main::log->do('debug', "Logon needs to be retried")
		    if $self->{DEBUG};
	    } elsif ($result =~ /${LEAD}${ESC}${EOT}${CR}/) {
		# Forced disconnected
		$main::log->do('crit',
			       "PC requested immediate disconnect: '%s'",
			       $report);
		return (undef, "Immediate disconnect requested: $report");
	    }

	    # make report on failure or debug
	    $main::log->do($logged_in==1 ? 'debug' : 'crit',
			   "proto_startup: %s",
			   $report)
		if ($report ne "" && ($self->{DEBUG} || $logged_in != 1));
	}
	unless ($logged_in) {
	    $main::log->do('crit',
			   "Tried to log in $LOGONretries times and failed");
	    return undef;
	}

	unless (defined $early_go_ahead) {
	    # wait for them to be done announcing crap
	    #                    ${GO_AHEAD}\r
	    # n is not spec'd here
	    $result = $modem->chat("", "", "${ESC}\\[p${CR}", $T[3], $N[0]);
	    unless (defined $result) {
		$main::log->do('crit', "PC timed out during logon speech");
		return (undef, "Protocol timed out");
	    }
	    $modem->HexDump($result) if $self->{DEBUG};
	    $report = $self->ReportMsgSeq($result);

	    $main::log->do('debug', "go ahead: %s", $report)
		if ($report ne "" && $self->{DEBUG});
	}
    }
    $self->{MODEM} = $modem;
    return (1, "Proto startup success", $SST);
}

sub send
{
    my $self = shift;
    my ($PIN,$text) = @_;
    my ($report,@result,$proto);

    # PC in "Test" mode will pretend to deliver all pages
    return ($SUCCESS,"") if $self->{Proto} eq "Test";

    unless (defined $self->{MODEM}) {
	($rc, $report, $proto) = $self->start_proto();
	unless (defined $rc) {
	    $main::log->do('crit', "proto startup failed (%s)", $report);
	    return ($TEMP_ERROR, $report); # temp failure
	}
    }

    # now we are at step 8, and we can send pages
    my @fields = ($PIN, $text);

    if ($proto eq "UCP") {	# UCP has his own message-handler
	@result = $self->HandleUCPMessage(@fields);
    } elsif ($proto eq "SMS") {
	@result = $self->HandleSMSMessage(@fields);
    } else {
	@result = $self->HandleTAPMessage(@fields);
    }

    # Handle any post-processing (maxpages, etc)
    $self->{PagesProcessed}++;

    if ($self->{MaxPages} > 0 && $self->{PagesProcessed} >= $self->{MaxPages}) {
	# shouldn't send any more pages

	# make a note in the logs
	$main::log->do('info',
		       "Disconnecting from Paging Central: %d page limit reached.",
		       $self->{MaxPages});

	# drop the connection (don't check for errors...)
	$self->disconnect();
    }

    return @result;
}

sub deliver
{
    my ($self, $page) = @_;
    my ($rc, $report);
    my ($to, $cc, $extra, $attempts, $age);

    my $queuedir = $self->{CONFIG}->get("queuedir");

    for ($page->reset(), $page->next();
	 defined($recip = $page->recip());
	 $page->next())
    {
	  # gather info from the page
	  $attempts = $page->attempts();
	  $to       = $page->option('from');
	  $cc       = $recip->datum('email-cc');
	  $age      = $page->age();

	  # Check for maximum lifetime
	  if ($self->{MaxAge} > 0 && $age > $self->{MaxAge}) {
	      $rc=$PERM_ERROR;
	      $report = sprintf("Page exceeded maximum queue age: %d > %d seconds",
				$age, $self->{MaxAge});
	  } else {
	      # attempt to send the page
	      ($rc, $report) = $self->send($recip->pin, $page->text);
	  }
	  my $now = time;

	  # push temp error into a perm fail if needed
	  if ($rc == $TEMP_ERROR && $attempts > $self->{MaxTempFail}) {
	      $rc = $PERM_ERROR;
	      $report .= "\n'Too many errors ($attempts) -- giving up.'";
	  }

	  # gather the reported info
	  $extra = "";
	  if (defined($report) && $report ne "") {
	      $extra = "Paging Central reported:\n$report";
	  }

	  # delay information
	  if ($now < $page->option('when')) {
	      $main::log->do('warning',
			     "Weird.  Page got delivered before it was ready to be sent.");
	  } else {
	      my $delay = $now-$page->option('when');

	      $extra = sprintf("Delivery delay: %d second%s.\n",
			       $delay,$delay == 1 ? "" : "s") . $extra;
	  }

	  if ($extra ne "") {
	      $extra = "---diagnostics---\n" . $extra;
	  }

	  # logging info
	  my $paged  = $recip->name();
	  my $pc     = $self->{NAME};
	  my $file   = $page->option('FILE');

	  my $sender = $to;
	  $sender = "nobody" if $sender eq "";

	  my $diag = "";
	  $diag = "PC=$report" if $report ne "";

	  # eliminate ctrl chars in "diag"
	  $diag = Sendpage::Modem->HexStr($diag); # call this directly

	  my $state = "unknown";
	  $state = "Sent" if $rc == $SUCCESS;
	  $state = "Temp-Failure" if $rc == $TEMP_ERROR;
	  $state = "Abandoned" if $rc == $PERM_ERROR;

	  # log our page's state
	  $main::log->do('info',
			 "$pc/$file: state=$state, to=%s, from=%s, size=%d%s",
			 $paged, $sender, length($page->text()),
			 $diag eq "" ? "" : ", $diag");

	  if ($rc == $SUCCESS) {
	      # success

	      # remove recipient from list
	      $page->drop_recip();

	      # Send email notification
	      my $subject = "Page delivered";
	      my $body = "The following page was delivered to "
		  . "$paged:\n\n" . $page->text() . "\n\n"
			  . $extra;
	      my $email_to = $to;
	      my $email_cc = $cc;

	      # If we're doing a simple CC, we need to not
	      # send the complex one now.
	      if ($self->{CCSimple}) {
		  $email_cc = "";
	      }
	      if ($email_to ne "" || $email_cc ne "") {
		  $self->SendMail($email_to,
				  $self->{PageDaemon},
				  $email_cc,
				  $self->{PageDaemon},
				  $subject,
				  $body);
	      }

	      # Now, if we're doing a CC email, and it's the
	      # simple body, send it here.
	      if ($self->{CCSimple} && defined($cc) && $cc ne "") {
		  $email_to = $cc;
		  $subject  = "";
		  $body     = $page->text() . "\n\n";
		  $self->SendMail($email_to,
				  $self->{PageDaemon},
				  $email_cc,
				  $self->{PageDaemon},
				  $subject,
				  $body);
	      }

	      # external commands...
	      if (defined $self->{CompletionCmd}) {
		  open(CMD,
		       "|$self->{CompletionCmd} 1 $paged $queuedir/$pc/$file "
		       . $page->option('when') . " $now");
		  print CMD $page->text();
		  close CMD;
	      }
	  } elsif ($rc == $TEMP_ERROR) {
	      # temp failure

	      # add page-daemon to CC possibly
	      my $errcc = $cc;
	      if ($self->{CConErr}) {
		  if ($errcc eq "") {
		      $errcc = $self->{PageDaemon};
		  } else {
		      $errcc = "$errcc, $self->{PageDaemon}";
		  }
	      }

	      # Send email notification
	      if ($self->{NotifyAfter} > 0 && $attempts > 0
		  && ($attempts % $self->{NotifyAfter} == 0)
		  && ($to ne "" || $errcc ne ""))
	      {
		  $self->SendMail($to,
				  $self->{PageDaemon},
				  $errcc,
				  $self->{PageDaemon},
				  "Page temporarily failed",
				  "The following page is still trying to be delivered to "
				  . $recip->name() . ":\n\n"
				  . $page->text() . "\n\n"
				  . $extra
				 );
	      }
	  } elsif ($rc == $PERM_ERROR) {
	      # total failure

	      # remove recipient from list
	      $page->drop_recip();

	      # add page-daemon to CC possibly
	      my $errcc = $cc;
	      if ($self->{CConErr}) {
		  if ($errcc eq "") {
		      $errcc = $self->{PageDaemon};
		  } else {
		      $errcc = "$errcc, $self->{PageDaemon}";
		  }
	      }

	      # Send email notification
	      if ($self->{FailNotify}
		  && ($to ne "" || $errcc ne ""))
	      {
		  $self->SendMail($to,
				  $self->{PageDaemon},
				  $errcc,
				  $self->{PageDaemon},
				  "Page NOT delivered",
				  "The following page has FAILED to be delivered to "
				  . $recip->name() . ":\n\n"
				  . $page->text() . "\n\n"
				  . $extra
				 );
	      }

	      # external commands...
	      if (defined $self->{CompletionCmd}) {
		  open(CMD,
		       "|b$self->{CompletionCmd} 0 $paged $queuedir/$pc/$file "
		       . $page->option('when') . " $now"
		      );
		  print CMD $page->text();
		  close CMD;
	      }
	  } else {
	      # truely weird
	      $main::log->do('warning',
			     "PagingCentral: weird.  Bad return code");
	      $main::log->do('info', "from PC: %s",
			     $report)
		  if $report ne "";
	  }
      }
    $page->attempts(1);
}

sub dropmodem
{
    my $self = shift;

    return 1 unless defined $self->{MODEM}; # already dropped

    # give up the modem
    #$self->{MODEM}->unlock();
    undef $self->{MODEM};

    return 1;
}

sub disconnect
{
    my $self = shift;
    my $report;

    # clear our counters
    $self->clear_counters();

    return 1 unless defined $self->{MODEM}; # already disconnected

    $main::log->do('debug',
		   "PagingCentral '$self->{NAME}' disconnecting")
	if $self->{DEBUG};

    if ($self->{CONFIG}->get("pc:$self->{NAME}\@proto") =~ /^TAP|PG[13]$/) {
	#neither t nor n spec'd
	my $result = $self->{MODEM}->chat("${EOT}${CR}", "",
					  "${CR}", $T[1], $N[0]
					 );
	unless (defined $result) {
	    $main::log->do('crit', "disconnect chat failed -- continuing");
	    $result = 1;
	} else {
	    $self->{MODEM}->HexDump($result) if $self->{DEBUG};
	    $report = $self->ReportMsgSeq($result);

	    if ($result =~ /${RS}${CR}/) {
		$main::log->do('crit', "transaction broken");
		$result = undef;
	    } elsif ($result =~ /${ESC}${EOT}${CR}/) {
		$main::log->do('debug', "transcation complete")
		    if $self->{DEBUG};
		$result = 1;
	    }

	    $main::log->do('debug', "PagingCentral '%s' reported '%s'",
			   $self->{NAME}, $report)
		if $self->{DEBUG};


	    # report on failure or debug
	    $main::log->do($result!=1 ? 'crit' : 'debug',
			   "disconnect: %s", $report)
		if ($report ne "" && ($self->{DEBUG} || $result!=1));
	}
    } else {
	# UCP and SMS have no loggoff sequence,
	# so we just skip a protocol hangup
	$result = 1;
    }

    $self->dropmodem();

    $main::log->do('debug',"PagingCentral '$self->{NAME}' disconnected")
	if $self->{DEBUG};

    return $result;
}

sub GenerateBlocks
{
    my $self = shift;
    my @fields = @_;
    my (@blocks, $field, $fields, $origfield, $newfield, $chunk, $block);

    $fields =$#fields + 1; # count fields (that many more control chars)

    # allow for extra fields (what was called "PET3" in old sendpage)
    $fields = $self->{FIELDS} if $fields < $self->{FIELDS};
    if ($self->{DEBUG}) {
	$main::log->do('debug', "\t\tFields to send: %s:", $fields);
	grep($main::log->do('debug', "\t\t\t%s", $_), @fields);
    }

    # Build a message block.  Cannot exceed 256 characters.
    # (250 + 3 control chars + 3 checksum chars) == 256 chars)
    # so $self->{CharsPerBlock} == 250 normally

    @blocks = ();
    $chunk = $block = "";
    undef $field;
    while ((defined($field) && length($field) > 0) || ($#fields >= 0)) {
	if (!defined($field) || $field eq "") {
	    $field     = shift @fields;
	    $origfield = $field;	# save a copy for the future
	}

	#	warn "origfield: '$origfield'\n";
	#	warn "field:     '$field'\n";

	# pull the next char and translate and escape it if we need to
	my ($chunk, $newfield) = $self->PullNextChar($field);

	#	warn "chunk:     '$chunk'\n";
	#	warn "newfield:  '$newfield'\n";

	# Each field is terminated with a CR, so we must keep $fields-many
	# characters available in the block.  FIXME: This calculating is overly
	# aggressive.
	if (length($chunk) +length($block)
	    <= ($self->{CharsPerBlock} - $fields))
	{
	    $block .= $chunk;

	    # did we just exhaust a field?
	    if (!defined($newfield) || $newfield eq "") {
		undef $field;		# clear it for the next field
		$block .= $CR;		# attach a CR
		$fields--;		# drop the count of fields
	    } else {
		$field = $newfield; # drop that leading char
	    }
	} else {
	    # we are now at our maximum block size

	    # if we didn't finish the field, we need to use a
	    #    "US" marker to continue the field in the next block
	    # if we have more blocks to send, we need to use "ETB"
	    # if we're done sending, we send "ETX"
	    if ($field eq $origfield) {
		# if $field is untouched, we're not in the
		#  middle of a field on this block
		$sep = (length($field) > 0 || defined($fields[0]))
		    ? $ETB : $ETX;
	    } else {
		$sep = $US;
	    }
	    push @blocks, [ $block, $sep ];
	    $part++;		# now on to the next part?
	    $block = "";
	}
    }
    # FIXME: won't this ALWAYS be true, since we never undef $block?
    # This seems like a bug: we're always sending an additional empty field.
    if (defined $block) {
	# done with everything, store the final block
	push @blocks, [ $block, $ETX ];
    }

    return @blocks;
}

# Handling the UCP Message
sub HandleUCPMessage
{
    my $self = shift;
    my ($pin, $msgtext) = @_;

    # checking maxlenth of Text to send
    if (length($msgtext) > $self->{MAXCHARS}) {
	$main::log->do('crit',"Cannot send message!"
		       . " Message with %d chars to long.",
		       $self->{MAXCHARS}
		      );
	$self->disconnect();
    }

    # Create the whole message for sending, including header and checksum
    $msg = $self->AssembleUCPMessage($pin,$msgtext);

    # Transmit the message
    ($result, $report) = $self->TransmitUCPmsg($msg);

    $main::log->do('info',"RETURN: %s", $result);
    print length($fields[1]) . "\n";
    return ($result, $report);
}

# Putting the whole message together
sub AssembleUCPMessage
{
    my $self = shift;
    my ($pin, $msgtext) = @_;
    my ($field, $UCPlength, $UCPChecksum, $HEADERchksum);
    my ($HEADER, $HEADERlen, $ASCIImsg, $MSG);

    chop $msgtext;
    $ASCIImsg = $self->CreateUCPMessage($msgtext);

    $UCPlength = length($pin) + length($ASCIImsg);
    ($HEADER, $HEADERlen, $HEADERchksum) = $self->CreateUCPHeader($UCPlength);
    $MSG = $HEADER . $pin . $TRN . $TRN . $TRN . "3" . $TRN . $ASCIImsg . $TRN;
    $UCPChecksum = $self->CalcUCPChecksum($MSG);
    return $MSG . $UCPChecksum;
}

# Calculating the UCP Checksum
sub CalcUCPChecksum
{
    my $self = shift;
    my ($HoleMSG) = @_;
    my ($CHKtotal, @bytes, $CHKbin, $i, $int);

    @chars = split //, $HoleMSG;
    $CHKtotal += ord foreach @chars;
    $CHKbin = sprintf("%b", $CHKtotal);

    push @bytes, substr($CHKbin, length($CHKbin) - 8, 4);
    push @bytes, substr($CHKbin, length($CHKbin) - 4, 4);

    undef $CHKtotal;
    for ($i=0; $i < @bytes; $i++) {
	$int = oct("0b" . $bytes[$i]);
	if ($int <= 9) {
	    $int += 48;
	} else {
	    $int += 55;
	}
	$CHKtotal .= chr($int);
    }

    return $CHKtotal;
}

# Translate Messagepart to ASCII
sub CreateUCPMessage
{
    my $self = shift;
    my ($field) = @_;
    my ($str, $newfield, $origfield, $chunk, $chksum, $i, $length);

    $origfield = $field;
    for ($i=0; $i < length($field); $i++) {
	undef $newfield;
	# pull the next char and translate and escape it if we need to
	my ($chunk, $newfield) = $self->PullNextChar($origfield);
	$str .= sprintf("%02X", ord($chunk));
	$origfield = $newfield;
    }

    return $str;
}

# UCP Header
sub CreateUCPHeader
{
    my $self = shift;
    my ($UCPlength) = @_;
    my ($HDtext, $HDmsg, $HDlen, $HDchksum, $totalLength);

    $totalLength = sprintf("%05u", ($UCPlength + 22));

    $HDmsg = "01" . $TRN . $totalLength . $TRN . "O" . $TRN . "01" . $TRN;

    return $HDmsg;
}

sub HandleSMSMessage
{
    my ($self, $pin, $msgtext) = @_;

    # checking maxlenth of Text to send
    if (length($msgtext) > $self->{MAXCHARS}) {
	$main::log->do('crit',"Cannot send message!"
		       . " Message with %d chars to long.",
		       $self->{MAXCHARS}
		      );
	return ($PERM_ERROR, "Message too long");
    }

    unless (defined $self->{MODEM}) {
	($rc, $report) = $self->start_proto();
	unless (defined $rc) {
	    $main::log->do('crit', "SMS proto startup failed (%s)", $report);
	    return ($TEMP_ERROR, $report); # temp failure
	}
    }

    # transmit block here
    $result = $self->{MODEM}->chat("AT+CMGS=\"$pin\"\r", "",
				   "${CR}${LF}?> ", $T[3], 1
				  );
    unless (defined $result) {
	$main::log->do('warning', "SMS message start attempt timed out");
	return ($TEMP_ERROR, "SMS message start attempt timed out");
    }

    $self->{MODEM}->HexDump($result) if $self->{DEBUG};

    $result = $self->{MODEM}->chat("$msgtext\cZ\r", "\cZ\r",
				   "${CR}${LF}?" . qr(\+) . "CM.*\r",
				   $T[3], 1
				  );
    unless (defined $result) {
	$main::log->do('warning', "SMS message delivery attempt timed out");
	return ($TEMP_ERROR, "SMS message delivery attempt timed out");
    }

    $self->{MODEM}->HexDump($result) if $self->{DEBUG};

    return ($PERM_ERROR, "SMS delivery failure: $1")
	if $result =~ /\+CMS ERROR: (.*)/;

    return ($SUCCESS, "SMS delivered");
}

sub HandleTAPMessage
{
    my $self = shift;
    my @fields = @_;
    my ($i, @blocks, $block, $result, $report, $rc);
    my $send = undef;

    # new process needed here to support "maxblocks":
    # 1) generate full translated/escape text *first*
    # 2) figure out how many blocks it will take
    @blocks = $self->GenerateBlocks(@fields);

    # 3) sanity-check the "maxblocks" setting to make sure we could EVER
    #    send the page
    if ($self->{MaxBlocks} > 0) {
	if (@blocks > $self->{MaxBlocks}) {
	    $main::log->do('crit', "HandleTAPMessage: could NEVER send this "
			   . "page if 'maxblocks' is %d!", $self->{MaxBlocks}
			  );
	}
	# 4) decide if we drop the connection (enough spare blocks to send message?)
	elsif ($self->{BlocksProcessed} +@blocks > $self->{MaxBlocks}) {
	    $main::log->do('info', "Disconnecting from Paging Central: %d "
			   . "block limit reached.", $self->{MaxBlocks}
			  );
	    $self->disconnect();
	}
    }

    # 5) verify TAP connectivity (and establish if we need to, like "send")
    unless (defined $self->{MODEM}) {
	($rc, $report) = $self->start_proto();
	unless (defined $rc) {
	    $main::log->do('crit', "TAP proto startup failed (%s)", $report);
	    return ($TEMP_ERROR, $report); # temp failure
	}
    }

    # 6) go ahead with regular block processing
    $result = $SUCCESS;
    $report = "";

    foreach $block (@blocks) {
	my($blockbody, $blocksep) = @$block;

	($result, $report) = $self->TransmitBlock($blockbody, $blocksep);
	if ($result == $SKIP_MSG) {
	    return ($PERM_ERROR, $report);
	} elsif ($result != $SUCCESS) {
	    return ($result, $report);
	}
    }
    return ($result, $report);
}

sub PullNextChar
{
    my $self = shift;
    my ($text) = @_;
    my ($char, $left);

    $left = $text;

    # stop loops
    return ("","") if $left eq "";

    do {
	# yank the first char and encode it if need be
	$char = substr($left, 0, 1); # yank first char

	# FIXME: more efficient test for "end of string"
	if ($char ne $left) {
	    $left = substr($left, 1); # keep the rest
	} else {
	    $left = "";
	}

	# drop chars to 7 bits, as required by TAP protocol
	if (ord($char) != (ord($char) & 0x7f)) {
	    $main::log->do('warning',
			   "hi-bit character reduced to 7 bits: '%s'", $char
			  );
	    $char = chr(ord($char) & 0x7f);
	}

    } until ($self->CharOK($char));

    # don't check empties
    return ("","") if $char eq "";

    # escape low chars if the PC supports it
    if ($self->{ESC}) {
	if (ord($char) < 0x20) {
	    $char = chr(ord($char) + 0x40);
	    $char = "${SUB}$char";
	}
    }

    return($char, $left);
}

sub CharOK
{
    my $self = shift;
    my($char) = @_;

    #    # for some PCs, the TAP control chars can't be used, but all    
    #    # the others are trasmitable (in this case, they don't recognize
    #    # the ${SUB} escape codes
    #    my $not_allowed="($CR|$ESC|$STX|$ETX|$US|$ETB|$EOT)";
    #
    #    return undef if ($char =~ /^$not_allowed/);
    #
    #    return 1;

    # don't bother checking empties
    return 1 if $char eq "";

    if (ord($char) < 0x20
	&& !$self->{CTRL}
	&& !$self->{ESC}
	&& ($char ne $LF || !$self->{LFOK}))
    {
	# be more silent about dropping $LF (e.g., for numeric pagers)
	$main::log->do('warning', "Dropping bad char 0x"
		       . sprintf("%02X", ord($char)))
	    if ($char ne $LF || $self->{DEBUG});
	return undef;
    }
    return 1;
}

# UCP is much simpler than IOX so we need a
# different Transmit routine
sub TransmitUCPmsg
{
    my $self = shift;
    my ($block) = @_;
    my ($result, $done, $retries, $report);

    unless (defined $self->{MODEM}) {
	$main::log->do('warning', "Yikes!  The modem object disappeared!");
	return ($TEMP_ERROR, "Lost modem object");
    }

    $block = ${STX} . $block . ${ETX};

    my $LEAD=$self->{LEAD};

    $main::log->do('debug', "Block to trans (%d): "
		   . Sendpage::Modem->HexStr($block), length($block))
	if $self->{DEBUG};

    # count this block as being sent
    $self->{BlocksProcessed}++;

    undef $done;
    $retries = 0;
    while (!defined($done) && $retries <= $N[2]) {

	# make sure the modem stays connected
	unless ($self->{MODEM}->ready("TransmitBlock")) {
	    $self->dropmodem();
	    return ($TEMP_ERROR, "Lost modem connection");
	}
	# transmit block here
	$result = $self->{MODEM}->chat($block, "", "\x0A", $T[3], 1);
	unless (defined $result) {
	    $main::log->do('warning', "total block xmit failure--retrying");
	    $retries++;
	    next;		# restart block xmit
	}

	$self->{MODEM}->HexDump($result) if $self->{DEBUG};
	# show any messages
	$report = $self->ReportMsgSeq($result);
	$done   = $SUCCESS;
    }

    # assume a temporary error unless we already know our state
    $done = $TEMP_ERROR unless defined $done;

    return ($done, $report);
}

sub TransmitBlock
{
    my $self = shift;
    my ($block, $sep) = @_;
    my ($result, $done, $retries, $report);

    unless (defined $self->{MODEM}) {
	$main::log->do('warning', "Yikes!  The modem object disappeared!");
	return ($TEMP_ERROR, "Lost modem object");
    }

    $block  = ${STX} . $block . $sep;
    $block .= $self->TAPCheckSum($block) . $CR;

    my $LEAD = $self->{LEAD};

    $main::log->do('debug', "Block to trans (%d): ".
		   Sendpage::Modem->HexStr($block),length($block))
	if $self->{DEBUG};

    # count this block as being sent
    $self->{BlocksProcessed}++;

    undef $done;
    $retries = 0;
    while (!defined($done) && $retries <= $N[2]) {

	# make sure the modem stays connected
	unless ($self->{MODEM}->ready("TransmitBlock")) {
	    $self->dropmodem();
	    return ($TEMP_ERROR,"Lost modem connection");
	}

	# transmit block here
	$result = $self->{MODEM}->chat($block,
				       "",
				       "${LEAD}(${ACK}|${NAK}|${RS}|${ESC}${EOT})${CR}",
				       $T[3],
				       1
				      );
	unless (defined $result) {
	    $main::log->do('warning', "total block xmit failure--retrying");
	    $retries++;
	    next;		# restart block xmit
	}

	$self->{MODEM}->HexDump($result) if $self->{DEBUG};
	# show any messages
	$report = $self->ReportMsgSeq($result);

	# check for answer here
	if ($result =~ /${LEAD}${ACK}${CR}/) {
	    $main::log->do('debug', "block taken") if $self->{DEBUG};
	    $done = $SUCCESS;
	} elsif ($result =~ /${LEAD}${NAK}${CR}/) {
	    $main::log->do('debug', "retrans block needed")
		if $self->{DEBUG};
	    $retries++;
	} elsif ($result =~ /${LEAD}${RS}${CR}/) {
	    $main::log->do('debug', "skipping block") if $self->{DEBUG};
	    $done = $SKIP_MSG;
	} elsif ($result =~ /${LEAD}${ESC}${EOT}${CR}/) {
	    $main::log->do('crit', "immediate disconnect requested!");
	    $self->disconnect();
	    $done=$TEMP_ERROR;
	}
    }

    # assume a temporary error unless we already know our state
    $done = $TEMP_ERROR unless defined $done;

    return ($done, $report);
}

# calculate the 3-char checksum for a block
sub TAPCheckSum
{
    my $self = shift;
    my ($data) = @_;
    my ($sum, @chars, $c, @check);
    $sum = 0;
    @chars = split //, $data;
    $sum += (ord($_) & 0x7f) foreach @chars; # drop hi bits (shouldn't be there)

    #        /* the checksum is represented as 3 ascii characters having the values
    #                between 0x30 and 0x3f */
    $check[2] = chr(0x30 + ($sum & 0x0f));
    $sum >>= 4;
    $check[1] = chr(0x30 + ($sum & 0x0f));
    $sum >>= 4;
    $check[0] = chr(0x30 + ($sum & 0x0f));

    return join "", @check;
}

#
#   ${STX}${FIELD1}\r${FIELD2}\r${ETX}${CHECKSUM}\r
#
#  (note: pages can be broken into multiple packets, separated by "ETB")
#
#                    seq\rcode\r
#   nak: retry
#   ack: got it
#   rs:  skip this one
#   eot: hang up NOW
#
#   ${EOT}\r
#                    something\r
#   seq: all good
#   rs: something broken
#   eot: goodbye

sub ReportMsgSeq
{
    my $self = shift;
    my ($seq) = @_;
    my (@lines, $line, $msg, @msgs, $num, $text, $str);

    @lines = split /${CR}/, $seq;
    undef @msgs;
    undef $msg;
    $str = "";

    foreach $line (@lines) {
	if ($line =~ /^(\d\d\d)\D/) {
	    if (defined $msg) {
		push @msgs, $msg;
	    }
	    # extract the sequence msgs number
	    $line =~ /^(\d\d\d)(.*)$/;
	    $num  = $1;
	    $text = $2;
	    # prepend ": " if any text exists
	    $text = ": $text" if $text !~ /^\s*$/;
	    # decode our message
	    if (defined $SeqMinor{$num}) {
		$msg = "$SeqMinor{$num}$text";
	    } else {
		$msg = "(undefined Sequence: $num)$text";
	    }

	} else {
	    $msg .= $line;
	}
    }
    push @msgs, $msg if defined $msg;

    foreach $msg (@msgs) {
	# drop standard signalling messages
	$msg =~ s/($ESC(\[p|$EOT)*|$ACK|$NAK|$RS)//g;

	$str .= "'" . Sendpage::Modem->HexStr($msg) . "'\n"
	    if $msg !~ /^[\s\n\r]*$/;
    }

    return $str;
}

sub maxchars { $_[0]->{MAXCHARS} }

sub maxsplits { $_[0]->{MAXSPLITS} }

sub SendMail
{
    my ($self, $to, $from, $cc, $errorsto, $subject, $body) = @_;

    my($msg,$fh);

    $msg = new Mail::Send;

    if ($self->{DEBUG}) {
	$main::log->do('debug',
		       "Emailing: To: '%s', Cc: '%s', "
		       . "From: '%s', Subject: '%s'",
		       $to, $cc, $from, $subject
		      );
    }

    unless (defined $msg) {
	$main::log->do('crit', "Cannot deliver email!  Mail::Send won't start");
    } else {
	$msg->to($to) if (defined($to) && $to ne "");
	$msg->cc($cc) if (defined($cc) && $cc ne "");
	$msg->set('X-Pager', "sendpage v$main::VERSION");
	$msg->set('Errors-To',"<$errorsto>")
	    if (defined($errorsto) && $errorsto ne "");
	$msg->set('From',$from);
	$msg->subject($subject);

	# use mail-agent, see if the from gets passed now
	$fh = $msg->open($self->{CONFIG}->get("mail-agent"));

	unless (defined $fh) {
	    $main::log->do('crit',
			   "Cannot deliver email!  Mail::Send won't open -- check your 'mail-agent' setting");
	} else {
	    print $fh $body
		|| $main::log->do('crit',
				  "Error writing email: %s", $!
				 );
	    $fh->close
		|| $main::log->do('crit',
				  "Error closing email -- check your 'mail-agent' setting: %s",
				  $!
				 );
	}
    }
}

sub DESTROY
{
    my $self = shift;

    $main::log->do('debug',
		   "PagingCentral object '$self->{NAME}' being destroyed")
	if $self->{DEBUG};

    $self->disconnect();
}

1;

__END__

=head1 AUTHOR

Kees Cook <kees@outflux.net>

=head1 SEE ALSO

Man pages: L<perl>, L<sendpage>.

Module documentation: L<Sendpage::KeesConf>, L<Sendpage::KeesLog>,
L<Sendpage::Modem>, L<Sendpage::PageQueue>, L<Sendpage::Page>,
L<Sendpage::Recipient>, L<Sendpage::Queue>

=head1 COPYRIGHT

Copyright 2000 Kees Cook.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
