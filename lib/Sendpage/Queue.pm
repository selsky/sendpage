#
# this tools handles dealing with a single queue directory
# it processes *one* file at a time with a few functions
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

package Sendpage::Queue;
use FileHandle;

=head1 NAME

Queue.pm - implements a simple directory-based file queue

=head1 SYNOPSIS

    $queue=Sendpage::Queue->new($dir);

    while ($queue->ready()) {
	$filename=$queue->file();
	$fh=$queue->getReadyFile();
	if ($can_remove_file) {
		$queue->fileToss();
	}
	else {
		$queue->fileDone();
	}
    }

    # open a new queue file
    $fh=$queue->getNewFile();
    # ... do things to the file handle here
    # release the file
    $queue->doneNewFile();

=head1 DESCRIPTION

This is a module for use in sendpage(1).

=head1 BUGS

Need to write more docs.

=cut


sub new {
        my $proto = shift;
        my $class = ref($proto) || $proto;
        my $self  = {};

	# self configuration area
	$self->{DIR}=shift;   # location of my queue
	@{$self->{FILES}}=undef; # where to store our directory list
	$self->{OPEN}=undef;  # current open file
	$self->{COUNTER}=0;   # for the unique filename
	
	if (! -d $self->{DIR}) {
		$main::log->do('alert',"'".$self->{DIR}."' is not a directory!");
		return undef;
	}
	if (! -w $self->{DIR}) {
		$main::log->do('alert', "Cannot write to '".$self->{DIR}."' directory!");
		return undef;
	}
	if (! -r $self->{DIR}) {
		$main::log->do('alert', "Cannot read '".$self->{DIR}."' directory!");
		return undef;
	}

        bless($self,$class);
        return $self;
}

sub file {
	my $self = shift;
	return $self->{FILES}[0];
}

# is the queue ready to have files taken from it?
sub ready {
	my $self = shift;

	if ($self->{OPEN}) {
		$main::log->do('alert', "Cannot check queue '".$self->{DIR}."' with open file (".$self->{FILES}[0].")!");
		return -2;
	}

	opendir(DIRHANDLE,$self->{DIR})
		|| $main::log->do('alert', "Cannot access '".$self->{DIR}."': $!");
	my @files=readdir(DIRHANDLE);
	#grep(warn("in '".$self->{DIR}."': $_\n"),@files);

	@{$self->{FILES}}=grep(/^q/,@files);
	@files=@{$self->{FILES}};

	#grep(warn("in FILES: $_\n"),@files);
	#warn "ready will be: ".$#files."\n";

	close(DIRHANDLE);
	
	return $#files;
}	

# get a file handle from the queue
#	handle is locked, and must be release with "fileDone"
sub getReadyFile {
	my $self = shift;
	my $fh = new FileHandle;

	if ($self->{OPEN}) {
		$main::log->do('alert', "Cannot read next file from queue '".$self->{DIR}."' with open file (".$self->{FILES}[0].")!");

		return undef;
	}
	my($file)=$self->{FILES}[0];
	return undef if (!defined($file));

	my $err="queue '$file' from '".$self->{DIR}."':";

	my $fname = $self->{DIR}."/$file";

	# create new queue files
	if (!-f $fname) {
		open($fh,">$fname") || $main::log->do('alert', "Cannot write $err $!");
		close($fh);
	}

	# open queue files read/write
	if (!open($fh,"+<$fname")) {
		$main::log->do('alert', "Cannot read $err $!");

		# try the next file
		shift @{$self->{FILES}};
		return $self->getReadyFile();
	}

	if (!$self->lockFile($fname)) {
		$main::log->do('alert', "Cannot lock $err $!");
		close($fh);

		# try the next file
		shift @{$self->{FILES}};
		return $self->getReadyFile();
	}

	if (! -f $fname) {
		# someone deleted the file while they had it locked,
		close($fh);

		# we should try for the next file in the queue
		shift @{$self->{FILES}};
		return $self->getReadyFile();
	}

	$self->{OPEN}=$fh;

	return $self->{OPEN};
}

# releases locks, closes file, removes file, etc
sub fileToss {
	my($self)=shift;

	if (!$self->{OPEN}) {
		$main::log->do('alert', "Cannot call fileToss without an open file!");
		return undef;
	}

	# unlink before unlock: no one can get it then FIXME: this is not right
	my $fname = $self->{DIR}."/".$self->{FILES}[0];

	if (unlink($fname)<1) {
		$main::log->do('alert', "Could not delete file '$fname': $!");
	}

	$self->unlockFile($fname);
	close($self->{OPEN});
	$self->{OPEN}=undef;

	# drop the filename
	shift @{$self->{FILES}};

	return 1;
}

# releases locks, closes file, assumes that it should stay
sub fileDone {
	my($self)=shift;

	if (!$self->{OPEN}) {
		$main::log->do('alert', "Cannot call fileDone without an open file!");
		return undef;
	}

	my $fname = $self->{DIR}."/".$self->{FILES}[0];

	$self->unlockFile($fname);
	close($self->{OPEN});
	$self->{OPEN}=undef;
	shift @{$self->{FILES}};	# drop the leading filename

	return 1;
}

# gets a new file handle, must be released with "doneNewFile"
sub getNewFile {
	my($self)=shift;

	if ($self->{OPEN}) {
		$main::log->do('alert', "Cannot create new file for queue '".$self->{DIR}."' with open file (".$self->{FILES}[0].")!");
		return undef;
	}

	unshift(@{$self->{FILES}},"Q".$self->createUniqueName());
	return $self->getReadyFile();
}

sub doneNewFile {
	my($self)=shift;

	my $fname;

	if (!defined($self->{OPEN})) {
		$main::log->do('alert', "Cannot close new file while no file is open!");
		return undef;
	}

	$fname=$self->{FILES}[0];
	if ($fname !~ /^Q/) {
		$main::log->do('alert', "Not operating on a new Queue file");
		return undef;
	}

	my $newname=$fname;
	$newname =~ s/^Q/q/;

	# need the queue dirs here, too
	$fname=$self->{DIR}."/$fname";
	$newname=$self->{DIR}."/$newname";
	if (!rename($fname,$newname)) {
		$main::log->do('crit', "Cannot rename '$fname' -> '$newname': $!\n");
	}

	# done with this handle
	$self->fileDone();	
}


#############
# internal functions
#############

# locks a single file  FIXME
sub lockFile {
	my($self,$file)=@_;
	$main::log->do('debug',"need to be locking '$file'")
		if ($main::DEBUG);
	return 1;
}

# unlocks a single file   FIXME
sub unlockFile {
	my($self,$file)=@_;
	$main::log->do('debug',"need to be unlocking '$file'")
		if ($main::DEBUG);
	return 1;
}

# locks the queue run (do we really need this?)
sub lockQueue {
}

# unlocks the queue directory (may not need this...)
sub unlockQueue {
}

# returns a name based on time, process id, hostname, and cycle
# FIXME: USE the hostname
sub createUniqueName {
	my($self)=shift;

	return sprintf("%010d%05d%03d",time(),$$,$self->{COUNTER}++);
}

1;

__END__

=head1 AUTHOR

Kees Cook <cook@cpoint.net>

=head1 SEE ALSO

perl(1), sendpage(1), Sendpage::KeesConf(3), Sendpage::KeesLog(3),
Sendpage::Modem(3), Sendpage::PagingCentral(3), Sendpage::PageQueue(3),
Sendpage::Page(3), Sendpage::Recipient(3)

=head1 COPYRIGHT

Copyright 2000 Kees Cook.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

